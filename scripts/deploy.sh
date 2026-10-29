#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Deployment failed" >&2; exit 1' ERR
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
REPO_ROOT=$(cd -- "$REPO_ROOT" && pwd)
TARGET=${DEPLOY_TARGET:-devops}
URL=${DEPLOY_URL:-https://devops.local/}
CA_CERT=${CA_CERT:-$REPO_ROOT/certs/devops.crt}
DRY_RUN=0
if [[ $# -eq 1 && $1 == --dry-run ]]; then
    DRY_RUN=1
elif [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--dry-run]" >&2
    exit 1
fi
if [[ ! -f "$REPO_ROOT/site/index.html" ]]; then
    echo "Missing site/index.html" >&2
    exit 1
fi
if [[ -n $(git -C "$REPO_ROOT" status --porcelain) ]]; then
    echo "Working tree is dirty; commit changes first" >&2
    exit 1
fi
OPTIONS=(-avz --delete --chmod=D755,F644)
if [[ $DRY_RUN -eq 1 ]]; then OPTIONS+=(--dry-run); fi
rsync "${OPTIONS[@]}" \
    -e 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes' \
    "$REPO_ROOT/site/" "$TARGET:/var/www/devops-site/"
if [[ $DRY_RUN -eq 1 ]]; then
    echo 'Dry run complete; server unchanged'
    exit 0
fi
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" "$URL" > /dev/null
printf 'Deployed %s\n' "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
