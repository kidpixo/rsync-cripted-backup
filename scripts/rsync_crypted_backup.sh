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
  echo "lsblk :"
  lsblk -f
  echo "Connected disks at ${RCB_DISK_BY_ID_GLOB:-/dev/disk/by-id/usb-*} :"
  ls -l ${RCB_DISK_BY_ID_GLOB:-/dev/disk/by-id/usb-*} | sort 
}

# List all known disk configs
list_known_configs() {
  find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
}

# Prompt to create a config for a new disk
create_disk_config() {
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

# Select or create disk config
select_or_create_disk_config() {
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
  local json_file="$CONFIG_DIR/external_disk_notes.json"
  if [[ -f "$json_file" ]]; then
    jq . "$json_file"
  else
    echo "No external disk paths file found at $json_file"
  fi
}

backup_mount_external_disks() {
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
#######################################################################
# Function to get the status of the backup mount points and the current disk
#
# This function checks if the desired mount points are present in the /proc/mounts file
# and if the current disk is set. It prints the status of each mount point and the current disk value.
#
# This function does not take any parameters.
#
# This function does not return any value.
#######################################################################
  # Get the current disk
  local CURRENT_DISK=$(backup_check_disk)

  # Define the desired mount points as an array from config
  local desired_mounts=("${RCB_DESIRED_MOUNTS[@]}")

  # Define color codes for printing messages
  local green='\033[0;32m'  # Green color code
  local red='\033[0;31m'    # Red color code
  local reset='\033[0m'     # Reset color code

  # Show block devices and filesystems
  lsblk -fA
  echo

  # Loop through desired mount points
  for mount_point in "${desired_mounts[@]}"; do
    # Check if mount point is present in /proc/mounts
    if grep -q "$mount_point" /proc/mounts; then
      # Print message if mount point is mounted
      echo -e "${green}'$mount_point' is mounted.${reset}"
    else
      # Print message if mount point is not mounted
      echo -e "${red}'$mount_point' is not mounted.${reset}"
    fi
  done

  # Check if the current disk value is empty or not
  if [[ -n "$CURRENT_DISK" ]]; then
      # Print message if current disk value is not empty
      echo -e "${green}CURRENT_DISK value is '${CURRENT_DISK}'${reset}"
  else
      # Print message if current disk value is empty
      echo  -e "${red}CURRENT_DISK is empty.${reset}"
  fi
}
#### SHORT ALIASES
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