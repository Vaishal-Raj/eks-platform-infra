#!/usr/bin/env bash
# Run one stack for one client environment. Used locally and by the pipelines.
#
# Usage: scripts/tf-stack.sh <client> <env> <stack> <plan|apply>
#   e.g. scripts/tf-stack.sh client-a dev 10-network plan
#
# Needs build/<client>/<env>/ from: python scripts/config.py resolve --client <client> --env <env>
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <client> <env> <stack> <plan|apply>" >&2
  exit 2
fi

CLIENT=$1 ENV=$2 STACK=$3 ACTION=$4
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/build/$CLIENT/$ENV"
DIR="$ROOT/stacks/$STACK"
KEY="${STACK#*-}/terraform.tfstate" # 10-network -> network/terraform.tfstate

[[ -d "$DIR" ]] || { echo "No such stack: stacks/$STACK" >&2; exit 1; }
[[ -f "$BUILD/config.tfvars.json" ]] || {
  echo "Missing $BUILD/config.tfvars.json - run: python scripts/config.py resolve --client $CLIENT --env $ENV" >&2
  exit 1
}

# -reconfigure: the same stack folder serves every client, so always re-point the backend
terraform -chdir="$DIR" init -input=false -reconfigure \
  -backend-config="$BUILD/backend.hcl" \
  -backend-config="key=$KEY"

case "$ACTION" in
  plan)
    terraform -chdir="$DIR" plan -input=false -lock-timeout=5m \
      -var-file="$BUILD/config.tfvars.json" -out="$BUILD/$STACK.tfplan"
    ;;
  apply)
    terraform -chdir="$DIR" apply -input=false -lock-timeout=5m \
      -var-file="$BUILD/config.tfvars.json" -auto-approve
    ;;
  *)
    echo "action must be plan or apply, got: $ACTION" >&2
    exit 2
    ;;
esac
