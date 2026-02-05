---
title: Print Photo Capture
---

# Print Photo Capture

**Available in: Extended firmware only**

Automatically captures a webcam photo of every finished print. The photo replaces the gcode file's embedded thumbnail so the touchscreen shows the actual printed result, and is saved at a predictable path with metadata JSON for scripted workflows like automated online listings.

## Features

- Automatic photo capture at every print end, no configuration needed
- Gcode thumbnail replacement -- touchscreen file browser shows the real print instead of the slicer preview
- Full-resolution photos saved to `/userdata/print_photos/` with predictable naming
- Metadata JSON alongside each photo with job name, source gcode file, and timestamp
- `latest.jpg` and `latest.json` symlinks always point to the most recent capture
- Manual capture available via Fluidd/Mainsail console command

## How It Works

The feature is implemented as firmware overlay `53-print-photo` containing three components that work together:

### Print-End Flow

When a print completes, the firmware's `PRINT_END` macro is intercepted by a wrapper macro defined in `10_print_photo.cfg`:

```
Original PRINT_END              Modified PRINT_END
─────────────────               ──────────────────
1. (slicer cleanup)             1. Retract filament 2mm
2. Retract                      2. Raise Z 2mm (safety clearance)
3. Park extruder                3. Park extruder at X5 Y5 (out of camera view)
4. Raise Z to 200               4. *** CAPTURE_PRINT_PHOTO ***
5. Turn off heaters              5. Original PRINT_END runs:
6. Disable steppers                 - Raise Z to 200
                                    - Turn off heaters
                                    - Disable steppers
```

The photo is captured at step 4, after the extruder has moved out of the camera's field of view but before the bed drops away from the print. This produces a clean, unobstructed photo of the finished object at its final print height.

### Component Architecture

```
Klipper                          Shell                          Filesystem
──────                           ─────                          ──────────
PRINT_END macro
  │
  ├─ G91; G1 E-2; G1 Z2; G90   (retract + Z-hop)
  ├─ G1 X5 Y5 F6000            (park extruder)
  │
  ├─ CAPTURE_PRINT_PHOTO
  │   └─ RUN_SHELL_COMMAND ──────► capture_print_thumbnail.sh
  │       (gcode_shell_command)    │
  │                                ├─ curl snapshot.jpg ──────► /userdata/print_photos/<job>_<ts>.jpg
  │                                ├─ write metadata ─────────► /userdata/print_photos/<job>_<ts>.json
  │                                ├─ ln -sf ─────────────────► /userdata/print_photos/latest.jpg
  │                                ├─ ln -sf ─────────────────► /userdata/print_photos/latest.json
  │                                ├─ ffmpeg resize
  │                                ├─ base64 encode
  │                                └─ python3 replace ────────► <gcode file> thumbnail updated
  │
  └─ _PRINT_END_PHOTO_BASE     (original cleanup)
```

### Overlay Contents

The overlay installs three files onto the printer's filesystem:

| Installed path | Source | Purpose |
|---|---|---|
| `/home/lava/klipper/klippy/extras/gcode_shell_command.py` | Klipper extension | Adds `[gcode_shell_command]` config sections and the `RUN_SHELL_COMMAND` gcode command, allowing macros to execute shell scripts |
| `/home/lava/scripts/capture_print_thumbnail.sh` | Bash script | Captures webcam snapshot, saves photo + metadata, resizes to thumbnail, replaces gcode thumbnail block |
| `/usr/local/share/firmware-config/extended/klipper/10_print_photo.cfg` | Klipper config | Defines `CAPTURE_PRINT_PHOTO` macro and wraps `PRINT_END` with `rename_existing` |

The Klipper config file is auto-included via the `[include extended/klipper/*.cfg]` directive added by the `11-enable-klipper-includes` overlay.

## Photo Output

All photos are saved to `/userdata/print_photos/`. This directory is on the `/userdata` partition which persists across firmware updates and reboots.

### File Layout

After three prints (`Benchy.gcode`, `Vase.gcode`, `Benchy.gcode` again):

```
/userdata/print_photos/
├── Benchy_20260115_143045.jpg        # first Benchy print photo
├── Benchy_20260115_143045.json       # first Benchy metadata
├── Vase_20260115_162030.jpg          # Vase print photo
├── Vase_20260115_162030.json         # Vase metadata
├── Benchy_20260116_091500.jpg        # second Benchy print photo
├── Benchy_20260116_091500.json       # second Benchy metadata
├── latest.jpg -> /userdata/print_photos/Benchy_20260116_091500.jpg
└── latest.json -> /userdata/print_photos/Benchy_20260116_091500.json
```

### Naming Convention

```
<job_name>_<YYYYMMDD_HHMMSS>.jpg
<job_name>_<YYYYMMDD_HHMMSS>.json
```

- **`job_name`**: Derived from the gcode filename. The `.gcode` / `.gc` / `.g` extension is stripped and characters unsafe for filenames (spaces, slashes, quotes, etc.) are replaced with underscores.
- **`YYYYMMDD_HHMMSS`**: Timestamp at the moment of capture. This makes each photo unique even when re-printing the same file.

### Metadata JSON

Each photo has a companion `.json` file:

```json
{
    "job_name": "Benchy",
    "gcode_file": "Benchy.gcode",
    "timestamp": "20260115_143045",
    "photo_path": "/userdata/print_photos/Benchy_20260115_143045.jpg",
    "photo_dir": "/userdata/print_photos"
}
```

| Field | Description |
|-------|-------------|
| `job_name` | Sanitized name of the print job (filename without extension) |
| `gcode_file` | Original gcode filename as reported by Klipper |
| `timestamp` | Capture time in `YYYYMMDD_HHMMSS` format |
| `photo_path` | Absolute path to the full-resolution JPEG |
| `photo_dir` | Directory containing all print photos |

### Symlinks

Two symlinks are always maintained:

- **`latest.jpg`** -- points to the most recently captured photo
- **`latest.json`** -- points to the most recently written metadata

These provide a stable, fixed path for scripts that only care about the last print.

## Scripting

The predictable paths and metadata make it straightforward to script automated workflows.

### Grab the latest photo

```bash
# Fixed path, always works
scp lava@printer:/userdata/print_photos/latest.jpg ./
scp lava@printer:/userdata/print_photos/latest.json ./
```

### Read metadata

```bash
# On the printer
cat /userdata/print_photos/latest.json | python3 -m json.tool

# From a remote machine
ssh lava@printer cat /userdata/print_photos/latest.json
```

### Find all photos for a specific model

```bash
ls /userdata/print_photos/Benchy_*.jpg
```

### List all prints chronologically

```bash
ls -lt /userdata/print_photos/*.jpg
```

### Watch for new photos (inotifywait)

```bash
# Trigger a script whenever a new photo is saved
inotifywait -m -e create /userdata/print_photos/ |
while read dir event file; do
    if [[ "$file" == *.jpg && "$file" != "latest.jpg" ]]; then
        echo "New print photo: $file"
        # your upload/notification logic here
    fi
done
```

### Automated listing upload

```bash
#!/bin/bash
# upload_print_photo.sh - Upload latest print photo to a listing API
PHOTO="/userdata/print_photos/latest.jpg"
META="/userdata/print_photos/latest.json"

JOB=$(python3 -c "import json; print(json.load(open('$META'))['job_name'])")
TS=$(python3 -c "import json; print(json.load(open('$META'))['timestamp'])")

curl -X POST "https://your-api.com/listings" \
    -F "image=@$PHOTO" \
    -F "title=$JOB" \
    -F "printed_at=$TS" \
    -F "metadata=@$META"
```

### SCP all photos to a local machine

```bash
# One-time bulk copy
scp lava@printer:/userdata/print_photos/*.jpg ./print_photos/
scp lava@printer:/userdata/print_photos/*.json ./print_photos/

# Or rsync for incremental sync
rsync -avz lava@printer:/userdata/print_photos/ ./print_photos/
```

## Touchscreen Thumbnail Replacement

When the print photo is captured, the gcode file's embedded thumbnail is also replaced. This means the touchscreen file browser shows the actual printed result instead of the slicer's 3D render preview the next time you browse to that file.

### How thumbnail replacement works

1. The script scans the gcode file header for `; thumbnail begin WxH <size>` markers
2. It selects the largest thumbnail block (typically 300x300 for OrcaSlicer, 256x256 for PrusaSlicer)
3. The webcam photo is resized to match those dimensions using `ffmpeg`, maintaining aspect ratio with black padding
4. The resized image is base64-encoded and formatted as a standard PrusaSlicer/OrcaSlicer thumbnail block
5. The original thumbnail block in the gcode file is replaced with the new one
6. The gcode file is written atomically (write to temp file, then rename) to prevent corruption

### Supported slicer formats

The thumbnail format is standard across major slicers:

```gcode
; thumbnail begin 300x300 12345
; iVBORw0KGgoAAAANSUhEUgAAASwAAAEsCAYAAAB5fY51...
; ... (base64 PNG data, 78 chars per line) ...
; thumbnail end
```

This format is used by OrcaSlicer, PrusaSlicer, SuperSlicer, and Cura (with thumbnail plugin).

### Slicer configuration

For thumbnails to be replaced, the slicer must embed them in the gcode output. In OrcaSlicer this is enabled by default. In PrusaSlicer, enable it under **Printer Settings > General > G-code thumbnails** and set a resolution (e.g., `300x300`).

## Timelapse Default ON

The timelapse Moonraker component has been updated to default to `enabled: True`. Previously, timelapse had to be manually enabled per-print via the touchscreen. Now every print will record a timelapse automatically.

The setting can still be toggled via the Moonraker API:

```bash
# Disable timelapse for the current session
curl -X POST http://localhost:7125/machine/timelapse/settings \
    -H "Content-Type: application/json" \
    -d '{"enabled": false}'

# Check current setting
curl http://localhost:7125/machine/timelapse/settings
```

> **Note:** The timelapse toggle resets to `enabled: True` on each Moonraker restart. To permanently disable timelapse, disable the camera in `extended2.cfg` (see [Camera Support](camera_support.md#internal-camera-selection)).

## `gcode_shell_command` Extension

This overlay includes a Klipper extension that allows gcode macros to execute shell commands. It is used internally by the print photo feature but is also available for custom macros.

### Configuration

```cfg
[gcode_shell_command my_command]
command: /path/to/script.sh
timeout: 10.
verbose: True
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `command` | (required) | Path to the script or command to execute |
| `timeout` | `2.0` | Maximum execution time in seconds before the command is killed |
| `verbose` | `True` | When `True`, stdout and stderr are printed to the Klipper console |

### Usage in macros

```cfg
[gcode_macro MY_MACRO]
gcode:
    RUN_SHELL_COMMAND CMD=my_command PARAMS="arg1 arg2"
```

The `PARAMS` string is split by `shlex` and passed as individual arguments to the command. Shell metacharacters are not interpreted (the command runs via `subprocess` with a list, not through a shell).

### Security

The extension avoids shell injection by using `subprocess.run()` with a list argument rather than `shell=True`. The configured command path is parsed via `shlex.split()`, and each `PARAMS` token is appended as a separate list element, so filenames with spaces or special characters are handled safely.

## Manual Photo Capture

You can trigger a photo capture manually from the Fluidd or Mainsail console:

```
CAPTURE_PRINT_PHOTO
```

This captures a snapshot for whatever gcode file is currently loaded in `printer.print_stats.filename`. If no file is loaded, it reports an error without failing.

## Dependencies

All dependencies are included in the extended firmware:

| Dependency | Version | Used for |
|------------|---------|----------|
| Camera service | any | Provides `http://localhost/webcam/snapshot.jpg` endpoint |
| `curl` | any | Fetches the webcam snapshot |
| `ffmpeg` | 4.4+ | Resizes the snapshot to thumbnail dimensions |
| `python3` | 3.11+ | Replaces the thumbnail block in the gcode file |
| `base64` | coreutils | Encodes the resized thumbnail as base64 |

## Troubleshooting

### No photo captured

1. Verify the camera is serving snapshots:
   ```bash
   curl -o /tmp/test.jpg http://localhost/webcam/snapshot.jpg
   ls -la /tmp/test.jpg
   ```
2. Check Klipper logs for shell command errors:
   ```bash
   grep -i "shell command" /home/lava/printer_data/logs/klippy.log | tail -20
   ```
3. Run the capture manually from the Fluidd console and read the output:
   ```
   CAPTURE_PRINT_PHOTO
   ```
4. Run the script directly via SSH to see full output:
   ```bash
   /home/lava/scripts/capture_print_thumbnail.sh "your_file.gcode"
   ```

### Thumbnail not updated on touchscreen

- The gcode file must contain a `; thumbnail begin ... ; thumbnail end` block. This is standard in OrcaSlicer and PrusaSlicer output. If your slicer does not embed thumbnails, the photo will still be saved to `/userdata/print_photos/` but the gcode thumbnail will not be replaced.
- Check that the gcode file is writable. Files on read-only storage cannot be updated.
- Browse away from the file and back on the touchscreen to refresh the thumbnail cache.

### Photo is blurry, dark, or shows the nozzle

- The photo is captured immediately after the extruder parks at X5 Y5. If the camera needs time to adjust auto-exposure, the first frame may be underexposed. Consider adding a small `G4 P2000` (2-second dwell) before `CAPTURE_PRINT_PHOTO` in the Klipper config if this is an issue.
- If the extruder is visible in the photo, adjust the park position in `10_print_photo.cfg` to move it further out of the camera's field of view.

### Shell command timeout

The capture script has a 45-second timeout. If the script consistently times out, this could indicate:
- A slow or unresponsive camera (`curl` has its own 10-second timeout)
- A very large gcode file slowing down the thumbnail replacement
- Insufficient free space on `/userdata` for the photo

Check `/home/lava/printer_data/logs/klippy.log` for timeout messages.

### Disk space

Print photos accumulate over time. Each full-resolution JPEG is typically 50-200 KB. To free space:

```bash
# Remove photos older than 30 days
find /userdata/print_photos/ -name "*.jpg" -mtime +30 -delete
find /userdata/print_photos/ -name "*.json" -mtime +30 -delete
```
