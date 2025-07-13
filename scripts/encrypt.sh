#!/usr/bin/env bash
set -euo pipefail

# Instruction: Edit this script in case you have a different name/location for the age public-key.
#
# This file takes the content from plain_staging, splits it into chunks, encrypts them, adds some helpers to the "encrypted" folder
# It vitally also copies the encrypted age private key into the encrypted directory
# This ensures that decryption can happen from just a single good secret
#
# If you wish to keep the encrypted age private key out, please adjust the script
# However this would add another single point of failure beyond the credentials that are required to decrypt that key.

STAGING_DIR="$(dirname "$0")/../plain_staging"
ENCRYPTED_DIR="$(dirname "$0")/../encrypted"
KEYS_DIR="$(dirname "$0")/../keys"
AGE_RECIPIENT_FILE="$KEYS_DIR/backup_pub.age"

MIN_SIZE=256  # bytes 
CHUNK_SIZE="256K" #IMPORTANT: if you change the chunk size here, you _MUST_ change CHUNK_SIZE in assemble_chunks.py
MIN_SPLIT_SIZE=$((512 * 1024))  # 512 KiB

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- encrypt.sh --"


# check and set up staging
shopt -s nullglob
files=("$STAGING_DIR"/*)
if [ ${#files[@]} -eq 0 ]; then
  echo "❌ No files found in $STAGING_DIR. Exiting."
  exit 1
fi
mkdir -p "$ENCRYPTED_DIR"

#@TODO consider a checksum for plain files, before encryption as well.

# split files into 256k chunks and encrypt with age public key
for file in "${files[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Skipping non-regular file $file"
    continue
  fi

  size=$(stat --printf="%s" "$file")
  filename=$(basename "$file")

  if [ "$size" -lt "$MIN_SIZE" ]; then
    log_summary "⚠️ Warning: File quite small: $file is only $size bytes." >&2
  fi

  if [ "$size" -lt "$MIN_SPLIT_SIZE" ]; then
    chunks=("$file")
    chunk_prefix=""
  else
    echo "Splitting $filename into $CHUNK_SIZE chunks..."
    split -b "$CHUNK_SIZE" --numeric-suffixes=0 --suffix-length=4 "$file" "$STAGING_DIR/${filename}.chunk."
    chunks=( "$STAGING_DIR/${filename}.chunk."* )
    chunk_prefix="$STAGING_DIR/"
  fi

  for chunk in "${chunks[@]}"; do
    chunk_name=$(basename "$chunk")
    enc_file="$ENCRYPTED_DIR/${chunk_name}.age"

    echo "Encrypting $chunk_name with age..."
    age -r "$(cat "$AGE_RECIPIENT_FILE")" -o "$enc_file" "$chunk"

    [[ "$chunk_prefix" ]] && rm "$chunk"
  done
done

log_summary "✅ Encryption complete. Files stored in $ENCRYPTED_DIR"

echo "Adding encrypted keys required for decryption. Secured by Emergency key:"

# Copies encrypted private key (vital for later decryption!) and its rasterized version to encrypted folder.
# Also copy over helpful scripts, especially decrypt.sh
cp "$KEYS_DIR/backup_age.key.gpg" "$ENCRYPTED_DIR/"
cp "$KEYS_DIR/backup_age.key.gpg.base64.txt" "$ENCRYPTED_DIR/"
cp "$KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.pgm" "$ENCRYPTED_DIR/"
cp $KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm "$ENCRYPTED_DIR/"
cp "$(dirname "$0")/shuffle_netpbm.py" "$ENCRYPTED_DIR/"
cp "$(dirname "$0")/assemble_chunks.py" "$ENCRYPTED_DIR/"
cp "$(dirname "$0")/undisperse.sh" "$ENCRYPTED_DIR/"
cp "$(dirname "$0")/decrypt.sh" "$ENCRYPTED_DIR/"

# Generate manifest of encrypted and copied over content
cd "$ENCRYPTED_DIR"

shopt -s nullglob
files=( $(find . -maxdepth 1 -type f ! -name 'checksums.sha256' | LC_ALL=C sort) )

# Filter out .par2 files - they can vary and we would find them only as leftover from previous full-runs at this stage
filtered_files=()
for file in "${files[@]}"; do
  [[ "$file" == *.par2 ]] && continue
  [[ -f "$file" ]] && filtered_files+=("$file")
done

if [ ${#filtered_files[@]} -eq 0 ]; then
  echo "❌ No files to checksum. Exiting."
  exit 1
fi

LC_ALL=C printf "%s\0" "${filtered_files[@]}" \
  | sort -z \
  | while IFS= read -r -d '' file; do
      shortname="${file#./}"  # strip leading './'
      sha256sum "$file" | sed "s|$file|$shortname|"
    done > checksums.sha256


log_summary "✅ Manifest generated at $ENCRYPTED_DIR/checksums.sha256"
