#!/usr/bin/env bash
set -euo pipefail

# Instruction: Edit this script to your hearts content. The goal is to place files in "plain_staging".
#
# This file unlocks and collects from the potential sources of secrets
# Per design staging gets cleared in the main.sh encryption workflow
# recommended single source of truth to only mount for the duration of collect.sh - see "lock/unlock" calls below

MAIN_SOURCE_DIR="$HOME/secure/plain_source"    # Instruction: change to your source of truth for general secrets
OTP_SOURCE_DIR="$HOME/Pixel 8 Backups/Aegis"   # Instruction: change to your source of truth for 2-factor OTP seeds e.g. Aegis backups. You might want to use "syncthing" from your phone.
STAGING_DIR="$(dirname "$0")/../plain_staging"

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- collect.sh --"

log_summary "Collecting files to add to plain_staging"

# set up staging
mkdir -p "$STAGING_DIR"

#collect from main vault
log_summary "🔑 Unlocking vault for collection"
pkexec myvault unlock # Instruction: NOT SUPPLIED - bring your own vault lock/unlock

if [ ! -d "$MAIN_SOURCE_DIR" ]; then
  log_summary "⚠️ Main Source directory $MAIN_SOURCE_DIR is not accessible."
  echo "Proceed with whatever is already in $STAGING_DIR? [y/N]"
  read -r confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "❌ Aborting."
    exit 1
  fi
else
 
  shopt -s nullglob
  source_files=("$MAIN_SOURCE_DIR"/*)
  shopt -u nullglob

  if [ ${#source_files[@]} -eq 0 ]; then
    log_summary "⚠️ No files found in $MAIN_SOURCE_DIR."
    echo "Proceed with whatever is already in $STAGING_DIR? [y/N]"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Aborting."
      exit 1
    fi
  else
    log_summary "🔄 Copying files from $MAIN_SOURCE_DIR to $STAGING_DIR..."
    cp -uv "$MAIN_SOURCE_DIR"/* "$STAGING_DIR/"
  fi
fi
log_summary "Locking vault after collection"
pkexec myvault lock


if [ -d "$MAIN_SOURCE_DIR" ]; then
  log_summary "⚠️ Warning, Main Source directory $MAIN_SOURCE_DIR remains unlocked. Please check busy-state and lock manually."
fi


# OTP collection
find "$OTP_SOURCE_DIR" -type f | while read -r filepath; do
  filename=$(basename "$filepath")
  dest="$STAGING_DIR/$filename"

  log_summary "Copying '$filepath' → '$filename' (overwriting if exists)"
  cp -- "$filepath" "$dest"
done

log_summary "✅ All files collected into $STAGING_DIR"

