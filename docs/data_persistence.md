---
title: Data Persistence
---

# Data Persistence

**Available in: Basic and Extended firmware**

By default, Snapmaker firmware resets all system changes on reboot for stability.

## Enable System Persistence

To persist system-level changes to `/etc` (SSH passwords, authorized keys, etc.):

```bash
touch /oem/.debug
```

To restore pristine system state:

```bash
rm /oem/.debug
reboot
```

## Printer Data

The `/home/lava/printer_data` directory always persists, regardless of `/oem/.debug`.

## Print Photos

Print photos captured at the end of each print are stored in `/userdata/print_photos/`. The `/userdata` partition persists across firmware updates and reboots.

```
/userdata/print_photos/
├── <job_name>_<timestamp>.jpg    # Full-resolution photo
├── <job_name>_<timestamp>.json   # Metadata (job name, gcode file, timestamp)
├── latest.jpg                    # Symlink to most recent photo
└── latest.json                   # Symlink to most recent metadata
```

See [Print Photo Capture](print_photo.md) for details on the naming convention, metadata format, and scripting examples.

## Firmware Upgrades

**Firmware upgrades automatically remove all persisted changes and delete `/oem/.debug`.**

After upgrading, you can re-enable persistence if needed:

```bash
touch /oem/.debug
```
