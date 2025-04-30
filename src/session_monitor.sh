#!/bin/bash
#
# Session Monitor Script
# Monitors user login/logout events and commands executed
# Stores logs in structured format

# Source configuration
source /opt/session_monitor/config/monitor.conf

# Ensure log directories exist
mkdir -p "$SESSION_LOG_DIR"

# Function to log message with timestamp
log_message() {
    local username="$1"
    local event_type="$2"
    local message="$3"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_file="$SESSION_LOG_DIR/${username}_$(date +%Y%m%d).log"
    
    echo "[$timestamp] [$event_type] $message" >> "$log_file"
    
    # Set proper permissions
    chmod 640 "$log_file"
}

# Function to handle user login events
handle_login() {
    local username="$1"
    local tty="$2"
    local ip="$3"
    
    log_message "$username" "LOGIN" "User logged in from $ip on $tty"
}

# Function to handle user logout events
handle_logout() {
    local username="$1"
    local tty="$2"
    
    log_message "$username" "LOGOUT" "User logged out from $tty"
}

# Function to clean up old logs
cleanup_old_logs() {
    find "$LOG_DIR" -type f -name "*.log" -mtime +$RETENTION_DAYS -delete
}

# Main monitoring loop
monitor_sessions() {
    # Use the last command to monitor login/logout events
    last -f /var/log/wtmp -n 1 | while read username tty ip rest; do
        if [[ "$username" != "wtmp" && "$username" != "reboot" ]]; then
            handle_login "$username" "$tty" "$ip"
        fi
    done
    
    # Monitor user logout events using wtmp
    last -f /var/log/wtmp | grep "gone" | head -n 1 | while read username tty rest; do
        if [[ "$username" != "wtmp" && "$username" != "reboot" ]]; then
            handle_logout "$username" "$tty"
        fi
    done
    
    # Monitor command history via syslog (configured in /etc/profile.d/session_monitor.sh)
    tail -f /var/log/syslog | grep "bash-history" | while read line; do
        username=$(echo "$line" | grep -oP 'bash-history-\K[^ ]+')
        command=$(echo "$line" | sed 's/.*bash-history-[^:]*: //')
        timestamp=$(echo "$line" | awk '{print $1" "$2" "$3}')
        
        log_message "$username" "COMMAND" "$command"
    done
}

# Run cleanup once a day
(
    while true; do
        cleanup_old_logs
        sleep 86400  # Sleep for 24 hours
    done
) &

# Start monitoring
echo "Starting session monitoring service..."
monitor_sessions
