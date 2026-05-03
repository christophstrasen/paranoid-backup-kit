#!/usr/bin/env bash

pbk__abs_dir_from_script() {
  local script_path="$1"
  cd "$(dirname "$script_path")" && pwd -P
}

pbk_require_supported_main_entrypoint() {
  local caller_path="${BASH_SOURCE[1]}"
  local script_dir
  script_dir="$(pbk__abs_dir_from_script "$caller_path")"
  local current_dir
  current_dir="$(pwd -P)"

  if [[ "$current_dir" != "$script_dir" ]]; then
    cat >&2 <<EOF
❌ Unsupported invocation path for paranoid-backup-kit.

Supported entrypoint inside this repo:
  cd "$script_dir"
  ./main.sh

Why this is required:
  Several helper scripts in this repo still resolve files relative to the scripts directory.
  Running main.sh from another working directory can make those helpers pick the wrong paths.

What to do:
  Change into the scripts directory first, then run ./main.sh.
EOF
    exit 1
  fi

  export PBK_MAIN_ENTRYPOINT=1
  export PBK_MAIN_SCRIPT_DIR="$script_dir"
}

pbk_require_main_entrypoint() {
  local caller_path="${BASH_SOURCE[1]}"
  local script_dir
  script_dir="$(pbk__abs_dir_from_script "$caller_path")"

  if [[ "${PBK_MAIN_ENTRYPOINT:-}" != "1" ]]; then
    cat >&2 <<EOF
❌ $(basename "$caller_path") is an internal helper and is not a supported entrypoint.

Run the repo through:
  cd "$script_dir"
  ./main.sh

Why this is required:
  This helper depends on the main workflow and on path assumptions made from the scripts directory.
EOF
    exit 1
  fi
}

pbk_require_main_or_recovery_entrypoint() {
  local caller_path="${BASH_SOURCE[1]}"
  local script_dir
  script_dir="$(pbk__abs_dir_from_script "$caller_path")"
  local current_dir
  current_dir="$(pwd -P)"

  if [[ "${PBK_MAIN_ENTRYPOINT:-}" == "1" ]]; then
    return 0
  fi

  if [[ "$(basename "$script_dir")" == "encrypted" && "$current_dir" == "$script_dir" ]]; then
    return 0
  fi

  cat >&2 <<EOF
❌ Unsupported invocation path for $(basename "$caller_path").

Supported ways to run it:
  Inside the repo workflow:
    cd "$script_dir"
    ./main.sh

  From a recovery bundle:
    cd /path/to/encrypted
    ./$(basename "$caller_path")

Why this is required:
  This script expects either the main workflow environment or to be run directly from an encrypted recovery directory.
EOF
  exit 1
}
