#!/usr/bin/env bash
set -euo pipefail

read_password() {
  prompt="$1"
  password=""
  echo -n "$prompt"
  while IFS= read -r -s -n1 char; do
    if [[ $char == $'\0' || $char == $'\n' ]]; then
      break
    fi
    if [[ $char == $'\177' ]]; then  # backspace
      if [ -n "$password" ]; then
        password="${password%?}"
        echo -ne '\b \b'
      fi
    else
      password+="$char"
      echo -n '*'
    fi
  done
  echo
  REPLY="$password"
}

read_password "Enter password to hash: "
PASSWORD="$REPLY"

# Use the python argon2 hash helper script located in the same directory
SCRIPT_DIR="$(dirname "$0")"
HASH=$(printf "%s" "$PASSWORD" | "$SCRIPT_DIR/argon2_hash.py")

echo "Argon2 hash:"
echo "$HASH"

