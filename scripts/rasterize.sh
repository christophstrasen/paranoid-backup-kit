#!/usr/bin/env bash
set -euo pipefail

# This file generates more failsafe (and much larger) Netpbm versions of common text-file formats and PDFs in plain_staging.
# As Bit-errors in encrypted files can cause large chunks if not whole files to become lost,
# an additional resiliance mechanism is provided via "spatial dispersion" of the ppm and pgm files.

# --- Counters for logging ---
RASTERIZED_COUNT=0
DISPERSED_COUNT=0

PLAIN_STAGING="$(dirname "$0")/../plain_staging"
SHUFFLER="$(dirname "$0")/shuffle_netpbm.py"

source "$(dirname "$0")/summary.sh"

log_summary " "
log_summary " -- rasterize.sh --"

shopt -s nullglob

MAX_SIZE=10240  # 10 KB in bytes
KEEP_ORIGINALS=false

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-originals)
      KEEP_ORIGINALS=true
      shift
      ;;
    *)
      break
      ;;
  esac
done



# ----------------- Rasterize Text to PGM -----------------
for txtfile in "$PLAIN_STAGING"/*.{txt,md,asc,json,yaml,yml,pub,key,pem,password,secret,"env",conf}; do
  [ -f "$txtfile" ] || continue

  size=$(stat --printf="%s" "$txtfile")
  if [ "$size" -gt "$MAX_SIZE" ]; then
    echo "Skipping $(basename "$txtfile"): file size $size bytes exceeds limit of $MAX_SIZE bytes."
    continue
  fi

  base64file="$txtfile.base64"
  wrappedfile="$txtfile.base64.wrapped"
  pgmfile="$txtfile.base64.wrapped.pgm"

  echo "Converting to base64: $(basename "$txtfile") $base64file"
  base64 "$txtfile" > "$base64file"

  echo "Wrapping base64 text to 80 columns: $base64file → $wrappedfile"
  fold -s -w 80 "$base64file" > "$wrappedfile"
  
  wrappedsize=$(stat --printf="%s" "$wrappedfile")

  if [ "$wrappedsize" -gt 5120 ]; then  # 5 KB = 5120 bytes
    pointsize=42
  else
    pointsize=72
  fi

  echo "Rasterizing wrapped base64 text file to PGM:$wrappedfile → $pgmfile with pointsize $pointsize"
  
  set +e
    magick -background white -colorspace Gray -depth 8 -fill black -font "FreeMono" -pointsize 72 label:@"$wrappedfile" "$pgmfile"
    status=$?
  
  if [[ $status -eq 0 ]]; then
 	((RASTERIZED_COUNT++))
  else
 	log_summary "⚠️ Warning, failed to create rasterized version version of $txtfile"
  fi
  
  set -e

  rm "$wrappedfile"
	
done

# ----------------- Rasterize PDFs to PPM -----------------
for pdffile in "$PLAIN_STAGING"/*.pdf; do
  [ -f "$pdffile" ] || continue
  echo "Rasterizing PDF to PPM(s): $(basename "$pdffile")"
  output_prefix="$PLAIN_STAGING/$(basename "${pdffile%.*}" | tr ' ' '_')"
  set +e
  if pdftoppm "$pdffile" "$output_prefix"; then
 	((RASTERIZED_COUNT++))
  else
 	log_summary "⚠️ Warning, failed to create rasterized version version of $pdffile"
  fi
  set -e
done

log_summary "Rasterized files: $RASTERIZED_COUNT"

# ----------------- Encode all *.pgm and *.ppm -----------------
# Chunk based encryption such as age's XChaCha20-Poly1305 even a single bit error can cause 64kb of pixel corruption
# To avoid readability issues from horizontal multi-line corruption, we want to spread out pixel errors over the entire image 
log_summary " "
log_summary " -- spatially dispersing all NetPBM raster images --"

for imgfile in "$PLAIN_STAGING"/*.{pgm,ppm}; do
  [ -f "$imgfile" ] || continue

  # Skip files that already include 'dispersed.seed' in their filename
  [[ "$imgfile" == *dispersed.seed* ]] && continue
  set +e
  if dispersed_file=$("$SHUFFLER" encode "$imgfile" --seed 42 --print-filename); then
 	((DISPERSED_COUNT++))
  	echo "Created: $(basename "$dispersed_file") and deleting original."
  else
  	log_summary "⚠️ Warning, failed to create dispersed version of $imgfile"
  fi
  set -e
  
	# Remove original .pgm/.ppm file unless --keep-originals is set
	if [[ "$KEEP_ORIGINALS" != true ]]; then
  	rm "$imgfile"
	fi
  
done

log_summary "Dispersed output files: $DISPERSED_COUNT"

# --- Check ---

if [[ "$RASTERIZED_COUNT" -ne "$DISPERSED_COUNT" ]]; then
  log_summary "⚠️ Warning: Mismatch in rasterized vs dispersed count!"
else
  log_summary "✅ All rasterized files successfully dispersed."
fi
