#!/usr/bin/env python3
import sys
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError, VerificationError

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <stored_argon2_hash>", file=sys.stderr)
        sys.exit(2)

    stored_hash = sys.argv[1]
    password = sys.stdin.read().strip()

    ph = PasswordHasher()

    try:
        # Verify the password against the stored Argon2 hash
        if ph.verify(stored_hash, password):
            # Optionally, rehash if parameters changed (recommended)
            if ph.check_needs_rehash(stored_hash):
                print("Warning: stored hash parameters outdated, consider rehashing.", file=sys.stderr)
            sys.exit(0)
    except VerifyMismatchError:
        # Password does not match
        sys.exit(1)
    except VerificationError as e:
        # Other verification errors (e.g. malformed hash)
        print(f"Verification error: {e}", file=sys.stderr)
        sys.exit(3)

if __name__ == "__main__":
    main()

