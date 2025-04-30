#!/bin/bash
#
# GUI Viewer for Session and Sudo Logs
# Provides a terminal-based interface to view and search logs using dialog

# Source configuration
source /opt/session_monitor/config/monitor.conf

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Error: dialog is not installed. Please install it using your package manager."
    echo "For example: sudo apt-get install dialog"
    exit 1
fi

# Set dialog colors to match the blue theme in the image
DIALOGRC_TMP="/tmp/dialogrc.$$"
cat <<EOF > "$DIALOGRC_TMP"
screen_color = (WHITE,BLUE,ON)
shadow_color = (BLACK,BLACK,ON)
dialog_color = (BLACK,WHITE,OFF)
title_color = (BLUE,WHITE,ON)
border_color = (WHITE,WHITE,ON)
button_active_color = (WHITE,BLUE,ON)
button_inactive_color = (BLACK,WHITE,OFF)
button_key_active_color = (WHITE,BLUE,ON)
button_key_inactive_color = (RED,WHITE,OFF)
button_label_active_color = (WHITE,BLUE,ON)
button_label_inactive_color = (BLACK,WHITE,ON)
inputbox_color = (BLACK,WHITE,OFF)
inputbox_border_color = (BLACK,WHITE,OFF)
searchbox_color = (BLACK,WHITE,OFF)
searchbox_title_color = (BLUE,WHITE,ON)
searchbox_border_color = (WHITE,WHITE,ON)
position_indicator_color = (BLUE,WHITE,ON)
menubox_color = (BLACK,WHITE,OFF)
menubox_border_color = (WHITE,WHITE,ON)
item_color = (BLACK,WHITE,OFF)
item_selected_color = (WHITE,BLUE,ON)
tag_color = (BLUE,WHITE,ON)
tag_selected_color = (WHITE,BLUE,ON)
tag_key_color = (RED,WHITE,OFF)
tag_key_selected_color = (RED,BLUE,ON)
check_color = (BLACK,WHITE,OFF)
check_selected_color = (WHITE,BLUE,ON)
uarrow_color = (RED,WHITE,ON)
darrow_color = (RED,WHITE,ON)
EOF

export DIALOGRC="$DIALOGRC_TMP"

# Function to get list of users with logs
get_users() {
    find "$LOG_DIR" -type f -name "*.log" | grep -oP '(?<=/)[^/]+(?=_\d{8}\.log)' | sort | uniq
}

# Function to get available dates for a user
get_dates() {
    local username="$1"
    find "$LOG_DIR" -type f -name "${username}_*.log" | grep -oP '\d{8}' | sort | uniq
}

# Function to format date
format_date() {
    local date_str="$1"
    echo "${date_str:0:4}-${date_str:4:2}-${date_str:6:2}"
}

# Display logs
display_logs() {
    local username="$1"
    local date="$2"
    local log_type="$3"
    local search_term="$4"
    
    local log_dir
    if [ "$log_type" == "Session" ]; then
        log_dir="$SESSION_LOG_DIR"
    else
        log_dir="$SUDO_LOG_DIR"
    fi
    
    local log_file="$log_dir/${username}_${date}.log"
    
    if [ ! -f "$log_file" ]; then
        dialog --title "Error" --msgbox "No logs found for $username on $(format_date $date)" 8 50
        return 1
    fi
    
    local title="$log_type Logs for $username on $(format_date $date)"
    
    if [ -n "$search_term" ]; then
        grep -i "$search_term" "$log_file" > /tmp/filtered_logs.$$
        dialog --title "$title (Filtered)" --textbox /tmp/filtered_logs.$$ 20 78
        rm -f /tmp/filtered_logs.$$
    else
        dialog --title "$title" --textbox "$log_file" 20 78
    fi
}

# Export logs
export_logs() {
    local username="$1"
    local date="$2"
    local log_type="$3"
    
    local log_dir
    if [ "$log_type" == "Session" ]; then
        log_dir="$SESSION_LOG_DIR"
    else
        log_dir="$SUDO_LOG_DIR"
    fi
    
    local log_file="$log_dir/${username}_${date}.log"
    
    if [ ! -f "$log_file" ]; then
        dialog --title "Error" --msgbox "No logs found for $username on $(format_date $date)" 8 50
        return 1
    fi
    
    local export_file
    export_file=$(dialog --title "Export Logs" --inputbox "Enter path to save logs:" 8 50 "$HOME/${username}-$date-$log_type.log" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$export_file" ]; then
        cp "$log_file" "$export_file"
        dialog --title "Export Complete" --msgbox "Logs exported to $export_file" 8 50
    fi
}

# Delete old logs
delete_old_logs() {
    local days
    days=$(dialog --title "Delete Old Logs" --inputbox "Delete logs older than how many days?" 8 50 "30" 3>&1 1>&2 2>&3)
    
    if [ $? -eq 0 ] && [ -n "$days" ] && [[ "$days" =~ ^[0-9]+$ ]]; then
        local count
        count=$(find "$LOG_DIR" -type f -name "*.log" -mtime +"$days" | wc -l)
        
        if [ "$count" -eq 0 ]; then
            dialog --title "No Logs Deleted" --msgbox "No logs found older than $days days." 8 50
            return
        fi
        
        if dialog --title "Confirm Deletion" --yesno "Are you sure you want to delete $count log files older than $days days?" 8 60; then
            find "$LOG_DIR" -type f -name "*.log" -mtime +"$days" -delete
            dialog --title "Logs Deleted" --msgbox "$count log files have been deleted." 8 50
        fi
    else
        dialog --title "Invalid Input" --msgbox "Please enter a valid number of days." 8 50
    fi
}

# Select user
select_user() {
    local users=($(get_users))
    
    if [ ${#users[@]} -eq 0 ]; then
        dialog --title "No Logs" --msgbox "No logs found. Please wait for logs to be generated." 8 50
        return 1
    fi
    
    local options=()
    local i=1
    for user in "${users[@]}"; do
        options+=("$i" "$user")
        ((i++))
    done
    
    local choice
    choice=$(dialog --title "Select User" --menu "Choose a user:" 15 50 8 "${options[@]}" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "${users[$((choice-1))]}"
}

# Select date
select_date() {
    local username="$1"
    local dates=($(get_dates "$username"))
    
    if [ ${#dates[@]} -eq 0 ]; then
        dialog --title "No Logs" --msgbox "No logs found for $username." 8 50
        return 1
    fi
    
    local options=()
    local i=1
    for date in "${dates[@]}"; do
        options+=("$i" "$(format_date "$date")")
        ((i++))
    done
    
    local choice
    choice=$(dialog --title "Select Date" --menu "Select a date for $username:" 15 50 8 "${options[@]}" 3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    echo "${dates[$((choice-1))]}"
}

# Select log type
select_log_type() {
    local choice
    choice=$(dialog --title "Log Type" --menu "Select log type:" 10 50 2 \
        "1" "Session" \
        "2" "Sudo" \
        3>&1 1>&2 2>&3)
    
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    if [ "$choice" = "1" ]; then
        echo "Session"
    else
        echo "Sudo"
    fi
}

# Main menu
main_menu() {
    while true; do
        local selected
        selected=$(dialog --title "Session Monitor System" --menu "Choose an option:" 15 60 6 \
            "1" "View Session Logs" \
            "2" "View Sudo Logs" \
            "3" "Search Logs" \
            "4" "Export Logs" \
            "5" "Delete Old Logs" \
            "6" "Exit" \
            3>&1 1>&2 2>&3)
        
        case "$selected" in
            1)
                local username=$(select_user) && local date_value=$(select_date "$username")
                [ $? -eq 0 ] && display_logs "$username" "$date_value" "Session"
                ;;
            2)
                local username=$(select_user) && local date_value=$(select_date "$username")
                [ $? -eq 0 ] && display_logs "$username" "$date_value" "Sudo"
                ;;
            3)
                local username=$(select_user) && local date_value=$(select_date "$username") && local log_type=$(select_log_type)
                [ $? -eq 0 ] && search_term=$(dialog --title "Search" --inputbox "Enter search term:" 8 50 "" 3>&1 1>&2 2>&3) && display_logs "$username" "$date_value" "$log_type" "$search_term"
                ;;
            4)
                local username=$(select_user) && local date_value=$(select_date "$username") && local log_type=$(select_log_type)
                [ $? -eq 0 ] && export_logs "$username" "$date_value" "$log_type"
                ;;
            5)
                delete_old_logs
                ;;
            6|*)
                clear
                break
                ;;
        esac
    done
}

# Run main menu with root check
if [ "$(id -u)" -eq 0 ]; then
    main_menu
else
    if dialog --title "Elevation Required" --yesno "This tool requires elevated privileges to access log files. Run with sudo?" 8 60; then
        sudo "$0"
        exit $?
    else
        dialog --title "Permission Denied" --msgbox "Cannot access log files without elevated privileges." 8 50
        exit 1
    fi
fi

# Cleanup
rm -f "$DIALOGRC_TMP"
