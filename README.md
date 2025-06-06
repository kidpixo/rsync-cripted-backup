# rsync-cripted-backup

A series of script I use for my backup.
**Disclaimer : Use it at your own risk.**

## Overview

The `rsync-crypted-backup` project provides scripts and configuration files to facilitate automated encrypted backups using `rsync`.

The main disk follows Arch [dm-crypt LVM on LUKS](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS) instructions.
My layout is :

- partition 1 : mounted to `/boot`, not encrypted.
- partition 2
  - LUKS cryptlvm
    - volume-swap : swap partition, size to match your RAM
    - volume-root : root system , mounted on `/`
    - volume-home : user homes, mounted a `/home`

The idea is to create a new external disk with the exact same layout (LVM on LUKS), with different UUID, and rsync everything.
A copy of the updated fstab and systemd-boot for each disk with updated UUID are maintained in the configuration and copied over the disk after the rsync.

The resulting disks are bootable copies of the original disk, making possible to plug them in and start from the point of the last backup.

The main script, [`rsync_crypted_backup.sh`](scripts/rsync_crypted_backup.sh), handles backup operations, 
including checking for external disks, mounting them, and performing the backup using your specified configuration.


## Project Structure
```
rsync-cripted-backup
├── install.sh                        # Installer script for setting up the backup system
├── scripts
│   └── rsync_crypted_backup.sh       # Main backup script
├── config
│   ├── external_disk_notes.json      # Optional: notes about external disks
│   └── rsync_crypted_backup.conf     # Example configuration file
└── README.md                         # Documentation for the project
```

Optionally you can put a json file in `CONFIG_DIR="$HOME/.config/rsync_backup"` called `external_disk_notes.json` like :

```json
{
 "disk_UUID" : "Comment, old crappy disk" 
}
```

## Installation Instructions

1. **Clone the repository** (or download the project files):
   ```sh
   git clone <repository-url>
   cd rsync-cripted-backup
   ```

2. **Run the installer script**:
   ```sh
   bash install.sh
   ```

   This script will:
   - Copy [`rsync_crypted_backup.sh`](scripts/rsync_crypted_backup.sh) to `~/.local/bin/` for easy execution.
   - Create a configuration directory at `~/.config/rsync_backup/` and copy [`rsync_crypted_backup.conf`](config/rsync_crypted_backup.conf) there.

## Usage Guidelines

Running `rsync_crypted_backup.sh` without arguments will not perform any actions by default.

To safely perform a backup, follow these steps using the provided aliases (or call the functions directly):

1. **Mount the external disk**  : Unlock, activate, and mount the external backup disk partitions:

```sh
b_mount_external_disks
```
2. **Check the status** 

Verify that all required partitions are mounted and the disk is detected:

```sh
b_status
```

3. **Check the status again** : (Seriously, double-check that everything is mounted and detected correctly!)

4. **Run the backup with rsync**

Start the backup process:

```sh
b_rsync
```

5. When finished, **safely unmount and close the encrypted disks**

```sh
b_close_external_disks
```

Note:

- Each command above is an alias for a function defined in the script.
- Always check the status before running b_rsync to avoid accidental data loss or backup to the wrong disk.

- Before running the script, configure your backup settings in:
  ```
  ~/.config/rsync_backup/rsync_crypted_backup.conf
  ```
  You can copy and modify this file for different backup profiles if needed:
  ```sh
  cp ~/.config/rsync_backup/rsync_crypted_backup.conf ~/.config/rsync_backup/my_backup.conf
  ```

- Edit `rsync_crypted_backup.conf` to set your source, destination, exclude patterns, mount points, and other options.

---

## Script Workflow and Deep Explanation

This script is designed to make a full, encrypted backup of your system to an external disk, following best practices such as those described in the [Arch Wiki: Rsync#Full_system_backup](https://wiki.archlinux.org/title/Rsync#Full_system_backup). The workflow is as follows:

1. **Prepare a New External Disk (One-Time Setup)**
   - Use the `prepare_new_disk` function to interactively partition, encrypt (LUKS), and format a new disk for backup use. This is a destructive operation and should only be done once per new disk.
   - The script will create the necessary partitions (EFI/boot, LUKS), set up LVM volumes, and format the filesystems.

2. **Create Disk Configuration**
   - Use `create_disk_config` to snapshot your main disk's `/etc/fstab` and systemd-boot loader entries. This ensures the backup disk can be made bootable and that mount points are correct.
   - The script copies these files into a per-disk config directory.

3. **Adapt System Files for the New Disk**
   - After copying, you may need to manually edit the `fstab` and bootloader entries in the config directory to match the new disk's UUIDs or device names.

4. **Mount and Unlock the External Disk**
   - The script detects the external disk by its ID, unlocks the LUKS partition, activates the LVM volume group, and mounts the root, home, and boot partitions to the configured mount points.

5. **Perform the Backup**
   - The `backup_rsync` function uses `rsync` to copy your system to the external disk, excluding volatile and unnecessary directories (e.g., `/dev`, `/proc`, `/sys`, `/tmp`, `/run`, `/mnt`, `/media`, `/lost+found`).
   - The backup includes `/boot` and the rest of the system, following the recommended approach for full system backups.

6. **Copy System Files**
   - The script copies the saved `fstab` and bootloader entries from the config directory to the appropriate locations on the backup disk.

7. **Unmount and Close the Disk**
   - After the backup, you should unmount the LVM partitions and close the encrypted container. (Use `backup_close_external_disks`.)

8. **Disconnect the Disk**
   - Safely disconnect the external disk. Your backup is now complete and encrypted.

---

## Script Functions and Aliases

| Function Name                     | Alias                    | Description                                                                                    |
|-----------------------------------|--------------------------|------------------------------------------------------------------------------------------------|
| `list_connected_disks`            |                          | List all connected disks by-id matching the configured glob pattern.                           |
| `list_known_configs`              |                          | List all known disk configurations in the config directory.                                    |
| `create_disk_config`              |                          | Create a configuration snapshot (fstab, bootloader entries) for a new disk.                    |
| `select_or_create_disk_config`    |                          | Interactively select or create a disk configuration.                                           |
| `backup_check_disk`               | `b_check_disk`           | Find the first connected disk with a configuration.                                            |
| `backup_mount_external_disks`     | `b_mount_external_disks` | Unlock, activate, and mount the external backup disk partitions.                               |
| `backup_check_mountpoints`        |                          | Check if all required mount points are present.                                                |
| `backup_rsync`                    | `b_rsync`                | Run the backup process using rsync with configured options and exclusions.                     |
| `backup_status`                   | `b_status`               | Show the current backup/mount status.                                                          |
| `backup_close_external_disks`     | `b_close_external_disks` | Unmount and close the external backup disk.                                                    |
| `backup_external_disk_notes`      |                          | Show notes or JSON info about external disks (if present).                                     |
| `backup_debug_dmsetup`            | `b_debug_dmsetup`        | Show device-mapper table and status for debugging.                                             |
| `backup_debug_cryptsetup`         | `b_debug_cryptsetup`     | Show cryptsetup mapping status for debugging.                                                  |
| `backup_debug_lvm`                | `b_debug_lvm`            | Show LVM VG and LV info for debugging.                                                         |

---

## Configuration Options

Below are the most useful configuration variables you can modify in [`rsync_crypted_backup.conf`](config/rsync_crypted_backup.conf):

 | Variable                                             | Description                                                                                        | Example Value                                             |
 | -------------------------------------------          | -------------------------------------------------------------------------------------------------- | -----------------------------------------------           |
 | `RCB_DISK_BY_ID_GLOB`                                | Glob pattern for external disk device IDs                                                          | `/dev/disk/by-id/usb-*`                                   |
 | `RCB_SOURCE_DIR`                                     | Directory to back up (source)                                                                      | `/home/user`                                              |
 | `RCB_DESTINATION_DIR`                                | Directory where backup will be stored (destination)                                                | `/mnt/backup`                                             |
 | `RCB_EXCLUDE_PATTERNS`                               | Array of patterns to exclude from backup                                                           | `("/dev/*" "/proc/*" "/tmp/*")`                           |
 | `RCB_VERBOSE`                                        | Enable verbose output for rsync (`true` or `false`)                                                | `true`                                                    |
 | `RCB_RSYNC_OPTIONS`                                  | Additional options passed to rsync                                                                 | `-aAXHl --delete --info=progress2 --human-readable`       |
 | `RCB_DRY_RUN`                                        | If set to `true`, rsync will perform a dry run (no changes made)                                   | `true`                                                    |
 | `RCB_LOG_FILE`                                       | Path to log file for backup operations                                                             | `/var/log/rsync_crypted_backup.log`                       |
 | `RCB_MOUNT_ROOT`, `RCB_MOUNT_HOME`, `RCB_MOUNT_BOOT` | Mount points for root, home, and boot partitions on the backup disk                                | `/mnt/backup`, `/mnt/backup/home`, `/mnt/backup/boot`     |
 | `RCB_LVM_VG_NAME`, `RCB_LUKS_NAME`                   | LVM volume group and LUKS mapping names                                                            | `volume_backup`, `cryptlvm_backup`                        |
 | `RCB_DISK_PART_BOOT`, `RCB_DISK_PART_LUKS`           | Suffixes for boot and LUKS partitions on the disk                                                  | `-part1`, `-part2`                                        |
 | `RCB_DESIRED_MOUNTS`                                 | Array of mount points that must be present for backup to proceed                                   | `("$RCB_MOUNT_ROOT" "$RCB_MOUNT_HOME" "$RCB_MOUNT_BOOT")` |
 | `RCB_DEST_FSTAB_PATH`                                | Path where the fstab file will be copied on the backup disk                                        | `$RCB_DESTINATION_DIR/etc/`                               |
 | `RCB_DEST_BOOTLOADER_ENTRIES_PATH`                   | Path where bootloader entry files will be copied on the backup disk                                | `$RCB_DESTINATION_DIR/boot/loader/entries/`               |

**Tip:**  
Edit these variables in your config file to match your system and backup requirements.

---

## Additional Information

- Ensure you have the necessary permissions to mount external disks and perform backups.
- The script uses `sudo` for certain operations, so you may be prompted for your password.
- For any issues or contributions, please refer to the project's repository or contact the maintainer.
