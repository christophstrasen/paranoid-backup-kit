#!/usr/bin/env python3
import argparse
import os
import random

FIXED_HEADER_SIZE = 510 # important MUST be divisible by 2 and 3
MAGIC_PGM = b'P5'
MAGIC_PPM = b'P6'

def parse_header(f):
    def _read_token():
        token = b''
        while True:
            c = f.read(1)
            if not c:
                break
            if c.isspace():
                if token:
                    break
                continue
            if c == b'#':
                while c and c != b'\n':
                    c = f.read(1)
                continue
            token += c
        return token

    f.seek(0)
    magic = f.read(2)
    if magic not in (MAGIC_PGM, MAGIC_PPM):
        raise ValueError(f"Unsupported format: {magic}")
    tokens = []
    while len(tokens) < 3:
        tok = _read_token()
        if not tok:
            raise ValueError("Incomplete header")
        tokens.append(tok)
    width, height, maxval = map(int, tokens)
    header_end = f.tell()
    return magic, width, height, maxval, header_end

def write_fixed_header(out, magic, width, height, maxval, pixel_size):
    if FIXED_HEADER_SIZE % pixel_size != 0:
        raise ValueError("Fixed header size must be divisible by pixel size")

    base_header = f"{magic.decode()}\n".encode()
    dims = f"{width} {height}\n{maxval}\n".encode()

    remaining = FIXED_HEADER_SIZE - len(base_header) - len(dims)
    if remaining < 2:
        raise ValueError("Not enough room for padding comment")

    comment = b"#" + b"X" * (remaining - 2) + b"\n"
    final_header = base_header + comment + dims

    if len(final_header) != FIXED_HEADER_SIZE:
        raise AssertionError("Final header is not exactly the fixed size")
    if len(final_header) % pixel_size != 0:
        raise AssertionError("Final header is not aligned to pixel size")

    out.write(final_header)

def shuffle_pixels(data, pixel_size, seed):
    pixels = [data[i:i + pixel_size] for i in range(0, len(data), pixel_size)]
    indices = list(range(len(pixels)))
    rng = random.Random(seed)
    rng.shuffle(indices)
    shuffled = b''.join(pixels[i] for i in indices)
    return shuffled

def unshuffle_pixels(data, pixel_size, seed):
    pixels = [data[i:i + pixel_size] for i in range(0, len(data), pixel_size)]
    indices = list(range(len(pixels)))
    rng = random.Random(seed)
    rng.shuffle(indices)
    reverse_indices = [0] * len(pixels)
    for i, idx in enumerate(indices):
        reverse_indices[idx] = i
    unshuffled = b''.join(pixels[i] for i in reverse_indices)
    return unshuffled

def reconstruct_header_from_filename(filename):
    basename = os.path.basename(filename)
    try:
        seed = int(basename.split("seed")[1].split(".")[0])
        dims_part = basename.split("seed")[1].split(".")[1]
        width = int(dims_part.split("w")[1].split("h")[0])
        height = int(dims_part.split("h")[1].split(".")[0])
        magic_str = basename.split(".")[-2]
        magic = magic_str.encode()
        ext = basename.split(".")[-1]
        pixel_size = 1 if ext == "pgm" else 3 if ext == "ppm" else None
        if pixel_size is None:
            raise ValueError("Unknown file extension")
        return seed, width, height, magic, pixel_size
    except Exception as e:
        raise ValueError(f"Failed to reconstruct header from filename: {e}")

def encode(args):
    with open(args.input, "rb") as f:
        magic, width, height, maxval, header_end = parse_header(f)
        f.seek(header_end)
        pixel_data = f.read()

    
    if magic == MAGIC_PGM:
        pixel_size = 2 if maxval > 255 else 1
    elif magic == MAGIC_PPM:
        pixel_size = 6 if maxval > 255 else 3
    else:
        raise ValueError(f"Unsupported magic: {magic} with maxval: {maxval}")


    expected_bytes = width * height * pixel_size
    if (False):
        print("⚠️ Pixel size mismatch:", flush=True)
        print(f"  Magic format: {magic}", flush=True)
        print(f"  Width: {width}", flush=True)
        print(f"  Height: {height}", flush=True)
        print(f"  Maxval: {maxval}", flush=True)
        print(f"  Pixel size: {pixel_size}", flush=True)
        print(f"  Expected bytes: {expected_bytes}", flush=True)
        print(f"  Actual bytes:   {len(pixel_data)}", flush=True)
    
    if len(pixel_data) != expected_bytes:
        raise ValueError(f"Expected {expected_bytes} bytes of pixel data, got {len(pixel_data)}")

    shuffled = pixel_data if getattr(args, "noshuffle", False) else shuffle_pixels(pixel_data, pixel_size, args.seed)
    if getattr(args, "noshuffle", False):
        print("[ℹ️] No shuffling applied.")

    ext = ".pgm" if magic == MAGIC_PGM else ".ppm"
    base = os.path.splitext(os.path.basename(args.input))[0]
    suffix = "noshuf" if getattr(args, "noshuffle", False) else f"seed{args.seed}"
    out_name = os.path.join(os.path.dirname(args.input), f"{base}.dispersed.{suffix}.w{width}h{height}.m{maxval}.{magic.decode()}{ext}")

    with open(out_name, "wb") as out:
        write_fixed_header(out, magic, width, height, maxval, pixel_size)
        out.write(shuffled)

    if getattr(args, "print_filename", True):
        print(out_name)

def decode(args):
    basename = os.path.basename(args.input)
    try:
        seed = int(basename.split("seed")[1].split(".")[0])
        dims_part = basename.split("seed")[1].split(".")[1]
        width = int(dims_part.split("w")[1].split("h")[0])
        height = int(dims_part.split("h")[1].split(".")[0])
        maxval = int(basename.split(".m")[1].split(".")[0])
    except Exception as e:
        raise ValueError(f"Failed to reconstruct metadata from filename: {e}")

    magic_str = basename.split(".")[-2]
    magic = magic_str.encode()
    ext = basename.split(".")[-1]
    pixel_size = 1 if ext == "pgm" else 3 if ext == "ppm" else None
    if pixel_size is None:
        raise ValueError("Unknown file extension")

    expected_bytes = width * height * pixel_size
    with open(args.input, "rb") as f:
        f.seek(FIXED_HEADER_SIZE)
        raw_data = f.read()

    if len(raw_data) < expected_bytes:
        print(f"[⚠️] File contains only {len(raw_data)} bytes but {expected_bytes} expected. Filling with black pixels.")
        raw_data += b'\x00' * (expected_bytes - len(raw_data))
    elif len(raw_data) > expected_bytes:
        print(f"[⚠️] File contains {len(raw_data)} bytes but only {expected_bytes} expected. Truncating extra data.")
        raw_data = raw_data[:expected_bytes]

    unshuffled = unshuffle_pixels(raw_data, pixel_size, seed)

    out_name = os.path.splitext(args.input)[0] + ".restored." + ext
    with open(out_name, "wb") as out:
        write_fixed_header(out, magic, width, height, maxval, pixel_size)
        out.write(unshuffled)

    print(f"[✅] Decoded and saved to: {out_name}")

def main():
    parser = argparse.ArgumentParser(description="Deterministic PGM/PPM pixel shuffler")
    subparsers = parser.add_subparsers(dest="command")

    encode_parser = subparsers.add_parser("encode")
    encode_parser.add_argument("input", help="Input PGM/PPM file")
    encode_parser.add_argument("--seed", type=int, required=True)
    encode_parser.add_argument("--noshuffle", action="store_true", help="Don't shuffle pixels, just add fixed header")
    encode_parser.add_argument("--print-filename", action="store_true", help="Output only the resulting filename")

    decode_parser = subparsers.add_parser("decode")
    decode_parser.add_argument("input", help="Input dispersed file")
    decode_parser.add_argument("--seed", type=int, required=True)

    args = parser.parse_args()
    if args.command == "encode":
        encode(args)
    elif args.command == "decode":
        decode(args)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
