#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEYS_DIR="$REPO_ROOT/keys"

missing=false

# Required external tools
required_tools=(
  age gpg par2 magick pdftoppm git rclone rsync pkexec mdadm cryptsetup \
  ykchalresp mkisofs growisofs dvd+rw-mediainfo dvd+rw-format bc xxd pv python3
)

# Helper commands expected by other scripts
required_helpers=(myvault myraid)

# Required key files
required_files=(
  "$KEYS_DIR/backup_age.key.gpg"
  "$KEYS_DIR/backup_age.key.gpg.base64.txt"
  "$KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt"
  "$KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.pgm"
  $KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm
  "$KEYS_DIR/backup_pub.age"
  "$KEYS_DIR/b2-security-backups-write.env.gpg"
  "$KEYS_DIR/rclone.conf.gpg"
  "$KEYS_DIR/key_to_pgm.sh"
)

for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ Missing tool: $tool"
    missing=true
  fi
done

for helper in "${required_helpers[@]}"; do
  if ! command -v "$helper" >/dev/null 2>&1; then
    echo "❌ Missing helper command: $helper"
    missing=true
  fi
done

for f in "${required_files[@]}"; do
  if [ ! -f "$f" ]; then
    echo "❌ Missing file: $f"
    missing=true
  fi
done

if ! $missing; then
  echo "✅ Setup looks good."
else
  echo "Some checks failed." >&2
  echo
  echo "Required tools:" >&2
  printf '  %s\n' "${required_tools[@]}" >&2
  echo
  echo "Required helper commands:" >&2
  printf '  %s\n' "${required_helpers[@]}" >&2
  echo
  echo "Required files (wildcards expanded. dispersed pgm file name is OK to differ):" >&2
  printf '  %s\n' "${required_files[@]}" >&2
  exit 1
fi
