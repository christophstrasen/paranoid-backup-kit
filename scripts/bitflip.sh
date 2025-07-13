#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <inputfile>" >&2
  exit 1
fi

INPUT_FILE="$1"

# Get file size
FILE_SIZE=$(stat --format="%s" "$INPUT_FILE")
if [[ "$FILE_SIZE" -eq 0 ]]; then
  echo "Input file is empty." >&2
  exit 1
fi

# Choose offset in the middle of the file
BYTE_OFFSET=$((FILE_SIZE / 2))
BIT_TO_FLIP=1  # Flip least significant bit (change to 2, 4, 8, etc. if you want)

# Read byte at offset
ORIGINAL_BYTE=$(dd if="$INPUT_FILE" bs=1 count=1 skip=$BYTE_OFFSET 2>/dev/null | xxd -p)
ORIGINAL_BYTE_DEC=$((16#$ORIGINAL_BYTE))

# Flip the bit
CORRUPTED_BYTE_DEC=$((ORIGINAL_BYTE_DEC ^ BIT_TO_FLIP))
CORRUPTED_BYTE_HEX=$(printf "%02x" $CORRUPTED_BYTE_DEC)

# Output to stdout: prefix + corrupted byte + suffix
dd if="$INPUT_FILE" bs=1 count="$BYTE_OFFSET" status=none
printf "\\x$CORRUPTED_BYTE_HEX"
dd if="$INPUT_FILE" bs=1 skip=$((BYTE_OFFSET + 1)) status=none

# Log info to stderr
echo "⚠️  Bit error injected at offset $BYTE_OFFSET (original byte: 0x$ORIGINAL_BYTE, flipped to: 0x$CORRUPTED_BYTE_HEX)" >&2

