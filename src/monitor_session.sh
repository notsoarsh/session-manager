#!/bin/bash

# monitor_system.sh - A comprehensive system monitoring tool
# 
# This script provides a dialog-based interface to monitor user sessions
# and sudo commands on a Linux system.


# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "dialog is not installed. Installing..."
    sudo apt-get update && sudo apt-get install -y dialog
    if [ $? -ne 0 ]; then
        echo "Failed to install dialog. Please install it manually."
        exit 1
    fi
fi

# Set dialog dimensions
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
MENU_HEIGHT=12
EXPORT_DIR="$HOME/system_logs_export"

# Create export directory if it doesn't exist
mkdir -p "$EXPORT_DIR"

# Check if running as root
is_root() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    else
        return 0
    fi
}

# Function to display a message box
show_message() {
    local title="$1"
    local message="$2"
    
    dialog --title "$title" --msgbox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

# Function to display text in a scrollable box
show_text() {
    local title="$1"
    local text="$2"
    local temp_file=$(mktemp)
    
    echo "$text" > "$temp_file"
    
    dialog --title "$title" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to get total number of users from /etc/passwd
get_total_users() {
    local user_count=$(cat /etc/passwd | grep -v "nologin\|false" | wc -l)
    local user_list=$(cat /etc/passwd | grep -v "nologin\|false" | cut -d: -f1 | sort)
    
    show_text "Total Users" "Total number of users on the system: $user_count\n\nUser list:\n$user_list"
}

# Function to show currently logged in users
show_logged_in_users() {
    local logged_in=$(who 2>/dev/null)
    local user_count=0
    
    if [ -n "$logged_in" ]; then
        user_count=$(echo "$logged_in" | wc -l)
        show_text "Logged In Users" "Number of users currently logged in: $user_count\n\n$logged_in"
    else
        show_text "Logged In Users" "No users currently logged in or unable to retrieve information."
    fi
}

# Function to show session time per user
show_session_time() {
    local session_info=$(w -h 2>/dev/null)
    
    if [ -n "$session_info" ]; then
        show_text "Session Time per User" "Login time and duration for each active session:\n\nUSER\tTTY\t\tLOGIN@\t\tIDLE\n$session_info"
    else
        show_text "Session Time" "No active sessions found or unable to retrieve information."
    fi
}

# Function to display CPU utilization
show_cpu_utilization() {
    local temp_file=$(mktemp)
    
    echo "Current CPU utilization:" > "$temp_file"
    echo "" >> "$temp_file"
    
    if top -bn1 &>/dev/null; then
        top -bn1 | head -n 5 >> "$temp_file"
    else
        echo "Unable to retrieve CPU information using top." >> "$temp_file"
    fi
    
    echo "" >> "$temp_file"
    echo "Detailed CPU stats:" >> "$temp_file"
    
    if command -v mpstat &>/dev/null; then
        mpstat | tail -n +4 >> "$temp_file"
    else
        echo "mpstat not installed. Install using: sudo apt-get install sysstat" >> "$temp_file"
    fi
    
    dialog --title "CPU Utilization" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to display memory utilization
show_memory_utilization() {
    local temp_file=$(mktemp)
    
    echo "Current memory usage:" > "$temp_file"
    echo "" >> "$temp_file"
    
    if free -h &>/dev/null; then
        free -h >> "$temp_file"
    else
        echo "Unable to retrieve memory information using free." >> "$temp_file"
    fi
    
    echo "" >> "$temp_file"
    echo "Detailed memory stats:" >> "$temp_file"
    
    if vmstat -s &>/dev/null; then
        vmstat -s | head -n 10 >> "$temp_file"
    else
        echo "Unable to retrieve memory statistics using vmstat." >> "$temp_file"
    fi
    
    dialog --title "Memory Utilization" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to display network utilization
show_network_utilization() {
    local temp_file=$(mktemp)
    
    echo "Network interface statistics:" > "$temp_file"
    echo "" >> "$temp_file"
    
    if command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "inet|RX|TX" >> "$temp_file"
    elif command -v ip &> /dev/null; then
        ip -s link >> "$temp_file"
    else
        echo "Neither ifconfig nor ip command found." >> "$temp_file"
    fi
    
    echo "" >> "$temp_file"
    
    # Check if vnstat is available for historical data
    if command -v vnstat &> /dev/null; then
        echo "Network traffic summary (vnstat):" >> "$temp_file"
        vnstat -s >> "$temp_file"
    else
        echo "vnstat not installed. Install using: sudo apt-get install vnstat" >> "$temp_file"
    fi
    
    dialog --title "Network Utilization" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to list commands run by each user
list_user_commands() {
    local temp_file=$(mktemp)
    local users=$(cat /etc/passwd | grep -v "nologin\|false" | cut -d: -f1)
    local found_history=0
    
    echo "Recent commands run by users (last 20 per user):" > "$temp_file"
    echo "" >> "$temp_file"
    
    for user in $users; do
        if [ -f "/home/$user/.bash_history" ] && [ -r "/home/$user/.bash_history" ]; then
            echo "User: $user" >> "$temp_file"
            tail -n 20 "/home/$user/.bash_history" 2>/dev/null | sort | uniq -c | sort -nr >> "$temp_file"
            echo "" >> "$temp_file"
            found_history=1
        fi
    done
    
    if [ $found_history -eq 0 ]; then
        echo "No command history found or permission denied." >> "$temp_file"
        echo "" >> "$temp_file"
        echo "Note: This feature requires root privileges to access other users' bash history files." >> "$temp_file"
    fi
    
    dialog --title "User Command History" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to display sudo commands
show_sudo_commands() {
    local temp_file=$(mktemp)
    local found_logs=0
    
    echo "Recent sudo commands (last 50):" > "$temp_file"
    echo "" >> "$temp_file"
    
    if [ -f "/var/log/auth.log" ] && [ -r "/var/log/auth.log" ]; then
        grep "sudo" /var/log/auth.log 2>/dev/null | tail -n 50 >> "$temp_file"
        found_logs=1
    elif command -v journalctl &> /dev/null; then
        journalctl | grep "sudo" 2>/dev/null | tail -n 50 >> "$temp_file"
        found_logs=1
    fi
    
    if [ $found_logs -eq 0 ]; then
        echo "No sudo logs found or permission denied." >> "$temp_file"
        echo "" >> "$temp_file"
        echo "Note: This feature requires root privileges to access system logs." >> "$temp_file"
        echo "Try running the script with sudo: sudo ./monitor_system.sh" >> "$temp_file"
    fi
    
    dialog --title "Sudo Commands" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to display structured sudo commands by user
show_structured_sudo() {
    local temp_file=$(mktemp)
    local found_logs=0
    
    echo "Sudo Command Usage by User:" > "$temp_file"
    echo "===========================" >> "$temp_file"
    echo "" >> "$temp_file"
    
    if [ -f "/var/log/auth.log" ] && [ -r "/var/log/auth.log" ]; then
        grep "sudo" /var/log/auth.log 2>/dev/null | grep "COMMAND" | \
        awk '{
            user=""; 
            for(i=1; i<=NF; i++) { 
                if($i ~ /USER=/) {
                    user=substr($i, 6);
                    break;
                }
            }
            cmd="";
            for(i=1; i<=NF; i++) {
                if($i ~ /COMMAND=/) {
                    for(j=i; j<=NF; j++) {
                        cmd=cmd" "$j;
                    }
                    break;
                }
            }
            timestamp=$1" "$2" "$3;
            printf "%-12s | %-20s | %s\n", user, timestamp, cmd;
        }' | tail -n 100 >> "$temp_file"
        found_logs=1
    elif command -v journalctl &> /dev/null; then
        journalctl 2>/dev/null | grep "sudo" | grep "COMMAND" | \
        awk '{
            user=""; 
            for(i=1; i<=NF; i++) { 
                if($i ~ /USER=/) {
                    user=substr($i, 6);
                    break;
                }
            }
            cmd="";
            for(i=1; i<=NF; i++) {
                if($i ~ /COMMAND=/) {
                    for(j=i; j<=NF; j++) {
                        cmd=cmd" "$j;
                    }
                    break;
                }
            }
            timestamp=$1" "$2" "$3;
            printf "%-12s | %-20s | %s\n", user, timestamp, cmd;
        }' | tail -n 100 >> "$temp_file"
        found_logs=1
    fi
    
    if [ $found_logs -eq 0 ]; then
        echo "No sudo logs found or permission denied." >> "$temp_file"
        echo "" >> "$temp_file"
        echo "Note: This feature requires root privileges to access system logs." >> "$temp_file"
        echo "Try running the script with sudo: sudo ./monitor_system.sh" >> "$temp_file"
    fi
    
    dialog --title "Structured Sudo Commands" --backtitle "System Monitor" \
           --scrollbar --cr-wrap \
           --textbox "$temp_file" $DIALOG_HEIGHT $DIALOG_WIDTH
    
    rm -f "$temp_file"
}

# Function to export logs
    
# Function to export logs
export_logs() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_file="$EXPORT_DIR/system_logs_$timestamp.txt"

    # Create export file
    touch "$export_file" || { show_message "Export Error" "Failed to create export file."; return; }

    # SYSTEM INFO
    echo "=== SYSTEM INFORMATION ===" >> "$export_file"
    echo "Date: $(date)" >> "$export_file"
    echo "Hostname: $(hostname)" >> "$export_file"
    echo "Kernel: $(uname -r)" >> "$export_file"
    echo "Uptime: $(uptime -p)" >> "$export_file"
    echo "" >> "$export_file"

    # USERS
    echo "=== USER INFORMATION ===" >> "$export_file"
    local user_count=$(cat /etc/passwd | grep -v "nologin\|false" | wc -l)
    echo "Total Users: $user_count" >> "$export_file"
    echo "User List:" >> "$export_file"
    cat /etc/passwd | grep -v "nologin\|false" | cut -d: -f1 | sort >> "$export_file"
    echo "" >> "$export_file"

    echo "=== LOGGED IN USERS ===" >> "$export_file"
    who >> "$export_file" 2>/dev/null || echo "Unable to retrieve who output." >> "$export_file"
    echo "" >> "$export_file"

    echo "=== SESSION TIME ===" >> "$export_file"
    w -h >> "$export_file" 2>/dev/null || echo "Unable to retrieve session time." >> "$export_file"
    echo "" >> "$export_file"

    # CPU
    echo "=== CPU UTILIZATION ===" >> "$export_file"
    top -bn1 | head -n 5 >> "$export_file" 2>/dev/null || echo "top command failed." >> "$export_file"
    if command -v mpstat &>/dev/null; then
        mpstat | tail -n +4 >> "$export_file"
    else
        echo "mpstat not installed." >> "$export_file"
    fi
    echo "" >> "$export_file"

    # MEMORY
    echo "=== MEMORY UTILIZATION ===" >> "$export_file"
    free -h >> "$export_file" 2>/dev/null || echo "free command failed." >> "$export_file"
    if command -v vmstat &>/dev/null; then
        vmstat -s | head -n 10 >> "$export_file"
    else
        echo "vmstat not available." >> "$export_file"
    fi
    echo "" >> "$export_file"

    # NETWORK
    echo "=== NETWORK UTILIZATION ===" >> "$export_file"
    if command -v ifconfig &> /dev/null; then
        ifconfig | grep -E "inet|RX|TX" >> "$export_file"
    elif command -v ip &> /dev/null; then
        ip -s link >> "$export_file"
    else
        echo "No network tools available." >> "$export_file"
    fi
    if command -v vnstat &>/dev/null; then
        echo "" >> "$export_file"
        vnstat -s >> "$export_file"
    else
        echo "vnstat not installed." >> "$export_file"
    fi
    echo "" >> "$export_file"

    # USER COMMAND HISTORY
    echo "=== USER COMMAND HISTORY ===" >> "$export_file"
    local users=$(cat /etc/passwd | grep -v "nologin\|false" | cut -d: -f1)
    for user in $users; do
        if [ -f "/home/$user/.bash_history" ] && [ -r "/home/$user/.bash_history" ]; then
            echo "User: $user" >> "$export_file"
            tail -n 20 "/home/$user/.bash_history" 2>/dev/null | sort | uniq -c | sort -nr >> "$export_file"
            echo "" >> "$export_file"
        fi
    done
    echo "" >> "$export_file"

    # SUDO COMMANDS
    echo "=== SUDO COMMAND HISTORY ===" >> "$export_file"
    if [ -f "/var/log/auth.log" ]; then
        grep "sudo" /var/log/auth.log | tail -n 50 >> "$export_file"
    elif command -v journalctl &> /dev/null; then
        journalctl | grep "sudo" | tail -n 50 >> "$export_file"
    else
        echo "Unable to retrieve sudo logs." >> "$export_file"
    fi

    show_message "Export Successful" "Logs exported to:\n$export_file"
}


# Function to check privileges and show warning if needed
check_privileges() {
    if ! is_root; then
        show_message "Privilege Warning" "You are not running this script as root.\n\nSome features may not work correctly without root privileges, such as:\n- Accessing system logs\n- Reading other users' command history\n- Viewing detailed sudo commands\n\nConsider running with sudo for full functionality."
    fi
}

# Main menu function
main_menu() {
    # Check privileges on startup
    check_privileges
    
    while true; do
        exec 3>&1
        selection=$(dialog \
            --backtitle "System Monitor" \
            --title "Main Menu" \
            --clear \
            --cancel-label "Exit" \
            --menu "Select an option:" $DIALOG_HEIGHT $DIALOG_WIDTH $MENU_HEIGHT \
            "1" "User Sessions" \
            "2" "Sudo Commands" \
            "3" "Export Logs" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-
        
        case $exit_status in
            1)
                clear
                echo "Program terminated."
                exit 0
                ;;
            255)
                clear
                echo "Program terminated."
                exit 0
                ;;
        esac
        
        case $selection in
            1)
                user_sessions_menu
                ;;
            2)
                sudo_commands_menu
                ;;
            3)
                export_logs
                ;;
        esac
    done
}

# User Sessions submenu
user_sessions_menu() {
    while true; do
        exec 3>&1
        selection=$(dialog \
            --backtitle "System Monitor" \
            --title "User Sessions" \
            --clear \
            --cancel-label "Back" \
            --menu "Select an option:" $DIALOG_HEIGHT $DIALOG_WIDTH $MENU_HEIGHT \
            "1" "Total number of users" \
            "2" "Currently logged in users" \
            "3" "Session time per user" \
            "4" "CPU utilization" \
            "5" "Memory utilization" \
            "6" "Network utilization" \
            "7" "User command history" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-
        
        case $exit_status in
            1)
                break
                ;;
            255)
                break
                ;;
        esac
        
        case $selection in
            1)
                get_total_users
                ;;
            2)
                show_logged_in_users
                ;;
            3)
                show_session_time
                ;;
            4)
                show_cpu_utilization
                ;;
            5)
                show_memory_utilization
                ;;
            6)
                show_network_utilization
                ;;
            7)
                list_user_commands
                ;;
        esac
    done
}

# Sudo Commands submenu
sudo_commands_menu() {
    while true; do
        exec 3>&1
        selection=$(dialog \
            --backtitle "System Monitor" \
            --title "Sudo Commands" \
            --clear \
            --cancel-label "Back" \
            --menu "Select an option:" $DIALOG_HEIGHT $DIALOG_WIDTH $MENU_HEIGHT \
            "1" "Raw sudo commands" \
            "2" "Structured sudo commands by user" \
            2>&1 1>&3)
        exit_status=$?
        exec 3>&-
        
        case $exit_status in
            1)
                break
                ;;
            255)
                break
                ;;
        esac
        
        case $selection in
            1)
                show_sudo_commands
                ;;
            2)
                show_structured_sudo
                ;;
        esac
    done
}

# Start the main menu
main_menu
