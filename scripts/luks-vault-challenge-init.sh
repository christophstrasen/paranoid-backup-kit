#!/usr/bin/env bash
set -euo pipefail

VAULT_IMG="$HOME/secure.img"
CHALLENGE="myvault-challenge"
AUTH_KEYFILE="$HOME/keyfile.txt"  # Existing unlock key (e.g. original password)

echo "🔐 Setting up LUKS unlock with YubiKey slot 1 + password..."
read -rsp "Enter the password to combine with your YubiKey: " PASSWORD
echo

YK_RESPONSE=$(ykchalresp -1 "$CHALLENGE") || {
  echo "❌ YubiKey not responding on slot 1."
  exit 1
}

KEY=$(echo -n "$PASSWORD$YK_RESPONSE" | sha256sum | awk '{print $1}')

# Provide the NEW key via stdin, and use the OLD key from file to authorize
echo -n "$KEY" | sudo cryptsetup luksAddKey "$VAULT_IMG" --key-file="$AUTH_KEYFILE"

echo "✅ Setup complete. Your vault can now be unlocked using your YubiKey + password."
