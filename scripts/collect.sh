#!/usr/bin/env bash
set -euo pipefail

# Instruction: Edit this script to your hearts content. The goal is to place files in "plain_staging".
#
# This file unlocks and collects from the potential sources of secrets
# Per design staging gets cleared in the main.sh encryption workflow
# recommended single source of truth to only mount for the duration of collect.sh - see "lock/unlock" calls below

SCRIPT_DIR="$(dirname "$0")"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBK_REPO_ROOT="$REPO_ROOT"
STAGING_DIR="$REPO_ROOT/plain_staging"

source "$SCRIPT_DIR/runtime_guard.sh"
pbk_require_main_entrypoint
source "$SCRIPT_DIR/config_loader.sh"
pbk_load_config
source "$SCRIPT_DIR/summary.sh"

log_summary " "
log_summary " -- collect.sh --"

log_summary "Collecting files to add to plain_staging"

# set up staging
mkdir -p "$STAGING_DIR"

#collect from main vault
log_summary "🔑 Unlocking vault for collection"
pkexec "$PBK_VAULT_HELPER" unlock

if [ ! -d "$PBK_MAIN_SOURCE_DIR" ]; then
  log_summary "⚠️ Main Source directory $PBK_MAIN_SOURCE_DIR is not accessible."
  echo "Proceed with whatever is already in $STAGING_DIR? [y/N]"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Aborting."
    exit 1
  fi
else
 
  shopt -s nullglob
  source_files=("$PBK_MAIN_SOURCE_DIR"/*)
  shopt -u nullglob

  if [ ${#source_files[@]} -eq 0 ]; then
    log_summary "⚠️ No files found in $PBK_MAIN_SOURCE_DIR."
    echo "Proceed with whatever is already in $STAGING_DIR? [y/N]"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Aborting."
      exit 1
    fi
  else
    log_summary "🔄 Copying files from $PBK_MAIN_SOURCE_DIR to $STAGING_DIR..."
    cp -uv "$PBK_MAIN_SOURCE_DIR"/* "$STAGING_DIR/"
  fi
fi
log_summary "Locking vault after collection"
pkexec "$PBK_VAULT_HELPER" lock


if [ -d "$PBK_MAIN_SOURCE_DIR" ]; then
  log_summary "⚠️ Warning, Main Source directory $PBK_MAIN_SOURCE_DIR remains unlocked. Please check busy-state and lock manually."
fi


# OTP collection
find "$PBK_OTP_SOURCE_DIR" -type f | while read -r filepath; do
  filename=$(basename "$filepath")
  dest="$STAGING_DIR/$filename"

  log_summary "Copying '$filepath' → '$filename' (overwriting if exists)"
  cp -- "$filepath" "$dest"
done

log_summary "✅ All files collected into $STAGING_DIR"
