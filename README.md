# EKS Platform — Infrastructure

Terraform for the multi-client EKS platform described in the M0 design doc.
This repo holds **infrastructure only**. The application build/deploy pipeline
lives in a separate repo.

Each client gets its own isolated stack (VPC, EKS, RDS, …), built from the same
code and driven by per-client settings.

## Repository layout

```
infra-repo/
├── bootstrap/
│   └── state-backend/             # S3 bucket that stores Terraform state for one client-env
│       ├── versions.tf            # providers only; NO backend block here
│       ├── backend.tf             # generated after the first apply (step 2 below)
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── README.md
```

More folders get added as the platform grows (network, database, EKS, …).

## Prerequisites

| Tool      | Version        | Check                         |
|-----------|----------------|-------------------------------|
| Terraform | >= 1.10        | `terraform version`           |
| AWS CLI   | v2             | `aws --version`               |
| AWS login | target account | `aws sts get-caller-identity` |

Terraform 1.10+ is required for S3 native state locking (`use_lockfile`), so no
DynamoDB table is needed.

---

## Onboarding a new client: state bucket

Every client-environment gets its own state bucket:

```
tfstate-<client>-<env>-<account-id>      e.g. tfstate-client-a-dev-123456789012
```

The bucket is created by `bootstrap/state-backend`. That root has a
chicken-and-egg problem: it can't store its state in a bucket that doesn't exist
yet. So the first apply uses **local** state, and the state is then **migrated**
into the new bucket. This is done **once per client-environment**.

The backend block lives in its **own file**, `backend.tf`, never in `versions.tf`:

| Phase                  | `backend.tf`   | Where state lives |
|------------------------|----------------|-------------------|
| 1. First apply         | does not exist | local file        |
| 2. After the bucket exists | generated  | S3 bucket         |

Terraform allows only **one** backend block per root, across all files.

Set these once in your terminal. They are used by every command below:

```bash
CLIENT=client-a
ENV=dev
REGION=us-east-1
```

### 1. First apply (local state)

Make sure there is **no** `backend.tf`, and no `backend` block anywhere else:

```bash
cd bootstrap/state-backend
ls backend.tf 2>/dev/null && echo "remove backend.tf first" || echo "ok, no backend yet"
grep -rn 'backend "s3"' *.tf || echo "ok, no backend block in any .tf file"
```

Then:

```bash
terraform init
terraform apply \
  -var "client_id=$CLIENT" \
  -var "environment=$ENV" \
  -var "region=$REGION"
```

This creates 4 resources: the S3 bucket, its versioning, SSE-KMS encryption,
and a public access block with all four switches on.

State is now in a **local** `terraform.tfstate` file.

### 2. Add the backend and migrate the state into the bucket

There is no AWS CLI command that edits Terraform config. The backend is a
Terraform setting, not an AWS one. But the file can be generated from
Terraform's own output, so nobody types the bucket name:

```bash
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket       = "$(terraform output -raw bucket_name)"
    key          = "bootstrap/state-backend/terraform.tfstate"
    region       = "$REGION"
    encrypt      = true
    use_lockfile = true
  }
}
EOF

cat backend.tf        # check the bucket name was filled in
```

The generated file looks like this. You could also type it by hand:

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-client-a-dev-<account-id>"
    key          = "bootstrap/state-backend/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

Now move the state:

```bash
terraform init -migrate-state
```

Answer `yes` when asked to copy the existing state to the new backend.

> **Alternative with no file at all:** skip `backend.tf`, put an empty
> `backend "s3" {}` block in the config, and pass the values on the command line:
>
> ```bash
> terraform init -migrate-state \
>   -backend-config="bucket=$(terraform output -raw bucket_name)" \
>   -backend-config="key=bootstrap/state-backend/terraform.tfstate" \
>   -backend-config="region=$REGION" \
>   -backend-config="encrypt=true" \
>   -backend-config="use_lockfile=true"
> ```
>
> The catch: every later `terraform init` (for example on a fresh clone) must
> repeat the same flags. A committed `backend.tf` avoids that.

### 3. Verify, then clean up

```bash
terraform state list     # 4 resources (+ the aws_caller_identity data source), now read from S3
terraform plan           # must say "No changes"
aws s3 ls "s3://$(terraform output -raw bucket_name)" --recursive
```

Only once the checks pass:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
```

Commit `backend.tf`. It holds only a bucket name and region, nothing secret.

> `backend.tf` is written for **one** client-env. When a second client is
> bootstrapped from this same folder, regenerate `backend.tf` for that client and
> run `terraform init -reconfigure` (not `-migrate-state`), so one client's state
> is never copied into another client's bucket.

---

## How other roots use the state bucket

Every other Terraform root (network, database, …) gets its own `backend.tf`
pointing at the **same bucket** but with its **own `key`**. These roots don't
need the local-state first step: the bucket already exists, so state goes to S3
from the very first `terraform init`.

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-client-a-dev-<account-id>"
    key          = "<root-name>/terraform.tfstate"   # e.g. network/terraform.tfstate
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

The bucket name can be looked up rather than typed:

```bash
aws s3 ls | grep "tfstate-$CLIENT-$ENV"
```

The result is one bucket per client-env, holding one state file per root:

```
tfstate-client-a-dev-<account-id>/
├── bootstrap/state-backend/terraform.tfstate
└── network/terraform.tfstate        # added in Step 3
```

---

## State locking

`use_lockfile = true` makes Terraform write a `<key>.tflock` object next to the
state while a run is in progress. A second run against the same state fails with
`Error acquiring the state lock` until the first one finishes.

If a crashed run leaves a stale lock behind:

```bash
terraform force-unlock <LOCK_ID>   # LOCK_ID is shown in the error message
```

Only do this when you are sure nothing else is running.

---

## Deleting a state bucket (rarely needed)

The bucket is protected twice:
- `prevent_destroy = true`: Terraform refuses to plan its deletion.
- `force_destroy = false`: AWS refuses to delete a bucket that still has objects in it.

And the bucket holds its **own** state, so it can't delete itself. The order
must be:

1. Delete `backend.tf` (and make sure no other backend block exists), then run
   `terraform init -migrate-state` to copy the state back to local.
2. Check `terraform state list` shows all resources. **Stop if it's empty.**
3. Set `prevent_destroy = false` and `force_destroy = true`, then run `terraform apply`.
4. Run `terraform destroy`.
5. Put both settings back to their protected values.

---

## Conventions

- **Tags:** applied to every resource through the provider's `default_tags`
  (`Project`, `Client`, `Environment`, `ManagedBy`).
- **Never commit** `.terraform/`, `*.tfstate` or `*.tfstate.*` (see `.gitignore`).
- **Do commit** `.terraform.lock.hcl` (it pins provider versions) and each
  root's `backend.tf`.

## Progress

- [x] Step 1: state bucket (`bootstrap/state-backend`)
- [ ] Step 2: remote state and locking
- [ ] Step 3: VPC
