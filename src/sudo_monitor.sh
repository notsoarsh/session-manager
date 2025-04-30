#!/bin/bash
#
# Sudo Monitor Script
# Monitors all sudo activities and logs them
# Tracks who, what, and when for sudo commands

# Source configuration
source /opt/session_monitor/config/monitor.conf

# Ensure log directories exist
mkdir -p "$SUDO_LOG_DIR"

# Function to log sudo event
log_sudo_event() {
    local username="$1"
    local command="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_file="$SUDO_LOG_DIR/${username}_$(date +%Y%m%d).log"
    local status="$3"
    
    echo "[$timestamp] [$status] $command" >> "$log_file"
    
    # Set proper permissions
    chmod 640 "$log_file"
}

# Function to monitor sudo log
monitor_sudo_log() {
    # Monitor the sudo log file
    tail -f /var/log/sudo.log | while read line; do
        # Extract username, command and status from sudo log
        if [[ "$line" =~ .*COMMAND=.* ]]; then
            username=$(echo "$line" | grep -oP '(?<=USER=)[^ ]+')
            command=$(echo "$line" | grep -oP '(?<=COMMAND=).*')
            
            # Check if command was successful or failed
            if [[ "$line" =~ .*COMMAND_NOT_FOUND.* ]]; then
                status="FAILED"
            else
                status="SUCCESS"
            fi
            
            log_sudo_event "$username" "$command" "$status"
        fi
    done
}

# Function to monitor auth.log for failed sudo attempts
monitor_auth_log() {
    tail -f /var/log/auth.log | grep "sudo" | while read line; do
        if [[ "$line" =~ .*authentication failure.* ]]; then
            username=$(echo "$line" | grep -oP '(?<=user=)[^ ]+')
            timestamp=$(echo "$line" | awk '{print $1" "$2" "$3}')
            
            log_sudo_event "$username" "Failed sudo authentication" "FAILED"
        fi
    done
}

# Function to clean up old logs
cleanup_old_logs() {
    find "$SUDO_LOG_DIR" -type f -name "*.log" -mtime +$RETENTION_DAYS -delete
}

# Run cleanup once a day
(
    while true; do
        cleanup_old_logs
        sleep 86400  # Sleep for 24 hours
    done
) &

# Start monitoring in parallel
echo "Starting sudo monitoring service..."
monitor_sudo_log &
monitor_auth_log
