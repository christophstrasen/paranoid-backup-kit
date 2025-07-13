#!/usr/bin/env bash
set -euo pipefail

# Does what it says and cleans
# @TODO could consider wiping all of /tmp/ or calling the respective systemd

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING_DIR="$REPO_ROOT/plain_staging"

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- cleanup.sh --"

shopt -s nullglob
files=("$STAGING_DIR"/*)
if [ ${#files[@]} -eq 0 ]; then
  log_summary "No files found in staging directory ($STAGING_DIR). Nothing to clean."
  exit 0
fi

log_summary "Attemping secure wipe via shred --remove --zero."

for file in "${files[@]}"; do
  if [ -f "$file" ]; then
    echo "Shredding $file..."
    shred --remove --zero "$file"
  fi
done

log_summary "🗑️ Cleanup complete."

