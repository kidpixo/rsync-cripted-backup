#!/bin/bash

CONFIG_DIR="$HOME/.config/rsync_backup"
SCRIPT_NAME="rsync_crypted_backup.sh"

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

CONFIG_FILE="${CONFIG_DIR}/rsync_crypted_backup.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# List all connected disks by-id
list_connected_disks() {
########################################################################
# Function to list all connected disks by-id
#
# This function prints block device information using lsblk and lists all
# connected disks matching the configured glob pattern (RCB_DISK_BY_ID_GLOB).
#
# Returns:
#   None (prints output to stdout)
#
# Example usage:
#   list_connected_disks
########################################################################
  echo "lsblk :"
  lsblk -f
  echo "Connected disks at ${RCB_DISK_BY_ID_GLOB:-/dev/disk/by-id/usb-*} :"
  ls -l ${RCB_DISK_BY_ID_GLOB:-/dev/disk/by-id/usb-*} | sort 
}

# List all known disk configs
list_known_configs() {
########################################################################
# Function to list all known disk configurations
#
# This function lists all directories in the config directory, which represent
# known disk configurations.
#
# Returns:
#   None (prints output to stdout)
#
# Example usage:
#   list_known_configs
########################################################################
  find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

# Prompt to create a config for a new disk
create_disk_config() {
########################################################################
# Function to create a configuration for a new disk
#
# This function creates a new configuration directory for the specified disk,
# and copies fstab and bootloader entries from the mounted disk to the config.
#
# Args:
#   disk_id: The disk ID (by-id basename) to create a config for.
#
# Returns:
#   None (prints output to stdout)
#
# Example usage:
#   create_disk_config "usb-TOSHIBA_EXTERNAL_USB_20231120008590F-0:0"
########################################################################
  local disk_id="$1"
  local config_path="$CONFIG_DIR/$disk_id"
  mkdir -p "$config_path/boot_loader_entries"
  echo "Creating config for $disk_id in $config_path"

  # Try to mount and copy fstab and bootloader entries
  # User must ensure the disk is mounted at $RCB_MOUNT_ROOT and $RCB_MOUNT_BOOT
  if [ -d "$RCB_MOUNT_ROOT/etc" ] && [ -d "$RCB_MOUNT_BOOT/loader/entries" ]; then
    cp "$RCB_MOUNT_ROOT/etc/fstab" "$config_path/fstab"
    cp "$RCB_MOUNT_BOOT/loader/entries/"*.conf "$config_path/boot_loader_entries/"
    echo "{\"created\":\"$(date)\",\"disk_id\":\"$disk_id\"}" > "$config_path/info.json"
    echo "Config created for $disk_id."
  else
    echo "Please mount the disk at $RCB_MOUNT_ROOT and $RCB_MOUNT_BOOT before creating config."
  fi
}

backup_close_external_disks() {
########################################################################
# Function to close the current external disk
#
# This function checks the current external disk and unmounts it from the
# specified mount point. It also deactivates the LVM volume group and
# closes the encrypted partition.
#
# Returns:
#   None
#
# Example usage:
#   backup_close_external_disks
########################################################################
  local CURRENT_DISK=$(backup_check_disk)
  if [ -n "$CURRENT_DISK" ]; then
    echo "Current Disk : $CURRENT_DISK"
    echo "Umount everything under $RCB_MOUNT_ROOT"
    sudo umount -R "$RCB_MOUNT_ROOT"
    echo "Deactivate $RCB_LVM_VG_NAME"
    sudo vgchange -an "$RCB_LVM_VG_NAME"
    echo "Close encrypted partition $RCB_LUKS_NAME"
    sudo cryptsetup close "$RCB_LUKS_NAME"
  else
    echo "NO External Disk Present : STOPPING"
  fi
}

# Select or create disk config
select_or_create_disk_config() {
########################################################################
# Function to select or create a disk configuration interactively
#
# This function lists connected disks and known configs, prompts the user
# to select a disk, and creates a config if needed.
#
# Returns:
#   The selected disk id (prints to stdout)
#
# Example usage:
#   disk_id=$(select_or_create_disk_config)
########################################################################
  local disk_id
  echo "Connected disks:"
  list_connected_disks
  echo "Known configs:"
  list_known_configs
  echo "Enter disk id (from above) to use:"
  read -r disk_id
  if [ ! -d "$CONFIG_DIR/$disk_id" ]; then
    echo "No config found for $disk_id. Create one? [y/N]"
    read -r yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
      create_disk_config "$disk_id"
    else
      exit 1
    fi
  fi
  echo "$disk_id"
}

backup_check_disk() {
########################################################################
# Function to check the current external disk
#
# This function iterates over all known disk configs and checks if each
# disk is currently connected (exists in by-id). It returns the basename
# of the first disk that is both known (has a config) and connected.
#
# Returns:
#   The basename of the first existing disk path, or an empty string if
#   no path exists.
#
# Example usage:
#   current_disk=$(backup_check_disk)
#   echo "Current Disk: $current_disk"
########################################################################
  local -a known_disks
  mapfile -t known_disks < <(list_known_configs)
  for disk in "${known_disks[@]}"; do
    if [[ -e "${RCB_DISK_BY_ID_GLOB/$'*'/$disk}" || -e "/dev/disk/by-id/$disk" ]]; then
      echo "$disk"
      return
    fi
  done
  echo ""
}

backup_external_disk_notes() {
########################################################################
# Function to print notes about external disks
#
# This function prints the contents of the external_disk_notes.json file
# if it exists, using jq for pretty-printing.
#
# Returns:
#   None (prints output to stdout)
#
# Example usage:
#   backup_external_disk_notes
########################################################################
  local json_file="$CONFIG_DIR/external_disk_notes.json"
  if [[ -f "$json_file" ]]; then
    jq . "$json_file"
  else
    echo "No external disk paths file found at $json_file"
  fi
}

backup_mount_external_disks() {
########################################################################
# Function to mount the current external disk
#
# This function checks the current external disk and mounts it to the
# specified mount points, decrypts the LUKS partition, and activates LVM.
#
# Returns:
#   None
#
# Example usage:
#   backup_mount_external_disks
########################################################################
  local CURRENT_DISK=$(backup_check_disk)
  if [ -n "$CURRENT_DISK" ]; then
    echo "Current Disk : $CURRENT_DISK"
    sudo cryptsetup open --type luks "/dev/disk/by-id/$CURRENT_DISK$RCB_DISK_PART_LUKS" "$RCB_LUKS_NAME"
    sudo vgchange -a y "$RCB_LVM_VG_NAME"
    sudo mount "/dev/$RCB_LVM_VG_NAME/root" "$RCB_MOUNT_ROOT"
    sudo mount "/dev/$RCB_LVM_VG_NAME/home" "$RCB_MOUNT_HOME"
    sudo mount "/dev/disk/by-id/$CURRENT_DISK$RCB_DISK_PART_BOOT" "$RCB_MOUNT_BOOT"
  else
    echo "NO External Disk Present : STOPPING"
  fi
}

backup_check_mountpoints() {
########################################################################
# Function to check if the desired mount points are present
#
# This function checks if all desired mount points (from config) are present
# in the /proc/mounts file and returns 0 if all mounts are found, 1 otherwise.
#
# Returns:
#   0 if all mounts found, 1 otherwise (also prints result)
#
# Example usage:
#   backup_check_mountpoints
########################################################################
  local all_mounts=$(awk '{print $2}' /proc/mounts)
  local found=0
  for mount_point in "${RCB_DESIRED_MOUNTS[@]}"; do
    if [[ ! $all_mounts =~ $mount_point ]]; then
      found=1
      break
    fi
  done
  echo $found
  return $found
}

backup_rsync() {
########################################################################
# Function to perform an rsync backup of the system to an external disk.
#
# This function checks if the desired mount points are present and if the
# external disk is connected. If both conditions are met, it performs the
# backup using rsync. Otherwise, it prints a message and stops.
#
# Returns:
#   None
#
# Example usage:
#   backup_rsync
########################################################################
  local green='\033[0;32m'
  local red='\033[0;31m'
  local reset='\033[0m'
  local CURRENT_DISK=$(backup_check_disk)
  echo "Current Disk : $CURRENT_DISK"
  if [[ $(backup_check_mountpoints) -eq 0 ]] && [[ -n "$CURRENT_DISK" ]] ; then
    echo -e "${green}All desired mount points found!${reset}"
    echo "Going on with rsync"

    # Build exclude options from config array
    local exclude_opts=()
    for pattern in "${RCB_EXCLUDE_PATTERNS[@]}"; do
      exclude_opts+=(--exclude="$pattern")
    done

    # Optionally add --dry-run if RCB_DRY_RUN is set
    local dry_run_opt=""
    if [[ "$RCB_DRY_RUN" == "true" ]]; then
      dry_run_opt="--dry-run"
    fi

    # Optionally add -v for verbose
    local verbose_opt=""
    if [[ "$RCB_VERBOSE" == "true" ]]; then
      verbose_opt="-v"
    fi

    # Run rsync for /boot
    sudo rsync $RCB_RSYNC_OPTIONS $verbose_opt $dry_run_opt "${exclude_opts[@]}" \
      "$RCB_SOURCE_DIR/boot/" "$RCB_DESTINATION_DIR/boot"

    # Copy config fstab and bootloader entries from config dir
    sudo cp "$CONFIG_DIR/$CURRENT_DISK/boot_loader_entries/"*.conf "$RCB_DEST_BOOTLOADER_ENTRIES_PATH"
    sudo cp "$CONFIG_DIR/$CURRENT_DISK/fstab" "$RCB_DEST_FSTAB_PATH"

    # Run rsync for the rest
    sudo rsync $RCB_RSYNC_OPTIONS $verbose_opt $dry_run_opt "${exclude_opts[@]}" \
      --exclude="/boot" \
      "$RCB_SOURCE_DIR/" "$RCB_DESTINATION_DIR/"

    # Log if RCB_LOG_FILE is set
    if [[ -n "$RCB_LOG_FILE" ]]; then
      echo "$(date): Backup completed for $CURRENT_DISK" >> "$RCB_LOG_FILE"
    fi
  else
    echo "Some desired mount points are missing!"
    backup_status
  fi
}

backup_status(){
########################################################################
# Function to get the status of the backup mount points and the current disk
#
# This function checks if the desired mount points are present in the /proc/mounts file
# and if the current disk is set. It prints the status of each mount point and the current disk value.
#
# Returns:
#   None
#
# Example usage:
#   backup_status
########################################################################
  local CURRENT_DISK=$(backup_check_disk)
  local desired_mounts=("${RCB_DESIRED_MOUNTS[@]}")
  local green='\033[0;32m'
  local red='\033[0;31m'
  local reset='\033[0m'
  lsblk -fA
  echo
  for mount_point in "${desired_mounts[@]}"; do
    if grep -q "$mount_point" /proc/mounts; then
      echo -e "${green}'$mount_point' is mounted.${reset}"
    else
      echo -e "${red}'$mount_point' is not mounted.${reset}"
    fi
  done
  if [[ -n "$CURRENT_DISK" ]]; then
      echo -e "${green}CURRENT_DISK value is '${CURRENT_DISK}'${reset}"
  else
      echo  -e "${red}CURRENT_DISK is empty.${reset}"
  fi
}

#######################################################################
# Debugging helpers for device-mapper, cryptsetup, and LVM

backup_debug_dmsetup() {
########################################################################
# Function to debug device-mapper
#
# This function prints the device-mapper table and status.
#
# Returns:
#   None
#
# Example usage:
#   backup_debug_dmsetup
########################################################################
  echo "Device-mapper table:"
  sudo dmsetup table
  echo
  echo "Device-mapper status:"
  sudo dmsetup status
}

backup_debug_cryptsetup() {
########################################################################
# Function to debug cryptsetup
#
# This function prints the status of the active cryptsetup mappings.
#
# Returns:
#   None
#
# Example usage:
#   backup_debug_cryptsetup
########################################################################
  echo "Active cryptsetup mappings:"
  sudo cryptsetup status "$RCB_LUKS_NAME" || echo "No mapping named $RCB_LUKS_NAME"
  echo
  echo "All cryptsetup mappings:"
  sudo cryptsetup -v status --all 2>/dev/null || true
}

backup_debug_lvm() {
########################################################################
# Function to debug LVM
#
# This function prints the details of LVM volume groups and logical volumes.
#
# Returns:
#   None
#
# Example usage:
#   backup_debug_lvm
########################################################################
  echo "LVM Volume Groups:"
  sudo vgdisplay
  echo
  echo "LVM Logical Volumes:"
  sudo lvdisplay
}

#######################################################################

#### SHORT ALIASES
# Add short aliases for debug helpers
alias b_debug_dmsetup='backup_debug_dmsetup'
alias b_debug_cryptsetup='backup_debug_cryptsetup'
alias b_debug_lvm='backup_debug_lvm'

alias b_check_disk='backup_check_disk'
alias b_mount_external_disks='backup_mount_external_disks'
alias b_close_external_disks='backup_close_external_disks'
alias b_rsync='backup_rsync'
alias b_status='backup_status'

# Bash completion for backup_ and b_ functions
_backup_completion() {
  local functions=( $(compgen -A function "${@:1}" | grep -E '^[backup_|b_]') )
  COMPREPLY=("${functions[@]}")
}
complete -F _backup_completion backup_

# Main entrypoint for interactive config selection
if [[ "$1" == "--select-disk" ]]; then
  select_or_create_disk_config
fi