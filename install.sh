#!/bin/bash

# Installer script for rsync backup

# Define the source and destination directories
SCRIPT_SOURCE="./scripts/rsync_crypted_backup.sh"
SCRIPT_DESTINATION="$HOME/.local/bin/rsync_crypted_backup.sh"
CONFIG_SOURCE="./config/rsync_crypted_backup.conf"
CONFIG_DESTINATION="$HOME/.config/rsync_backup/rsync_crypted_backup.conf"

# Create the destination directories if they do not exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/rsync_backup"

# Move the backup script to the local bin directory
if cp "$SCRIPT_SOURCE" "$SCRIPT_DESTINATION"; then
    echo "Backup script installed to $SCRIPT_DESTINATION"
else
    echo "Failed to install backup script."
    exit 1
fi

# Move the rsync_backup configuration file to the config directory
if cp "$CONFIG_SOURCE" "$CONFIG_DESTINATION"; then
    echo "rsync_backup configuration file installed to $CONFIG_DESTINATION"
else
    echo "Failed to install configuration file."
    exit 1
fi

echo "Installation completed successfully."