#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PBK_REPO_ROOT="$REPO_ROOT"

source "$SCRIPT_DIR/runtime_guard.sh"
pbk_require_main_entrypoint
source "$SCRIPT_DIR/config_loader.sh"
pbk_load_config

missing=false

# Required external tools
required_tools=(
  age gpg par2 magick pdftoppm git rclone rsync pkexec mdadm cryptsetup \
  ykchalresp mkisofs growisofs dvd+rw-mediainfo dvd+rw-format bc xxd pv python3
)

for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ Missing tool: $tool"
    missing=true
  fi
done

for helper in "${PBK_REQUIRED_HELPERS[@]}"; do
  if ! command -v "$helper" >/dev/null 2>&1; then
    echo "❌ Missing helper command: $helper"
    missing=true
  fi
done

for var_name in "${PBK_REQUIRED_CONFIG_VARS[@]}"; do
  if [[ -z "${!var_name:-}" ]]; then
    echo "❌ Missing config value: $var_name"
    missing=true
  fi
done

for pattern in "${PBK_SETUP_REQUIRED_PATTERNS[@]}"; do
  if [[ "$pattern" == *"*"* || "$pattern" == *"?"* || "$pattern" == *"["* ]]; then
    if ! compgen -G "$pattern" >/dev/null; then
      echo "❌ Missing file matching: $pattern"
      missing=true
    fi
  elif [ ! -f "$pattern" ]; then
    echo "❌ Missing file: $pattern"
    missing=true
  fi
done

if ! $missing; then
  echo "✅ Setup looks good."
else
  echo "Some checks failed." >&2
  echo
  echo "Required tools:" >&2
  printf '  %s\n' "${required_tools[@]}" >&2
  echo
  echo "Required helper commands:" >&2
  printf '  %s\n' "${PBK_REQUIRED_HELPERS[@]}" >&2
  echo
  echo "Required config values:" >&2
  printf '  %s\n' "${PBK_REQUIRED_CONFIG_VARS[@]}" >&2
  echo
  echo "Required files or patterns:" >&2
  printf '  %s\n' "${PBK_SETUP_REQUIRED_PATTERNS[@]}" >&2
  exit 1
fi
