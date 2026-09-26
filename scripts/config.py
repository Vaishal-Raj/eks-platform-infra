#!/usr/bin/env python3
"""Validate client configs and resolve one into Terraform inputs.

  python scripts/config.py validate
  python scripts/config.py resolve --client client-a --env dev
  python scripts/config.py resolve --client client-a --env dev --override-json '{"network":{"az_count":3}}'

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


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate and resolve client configs")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("validate").set_defaults(func=cmd_validate)

    p = sub.add_parser("resolve")
    p.add_argument("--client", required=True)
    p.add_argument("--env", required=True)
    p.add_argument("--override-json", default="")
    p.set_defaults(func=cmd_resolve)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())


# - config.tfvars.json wraps everything in {"config": {...}}. In Step 3, Terraform receives it as one typed variable, var.config.
# - backend.hcl holds the state bucket. The name follows the same pattern as your bootstrap bucket (tfstate-client-a-dev-264760299713), so it's derived, not stored.
# - GITHUB_OUTPUT only matters in the pipeline (Step 4). Locally it's ignored.