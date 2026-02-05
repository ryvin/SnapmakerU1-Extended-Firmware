#!/bin/bash
# capture_print_thumbnail.sh - Capture print photo and replace gcode thumbnail
#
# Called by the CAPTURE_PRINT_PHOTO Klipper macro at print end.
# Captures a webcam snapshot, resizes it to match the existing gcode
# thumbnail dimensions, base64-encodes it, and replaces the thumbnail
# block in the gcode file so the touchscreen shows the actual print result.
#
# Also saves a full-resolution photo to a predictable location for
# scripted workflows (e.g. automated online listings).
#
# == Photo output locations ==
#
#   /userdata/print_photos/<job_name>_<YYYYMMDD_HHMMSS>.jpg   (full-res)
#   /userdata/print_photos/latest.jpg                         (symlink)
#   /userdata/print_photos/<job_name>_<YYYYMMDD_HHMMSS>.json  (metadata)
#
# The metadata JSON contains: job_name, gcode_file, timestamp, photo_path
# so downstream scripts can discover which print a photo belongs to.
#
# Usage: capture_print_thumbnail.sh <gcode_filename>

set -euo pipefail

GCODE_DIR="/home/lava/printer_data/gcodes"
SNAPSHOT_URL="http://localhost/webcam/snapshot.jpg"
PHOTO_DIR="/userdata/print_photos"

FILENAME="${1:-}"

if [[ -z "$FILENAME" ]]; then
    echo "Error: No filename provided"
    echo "Usage: $0 <gcode_filename>"
    exit 1
fi

# --- Path traversal protection ---
GCODE_FILE="$GCODE_DIR/$FILENAME"
REAL_PATH=$(realpath -m "$GCODE_FILE")
if [[ "$REAL_PATH" != "$GCODE_DIR/"* ]]; then
    echo "Error: Filename escapes gcode directory: $FILENAME"
    exit 1
fi
GCODE_FILE="$REAL_PATH"

if [[ ! -f "$GCODE_FILE" ]]; then
    echo "Error: Gcode file not found: $GCODE_FILE"
    exit 1
fi

# --- Derive predictable job name from filename ---
# Strip path and .gcode extension, sanitize for filesystem use
JOB_NAME=$(basename "$FILENAME")
JOB_NAME="${JOB_NAME%.gcode}"
JOB_NAME="${JOB_NAME%.gc}"
JOB_NAME="${JOB_NAME%.g}"
# Replace spaces and unsafe chars with underscores
JOB_NAME=$(echo "$JOB_NAME" | tr ' /\\:*?"<>|' '_')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create temp directory with cleanup trap
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

SNAPSHOT="$WORK_DIR/snapshot.jpg"
THUMBNAIL="$WORK_DIR/thumbnail.png"

# --- Step 1: Capture snapshot from webcam ---
echo "Capturing snapshot from webcam..."
if ! curl -s -o "$SNAPSHOT" --max-time 10 "$SNAPSHOT_URL"; then
    echo "Error: Failed to capture snapshot from $SNAPSHOT_URL"
    exit 1
fi

if [[ ! -s "$SNAPSHOT" ]]; then
    echo "Error: Snapshot file is empty"
    exit 1
fi

# --- Step 2: Save full-resolution photo to predictable location ---
mkdir -p "$PHOTO_DIR"
PHOTO_FILE="${PHOTO_DIR}/${JOB_NAME}_${TIMESTAMP}.jpg"
cp "$SNAPSHOT" "$PHOTO_FILE"

# Update "latest" symlink (always points to most recent photo)
ln -sf "$PHOTO_FILE" "${PHOTO_DIR}/latest.jpg"

# Write metadata JSON for scripted workflows
cat > "${PHOTO_DIR}/${JOB_NAME}_${TIMESTAMP}.json" << METAEOF
{
    "job_name": "${JOB_NAME}",
    "gcode_file": "${FILENAME}",
    "timestamp": "${TIMESTAMP}",
    "photo_path": "${PHOTO_FILE}",
    "photo_dir": "${PHOTO_DIR}"
}
METAEOF

# Update latest metadata symlink
ln -sf "${PHOTO_DIR}/${JOB_NAME}_${TIMESTAMP}.json" "${PHOTO_DIR}/latest.json"

echo "Saved print photo: $PHOTO_FILE"
echo "Latest symlink: ${PHOTO_DIR}/latest.jpg"

# --- Step 3: Detect thumbnail dimensions from gcode ---
# Look for "; thumbnail begin WxH <size>" lines and pick the largest
THUMB_DIMS=$(grep -oP '; thumbnail begin \K\d+x\d+' "$GCODE_FILE" 2>/dev/null \
    | sort -t'x' -k1 -n | tail -1 || true)

if [[ -z "$THUMB_DIMS" ]]; then
    echo "Warning: No thumbnail found in gcode file, using 300x300"
    THUMB_DIMS="300x300"
fi

WIDTH="${THUMB_DIMS%x*}"
HEIGHT="${THUMB_DIMS#*x}"

# Validate dimensions are numeric
if ! [[ "$WIDTH" =~ ^[0-9]+$ && "$HEIGHT" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid thumbnail dimensions: ${WIDTH}x${HEIGHT}"
    exit 1
fi

echo "Target thumbnail dimensions: ${WIDTH}x${HEIGHT}"

# --- Step 4: Resize snapshot to thumbnail dimensions ---
# Maintain aspect ratio, pad with black bars if needed
echo "Resizing snapshot to ${WIDTH}x${HEIGHT}..."
ffmpeg -y -loglevel error \
    -i "$SNAPSHOT" \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2:color=black" \
    -frames:v 1 \
    "$THUMBNAIL"

if [[ ! -s "$THUMBNAIL" ]]; then
    echo "Error: Failed to create resized thumbnail"
    exit 1
fi

# --- Step 5: Base64 encode the thumbnail ---
B64_DATA=$(base64 -w 0 "$THUMBNAIL")
B64_SIZE=${#B64_DATA}

echo "Base64 encoded thumbnail: ${B64_SIZE} bytes"

# --- Step 6: Generate new thumbnail block ---
{
    echo "; thumbnail begin ${WIDTH}x${HEIGHT} ${B64_SIZE}"
    echo "$B64_DATA" | fold -w 78 | sed 's/^/; /'
    echo "; thumbnail end"
} > "$WORK_DIR/new_thumbnail_block.txt"

# --- Step 7: Replace thumbnail block in gcode file (atomic write) ---
python3 - "$GCODE_FILE" "$WORK_DIR/new_thumbnail_block.txt" "$WIDTH" "$HEIGHT" << 'PYEOF'
import sys
import re
import os
import tempfile

gcode_file = sys.argv[1]
new_block_file = sys.argv[2]
target_w = sys.argv[3]
target_h = sys.argv[4]
target_dim = f"{target_w}x{target_h}"

with open(new_block_file, 'r') as f:
    new_block = f.read().rstrip('\n')

with open(gcode_file, 'r') as f:
    content = f.read()

# Match the thumbnail block for the target dimensions
# Format: ; thumbnail begin WxH <size>\n(; <base64>\n)*; thumbnail end
pattern = re.compile(
    r'; thumbnail begin ' + re.escape(target_dim) + r' \d+\n'
    r'(?:; [^\n]*\n)*'
    r'; thumbnail end',
    re.MULTILINE
)

replaced = False
match = pattern.search(content)
if match:
    content = content[:match.start()] + new_block + content[match.end():]
    replaced = True
    print(f"Replaced {target_dim} thumbnail in gcode file")
else:
    # Try to find any thumbnail block and replace the largest one
    pattern_any = re.compile(
        r'; thumbnail begin \d+x\d+ \d+\n'
        r'(?:; [^\n]*\n)*'
        r'; thumbnail end',
        re.MULTILINE
    )
    match_any = pattern_any.search(content)
    if match_any:
        content = content[:match_any.start()] + new_block + content[match_any.end():]
        replaced = True
        print(f"Replaced alternative thumbnail block with {target_dim} thumbnail")
    else:
        print(f"Warning: No thumbnail block found in gcode file to replace")

if replaced:
    # Atomic write: write to temp file in same directory, then rename
    gcode_dir = os.path.dirname(gcode_file)
    fd, tmp_path = tempfile.mkstemp(dir=gcode_dir, suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            f.write(content)
        os.rename(tmp_path, gcode_file)
        print("Gcode file updated atomically")
    except Exception:
        # Clean up temp file on failure
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise

PYEOF

echo "Print photo capture complete!"
