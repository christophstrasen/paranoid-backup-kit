#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBK_REPO_ROOT="$REPO_ROOT"
source "$SCRIPT_DIR/config_loader.sh"
pbk_load_config

RAID_DEV="$PBK_RAID_DEV"
RAID_NAME="$(basename "$RAID_DEV")"
CHALLENGE="$PBK_RAID_CHALLENGE"

if ! grep -q "^$RAID_NAME :" /proc/mdstat; then
  echo "Assembling RAID..."
  sudo mdadm --assemble "$RAID_DEV" $PBK_RAID_MEMBER_GLOB
else
  echo "$RAID_DEV already active. Skipping assembly."
fi

echo "🔐 Initializing YubiKey + password unlock for RAID..."
read -rsp "Enter the password to combine with your YubiKey: " PASSWORD
echo

YK_RESPONSE=$(ykchalresp -1 "$CHALLENGE") || {
  echo "❌ YubiKey not responding on slot 1."
  exit 1
}

KEY=$(echo -n "$PASSWORD$YK_RESPONSE" | sha256sum | awk '{print $1}')

echo "Please enter your EXISTING passphrase to authorize key addition to $RAID_DEV..."
echo -n "$KEY" | sudo cryptsetup luksAddKey "$RAID_DEV"
