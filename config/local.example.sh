#!/usr/bin/env bash

# Copy to config/local.sh and adjust for the machine running backups.

# Source locations collected into plain_staging/.
PBK_MAIN_SOURCE_DIR="$HOME/secure/plain_source" # Usually encrypted or otherwise inaccessible between backup runs.
PBK_OTP_SOURCE_DIR="$HOME/Pixel 8 Backups/Aegis" # Optional extra source directory, for example synced OTP exports.

# Privileged helper commands supplied by the user and called through pkexec.
PBK_VAULT_HELPER="myvault" # Expected to support: myvault unlock; myvault lock.
PBK_RAID_HELPER="myraid" # Expected to support: myraid unlock; myraid lock.

# Disk backup destination. PBK_RAID_HELPER should unlock/lock the storage backing this path.
PBK_DISC_DEST_DIR="/mnt/storage/security-backups"

# Google Drive rclone target. PBK_GDRIVE_REMOTE must match a section in keys/rclone.conf.gpg.
PBK_GDRIVE_REMOTE=""
PBK_GDRIVE_FOLDER=""

# Required encrypted backup artifacts checked by verify.sh.
# Override this list to match the critical files your backup must contain.
# PBK_BACKUP_REQUIRED_PATTERNS=(
#   "backup_age.key.gpg"
#   "backup_age.key.gpg.base64.txt"
#   "backup_age.key.gpg.base64.wrapped.txt.pgm"
#   "backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm"
#   "master-keys.txt.age"
#   "emergency-key.txt.age"
# )
#
# Advanced: PBK_SETUP_REQUIRED_PATTERNS controls check_setup.sh support-file
# checks. Override only if you intentionally renamed or moved key/config files.

# Advanced LUKS/YubiKey setup helpers.
# Only needed for scripts/luks-*-challenge-init.sh, not normal backup runs.
# These scripts add password+YubiKey-derived keys to LUKS keyslots.
# PBK_RAID_DEV="/dev/md0"
# PBK_RAID_MEMBER_GLOB="/dev/sd[ab]1"
# PBK_RAID_CHALLENGE="raid-challenge"
# PBK_VAULT_IMG="$HOME/secure.img"
# PBK_VAULT_CHALLENGE="myvault-challenge"
# Existing LUKS keyfile used only to authorize adding the derived vault key.
# Keep it outside this repo; remove or protect it after verifying the new unlock method.
# PBK_VAULT_AUTH_KEYFILE="$HOME/keyfile.txt"

# Optical media device used by write_dvd.sh.
PBK_DVD_DEVICE="/dev/sr0"
