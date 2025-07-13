#!/usr/bin/env bash
set -euo pipefail

# Writes to optical media
# Pretty solid for burning but not the most reliable in the verification part
# If verification exits early, try re-running manually with --simulate flag which still checks the written media.

DEVICE="/dev/sr0"
WORKING_DIR=/tmp/dvdbackup
MOUNTPOINT="$WORKING_DIR/burnverify"
BUILD_STAGING_DIR="$WORKING_DIR/selected_for_iso"
ISO="$WORKING_DIR/output.iso"
SMALL_ISO_THRESHOLD=$((50 * 1024 * 1024))  # 50 MiB
FULL_BLANK=true
SIMULATE=false

# --- Parse options until first non-option argument ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --avoid-full-blank)
      FULL_BLANK=false
      shift
      ;;
    --simulate)
      SIMULATE=true
      shift
      ;;
    --) # Explicit end of options
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      break
      ;;
  esac
done


# --- param checks  ---
if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 [--avoid-full-blank --simulate] <target_folder>" >&2
  exit 1
fi

target_folder="$1"
[ -d "$target_folder" ] || { echo "Not a directory: $target_folder"; exit 1; }


# Step 1: Build manifest that is sorted in a fashion spreading out files randomly
# so that potential dvd-edge rot spreads the damage instead of clusterering
echo "[*] Step 1: Build manifest for file spreading across ISO."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/build_iso_manifest.sh" "$target_folder"


# Step 2: Prepare folders and copy files based on iso_manifest.tsv
echo "[*] Step 2: Prepare folders and copy files based on iso_manifest.tsv"
mkdir -p $BUILD_STAGING_DIR
rm -Rf $BUILD_STAGING_DIR/* # clean potential remnants

(
  cd "$target_folder"
  cut -f2 iso_manifest.tsv | while read -r file; do
    echo "→ Copying: $file"
    cp --parents "$file" "$BUILD_STAGING_DIR/"
  done
)

SIZE_BEFORE=$(du -b "$BUILD_STAGING_DIR" | cut -f1)
COUNT_BEFORE=$(find "$BUILD_STAGING_DIR" -type f | wc -l)

# Step 3: create ISO and check size
echo "[*] Step 4: Creating ISO image from iso_manifest.tsv..."
mkisofs -R \
  -o "$ISO" \
  -V "ARCHIVE_DISC" \
  -sort <(awk -F'\t' '{ printf "%010d %s\n", $1, $2 }' "$target_folder/iso_manifest.tsv") \
  "$BUILD_STAGING_DIR"

ISO_SIZE=$(stat -c%s "$ISO")
SIZE_PERCENT=$(awk -v a="$ISO_SIZE" -v b="$SIZE_BEFORE" 'BEGIN { if (b > 0) printf "%.1f", (a / b) * 100; else print "0.0" }')

printf "[🧮] Staging: %4d files, %4d MiB → ISO: %4d MiB (%s%%)\n" \
  "$COUNT_BEFORE" "$((SIZE_BEFORE / 1024 / 1024))" "$((ISO_SIZE / 1024 / 1024))" "$SIZE_PERCENT"

if [[ $SIZE_PERCENT == ?(-)+([0-9])?(.*) ]] && (( $(echo "$SIZE_PERCENT > 150" | bc -l) )); then
  echo "❗ ISO size exceeds 150% of staged content. Likely a problem. Exiting."
  exit 1
fi

if [[ $ISO_SIZE -gt 4500000000 ]]; then
  echo "❌ Resulting ISO exceeds safe maximum of 4.19 GiB (4,500,000,000 bytes). Exiting."
  exit 1
fi

IS_SMALL_ISO=false
if [[ "$ISO_SIZE" -lt "$SMALL_ISO_THRESHOLD" ]]; then
  IS_SMALL_ISO=true
  echo "[!] Detected small ISO (< 50 MiB)"
fi

echo "[✅] ISO created and formally validated: $ISO"

# Step 5: Check media info
echo "[*] Step 5: Checking media info..."
dvd+rw-mediainfo "$DEVICE" > $WORKING_DIR/mediainfo.txt

IS_RW=false
if grep -q "DVD-RW" $WORKING_DIR/mediainfo.txt; then
  IS_RW=true
  echo "Media is rewritable (DVD-RW)"
fi

if [[ "$SIMULATE" != "true" ]]; then
	# Step 6: Blanking (if RW)
	if [[ "$IS_RW" == true ]]; then
	
  	echo "[*] Step 6: Ensuring blank writable for RW media"
  	if grep -q "Disc status:[[:space:]]*blank" $WORKING_DIR/mediainfo.txt; then
    	echo "Disc is already blank — skipping blanking"
  	else # blanking
    	if [[ "$FULL_BLANK" == true ]]; then
      	echo "Performing full blanking of DVD-RW..."
      	dvd+rw-format -blank=full "$DEVICE"
    	else
      	echo "Attempting fast blank of DVD-RW..."
      	if ! dvd+rw-format -blank "$DEVICE"; then
        	echo "[!] Fast blank failed or incomplete — falling back to full blank..."
        	dvd+rw-format -blank=full "$DEVICE"
      	fi
    	fi
  	fi
	else
  	echo "Media is write-once, skipping blank"
	fi
else
	echo "skipped step 6 the blanking process due to --simulate"
fi

if [[ "$SIMULATE" != "true" ]]; then
	# Step 7: Burn the ISO
	echo "[*] Step 7: Beginning burn process..."
	
	if [[ "$IS_RW" == true ]]; then
  	BURN_CMD=(growisofs -use-the-force-luke=notray -speed=16 -Z "$DEVICE=$ISO")
	else
  	BURN_CMD=(growisofs -use-the-force-luke=notray -speed=2 -Z "$DEVICE=$ISO")
	fi
	
	echo "Running burn via: ${BURN_CMD[*]}"
	"${BURN_CMD[@]}"
else
	echo "skipped step 7 burn process due to --simulate"
fi

sleep 5
echo "[*] Ejecting the DVD to finalize the burn and ensure clean verification..."
sudo eject /dev/sr0

read -p "📀 Please reinsert the DVD now and press ENTER once it has spun up."

# Step 8: Mount the burned disc
echo "[*] Step 8: Mounting disc to verify contents..."
sudo mkdir -p "$MOUNTPOINT"

if ! udisksctl mount -b "$DEVICE" >$WORKING_DIR/mount_output.txt 2>&1; then
  echo "[!] udisksctl failed — falling back to sudo mount"
  sudo mount "$DEVICE" "$MOUNTPOINT"
else
  MOUNTPOINT=$(grep 'Mounted' $WORKING_DIR/mount_output.txt | awk '{print $NF}')
  echo "[✅] Mounted via udisksctl at $MOUNTPOINT"
fi

# Step 9: Verify DVD contents against staging directory
echo "[*] Step 9: Verifying DVD contents with rsync (checksum-only)..."

RSYNC_LOG=$(mktemp)

set +e
rsync -rcn --checksum --out-format="%i %n%L" \
  "$MOUNTPOINT/" "$BUILD_STAGING_DIR/" | \
  grep -v '^\.f' > "$RSYNC_LOG"

if [[ -s "$RSYNC_LOG" ]]; then
  echo "[❌] rsync detected actual content differences between DVD and staging:"
  cat "$RSYNC_LOG"
  echo "⚠️  WARNING: You may want to investigate. Files differ in content. iso_manifest.tsv changes are probably no problem."
else
  echo "[✅] All file contents match (based on checksum)."
fi

rm -f "$RSYNC_LOG"
set -e


# Step 10: Cleanup
echo "[*] Step 10: cleaning up..."
sleep 10
# Attempt udisksctl unmount first, then fall back to sudo umount
safe_umount() {
  local target="$1"
  if ! udisksctl unmount -b "$target" 2>/dev/null; then
    sudo umount "$target" || echo "[!] Failed to unmount $target"
  else
    echo "Unmounted $target"
  fi
  sleep 2
}

safe_umount "$MOUNTPOINT"

# Clean up temp files and mount points
rm -f $WORKING_DIR/mediainfo.txt /tmp/dvdbackup/checksums_orig.txt

echo "[✅] done."
