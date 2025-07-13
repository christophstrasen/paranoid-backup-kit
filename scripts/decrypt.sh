#!/usr/bin/env bash
set -euo pipefail

ENCRYPTED_DIR="$(dirname "$0")/../encrypted"
RECOVERED_DIR="$(dirname "$0")/../plain_recovered"
TMP_KEY_FILE="/tmp/decryption_key"
BACKUP_KEY_ENC="backup_age.key.gpg"
CHECKSUM_FILE="$ENCRYPTED_DIR/checksums.sha256"

SKIP_CLEANUP=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-cleanup)
      SKIP_CLEANUP=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

: "${DEC_SUMMARY_FILE:=$(mktemp --tmpdir log-summary.XXXXXX)}"
export DEC_SUMMARY_FILE

log_summary() {
  local msg="$1"
  echo "$msg"
  echo "$msg" >> "$DEC_SUMMARY_FILE"
}

log_summary " "
log_summary " -- decrypt.sh --"

# --- Early exit if TMP_KEY_FILE exists ---
if [[ -f "$TMP_KEY_FILE" ]]; then
  log_summary "⚠️  WARNING: Temporary key file already exists at $TMP_KEY_FILE"
  log_summary "    Skipping key verification and decryption step."
else
  log_summary "Verifying backup key checksum..."

  expected_sum=$(awk -v file="$BACKUP_KEY_ENC" '$2 == file { print $1 }' "$CHECKSUM_FILE")
  if [[ -z "$expected_sum" ]]; then
    log_summary "❌ ERROR: No checksum found for $BACKUP_KEY_ENC. Aborting."
    exit 1
  fi

  actual_sum=$(sha256sum "$ENCRYPTED_DIR/$BACKUP_KEY_ENC" | cut -d' ' -f1)

  if [[ "$expected_sum" != "$actual_sum" ]]; then
    log_summary "⚠️ WARNING: Checksum mismatch for $BACKUP_KEY_ENC"
  else
    log_summary "✅ Checksum verified for $BACKUP_KEY_ENC"
  fi

  echo "Decrypting backup key..."
  gpg --output "$TMP_KEY_FILE" --decrypt "$ENCRYPTED_DIR/$BACKUP_KEY_ENC"
  chmod 600 "$TMP_KEY_FILE"
fi

age_or_chunk_errors=false
# --- Actual decryption loop ---
for file in "$ENCRYPTED_DIR"/*.age; do
  [ -f "$file" ] || continue
  base=$(basename "$file" .age)
  outfile="$RECOVERED_DIR/$base"
  echo "Decrypting $base..."

  if ! err_msg=$(age --decrypt -i "$TMP_KEY_FILE" -o "$outfile" "$file" 2>&1); then
  	age_or_chunk_errors=true
    log_summary "[!] Failed to decrypt $base"
    log_summary "    ↳ Exit code: $?"
    log_summary "    ↳ Error: $err_msg"
    continue
  fi
done


# -- concat and fixing any missing blocks with zeros

log_summary "🔧 Grouping decrypted chunks..."

find "$RECOVERED_DIR" -type f -name '*.chunk.[0-9][0-9][0-9][0-9]' -print0 |
  while IFS= read -r -d '' chunk_file; do
    prefix="${chunk_file%.chunk.[0-9][0-9][0-9][0-9]}"
    echo "$prefix"
  done | sort -u > /tmp/chunk_prefixes.txt



while IFS= read -r prefix; do
  input_glob="$RECOVERED_DIR/${prefix}.chunk.*"
  output_file="$RECOVERED_DIR/${prefix}"

  if compgen -G "$input_glob" > /dev/null; then
  	echo "🧩 Reassembling $prefix..."

  	mkdir -p "$RECOVERED_DIR/chunks"
	
  	while IFS= read -r line; do
  		echo "$line"
  		if [[ "$line" == *"Missing chunk"* ]]; then
    		log_summary "⚠️  $prefix: $line"
    		age_or_chunk_errors=true
  		fi
  	done < <( "./assemble_chunks.py" "$input_glob" -o "$output_file" --verbose 2>&1 )
	
  	# Move related chunks
  	set +e
  	for file in "$RECOVERED_DIR"/${prefix}.chunk.*; do
    	[ -e "$file" ] && mv "$file" "$RECOVERED_DIR/chunks/"
  	done
  	echo "Moved chunks into $RECOVERED_DIR/chunks/ in case you need them" 
  	set -e
  else
  	echo "❌ No files match: $input_glob"
  continue
fi
done < /tmp/chunk_prefixes.txt

# --- Cleanup ---
if $SKIP_CLEANUP; then
  log_summary "⚠️ Warning! --skip-cleanup used. Not removing key file: $TMP_KEY_FILE . Leaving this key file on disk is not recommend."
else
  rm -f "$TMP_KEY_FILE"
fi

# --- Info ---
echo 
log_summary "All done"

if [[ $age_or_chunk_errors = true ]]; then
	echo "❌⚠️❌ Encountered age decryption or missing chunks errors. Scroll up for details. This might not be fatal. Consider par2 parity repair and undisperse.sh"
fi

log_summary "ℹ️ In case of errors or missing chunks, run a parity check to recover first and then try decrypt again."
log_summary "ℹ️ To decode *.dispersed.* picture files run undisperse.sh."
log_summary "ℹ️ In case of truncation or difficulties opening use --recover flag of shuffle_netpbm.py."
