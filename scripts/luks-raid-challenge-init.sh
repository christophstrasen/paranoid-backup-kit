#!/usr/bin/env bash
set -euo pipefail

RAID_DEV="/dev/md0"
CHALLENGE="raid-challenge"

if ! grep -q '^md0 :' /proc/mdstat; then
  echo "Assembling RAID..."
  sudo mdadm --assemble "$RAID_DEV" /dev/sd[ab]1
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
echo "$KEY" | sudo cryptsetup luksAddKey "$RAID_DEV" --key-file=skey.txt
