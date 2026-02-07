---
title: Klipper and Moonraker Custom Includes
---

# Klipper and Moonraker Custom Includes

**Available in: Extended firmware**

Add custom Klipper and Moonraker configuration files through the Fluidd/Mainsail web interface.

Configuration files are automatically included from:
- Klipper: `extended/klipper/*.cfg`
- Moonraker: `extended/moonraker/*.cfg`

## Usage

1. Open Fluidd or Mainsail (`http://<printer-ip>`)
2. Go to **Configuration** tab
3. Navigate to **extended/klipper/** or **extended/moonraker/** folder
4. Create `.cfg` files with your custom configuration
5. Restart the respective service after making changes

### Example: Custom Klipper Macro

Create `extended/klipper/custom-macros.cfg`:

```cfg
[gcode_macro CUSTOM_MACRO]
gcode:
    G28
    G1 Z10 F600
```

For camera configuration examples, see [Camera Support](camera_support.md#moonraker-camera-configuration).

## Firmware-Provided Configs

The extended firmware ships several config files in `extended/klipper/` and `extended/moonraker/`. These are installed automatically and should not be deleted:

| File | Purpose |
|------|---------|
| `extended/klipper/00_keep.cfg` | Placeholder (do not remove) |
| `extended/klipper/10_print_photo.cfg` | Print photo capture and `PRINT_END` override (see [Print Photo Capture](print_photo.md)) |
| `extended/klipper/30_back_purge_macro.cfg` | Back purge line macros for all 4 extruders (credits: DocKuro) |
| `extended/klipper/mainsail_pause_resume.cfg` | Pause/Resume macro wrappers |
| `extended/moonraker/04_adaptive_mesh.cfg` | Enables object processing for adaptive bed mesh |

You can add your own `.cfg` files alongside these. They are loaded in alphabetical order, so use numeric prefixes to control ordering if needed.

## OrcaSlicer Start G-code Examples

### Adaptive Bed Mesh

The extended firmware enables Moonraker's object processing (`04_adaptive_mesh.cfg`), which allows adaptive bed meshing. Add this to your OrcaSlicer **Machine Start G-code** after homing:

```gcode
; Adaptive bed mesh - only probes the area being printed
BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5
```

### Back Purge Line

The `30_back_purge_macro.cfg` provides macros to draw a purge line at the back of the bed, keeping it away from your print. Add to your **Machine Start G-code**:

```gcode
; Reset purge state (required at start of each print)
RESET_PURGE_LINE_STATE

; Purge lines for each extruder used (add only the ones you need)
SM_PRINT_START_LINE_EXTRUDER_0 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_1 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_2 TARGET_TEMP=[nozzle_temperature_initial_layer]
SM_PRINT_START_LINE_EXTRUDER_3 TARGET_TEMP=[nozzle_temperature_initial_layer]
```

### Combined Example

A complete start gcode combining both features:

```gcode
; Home and heat bed
G28
M190 S[bed_temperature_initial_layer_single]

; Adaptive bed mesh
BED_MESH_CALIBRATE ADAPTIVE=1 ADAPTIVE_MARGIN=5

; Reset and draw purge lines
RESET_PURGE_LINE_STATE
SM_PRINT_START_LINE_EXTRUDER_0 TARGET_TEMP=[nozzle_temperature_initial_layer]
; Add more SM_PRINT_START_LINE_EXTRUDER_N as needed
```

## Important Notes

- All `.cfg` files in `extended/klipper/` and `extended/moonraker/` are automatically included
- Configuration files persist across reboots
- Do not modify or remove the `00_keep.cfg` placeholder files
- Invalid configuration will prevent Klipper/Moonraker from starting
- Test changes carefully before printing

## Configuration Recovery

If an invalid configuration breaks Moonraker (printer won't connect to WiFi), see [Firmware Configuration - Recovery & Reset](firmware_config.md#recovery--reset) for recovery instructions.
