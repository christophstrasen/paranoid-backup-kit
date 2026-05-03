#!/usr/bin/env bash
set -euo pipefail

# Sends encrypted content to backup locations and handles archival logic.

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBK_REPO_ROOT="$REPO_ROOT"
ENC_DIR="$REPO_ROOT/encrypted"

source "$SCRIPT_DIR/runtime_guard.sh"
pbk_require_main_entrypoint
source "$SCRIPT_DIR/config_loader.sh"
pbk_load_config
source "$SCRIPT_DIR/summary.sh"

log_summary " "
log_summary " -- backup.sh --"

cd "$REPO_ROOT" || { echo "Failed to cd to repo root"; exit 1; }

RUN_GIT=false
RUN_DISK=false
RUN_B2=false
RUN_GDRIVE=false

if [[ $# -eq 0 ]]; then
  RUN_GIT=true
  RUN_DISK=true
  RUN_B2=true
  RUN_GDRIVE=true
else
  for arg in "$@"; do
    case "$arg" in
      --git) RUN_GIT=true ;;
      --disk) RUN_DISK=true ;;
      --b2) RUN_B2=true ;;
      --gdrive) RUN_GDRIVE=true ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: $0 [--git] [--disk] [--b2] [--gdrive]"
        exit 1
        ;;
    esac
  done
fi

# ─────────────── GIT BACKUP ───────────────
if $RUN_GIT; then
  log_summary " "
  log_summary " -- GIT BACKUP --"
  echo "git add ."
  git add .

  if git diff --cached --quiet; then
    echo "No changes to commit."
  else
    msg="Backup commit on $(date +'%Y-%m-%d %H:%M:%S')"
    git commit -m "$msg"

    echo "Pushing to remote..."
    git push
    log_summary "✅ git commit and push done."
  fi
fi

# ─────────────── DISK BACKUP ───────────────
if $RUN_DISK; then
  log_summary " "
  log_summary " -- DISK BACKUP --"

  raid_found_mounted=false
  if [ ! -d "$PBK_DISC_DEST_DIR" ]; then
    raid_found_mounted=true
    log_summary "🔑 Raid seems not mounted so attempting to mount and unlock"
    pkexec "$PBK_RAID_HELPER" unlock
  fi
  echo "Syncing current backup folders to $PBK_DISC_DEST_DIR/backup_1 ..."

  if [ ! -d "$PBK_DISC_DEST_DIR" ]; then
    echo "ERROR: Destination directory $PBK_DISC_DEST_DIR does not exist."
    exit 1
  fi

  if [ ! -w "$PBK_DISC_DEST_DIR" ]; then
    echo "ERROR: Destination directory $PBK_DISC_DEST_DIR is not writable."
    exit 1
  fi

  echo "Rotating backups..."
  rm -rf "$PBK_DISC_DEST_DIR/backup_4"
  mv "$PBK_DISC_DEST_DIR/backup_3" "$PBK_DISC_DEST_DIR/backup_4" 2>/dev/null || true
  mv "$PBK_DISC_DEST_DIR/backup_2" "$PBK_DISC_DEST_DIR/backup_3" 2>/dev/null || true
  mv "$PBK_DISC_DEST_DIR/backup_1" "$PBK_DISC_DEST_DIR/backup_2" 2>/dev/null || true

  mkdir -p "$PBK_DISC_DEST_DIR/backup_1/encrypted"
  touch "$PBK_DISC_DEST_DIR/backup_1"
  ln -sfn backup_1 "$PBK_DISC_DEST_DIR/backup_latest"

  rsync -av --delete "$ENC_DIR/" "$PBK_DISC_DEST_DIR/backup_1/encrypted/"
  if [ "$raid_found_mounted" = true ]; then
    log_summary "Locking and unmounting raid as this was the previous state. Write cache flushing in the background can delay this operation. Patience recommended."
    pkexec "$PBK_RAID_HELPER" lock
    if [ -d "$PBK_DISC_DEST_DIR" ]; then
      log_summary "⚠️ Warning, raid containing $PBK_DISC_DEST_DIR remains unlocked. Please check busy-state and lock manually."
    else
      log_summary "✅ Raid locked and unmounted."
    fi
  fi

  log_summary "✅ Disk Backup rotation and sync complete in $PBK_DISC_DEST_DIR/backup_1/encrypted/"
fi

# ─────────────── B2 BACKUP ───────────────
if $RUN_B2; then
  log_summary " "
  log_summary " -- B2 BACKUP --"
  if [ ! -f "$PBK_B2_ENV_GPG" ]; then
    echo "ERROR: Missing encrypted B2 credentials file: $PBK_B2_ENV_GPG"
    exit 1
  fi

  echo "Decrypting B2 credentials using YubiKey..."
  source /dev/stdin <<<"$(gpg --decrypt "$PBK_B2_ENV_GPG")"

  : "${B2_BUCKET_NAME:?not set}"
  : "${B2_APPLICATION_KEY:?not set}"
  : "${B2_KEY_ID:?not set}"

  DATE=$(date +%Y-%m-%d-%H-%M-%S)
  B2_PATH="$B2_BUCKET_NAME/$DATE"

  echo "Uploading encrypted backup to B2 → $B2_PATH"

  RCLONE_CONF=$(mktemp)
  cleanup_b2() {
    rm -f "$RCLONE_CONF"
  }
  trap cleanup_b2 EXIT INT TERM

  cat > "$RCLONE_CONF" <<EOF
[b2temp]
type = b2
account = $B2_KEY_ID
key = $B2_APPLICATION_KEY
EOF

  if ! rclone copy "$ENC_DIR" "b2temp:$B2_PATH" \
    --config "$RCLONE_CONF" \
    --progress; then
    log_summary "❌ Upload to B2 failed — aborting"
    exit 1
  fi

  log_summary "✅ Upload to B2 complete: $B2_PATH"

  log_summary "Checking for expired backups on B2 to delete..."

  CUTOFF_DATE=$(date -d "$PBK_B2_CLEANUP_NEVER_BEFORE_DAYS days ago" +%Y-%m-%d-%H-%M-%S)
  YOUNG_CUTOFF=$(date -d "$PBK_B2_EXPECTED_BACKUP_INTERVAL_DAYS days ago" +%Y-%m-%d-%H-%M-%S)

  mapfile -t all_dates < <(rclone lsf "b2temp:$B2_BUCKET_NAME" \
    --config "$RCLONE_CONF" \
    --dirs-only | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}/$' | sed 's|/$||' | sort)

  NUM_TOTAL=${#all_dates[@]}
  b2_cleaning=true

  if (( NUM_TOTAL < PBK_B2_HARD_MINIMUM_BACKUPS_RETAINED )); then
    log_summary "⚠️  Too few B2 backups ($NUM_TOTAL) — skipping deletion"
    b2_cleaning=false
  fi

  has_young=false
  for d in "${all_dates[@]}"; do
    if [[ "$d" > "$YOUNG_CUTOFF" ]]; then
      has_young=true
      break
    fi
  done

  if [ "$has_young" = false ]; then
    log_summary "⚠️ No recent B2 backup (within $PBK_B2_EXPECTED_BACKUP_INTERVAL_DAYS days) — aborting deletion. Recommend you check for silent backup failures."
    b2_cleaning=false
  fi

  if [ "$b2_cleaning" = true ]; then
    for folder_date in "${all_dates[@]}"; do
      if [[ "$folder_date" < "$CUTOFF_DATE" ]]; then
        echo "🔻 Candidate for deletion: $folder_date < $CUTOFF_DATE"
        if rclone purge "b2temp:$B2_BUCKET_NAME/$folder_date" \
          --config "$RCLONE_CONF"; then
          log_summary "🗑️ Deleted B2 $folder_date"
        else
          log_summary "⚠️ Could not delete B2 $folder_date — retention may still be active"
        fi
      else
        log_summary "🛡️ Keeping B2 $folder_date (newer than cutoff)"
      fi
    done
  fi

  cleanup_b2
  trap - EXIT INT TERM
fi

# ─────────────── GOOGLE DRIVE BACKUP ───────────────
if $RUN_GDRIVE; then
  log_summary " "
  log_summary " -- GDRIVE BACKUP --"

  : "${PBK_GDRIVE_REMOTE:?Set PBK_GDRIVE_REMOTE in config/local.sh}"
  : "${PBK_GDRIVE_FOLDER:?Set PBK_GDRIVE_FOLDER in config/local.sh}"

  DATE=$(date +%Y-%m-%d)
  SOURCE_DIR="$ENC_DIR"
  DRIVE_TARGET_PATH="$PBK_GDRIVE_REMOTE:$PBK_GDRIVE_FOLDER/$DATE"

  TEMP_RCLONE_CONF="$(mktemp --tmpdir rclone-conf-XXXXXX.conf)"
  cleanup_gdrive() {
    if [[ -f "$TEMP_RCLONE_CONF" ]]; then
      shred -u "$TEMP_RCLONE_CONF"
      log_summary "🧹 Cleaned up Google Drive rclone config"
    fi
  }
  trap cleanup_gdrive EXIT INT TERM

  echo "Decrypting rclone config into $TEMP_RCLONE_CONF"
  gpg --quiet --decrypt "$PBK_RCLONE_CONF_GPG" > "$TEMP_RCLONE_CONF"

  echo "Uploading encrypted backup to Google Drive → $DRIVE_TARGET_PATH"
  if ! rclone copy "$SOURCE_DIR" "$DRIVE_TARGET_PATH" \
    --progress \
    --config "$TEMP_RCLONE_CONF"; then
    log_summary "❌ Upload to Google Drive failed"
    exit 1
  fi

  cleanup_gdrive
  trap - EXIT INT TERM

  log_summary "✅ Upload to Google Drive complete: $DRIVE_TARGET_PATH"
fi
