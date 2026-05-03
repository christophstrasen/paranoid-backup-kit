#!/usr/bin/env bash
set -euo pipefail

# Adds a default of 100% parity via the par2 tool

MIN_SIZE=256        # Minimum file size to include
ENCRYPTED_DIR="$(cd "$(dirname "$0")/../encrypted" && pwd -P)"

source "$(dirname "$0")/runtime_guard.sh"
pbk_require_main_entrypoint
source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- addparity.sh --"

log_summary "🗑️ Cleaning up old parity files..."
rm -f "$ENCRYPTED_DIR"/*.par2

log_summary "Starting parity generation inside $ENCRYPTED_DIR..."

# Collect relevant files
shopt -s nullglob
files=("$ENCRYPTED_DIR"/*.age "$ENCRYPTED_DIR"/*.sha256 "$ENCRYPTED_DIR"/*.gpg "$ENCRYPTED_DIR"/*.sh  "$ENCRYPTED_DIR"/*.ppm  "$ENCRYPTED_DIR"/*.pgm )

if [ ${#files[@]} -eq 0 ]; then
  log_summary "❌ ERROR: No files found for parity protection in $ENCRYPTED_DIR. Exiting."
  exit 1
fi

# Check size of each file
for file in "${files[@]}"; do
  size=$(stat --printf="%s" "$file")
  if [ "$size" -lt "$MIN_SIZE" ]; then
    log_summary "❌ ERROR: File '$file' is smaller than $MIN_SIZE bytes. Aborting."
    exit 1
  fi
done

# Move to encrypted directory for local paths
cd "$ENCRYPTED_DIR"

local_files=()
for file in "${files[@]}"; do
  local_files+=("$(basename "$file")")
done

# Generate parity file - default par2 block size 64kb generates ~5 recovery blocks for our chunks (default: 256kb)
# Note that if you adjust MIN_SIZE in encrypt.sh the block-size here should be adjusted accordingly
log_summary "Generating parity for ${#local_files[@]}"
par2 create -r100 -s65536 backup.par2 "${local_files[@]}" # Instructions: lower -r if you are strapped for storage and accept less parity.

# Self check parity validity
shopt -s nullglob
par2_files=( *.par2 )

if [ ${#par2_files[@]} -lt 2 ]; then
  log_summary "❌ ERROR: Less than two .par2 files generated!"
  exit 1
fi

for file in "${par2_files[@]}"; do
  if [ ! -s "$file" ] || [ "$(stat -c%s "$file")" -lt 10 ]; then
    log_summary "❌ ERROR: Parity file $file is too small (<10 bytes)!"
    exit 1
  fi
done

log_summary "✅ Parity files generated and validated."
