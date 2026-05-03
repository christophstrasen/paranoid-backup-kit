#!/usr/bin/env bash

pbk_load_config() {
  : "${PBK_REPO_ROOT:?PBK_REPO_ROOT must be set before loading config}"

  local defaults_file="$PBK_REPO_ROOT/config/defaults.sh"
  local local_file="$PBK_REPO_ROOT/config/local.sh"

  if [[ ! -f "$defaults_file" ]]; then
    echo "ERROR: Missing config defaults: $defaults_file" >&2
    exit 1
  fi

  source "$defaults_file"

  if [[ -f "$local_file" ]]; then
    source "$local_file"
  fi

  pbk_finalize_config
}
