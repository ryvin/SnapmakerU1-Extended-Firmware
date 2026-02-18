---
title: OrcaSlicer Setup for Extended Firmware
---

# OrcaSlicer Setup for Extended Firmware

This guide covers configuring OrcaSlicer to use the extended firmware features: adaptive bed mesh and back purge lines.

## Quick Setup

1. Open OrcaSlicer
2. Go to **Printer Settings** > **Machine G-code**
3. Replace **Machine start G-code** with the template below
4. Save your printer profile

## Machine Start G-code

### Single Extruder (T0 only)

```gcode
; Wait for bed temperature
M190 S[bed_temperature_initial_layer_single]

; Home all axes
G28

; Adaptive bed mesh - probes only the print area
BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5

; Purge line at back of bed
RESET_PURGE_LINE_STATE
SM_PRINT_START_LINE_EXTRUDER_0 TARGET_TEMP=[nozzle_temperature_initial_layer]
```

### Dual Extruder (T0 + T1)

```gcode
; Wait for bed temperature
M190 S[bed_temperature_initial_layer_single]

; Home all axes
G28

; Adaptive bed mesh - probes only the print area
BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5

; Purge lines at back of bed for both extruders
RESET_PURGE_LINE_STATE
SM_PRINT_START_LINE_EXTRUDER_0 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_1 TARGET_TEMP=[nozzle_temperature_initial_layer]
```

### Quad Extruder (All 4)

```gcode
; Wait for bed temperature
M190 S[bed_temperature_initial_layer_single]

; Home all axes
G28

; Adaptive bed mesh - probes only the print area
BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5

; Purge lines at back of bed for all extruders
RESET_PURGE_LINE_STATE
SM_PRINT_START_LINE_EXTRUDER_0 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_1 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_2 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_3 TARGET_TEMP=[nozzle_temperature_initial_layer]
```

## Machine End G-code

### With Print Photo Capture (Recommended)

Capture a photo of your finished print before the bed drops. The photo replaces the gcode thumbnail so the touchscreen shows the actual result.

```gcode
; Move extruder out of camera view
G1 X5 Y5 F6000

; Capture photo while bed is still at print height
CAPTURE_PRINT_PHOTO

; Standard end routine (raises Z, turns off heaters)
PRINT_END
```

Photos are saved to `/userdata/print_photos/` with timestamps and metadata. See [Print Photo Capture](print_photo.md) for details.

### Without Photo Capture

```gcode
PRINT_END
```

## Feature Explanation

### Adaptive Bed Mesh

Instead of probing the entire bed, adaptive mesh only probes the area where your print will be. This:
- Reduces probing time significantly for small prints
- Provides more accurate mesh for the actual print area
- Requires `enable_object_processing: True` in Moonraker (enabled by default in extended firmware)

**Parameters:**
- `ADAPTIVE=1` - Enable adaptive mode
- `ADAPTIVE_MARGIN=5` - Probe 5mm beyond the print boundaries

### Back Purge Line

Draws the purge/prime line at the **back** of the bed instead of the front, keeping it away from your print. Benefits:
- No purge line visible on the front of prints
- Works with all 4 extruders
- Each extruder gets its own purge position

**How it works:**
1. `RESET_PURGE_LINE_STATE` - Clears the "already purged" flags
2. `SM_PRINT_START_LINE_EXTRUDER_N` - Moves to back, heats nozzle, draws purge line
3. Each macro only runs once per print (tracked by `has_finished` variable)

## OrcaSlicer Placeholders Used

| Placeholder | Description |
|-------------|-------------|
| `[bed_temperature_initial_layer_single]` | Bed temp for first layer |
| `[nozzle_temperature_initial_layer]` | Nozzle temp for first layer (current extruder) |

## Troubleshooting

### "Unknown command: BED_MESH_CALIBRATE"
Your Klipper config may not have bed mesh configured. Check that `[bed_mesh]` section exists in your printer config.

### "Unknown command: SM_PRINT_START_LINE_EXTRUDER_0"
The purge macro config is not loaded. Verify `extended/klipper/30_back_purge_macro.cfg` exists on the printer.

### Adaptive mesh not working / probing entire bed
Check that Moonraker has object processing enabled:
```bash
curl -s "http://<printer-ip>:7125/server/config" | jq '.result.config.file_manager.enable_object_processing'
```
Should return `true`. If not, check `extended/moonraker/04_adaptive_mesh.cfg` exists.

### Purge line in wrong position
The purge macro uses `MOVE_TO_XY_IDLE_POSITION_EXTRUDER` which is a Snapmaker-specific macro. If you've modified idle positions, the purge line position may change.

### "Unknown command: CAPTURE_PRINT_PHOTO"
The print photo capture feature requires the `gcode_shell_command` extension. Verify:
1. `/home/lava/klipper/klippy/extras/gcode_shell_command.py` exists
2. `/home/lava/printer_data/config/extended/klipper/10_print_photo.cfg` exists
3. Restart Klipper with `/etc/init.d/S60klipper restart` (not just firmware restart)

### Photo capture says "No print filename available"
This is normal when testing outside of a print job. The macro only captures photos during an active print.

## Where to Configure in OrcaSlicer

1. **Printer Settings** tab (not Print Settings or Filament Settings)
2. Select your Snapmaker U1 printer profile
3. Scroll to **Machine G-code** section
4. Edit **Machine start G-code**

Save the profile after making changes. You can create multiple printer profiles with different start G-code configurations.
