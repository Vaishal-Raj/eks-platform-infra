#!/usr/bin/env python3
"""Validate client configs and resolve one into Terraform inputs.

  python scripts/config.py validate
  python scripts/config.py resolve --client client-a --env dev
  python scripts/config.py resolve --client client-a --env dev --override-json '{"network":{"az_count":3}}'
  python scripts/config.py profiles
  python scripts/config.py write-client --client client-b --env dev --profile small \
      --region us-east-1 --vpc-cidr 10.1.0.0/16 --account-id 264760299713 --az-count 3

Resolution order (later wins):
  profile -> client values -> client overrides -> what-if (plan only)
"""
from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import os
import sys
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "config"


def load(path: Path) -> dict:
    return json.loads(path.read_text())

def deep_merge(base: dict, override: dict) -> dict:
    """Merge nested dicts. Values in `override` win; nested dicts are merged, not replaced."""
    result = copy.deepcopy(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result

def schema_errors(instance: dict, schema_file: str) -> list[str]:
    schema = load(CONFIG / "schema" / schema_file)
    return [
        f"{'/'.join(str(p) for p in err.absolute_path) or '<root>'}: {err.message}"
        for err in jsonschema.Draft202012Validator(schema).iter_errors(instance)
    ]

# - from __future__ import annotations lets type hints like dict | None work on your Mac's Python 3.9.
# - deep_merge is the key function. {"network": {"az_count": 3}} changes only az_count and keeps the rest of the network section. A plain dict.update() would replace the whole section.
# - Lists are replaced, not merged. If an override sets interface_services, that becomes the complete list.


# MERGE CHAIN
def resolve(client_id: str, env: str, what_if: dict | None = None) -> dict:
    client = load(CONFIG / "clients" / client_id / f"{env}.json")
    profile = load(CONFIG / "profiles" / f"{client['profile']}.json")

    identity = {k: v for k, v in client.items() if k != "overrides"}
    config = deep_merge(profile, identity)                     # profile, then client values
    config = deep_merge(config, client.get("overrides", {}))   # then the client's exceptions

    if what_if:                                                # then the plan-only what-if
        unknown = set(what_if) - set(profile)
        if unknown:
            raise ValueError(f"what-if may only touch {sorted(profile)}, not {sorted(unknown)}")
        config = deep_merge(config, what_if)

    # The merged profile sections must still obey the profile rules
    errors = schema_errors({k: config[k] for k in profile}, "profile.schema.json")
    if errors:
        raise ValueError("resolved config is invalid:\n  " + "\n  ".join(errors))
    return config

# This is the chain profile → client → overrides → what-if from your design, in about ten lines. 
# The last check runs the merged network and endpoints sections through the profile schema again, so a bad override can't slip through.

# ================ Validation

def check_client(path: Path) -> list[str]:
    """Problems with one client file; an empty list means it's valid."""
    try:
        client = load(path)
    except json.JSONDecodeError as exc:
        return [f"invalid JSON: {exc}"]

    errors = schema_errors(client, "client.schema.json")
    if errors:
        return errors

    if (client["client_id"], client["environment"]) != (path.parent.name, path.stem):
        errors.append(f"client_id/environment must match the path ({path.parent.name}/{path.stem})")
    if not (CONFIG / "profiles" / f"{client['profile']}.json").exists():
        errors.append(f"unknown profile '{client['profile']}'")
    try:
        ipaddress.ip_network(client["vpc_cidr"])  # strict: rejects host bits, e.g. 10.0.0.1/16
    except ValueError as exc:
        errors.append(f"vpc_cidr: {exc}")
    if errors:
        return errors

    try:  # overrides are only valid if the merged result is valid
        resolve(client["client_id"], client["environment"])
    except ValueError as exc:
        errors.append(str(exc))
    return errors

def cmd_validate(_: argparse.Namespace) -> int:
    failures = 0

    for path in sorted((CONFIG / "profiles").glob("*.json")):
        errors = schema_errors(load(path), "profile.schema.json")
        failures += bool(errors)
        print(f"{'FAIL' if errors else 'ok  '}  {path.relative_to(ROOT)}")
        for e in errors:
            print(f"        {e}")

    networks = []
    for path in sorted((CONFIG / "clients").glob("*/*.json")):
        errors = check_client(path)
        failures += bool(errors)
        print(f"{'FAIL' if errors else 'ok  '}  {path.relative_to(ROOT)}")
        for e in errors:
            print(f"        {e}")
        if not errors:
            networks.append((path.relative_to(ROOT), ipaddress.ip_network(load(path)["vpc_cidr"])))

    # No two client environments may share address space (keeps future peering possible)
    for i, (path_a, net_a) in enumerate(networks):
        for path_b, net_b in networks[i + 1:]:
            if net_a.overlaps(net_b):
                failures += 1
                print(f"FAIL  {path_a} ({net_a}) overlaps {path_b} ({net_b})")

    print(f"\n{failures} problem(s)")
    return 1 if failures else 0

# ====================== resolve and the command line

def cmd_resolve(args: argparse.Namespace) -> int:
    if cmd_validate(args) != 0:
        return 1

    what_if = None
    if args.override_json.strip():
        try:
            what_if = json.loads(args.override_json)
        except json.JSONDecodeError as exc:
            print(f"FAIL  --override-json is not valid JSON: {exc}")
            return 1

    try:
        config = resolve(args.client, args.env, what_if)
    except (FileNotFoundError, ValueError) as exc:
        print(f"FAIL  {exc}")
        return 1

    out = ROOT / "build" / args.client / args.env
    out.mkdir(parents=True, exist_ok=True)
    (out / "config.tfvars.json").write_text(json.dumps({"config": config}, indent=2) + "\n")

    bucket = f"tfstate-{config['client_id']}-{config['environment']}-{config['account_id']}"
    (out / "backend.hcl").write_text(
        f'bucket       = "{bucket}"\n'
        f'region       = "{config["region"]}"\n'
        "encrypt      = true\n"
        "use_lockfile = true\n"
    )

    print(f"\nresolved -> {out.relative_to(ROOT)}/")
    print(json.dumps(config, indent=2))

    if os.environ.get("GITHUB_OUTPUT"):  # hand values to later jobs in GitHub Actions
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"account_id={config['account_id']}\n")
            fh.write(f"region={config['region']}\n")
    return 0


# ====================== onboard / update a client from the GitHub form

# Form fields that may override a profile value: form name -> (section, key, parse)
FORM_FIELDS = {
    "az_count":   ("network", "az_count", int),
    "endpoints":  ("endpoints", "enabled", lambda v: v == "on"),
    "s3_gateway": ("endpoints", "enable_s3_gateway", lambda v: v == "on"),
}

# Region facts, not client choices: AZs to avoid (EKS has no control plane in use1-az3)
REGION_EXCLUDED_ZONES = {"us-east-1": ["use1-az3"]}


def flatten(d: dict, prefix: str = "") -> dict:
    """{"network": {"az_count": 2}} -> {"network.az_count": 2}"""
    out = {}
    for key, value in d.items():
        if isinstance(value, dict):
            out.update(flatten(value, f"{prefix}{key}."))
        else:
            out[f"{prefix}{key}"] = value
    return out


def diff(desired: dict, base: dict) -> dict:
    """Only the (nested) values in `desired` that differ from `base`. These become the overrides."""
    out = {}
    for key, value in desired.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            nested = diff(value, base[key])
            if nested:
                out[key] = nested
        elif base.get(key) != value:
            out[key] = value
    return out


def fmt(value) -> str:
    if isinstance(value, bool):
        return "on" if value else "off"
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value)


def summary(text: str) -> None:
    """Print, and also add to the GitHub Actions run summary when running in CI."""
    print(text)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as fh:
            fh.write(text + "\n")


def cmd_profiles(_: argparse.Namespace) -> int:
    profiles = {p.stem: flatten(load(p)) for p in sorted((CONFIG / "profiles").glob("*.json"))}
    names = list(profiles)
    keys = sorted({k for p in profiles.values() for k in p})
    lines = [
        "### Available profiles",
        "",
        "| Setting | " + " | ".join(f"`{n}`" for n in names) + " |",
        "|---|" + "---|" * len(names),
    ]
    for key in keys:
        lines.append(f"| `{key}` | " + " | ".join(fmt(profiles[n].get(key, "—")) for n in names) + " |")
    summary("\n".join(lines) + "\n")
    return 0


def cmd_write_client(args: argparse.Namespace) -> int:
    path = CONFIG / "clients" / args.client / f"{args.env}.json"
    profile_path = CONFIG / "profiles" / f"{args.profile}.json"
    if not profile_path.exists():
        print(f"FAIL  unknown profile '{args.profile}'")
        return 1
    profile = load(profile_path)
    existing = load(path) if path.exists() else None

    if existing:
        # Identity can't change on an existing client: it would rebuild (or orphan) everything
        for field, new in (("region", args.region), ("vpc_cidr", args.vpc_cidr)):
            if new and new != existing[field]:
                print(f"FAIL  {field} can't change for an existing client ({existing[field]} -> {new})")
                return 1
        client = copy.deepcopy(existing)
        if args.cost_center:
            client["tags"] = {**client.get("tags", {}), "CostCenter": args.cost_center}
    else:
        missing = [f for f, v in (("region", args.region), ("vpc_cidr", args.vpc_cidr)) if not v]
        if missing:
            print(f"FAIL  {' and '.join(missing)} required for a new client")
            return 1
        client = {
            "client_id": args.client,
            "environment": args.env,
            "profile": args.profile,
            "account_id": args.account_id,
            "region": args.region,
            "vpc_cidr": args.vpc_cidr,
            "exclude_zone_ids": REGION_EXCLUDED_ZONES.get(args.region, []),
            "tags": {"CostCenter": args.cost_center or args.client},
            "overrides": {},
        }
    client["profile"] = args.profile

    # Start from what the client gets on this profile today (existing overrides kept),
    # apply the form's edits, then store only what differs from the profile.
    desired = deep_merge(profile, client.get("overrides", {}))
    for name, (section, key, parse) in FORM_FIELDS.items():
        choice = getattr(args, name)
        if choice == "profile":
            desired[section][key] = profile[section][key]
        elif choice != "unchanged":
            desired[section][key] = parse(choice)
    client["overrides"] = diff(desired, profile)

    errors = schema_errors(client, "client.schema.json") + schema_errors(desired, "profile.schema.json")
    if errors:
        print("FAIL  " + "\n      ".join(errors))
        return 1

    before, after = flatten(profile), flatten(desired)
    lines = [
        f"### {'Update' if existing else 'Onboard'} `{args.client} / {args.env}`, profile `{args.profile}`",
        "",
        "| Setting | profile | final |",
        "|---|---|---|",
    ]
    for key, value in after.items():
        mark = " ✏️" if value != before.get(key) else ""
        lines.append(f"| `{key}` | {fmt(before.get(key))} | **{fmt(value)}**{mark} |")
    lines += ["", "Stored as `overrides` (only what differs from the profile):", "```json",
              json.dumps(client["overrides"], indent=2), "```", ""]
    summary("\n".join(lines))

    if client == existing:  # nothing changed: leave the file (and its formatting) untouched
        print(f"no changes to {path.relative_to(ROOT)}")
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(client, indent=2) + "\n")
        print(f"wrote {path.relative_to(ROOT)}")

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"is_new={'false' if existing else 'true'}\n")
            fh.write(f"region={client['region']}\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate and resolve client configs")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate").set_defaults(func=cmd_validate)

    p = sub.add_parser("resolve")
    p.add_argument("--client", required=True)
    p.add_argument("--env", required=True)
    p.add_argument("--override-json", default="")
    p.set_defaults(func=cmd_resolve)

    sub.add_parser("profiles", help="print every profile's specs as a table").set_defaults(func=cmd_profiles)

    w = sub.add_parser("write-client", help="create or update a client file from the form")
    w.add_argument("--client", required=True)
    w.add_argument("--env", required=True)
    w.add_argument("--profile", required=True)
    w.add_argument("--region", default="")
    w.add_argument("--vpc-cidr", default="")
    w.add_argument("--account-id", default="")
    w.add_argument("--cost-center", default="")
    w.add_argument("--az-count", choices=["unchanged", "profile", "2", "3"], default="unchanged")
    w.add_argument("--endpoints", choices=["unchanged", "profile", "on", "off"], default="unchanged")
    w.add_argument("--s3-gateway", choices=["unchanged", "profile", "on", "off"], default="unchanged")
    w.set_defaults(func=cmd_write_client)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())


# - config.tfvars.json wraps everything in {"config": {...}}. In Step 3, Terraform receives it as one typed variable, var.config.
# - backend.hcl holds the state bucket. The name follows the same pattern as your bootstrap bucket (tfstate-client-a-dev-264760299713), so it's derived, not stored.
# - GITHUB_OUTPUT only matters in the pipeline (Step 4). Locally it's ignored.