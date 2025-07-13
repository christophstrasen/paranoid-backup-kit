#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
ENC_DIR="$SCRIPT_DIR/../encrypted"
source "$SCRIPT_DIR/summary.sh"

# Clean up on exit
trap 'rm -f "$SUMMARY_FILE"' EXIT

while true; do
  echo
  echo "Backup Utility - Select an option:"
  echo "  m + ENTER : Make encrypted backups (collect, rasterize, encrypt, addparity, verify, backup, cleanup)"
  echo "  s + ENTER : Check Setup fi missing tools or files"
  echo "  c + ENTER : Cleanup plaintext staging (cleanup.sh)"
  echo "  w + ENTER : Write encrypted files to DVD medium"
  echo "  d + ENTER : Decrypt backups (decrypt.sh)"
  echo "  u + ENTER : Undisperse recovered images (undisperse.sh)"
  echo "  q + ENTER : Quit"
  echo
  read -rp "Enter choice (m/s/c/w/d/u/q): " choice

  case "$choice" in
    m|M)
      echo "Running full encrypted backup process..."
      bash "$SCRIPT_DIR/collect.sh"
      bash "$SCRIPT_DIR/rasterize.sh"
      bash "$SCRIPT_DIR/encrypt.sh"
      bash "$SCRIPT_DIR/addparity.sh"
      bash "$SCRIPT_DIR/verify.sh"
      bash "$SCRIPT_DIR/backup.sh"
      bash "$SCRIPT_DIR/cleanup.sh"
      echo "Encrypted backups complete."
      # At end: print summary
      if [[ -s "$SUMMARY_FILE" ]]; then
	echo
	echo "-------------------"
	echo "📋 Summary:"
	sed 's/^/  /' "$SUMMARY_FILE"
      fi
      ;;
    s|S)
      echo "Checking Setup"
      bash "$SCRIPT_DIR/check_setup.sh"
      echo "Setup check complete."
      ;;
    c|C)
      echo "Running cleanup of plaintext staging..."
      bash "$SCRIPT_DIR/cleanup.sh"
      echo "Cleanup complete."
      ;;
    w|W)
      echo "Writing to dvd medium"
      bash "$SCRIPT_DIR/write_dvd.sh" "$ENC_DIR"
      echo "Setup check complete."
      ;;
    d|D)
      echo "Running decrypt to recover plaintext files..."
      bash "$SCRIPT_DIR/decrypt.sh"
      echo "Decryption complete."
      ;;
    u|U)
      echo "Running undisperse on recovered but spatially dispersed plaintext files .dispersed.seed<id>.(pgm|ppm)."
      bash "$SCRIPT_DIR/undisperse.sh"
      echo "Undisperse complete."
      ;;
    q|Q)
      echo "Quitting."
      exit 0
      ;;
    *)
      echo "Invalid choice: $choice"
      ;;
  esac
done

