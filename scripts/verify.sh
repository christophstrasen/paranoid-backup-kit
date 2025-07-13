#!/usr/bin/env bash
set -euo pipefail


# Instruction: Edit this script's "REQUIRED_FILES" section in case you have a different name/location for the age public-key.
# Instruction: Remove the existing/add your own critical assets in "REQUIRED_FILES" section. 
# 
# Tries to validate if encryption and parity-adding worked well.


SCRIPT_DIR="$(dirname "$0")"
PLAIN_DIR="$SCRIPT_DIR/../plain_staging"
ENC_DIR="$SCRIPT_DIR/../encrypted"

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- verify.sh --"

cd "$ENC_DIR"


# check if parity was created at all and runs it to check.
# TODO: compare parity dates with last file writes for a quick check?
log_summary "Verifying parity backup in $ENC_DIR ..."

if [ ! -f backup.par2 ]; then
  log_summary "❌ ERROR: parity file backup.par2 not found!"
  exit 1
fi

if ! par2 verify backup.par2; then
  log_summary "❌ ERROR: Parity verification failed!"
  exit 1
fi

shopt -s nullglob
errors=0

# Check if every plaintext file is meaningfully represented in the encrypted outcome
for plain_file in "$PLAIN_DIR"/*; do
  [ -f "$plain_file" ] || continue
  base=$(basename "$plain_file")

  # Gather encrypted artifacts for the given plain file: Its either chunks or a single .age file
  enc_files=()

  # Add chunks for the file if they exist
  while IFS= read -r -d '' f; do
    enc_files+=("$f")
  done < <(find "$ENC_DIR" -maxdepth 1 -type f -name "${base}.chunk*.age" -print0)

  # Add non-chunked .age file if it exists
  if [ -f "$ENC_DIR/${base}.age" ]; then
    enc_files+=("$ENC_DIR/${base}.age")
  fi

  if [ "${#enc_files[@]}" -eq 0 ]; then
    log_summary "❌ Missing encrypted file(s) for $base"
    errors=$((errors+1))
    continue
  fi

  # The encrypted version may never be smaller than the plain
  # Some encryption has inbuilt compression, age has not - and that should help recoverability, in theory.
  size_plain=$(stat --printf="%s\n" "$plain_file" | awk '{s+=$1} END {print s}')
  size_enc=$(stat --printf="%s\n" "${enc_files[@]}" | awk '{s+=$1} END {print s}')
  size_percent=$(awk -v a="$size_enc" -v b="$size_plain" 'BEGIN { if (b > 0) printf "%.1f", (a / b) * 100; else print "0.0" }')

  if [ "$size_enc" -lt "$size_plain" ]; then
    log_summary "❌ Bad size check with $size_percent% plain: $size_plain vs enc: $size_enc bytes for $base - This smells bad so breaking"
    errors=$((errors+1))
  else
  	echo "Good size check $size_percent% plain: $size_plain vs enc: $size_enc bytes for $base"
  fi
done


if [ "$errors" -ne 0 ]; then
  log_summary "❌ Detected $errors issues in encryption outputs!"
  exit 1
else
  log_summary "✅ All plaintext files have valid corresponding encrypted files or encrypted chunks."
fi


log_summary "Checking presence of encrypted keys."

# Define required files
REQUIRED_FILES=(
	# Vital for decryption! - gets copied in from the "keys" directory during encrypt.sh
  "backup_age.key.gpg"
  "backup_age.key.gpg.base64.txt"
  "backup_age.key.gpg.base64.wrapped.txt.pgm"
  "backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm"
  
   # Instruction: change sser-specified vital keys or assets to your liking
   # These normally come in via the regular flow landing in plain_staging and then getting encrypted
  "master-keys.txt.age"
  "master-keys.txt.base64.age"
  "master-keys.txt.base64.wrapped.dispersed.*.age"
  "emergency-key.txt.age"
  "emergency-key.txt.base64.age"
  "emergency-key.txt.base64.wrapped.dispersed.*.age"
)

# Look for required files
missing=false
shopt -s nullglob
for pattern in "${REQUIRED_FILES[@]}"; do
  unset matches  # prevent stale data
  matches=("$ENC_DIR"/$pattern)

  # Ensure match is at least one file and not literal
  if [ "${#matches[@]}" -eq 0 ]; then
    log_summary "❌ MISSING required: $pattern"
    missing=true
  else
    found=false
    for f in "${matches[@]}"; do
      if [ -f "$f" ]; then
        found=true
        break
      fi
    done

    if $found; then
      log_summary "✅ Found required: $pattern"
    else
      log_summary "❌ MISSING required: $pattern (match exists but not a regular file)"
      missing=true
    fi
  fi
done
shopt -u nullglob

if [ "$missing" = true ]; then
  log_summary "❌ ERROR: One or more required key files are missing. Aborting verification."
  exit 1
fi

# Checksum verification of the encrypted files stored in the folder. 
# Should be a rare error case this so soon after encryption
if [ -f checksums.sha256 ]; then
  echo "Verifying SHA256 checksums against manifest..."

  if ! sha256sum --check --status checksums.sha256; then
    log_summary "❌ ERROR: Checksum verification failed!"
    exit 1
  fi

  log_summary "✅ Checksum verification passed."
else
  log_summary "⚠️ No checksum manifest found, skipping checksum verification."
fi
