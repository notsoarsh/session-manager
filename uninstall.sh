#!/bin/bash
#
# Uninstallation script for Session and Sudo Monitor
# This script removes all components installed by the installation script

# Exit on error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Confirm uninstallation
echo "This will completely remove the Session and Sudo Monitor system."
read -p "Are you sure you want to continue? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Uninstallation cancelled."
    exit 0
fi

# Stop and disable services
echo "Stopping and disabling services..."
systemctl stop session-monitor.service 2>/dev/null || true
systemctl stop sudo-monitor.service 2>/dev/null || true
systemctl disable session-monitor.service 2>/dev/null || true
systemctl disable sudo-monitor.service 2>/dev/null || true

# Remove systemd services
echo "Removing systemd services..."
rm -f /etc/systemd/system/session-monitor.service
rm -f /etc/systemd/system/sudo-monitor.service
systemctl daemon-reload

# Remove sudoers configuration
echo "Removing sudo configuration..."
rm -f /etc/sudoers.d/session_monitor

# Remove bash profile hook
echo "Removing bash profile hook..."
rm -f /etc/profile.d/session_monitor.sh

# Remove symbolic link
echo "Removing symbolic links..."
rm -f /usr/local/bin/session-monitor-gui
#The following line was removed in the update: rm -f /usr/local/bin/user-management

# Ask about log files
read -p "Do you want to keep the log files? (y/n): " keep_logs
if [ "$keep_logs" != "y" ]; then
    echo "Removing log files..."
    rm -rf /var/log/session_monitor
fi

# Remove installation files
echo "Removing installation files..."
rm -rf /opt/session_monitor

echo "Uninstallation completed successfully!"
