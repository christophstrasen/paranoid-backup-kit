#!/usr/bin/env bash

# Committed defaults. Override machine-specific values in config/local.sh.

: "${PBK_REPO_ROOT:?PBK_REPO_ROOT must be set before sourcing defaults.sh}"

PBK_KEYS_DIR="${PBK_KEYS_DIR:-$PBK_REPO_ROOT/keys}"

PBK_MAIN_SOURCE_DIR="${PBK_MAIN_SOURCE_DIR:-$HOME/secure/plain_source}"
PBK_OTP_SOURCE_DIR="${PBK_OTP_SOURCE_DIR:-$HOME/Pixel 8 Backups/Aegis}"

PBK_VAULT_HELPER="${PBK_VAULT_HELPER:-myvault}"
PBK_RAID_HELPER="${PBK_RAID_HELPER:-myraid}"

PBK_DISC_DEST_DIR="${PBK_DISC_DEST_DIR:-/mnt/storage/security-backups}"

PBK_B2_CLEANUP_NEVER_BEFORE_DAYS="${PBK_B2_CLEANUP_NEVER_BEFORE_DAYS:-90}"
PBK_B2_EXPECTED_BACKUP_INTERVAL_DAYS="${PBK_B2_EXPECTED_BACKUP_INTERVAL_DAYS:-30}"
PBK_B2_HARD_MINIMUM_BACKUPS_RETAINED="${PBK_B2_HARD_MINIMUM_BACKUPS_RETAINED:-5}"

PBK_GDRIVE_REMOTE="${PBK_GDRIVE_REMOTE:-}"
PBK_GDRIVE_FOLDER="${PBK_GDRIVE_FOLDER:-}"

PBK_DVD_DEVICE="${PBK_DVD_DEVICE:-/dev/sr0}"
PBK_DVD_WORKING_DIR="${PBK_DVD_WORKING_DIR:-/tmp/dvdbackup}"

PBK_RAID_DEV="${PBK_RAID_DEV:-/dev/md0}"
PBK_RAID_MEMBER_GLOB="${PBK_RAID_MEMBER_GLOB:-/dev/sd[ab]1}"
PBK_RAID_CHALLENGE="${PBK_RAID_CHALLENGE:-raid-challenge}"
PBK_VAULT_IMG="${PBK_VAULT_IMG:-$HOME/secure.img}"
PBK_VAULT_CHALLENGE="${PBK_VAULT_CHALLENGE:-myvault-challenge}"
PBK_VAULT_AUTH_KEYFILE="${PBK_VAULT_AUTH_KEYFILE:-$HOME/keyfile.txt}"

pbk_finalize_config() {
  PBK_KEYS_DIR="${PBK_KEYS_DIR:-$PBK_REPO_ROOT/keys}"
  PBK_B2_ENV_GPG="${PBK_B2_ENV_GPG:-$PBK_KEYS_DIR/b2-security-backups-write.env.gpg}"
  PBK_RCLONE_CONF_GPG="${PBK_RCLONE_CONF_GPG:-$PBK_KEYS_DIR/rclone.conf.gpg}"

  if ! declare -p PBK_REQUIRED_HELPERS >/dev/null 2>&1 || [[ ${#PBK_REQUIRED_HELPERS[@]} -eq 0 ]]; then
    PBK_REQUIRED_HELPERS=("${PBK_VAULT_HELPER}" "${PBK_RAID_HELPER}")
  fi

  if ! declare -p PBK_REQUIRED_CONFIG_VARS >/dev/null 2>&1 || [[ ${#PBK_REQUIRED_CONFIG_VARS[@]} -eq 0 ]]; then
    PBK_REQUIRED_CONFIG_VARS=(PBK_GDRIVE_REMOTE PBK_GDRIVE_FOLDER)
  fi

  # Required kit support files checked by check_setup.sh. Override only if you
  # intentionally rename or move core key/config support files.
  if ! declare -p PBK_SETUP_REQUIRED_PATTERNS >/dev/null 2>&1 || [[ ${#PBK_SETUP_REQUIRED_PATTERNS[@]} -eq 0 ]]; then
    PBK_SETUP_REQUIRED_PATTERNS=(
      "$PBK_KEYS_DIR/backup_age.key.gpg"
      "$PBK_KEYS_DIR/backup_age.key.gpg.base64.txt"
      "$PBK_KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt"
      "$PBK_KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.pgm"
      "$PBK_KEYS_DIR/backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm"
      "$PBK_KEYS_DIR/backup_pub.age"
      "$PBK_B2_ENV_GPG"
      "$PBK_RCLONE_CONF_GPG"
      "$PBK_KEYS_DIR/key_to_pgm.sh"
    )
  fi

  # Required encrypted backup artifacts checked by verify.sh. These include
  # project-critical defaults and personal files users may want to override.
  if ! declare -p PBK_BACKUP_REQUIRED_PATTERNS >/dev/null 2>&1 || [[ ${#PBK_BACKUP_REQUIRED_PATTERNS[@]} -eq 0 ]]; then
    PBK_BACKUP_REQUIRED_PATTERNS=(
      "backup_age.key.gpg"
      "backup_age.key.gpg.base64.txt"
      "backup_age.key.gpg.base64.wrapped.txt.pgm"
      "backup_age.key.gpg.base64.wrapped.txt.dispersed.*.pgm"
      "master-keys.txt.age"
      "master-keys.txt.base64.age"
      "master-keys.txt.base64.wrapped.dispersed.*.age"
      "emergency-key.txt.age"
      "emergency-key.txt.base64.age"
      "emergency-key.txt.base64.wrapped.dispersed.*.age"
    )
  fi
}
