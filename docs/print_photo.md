---
title: Print Photo Capture
---

# Print Photo Capture

**Available in: Extended firmware only**

Automatically captures a webcam photo of every finished print, replaces the gcode file's embedded thumbnail so the touchscreen shows the actual printed result, and saves full-resolution photos to a predictable location for scripted workflows.

## Features

- Automatic photo capture at print end (extruder parked out of camera view, bed at print height)
- Gcode thumbnail replacement so the touchscreen file browser shows the real print result
- Full-resolution photos saved to `/userdata/print_photos/` with predictable naming
- Metadata JSON files for scripted workflows (automated listings, social media, inventory)
- `latest.jpg` and `latest.json` symlinks always point to the most recent capture

## How It Works

When a print completes, the `PRINT_END` macro is intercepted:

1. Filament retracts and Z raises 2mm for clearance
2. Extruder parks at X5 Y5, out of the internal camera's view
3. Webcam snapshot is captured while the bed is still at print height
4. The snapshot is resized to match the gcode file's thumbnail dimensions
5. The embedded thumbnail in the gcode file is replaced with the photo
6. A full-resolution copy and metadata JSON are saved to `/userdata/print_photos/`
7. The original `PRINT_END` continues (Z raise to 200, heaters off, steppers off)

## Photo Output Locations

All photos are saved to `/userdata/print_photos/` (persistent across firmware updates):

| File | Description |
|------|-------------|
| `<job_name>_<YYYYMMDD_HHMMSS>.jpg` | Full-resolution photo of the finished print |
| `<job_name>_<YYYYMMDD_HHMMSS>.json` | Metadata: job name, gcode file, timestamp, paths |
| `latest.jpg` | Symlink to the most recent photo |
| `latest.json` | Symlink to the most recent metadata |

The `<job_name>` is derived from the gcode filename with the extension stripped and unsafe characters replaced with underscores.

### Example

For a print from `Benchy v2.gcode` completed on January 15, 2026 at 14:30:45:

```
/userdata/print_photos/Benchy_v2_20260115_143045.jpg
/userdata/print_photos/Benchy_v2_20260115_143045.json
/userdata/print_photos/latest.jpg -> Benchy_v2_20260115_143045.jpg
/userdata/print_photos/latest.json -> Benchy_v2_20260115_143045.json
```

### Metadata JSON Format

```json
{
    "job_name": "Benchy_v2",
    "gcode_file": "Benchy v2.gcode",
    "timestamp": "20260115_143045",
    "photo_path": "/userdata/print_photos/Benchy_v2_20260115_143045.jpg",
    "photo_dir": "/userdata/print_photos"
}
```

## Scripting Examples

### Get the latest print photo

```bash
# Always available at this fixed path
cat /userdata/print_photos/latest.json | python3 -m json.tool
cp /userdata/print_photos/latest.jpg /path/to/upload/
```

### List all print photos

```bash
ls /userdata/print_photos/*.jpg
```

### Find photos for a specific job

```bash
ls /userdata/print_photos/Benchy_v2_*.jpg
```

### Automated upload script example

```bash
#!/bin/bash
# Post-print upload hook - run via cron or inotifywait
PHOTO=$(readlink -f /userdata/print_photos/latest.jpg)
META=$(readlink -f /userdata/print_photos/latest.json)
JOB=$(python3 -c "import json; print(json.load(open('$META'))['job_name'])")

echo "Uploading photo for job: $JOB"
curl -X POST "https://your-listing-api.com/upload" \
    -F "image=@$PHOTO" \
    -F "title=$JOB" \
    -F "metadata=@$META"
```

## Manual Photo Capture

You can trigger a photo capture manually from the Fluidd/Mainsail console:

```
CAPTURE_PRINT_PHOTO
```

This captures a snapshot and updates the thumbnail for the currently loaded gcode file (if any).

## Touchscreen Thumbnail

After a print completes, the gcode file's embedded thumbnail is replaced with the actual photo. When you browse files on the touchscreen, you'll see the real printed result instead of the slicer's 3D render preview.

The thumbnail replacement:
- Detects the thumbnail dimensions from the gcode file (typically 300x300 or 256x256)
- Resizes the photo to match, maintaining aspect ratio with black padding
- Uses the standard PrusaSlicer/OrcaSlicer thumbnail format (`; thumbnail begin/end`)
- Performs an atomic file write to prevent corruption

## Dependencies

This feature requires:
- Internal or USB camera enabled (provides `http://localhost/webcam/snapshot.jpg`)
- FFmpeg (included in the firmware for thumbnail resizing)
- Python 3 (included in the firmware for gcode thumbnail replacement)
- `gcode_shell_command` Klipper extension (included in this overlay)

## Troubleshooting

### No photo captured

- Verify the camera is working: `curl -o /tmp/test.jpg http://localhost/webcam/snapshot.jpg`
- Check Klipper logs for shell command errors
- Run `CAPTURE_PRINT_PHOTO` manually from the Fluidd console to see error output

### Thumbnail not updated on touchscreen

- The gcode file must contain a `; thumbnail begin ... ; thumbnail end` block (standard in OrcaSlicer/PrusaSlicer output)
- Check that the gcode file is not read-only
- Browse away from the file and back on the touchscreen to refresh the thumbnail cache

### Photo is blurry or dark

- The photo is captured immediately after the extruder parks; if the camera takes time to adjust exposure, the first frame may be suboptimal
- Ensure adequate lighting in the printer enclosure
