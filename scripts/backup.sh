#!/usr/bin/env bash
set -euo pipefail

# Sends the encrypted content to various backup locations and handles some of their archival logic
# Probably the least "nice" script and could be substituted by a more powerful tool

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENC_DIR="$REPO_ROOT/encrypted"
DISC_DEST_DIR="/mnt/storage/security-backups" # Instruction: Change this to the destionation suitable for storage
GPG_ENV_FILE="$REPO_ROOT/keys/b2-security-backups-write.env.gpg" # Instruction: Change if your b2 environment setup is stored elsewhere

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- backup.sh --"

cd "$REPO_ROOT" || { echo "Failed to cd to repo root"; exit 1; }

# Parse arguments
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
      --git)  RUN_GIT=true ;;
      --disk) RUN_DISK=true ;;
      --b2)   RUN_B2=true ;;
      --gdrive)   RUN_GDRIVE=true ;;
      *)
        echo "Unknown option: $arg"
        echo "Usage: $0 [--git] [--disk] [--b2]"
        exit 1
        ;;
    esac
  done
fi

# ─────────────── GIT BACKUP ───────────────
# Instruction: It is probably a good idea to first anticipate if an encrypted asset could be too big for git. Check the provided .gitignore
# Instruction: If you want to test before commiting go manually through "collect", "rasterize", "encrypt" and then check git status

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
  if [ ! -d "$DISC_DEST_DIR" ]; then
    raid_found_mounted=true
    log_summary "🔑 Raid seems not mounted so attempting to mount and unlock"
    pkexec myraid unlock # Instruction: NOT SUPPLIED - bring your own raid lock/unlock
  fi
  echo "Syncing current backup folders to $DISC_DEST_DIR/backup_1 ..."

  if [ ! -d "$DISC_DEST_DIR" ]; then
    echo "ERROR: Destination directory $DISC_DEST_DIR does not exist."
    exit 1
  fi

  if [ ! -w "$DISC_DEST_DIR" ]; then
    echo "ERROR: Destination directory $DISC_DEST_DIR is not writable."
    exit 1
  fi

  echo "Rotating backups..."
  rm -rf "$DISC_DEST_DIR/backup_4"
  mv "$DISC_DEST_DIR/backup_3" "$DISC_DEST_DIR/backup_4" 2>/dev/null || true
  mv "$DISC_DEST_DIR/backup_2" "$DISC_DEST_DIR/backup_3" 2>/dev/null || true
  mv "$DISC_DEST_DIR/backup_1" "$DISC_DEST_DIR/backup_2" 2>/dev/null || true

  mkdir -p "$DISC_DEST_DIR/backup_1/encrypted"
  touch "$DISC_DEST_DIR/backup_1"
  ln -sfn backup_1 "$DISC_DEST_DIR/backup_latest"

  rsync -av --delete "$ENC_DIR/" "$DISC_DEST_DIR/backup_1/encrypted/"
  if [ "$raid_found_mounted" = true ]; then
    log_summary "Locking and unmounting raid as this was the previous state. Write cache flushing in the background can delay this operation. Patience recommended."
    pkexec myraid lock
    if [ -d "$DISC_DEST_DIR" ]; then
      log_summary "⚠️ Warning, raid containing $DISC_DEST_DIR remains unlocked. Please check busy-state and lock manually."
    else
      log_summary "✅ Raid locked and unmounted." 
    fi
  fi

  log_summary "✅ Disk Backup rotation and sync complete in $DISC_DEST_DIR/backup_1/encrypted/"
fi

# ─────────────── B2 BACKUP ───────────────
if $RUN_B2; then
  # Instruction: Change the variables to suit your backup strategy
	cleanup_never_before_days=90 #days. Backups younger than this will not be touched
	expected_backup_intervals=30 #days. Used to warn and stop backup deletion if no fresher backup exists
	hard_minimum_backups_retained=5 #count of full backups to always keep, ignoring time-based rules
  log_summary " "
  log_summary " -- B2 BACKUP --"
  if [ ! -f "$GPG_ENV_FILE" ]; then
    echo "ERROR: Missing encrypted B2 credentials file: $GPG_ENV_FILE"
    exit 1
  fi

  echo "Decrypting B2 credentials using YubiKey..."
  source /dev/stdin <<<"$(gpg --decrypt "$GPG_ENV_FILE")" # Instruction: Change it if your b2 environment setup file is not protected

	# Instruction: Ensure that your b2 environment file exports B2_BUCKET_NAME, B2_APPLICATION_KEY and B2_KEY_ID
  : "${B2_BUCKET_NAME:?not set}"
  : "${B2_APPLICATION_KEY:?not set}"
  : "${B2_KEY_ID:?not set}"

  DATE=$(date +%Y-%m-%d-%H-%M-%S) # Date handling here is logically sunced with the date checks further below, so be careful if changing
  B2_PATH="$B2_BUCKET_NAME/$DATE"

  echo "Uploading encrypted backup to B2 → $B2_PATH"

  # creates a temporary rclone conf from the B2 information but traps it in rm unless you SIGKILL
  RCLONE_CONF=$(mktemp)
  cleanup() {
  	rm -f "$RCLONE_CONF"
	}
	trap cleanup EXIT
	trap cleanup INT TERM

  cat > "$RCLONE_CONF" <<EOF
[b2temp]
type = b2
account = $B2_KEY_ID
key = $B2_APPLICATION_KEY
EOF

  if ! rclone copy "$ENC_DIR" "b2temp:$B2_PATH" \
    --config "$RCLONE_CONF" \
    --progress; then
    log_summary  "❌ Upload to B2 failed — aborting"
    exit 1
  fi

  log_summary "✅ Upload to B2 complete: $B2_PATH"

  # B2 logic to clean-up.
  log_summary "Checking for expired backups on B2 to delete..."

  CUTOFF_DATE=$(date -d "$cleanup_never_before_days days ago" +%Y-%m-%d-%H-%M-%S) 
  YOUNG_CUTOFF=$(date -d "$expected_backup_intervals days ago" +%Y-%m-%d-%H-%M-%S)

  mapfile -t all_dates < <(rclone lsf "b2temp:$B2_BUCKET_NAME" \
    --config "$RCLONE_CONF" \
    --dirs-only | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}/$' | sed 's|/$||' | sort)

  NUM_TOTAL=${#all_dates[@]}
  b2_cleaning=true
  
  if (( NUM_TOTAL < $hard_minimum_backups_retained )); then
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
    log_summary "⚠️ No recent B2 backup (within 30 days) — aborting deletion. Recommend you check for silent backup failures."
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
fi


# ─────────────── GOOGLE DRIVE BACKUP ───────────────
if $RUN_GDRIVE; then
  log_summary " "
  log_summary " -- GDRIVE BACKUP --"

	# Instruction: Provide your own gdrive setup variables here or ensure it is included in the /keys/rclone.conf.gpg
  : "${GDRIVE_REMOTE:=your_gdrive_remote}"
  : "${GDRIVE_FOLDER:=your_fold}"

  DATE=$(date +%Y-%m-%d)
  SOURCE_DIR="$ENC_DIR"
  DRIVE_TARGET_PATH="$GDRIVE_REMOTE:$GDRIVE_FOLDER/$DATE"

  # Use a secure temp file
  TEMP_RCLONE_CONF="$(mktemp --tmpdir rclone-conf-XXXXXX.conf)"

  # Add cleanup trap
  cleanup_gdrive() {
    if [[ -f "$TEMP_RCLONE_CONF" ]]; then
      shred -u "$TEMP_RCLONE_CONF"
      log_summary "🧹 Cleaned up Google Drive rclone config"
    fi
  }
  trap cleanup_gdrive EXIT INT TERM

  echo "Decrypting rclone config into $TEMP_RCLONE_CONF"
  gpg --quiet --decrypt "$REPO_ROOT/keys/rclone.conf.gpg" > "$TEMP_RCLONE_CONF" # Instruction: change if you have a different rclone source or don't encrypt it.
  # Maybe your rclone is loaded in your user-session per default (less safe) then you can simplify the entire section

  echo "Uploading encrypted backup to Google Drive → $DRIVE_TARGET_PATH"
  if ! rclone copy "$SOURCE_DIR" "$DRIVE_TARGET_PATH" \
      --progress \
      --config "$TEMP_RCLONE_CONF"; then
    log_summary "❌ Upload to Google Drive failed"
    exit 1
  fi

  log_summary "✅ Upload to Google Drive complete: $DRIVE_TARGET_PATH"
fi


