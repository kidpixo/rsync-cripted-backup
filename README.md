# rsync-crypted-backup

## 🚩 Problem-First Approach

**The Problem:**  
How do you reliably, securely, and repeatably back up a full Linux system—including encrypted partitions—so you can restore or boot from an external disk at any time?

- Manual backups are error-prone and risky.
- Encrypted disks (LUKS, LVM) add complexity.
- You want a bootable, up-to-date copy of your system, not just files.
- You need to automate, verify, and troubleshoot the process.

**The Solution:**  
`rsync-crypted-backup` is a developer-friendly toolkit for creating bootable, encrypted backups of your Linux system. It automates disk detection, mounting, rsync-based backup, and configuration management—making disaster recovery and migration simple and safe.

---

## 🎬 Story: Why This Exists

Imagine your laptop dies, or you need to migrate to new hardware. You want to plug in an external disk, boot, and pick up where you left off.  
This project was born out of real-world pain:  
- Keeping encrypted backups in sync.
- Ensuring bootability (fstab, bootloader entries).
- Avoiding accidental overwrites or missed partitions.

**Design Choices:**
- Follows Arch Linux's [LVM on LUKS](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS) best practices.
- Uses disk-by-id for robust device detection.
- Maintains per-disk configs for UUID-sensitive files.
- Provides actionable CLI functions and aliases.
- Prioritizes safety, transparency, and debuggability.

---

## 💻 Code: How To Use It

### 1. **Installation**

```sh
git clone <repository-url>
cd rsync-crypted-backup
bash install.sh
```
- Installs the main script to `~/.local/bin/rsync_crypted_backup.sh`
- Copies config to `~/.config/rsync_backup/rsync_crypted_backup.conf`

### 2. **Configure Your Backup**

Edit `~/.config/rsync_backup/rsync_crypted_backup.conf`:

```conf
RCB_SOURCE_DIR="/"
RCB_DESTINATION_DIR="/mnt/backup"
RCB_EXCLUDE_PATTERNS=("/dev/*" "/proc/*" "/sys/*" "/tmp/*" "/run/*" "/mnt/*" "/media/*" "/lost+found")
RCB_VERBOSE=true
RCB_LOG_FILE="/var/log/rsync_crypted_backup.log"
# ...and other options
```

### 3. **Workflow: Production-Like Example**

#### **Mount and Unlock the External Disk**
```sh
b_mount_external_disks
```

#### **Verify Everything Is Ready**
```sh
b_status
```

#### **Run the Backup**
```sh
b_rsync
```

#### **Safely Unmount and Close**
```sh
b_close_external_disks
```

#### **Create/Update Disk Config (for bootability)**
```sh
create_disk_config "usb-YourDiskID"
```

#### **Show Disk Notes**
```sh
backup_external_disk_notes
```

### 4. **Edge Case: Dry Run**
Want to test without making changes?
```sh
# In your config:
RCB_DRY_RUN=true
b_rsync
```

---

## 🗺️ Context: Where, When, and How To Use

### **Where/When To Use**
- Full system backups (root, home, boot) to external encrypted disks.
- Disaster recovery, hardware migration, or cloning.
- When you need bootable, encrypted copies—not just file sync.

### **When NOT To Use**
- Backing up only user files (use simpler tools).
- Non-encrypted or non-LVM setups (project assumes LUKS/LVM).
- If you need cloud or incremental backups (consider alternatives).

### **Integration Points**
- Works with any Linux system using disk-by-id.
- Can be versioned/configured per disk.
- Easily scriptable for cron jobs or manual runs.

---

## 🔎 Progressive Disclosure

### **Quick Start**
- Install, configure, run the aliases.

### **Dive Deeper**
- Customize config for multiple disks.
- Edit per-disk fstab/bootloader entries for UUID changes.
- Use debug helpers:
  ```sh
  b_debug_dmsetup
  b_debug_cryptsetup
  b_debug_lvm
  ```

### **Advanced**
- Integrate with CI/CD for automated backup verification.
- Extend with hooks for notifications or remote sync.

---

## 📝 Per-Disk fstab & Bootloader Configuration

When you clone or back up a Linux system to a new disk, the partitions on the backup disk will have different UUIDs than the original. This means you **must update** the `fstab` and systemd-boot loader entries on the backup disk to reference the new UUIDs, or the system may fail to boot.

### Why Is This Important?

- **fstab** tells the system how to mount partitions at boot. If the UUIDs don't match the actual disk, mounts will fail.
- **systemd-boot loader entries** reference the root and boot partitions by UUID. Incorrect UUIDs mean the bootloader can't find the kernel or root filesystem.

### How This Project Handles It

- When you:w run [`create_disk_config`](scripts/rsync_crypted_backup.sh), the script:
  - Copies the current disk's `fstab` and bootloader entries into a per-disk config directory (e.g., `~/.config/rsync_backup/<disk-id>/`).
  - These files are then used during backup to update the backup disk's `/etc/fstab` and `/boot/loader/entries/*.conf` with the correct UUIDs.

### Workflow Example

1. **Mount the backup disk** using `b_mount_external_disks`.
2. **Create or update disk config**:
   ```sh
   create_disk_config "usb-YourDiskID"
   ```
   - This snapshots the current `fstab` and bootloader entries for the disk.
3. **Run the backup**:
   ```sh
   b_rsync
   ```
   - The script copies the per-disk `fstab` and bootloader entries to the backup disk, ensuring UUIDs match the new partitions.

### Manual Editing (If Needed)

If you change partition layouts or UUIDs manually, edit:
- `/etc/fstab` on the backup disk (`$RCB_DEST_FSTAB_PATH`)
- `/boot/loader/entries/*.conf` on the backup disk (`$RCB_DEST_BOOTLOADER_ENTRIES_PATH`)

Use `lsblk -f` to find the new UUIDs and update the files accordingly.

### Troubleshooting

- **Boot fails or root not found?**  
  Check that the UUIDs in `fstab` and bootloader entries match those of the backup disk's partitions.
- **Mount errors?**  
  Use `b_status` and `lsblk -f` to verify mount points and UUIDs.

---

**Tip:** Always verify bootability after backup by testing the backup disk on real hardware or a VM.

## 🧩 Scannable Reference

### **Main Functions & Aliases**

| Function                       | Alias                    | Purpose                                      |
|--------------------------------|--------------------------|----------------------------------------------|
| `list_connected_disks`         |                          | List detected external disks                 |
| `list_known_configs`           |                          | List configs for known disks                 |
| `create_disk_config`           |                          | Snapshot fstab/bootloader for a disk         |
| `backup_check_disk`            | `b_check_disk`           | Find first connected, configured disk        |
| `backup_mount_external_disks`  | `b_mount_external_disks` | Unlock, activate, and mount partitions       |
| `backup_rsync`                 | `b_rsync`                | Run rsync backup                            |
| `backup_status`                | `b_status`               | Show mount and disk status                   |
| `backup_close_external_disks`  | `b_close_external_disks` | Unmount and close encrypted disk             |
| `backup_external_disk_notes`   |                          | Show notes about disks (from JSON)           |
| `backup_debug_dmsetup`         | `b_debug_dmsetup`        | Device-mapper debug info                     |
| `backup_debug_cryptsetup`      | `b_debug_cryptsetup`     | Cryptsetup debug info                        |
| `backup_debug_lvm`             | `b_debug_lvm`            | LVM debug info                               |

---

## 🛠️ Failure Scenarios & Troubleshooting

### **Common Issues**

- **Mount Points Not Found**
  - Error: "Some desired mount points are missing!"
  - Solution: Run `b_status` to check, ensure disk is unlocked and mounted.

- **Disk Not Detected**
  - Error: "NO External Disk Present : STOPPING"
  - Solution: Check connection, run `list_connected_disks`, verify disk ID.

- **Rsync Fails**
  - Error: Permission denied, missing files.
  - Solution: Check config paths, run as root/sudo, verify exclusions.

- **Bootloader/Fstab Not Updated**
  - Error: Backup disk won't boot.
  - Solution: Edit per-disk config files, ensure UUIDs match.

### **Debugging**

- Use debug aliases for device-mapper, cryptsetup, and LVM.
- Check logs at `$RCB_LOG_FILE`.
- Use `backup_external_disk_notes` for disk identification.

---

## 🔄 Workflow Integration

- Version your config files and disk notes in Git.
- Use aliases/functions in shell scripts or CI pipelines.
- Documentation is Markdown—easy to extend, auto-generate, or embed in developer portals.

---

## 🧭 Alternatives

- For file-only backups: [rsnapshot](https://rsnapshot.org/), [restic](https://restic.net/)
- For cloud: [BorgBackup](https://borgbackup.readthedocs.io/en/stable/), [Duplicity](http://duplicity.nongnu.org/)
- For non-encrypted disks: vanilla `rsync` scripts.

---

## 🙋 FAQ

**Q: Can I use this for incremental backups?**  
A: Not directly—this is for full system syncs. Use rsync options for partial updates.

**Q: What if my disk UUID changes?**  
A: Update the config and per-disk fstab/bootloader entries.

**Q: Is this safe for production?**  
A: Yes, but always test with dry runs and verify backups before relying on them.

---

## 📚 Further Reading

- [Arch Wiki: Full System Backup](https://wiki.archlinux.org/title/Rsync#Full_system_backup)
- [Arch Wiki: LVM on LUKS](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS)
- [Universal Ctags](https://ctags.io/)

---

## 📝 Contributing & Support

- Issues and PRs welcome!
- For questions, open an issue or contact the maintainer.

---

**Happy (and safe) backing
