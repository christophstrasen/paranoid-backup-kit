#!/usr/bin/env bash
# summary.sh – provides log_summary()

# Use existing summary file or fall back to a temp one
: "${SUMMARY_FILE:=$(mktemp --tmpdir log-summary.XXXXXX)}"
export SUMMARY_FILE

log_summary() {
  local msg="$1"
  echo "$msg"
  echo "$msg" >> "$SUMMARY_FILE"
}
