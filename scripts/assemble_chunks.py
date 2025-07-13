#!/usr/bin/env python

import argparse
import glob
import os
import re
import sys

CHUNK_SIZE = 256 * 1024  # 256 KiB IMPORTANT: if you change chunk soze here, you MUST change CHUNK_SIZE in encrypt.sh as well

def extract_chunk_number(filename, prefix):
    match = re.search(rf"{re.escape(prefix)}([a-z]+|\d+)$", filename)
    if not match:
        return None
    suffix = match.group(1)
    if suffix.isdigit():
        return int(suffix)
    else:
        return base26(suffix)

def base26(s):
    """Convert suffix like 'aa', 'ab', ..., 'zz' to integer."""
    total = 0
    for char in s:
        total = total * 26 + (ord(char) - ord('a'))
    return total

def main():
    parser = argparse.ArgumentParser(description="Reassemble split chunks with placeholder padding for missing ones.")
    parser.add_argument("glob_pattern", help="Glob pattern for input chunks (e.g. myfile.chunk.*)")
    parser.add_argument("-o", "--output", default="reassembled.out", help="Output filename")
    parser.add_argument("--verbose", action="store_true", help="Print progress info")
    args = parser.parse_args()

    files = sorted(glob.glob(args.glob_pattern))
    if not files:
        print("No files matched the pattern.")
        sys.exit(1)

    prefix = os.path.commonprefix(files)
    chunks = {}
    max_num = 0

    for f in files:
        chunk_num = extract_chunk_number(f, prefix)
        if chunk_num is not None:
            chunks[chunk_num] = f
            if chunk_num > max_num:
                max_num = chunk_num

    if args.verbose:
        print(f"Detected {len(chunks)} chunks, expecting up to {max_num + 1}")
        print(f"Expected chunk size: {CHUNK_SIZE} bytes")
        print(f"Reassembling into {args.output}")

    with open(args.output, "wb") as out_f:
        for i in range(max_num + 1):
            if i in chunks:
                path = chunks[i]
                size = os.path.getsize(path)
                with open(path, "rb") as in_f:
                    data = in_f.read()
                    if size < CHUNK_SIZE:
                        print(f"[!] Chunk {i:04d} is smaller than expected ({size} bytes), padding with zeroes.")
                        data += b"\x00" * (CHUNK_SIZE - size)
                    elif size > CHUNK_SIZE:
                        print(f"[!] Chunk {i:04d} is larger than expected ({size} bytes), writing full data.")
                    else:
                        if args.verbose:
                            print(f"[✓] Writing chunk {i:04d}: {path}")
                    out_f.write(data)
            else:
                print(f"[❌] Missing chunk {i:04d}, inserting zero padding")
                out_f.write(b"\x00" * CHUNK_SIZE)

    print(f"✅ Reassembly complete: {args.output}")

if __name__ == "__main__":
    main()
