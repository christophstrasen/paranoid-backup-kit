#!/usr/bin/env python3
import sys
from argon2 import PasswordHasher

def main():
    ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=1)
    password = sys.stdin.read().strip()
    hash = ph.hash(password)
    print(hash)

if __name__ == "__main__":
    main()

