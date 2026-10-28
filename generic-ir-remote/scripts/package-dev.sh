#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smartthings-ir-dev.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# Package from an isolated copy so config.yaml in the checkout always remains
# the stable package identity. The dev build uses a separate SmartThings driver
# package key and should normally be published to a separate dev channel.
cp -R "$DRIVER_DIR"/. "$TMP_DIR"/
cp "$DRIVER_DIR/config.dev.yaml" "$TMP_DIR/config.yaml"
rm -f "$TMP_DIR/config.dev.yaml"

smartthings edge:drivers:package "$TMP_DIR" "$@"
