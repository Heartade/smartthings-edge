#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: bash scripts/deploy-dev.sh <channel-id> <hub-id> [extra package args...]" >&2
  exit 2
fi

CHANNEL_ID="$1"
HUB_ID="$2"
shift 2
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/package-dev.sh" --install --channel "$CHANNEL_ID" --hub "$HUB_ID" "$@"
