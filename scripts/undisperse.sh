
#!/usr/bin/env bash
set -euo pipefail

RECOVERED_DIR="$(dirname "$0")/../plain_recovered"
SHUFFLER="$(dirname "$0")/shuffle_netpbm.py"
ASSUME_YES=false
RECOVER=false
SEED_OVERRIDE=""
TARGET_DIR=""

# Parse flags and optional directory (must be last)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      ASSUME_YES=true
      shift
      ;;
    --seed)
      SEED_OVERRIDE="$2"
      shift 2
      ;;
    --print-filename)
      PRINT_FILENAME="--print-filename"
      shift
      ;;
    --recover)
      RECOVER=true
      shift
      ;;
    --*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$TARGET_DIR" ]]; then
        TARGET_DIR="$1"
        shift
      else
        echo "Unexpected argument: $1"
        exit 1
      fi
      ;;
  esac
done

# Default directory if none provided
if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$RECOVERED_DIR"
fi

shopt -s nullglob
for file in "$TARGET_DIR"/*."dispersed"*.{pgm,ppm}; do
  [[ -f "$file" ]] || continue

  if [[ -n "$SEED_OVERRIDE" ]]; then
    seed="$SEED_OVERRIDE"
  else
    echo "No --seed provided. Defaulting to 42. Seed information from filename might still take precedence."
    seed=42
  fi

  echo "Decoding $file (seed=$seed)..."
  cmd=( "$SHUFFLER" decode "$file" --seed "$seed" )
  $ASSUME_YES && cmd+=( --yes )
  [[ -n "${PRINT_FILENAME:-}" ]] && cmd+=( "$PRINT_FILENAME" )
  if $RECOVER; then
  	cmd+=(--recover)
  fi
  "${cmd[@]}"
done
