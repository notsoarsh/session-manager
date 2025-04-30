#!/bin/bash
#
# Installation script for Session and Sudo Monitor
# This script sets up the necessary directories, permissions, and systemd services

# Exit on error
set -e

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Create base directories
echo "Creating directories..."
mkdir -p /var/log/session_monitor/sessions
mkdir -p /var/log/session_monitor/sudo
mkdir -p /opt/session_monitor/scripts
mkdir -p /opt/session_monitor/config

# Copy scripts to installation directory
echo "Installing scripts..."
cp scripts/session_monitor.sh /opt/session_monitor/scripts/
cp scripts/sudo_monitor.sh /opt/session_monitor/scripts/
cp scripts/gui_viewer.sh /opt/session_monitor/scripts/

# Make scripts executable
chmod +x /opt/session_monitor/scripts/*.sh

# Create a symbolic link for the user management script
ln -sf /opt/session_monitor/scripts/user_management.sh /usr/local/bin/user-management

# Create config file
cat > /opt/session_monitor/config/monitor.conf << EOF
# Session Monitor Configuration
LOG_DIR=/var/log/session_monitor
SESSION_LOG_DIR=/var/log/session_monitor/sessions
SUDO_LOG_DIR=/var/log/session_monitor/sudo
RETENTION_DAYS=30
EOF

# Set up sudo monitoring by creating a custom sudoers include file
echo "Setting up sudo monitoring..."
cat > /etc/sudoers.d/session_monitor << EOF
Defaults log_output
Defaults!/opt/session_monitor/scripts/sudo_monitor.sh !log_output
Defaults logfile=/var/log/sudo.log
EOF

# Ensure proper permissions
chmod 440 /etc/sudoers.d/session_monitor

# Install systemd service for session monitoring
echo "Installing systemd services..."
cat > /etc/systemd/system/session-monitor.service << EOF
[Unit]
Description=User Session Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/session_monitor/scripts/session_monitor.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Install systemd service for sudo monitoring
cat > /etc/systemd/system/sudo-monitor.service << EOF
[Unit]
Description=Sudo Activity Monitoring Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/session_monitor/scripts/sudo_monitor.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions for log directories
echo "Setting permissions..."
chmod -R 750 /var/log/session_monitor
chown -R root:root /var/log/session_monitor
chmod -R 750 /opt/session_monitor
chown -R root:root /opt/session_monitor

# Create a symbolic link for the GUI viewer
ln -sf /opt/session_monitor/scripts/gui_viewer.sh /usr/local/bin/session-monitor-gui

# Enable and start services
echo "Enabling and starting services..."
systemctl daemon-reload
systemctl enable session-monitor.service
systemctl enable sudo-monitor.service
systemctl start session-monitor.service
systemctl start sudo-monitor.service

# Add bash profile hook for all users to track commands
echo "Setting up bash profile hook..."
cat > /etc/profile.d/session_monitor.sh << EOF
# Session Monitor Command Logging
export HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S "
export PROMPT_COMMAND='if [ -n "\$BASH_COMMAND" ]; then logger -p local1.notice -t bash-history-\$USER "\$(history 1 | sed "s/^[ ]*[0-9]\+[ ]*//" | sed "s/^[ ]*//")" 2>/dev/null; fi'
EOF

# Check for dependencies
echo "Checking dependencies..."
DEPS="dialog logger bash"
MISSING=""

for dep in $DEPS; do
    if ! command -v $dep &> /dev/null; then
        MISSING="$MISSING $dep"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Warning: The following dependencies are missing:$MISSING"
    echo "Please install them using your package manager."
fi

echo "Installation completed successfully!"
echo "You can now run 'session-monitor-gui' to view logs."
