#!/usr/bin/env bash

set -euo pipefail

MANIFEST_NAME="iso_manifest.tsv"

# --- Input check ---
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <directory>" >&2
  exit 1
fi

TARGET_DIR="$1"
cd "$TARGET_DIR"

# --- Temp file to build manifest ---
TMP_MANIFEST=".${MANIFEST_NAME}.tmp"

# --- Collect files, exclude previous manifest if any ---
mapfile -t ALL_FILES < <(find . -type f ! -name "$MANIFEST_NAME" | sort | shuf)
FILE_COUNT=${#ALL_FILES[@]}

# --- Compute midpoint index ---
MID_INDEX=$(( FILE_COUNT / 2 ))

# --- Write initial manifest with placeholder ---
{
  for i in "${!ALL_FILES[@]}"; do
    INDEX=$(printf "%03d" $((i + 1)))
    FILE="${ALL_FILES[$i]#./}"
    if [[ $i -eq $MID_INDEX ]]; then
      echo -e "$INDEX\t$MANIFEST_NAME\tTO_BE_FILLED\tTO_BE_FILLED"
      INDEX=$(printf "%03d" $((i + 2)))
    fi
    SIZE=$(stat --printf="%s" "$FILE")
    HASH=$(sha256sum "$FILE" | awk '{print $1}')
    echo -e "$INDEX\t$FILE\t$SIZE\t$HASH"
  done
} > "$TMP_MANIFEST"

# --- Finalize manifest ---
mv "$TMP_MANIFEST" "$MANIFEST_NAME"
MANIFEST_SIZE=$(stat --printf="%s" "$MANIFEST_NAME")
MANIFEST_HASH=$(sha256sum "$MANIFEST_NAME" | awk '{print $1}')

# --- Replace placeholder line with final info ---
sed -i "s|TO_BE_FILLED|$MANIFEST_SIZE\t$MANIFEST_HASH|" "$MANIFEST_NAME"

echo "Manifest generated: $TARGET_DIR/$MANIFEST_NAME"
