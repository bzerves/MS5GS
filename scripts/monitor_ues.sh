#!/bin/bash

# Ensure UTF-8 locale is set (important for date parsing and jq)
export LC_ALL=C.UTF-8

# --- Get Script Directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOGO_FILE="${SCRIPT_DIR}/logo.sh"

# --- Configuration ---
CACHE_FILE="/var/lib/rapid5gs/ue_cache.json" # Path to your JSON data

# --- Colors (ANSI Escape Codes) ---
COLOR_RESET='\033[0m'
COLOR_HEADER='\033[1;34m' # Bold Blue
COLOR_BORDER='\033[0;37m' # White/Grey
COLOR_IMSI='\033[0;36m'   # Cyan
COLOR_STATUS_ATTACHED='\033[0;32m' # Green
COLOR_STATUS_DETACHED='\033[0;31m' # Red
COLOR_STATUS_OTHER='\033[0;33m'  # Yellow
COLOR_LAST_SEEN='\033[0;35m' # Magenta
COLOR_APN='\033[0;90m'     # Dark Grey / Bright Black

# --- Column Widths (Ensure these account for padding spaces) ---
# These widths define the space BETWEEN the '|' separators
W_IMSI=18
W_STATUS=10
W_LAST_SEEN=22 # Increased width for M/D/YY, H:MM:SS AM/PM format
W_APNS=48      # Width for APNs - may need adjustment based on typical content

print_ascii_border() {
    local widths=("$@")
    local line="${COLOR_BORDER}+"
    for i in "${!widths[@]}"; do
        # Add +1 to column width to account for space padding inside each cell
        line+=$(printf '%*s' "$((widths[$i] + 1))" "" | tr ' ' "-")
        line+="+"
    done
    line+="${COLOR_RESET}"
    echo -e "$line"
}

# --- Main Table Printing Function ---
print_table() {
  # Check dependencies
  if ! command -v jq &> /dev/null; then
      echo "Error: jq is not installed. Please install it." >&2
      exit 1
  fi
   if ! command -v date &> /dev/null; then
      echo "Error: date command is not available." >&2
      exit 1
  fi

  # Check if cache file exists
  if [ ! -f "$CACHE_FILE" ]; then
      echo "Error: Cache file not found at $CACHE_FILE" >&2
      exit 1
  fi

  # Top border
  print_ascii_border $W_IMSI $W_STATUS $W_LAST_SEEN $W_APNS

  # Header row - Use explicit padding within printf format specifiers
  printf "${COLOR_BORDER}|${COLOR_RESET}"
  printf " ${COLOR_HEADER}%-${W_IMSI}s${COLOR_RESET}" "IMSI"
  printf "${COLOR_BORDER}|${COLOR_RESET}"
  printf " ${COLOR_HEADER}%-${W_STATUS}s${COLOR_RESET}" "STATUS"
  printf "${COLOR_BORDER}|${COLOR_RESET}"
  printf " ${COLOR_HEADER}%-${W_LAST_SEEN}s${COLOR_RESET}" "LAST SEEN" # Header text unchanged
  printf "${COLOR_BORDER}|${COLOR_RESET}"
  printf " ${COLOR_HEADER}%-${W_APNS}s${COLOR_RESET}" "APNs with IPs"
  printf "${COLOR_BORDER}|${COLOR_RESET}\n"

  # Separator line
  print_ascii_border $W_IMSI $W_STATUS $W_LAST_SEEN $W_APNS

  # Data rows processed by jq and while loop
  # JQ now outputs (A)/(D) instead of emojis
  jq -r '
    to_entries | sort_by(.key)[] | select(.value | type == "object") |
    .key as $imsi |
    (.value.status // "unknown") as $status |
    (.value.last_seen // "N/A") as $last_seen |
    (.value.sessions // {}) as $sessions |
    ($sessions | to_entries | map(
      .key + " " +
      (if .value.status == "attached" then "(A)" else "(D)" end) + # Use (A)/(D)
      (if .value.ipv4? then " (" + .value.ipv4 + ")" else "" end)
    ) | join("  ")) as $apns |
    [$imsi, $status, $last_seen, $apns] | @tsv
  ' "$CACHE_FILE" | while IFS=$'\t' read -r imsi status last_seen apns; do
      # Determine status color
      local status_color
      case "$status" in
          attached) status_color="$COLOR_STATUS_ATTACHED";;
          detached) status_color="$COLOR_STATUS_DETACHED";;
          *)        status_color="$COLOR_STATUS_OTHER";;
      esac

      # Format timestamp
      local formatted_last_seen
      if [[ "$last_seen" == "N/A" || -z "$last_seen" ]]; then
          formatted_last_seen="N/A"
      else
          # Use 'date -d' to parse ISO 8601 (handles 'Z' for UTC)
          # Outputs in server's local time by default.
          # Format: Month/Day/Year(2-digit), Hour(1-12):Minute:Second AM/PM
          # Redirect stderr to prevent clutter if date parsing fails
          formatted_last_seen=$(date -d "$last_seen" +"%m/%d/%y %l:%M:%S%p" 2>/dev/null)

          # If date conversion failed, fallback to original string
          if [[ $? -ne 0 || -z "$formatted_last_seen" ]]; then
              formatted_last_seen="$last_seen"
          else
            # Remove leading space potentially added by %l for single-digit hours
             formatted_last_seen="${formatted_last_seen/ /,}"
          fi
      fi

      # Truncate APN string (byte-based) if needed, subtract 1 for leading space
      local truncated_apns
      truncated_apns=${apns:0:$((W_APNS-1))}

      # Print data row with colors and ASCII separators
      printf "${COLOR_BORDER}|${COLOR_RESET}"
      printf " ${COLOR_IMSI}%-${W_IMSI}s${COLOR_RESET}" "$imsi"
      printf "${COLOR_BORDER}|${COLOR_RESET}"
      printf " ${status_color}%-${W_STATUS}s${COLOR_RESET}" "$status"
      printf "${COLOR_BORDER}|${COLOR_RESET}"
      printf " ${COLOR_LAST_SEEN}%-${W_LAST_SEEN}s${COLOR_RESET}" "$formatted_last_seen" # Use formatted date
      printf "${COLOR_BORDER}|${COLOR_RESET}"
      # Pad the potentially truncated string to the full column width
      printf " ${COLOR_APN}%-${W_APNS}s${COLOR_RESET}" "$truncated_apns"
      printf "${COLOR_BORDER}|${COLOR_RESET}\n"

  done

  # Bottom border
  print_ascii_border $W_IMSI $W_STATUS $W_LAST_SEEN $W_APNS
}

# ==============================================
# --- Main Display Loop ---
# ==============================================
# Initial cache load
clear
echo "Updating cache..."
"${SCRIPT_DIR}/monitor_ues__update_cache.sh" > /dev/null 2>&1

while true; do
    # Clear screen
    clear

    # --- Load Logo Function ---
    if [ -r "${SCRIPT_DIR}/logo.sh" ]; then
        . "${SCRIPT_DIR}/logo.sh"
        draw_logo
    else
        echo "Warning: Logo file not found or not readable at ${SCRIPT_DIR}/logo.sh" >&2
        # Define empty logo function as fallback
        function draw_logo() { echo ""; }
    fi

    # --- Call the function to display the table ---
    print_table

    echo # Add one blank line
    echo -e "\e[1;97mPRESS Q TO QUIT, OR R TO REFRESH\e[0m"

    # Wait for single key press
    read -n 1 -s -r key

    # Process the key
    case "$key" in
        q|Q) 
            exit 0 
            ;;
        r|R)
            # Run the update script again on refresh request
            echo "Refreshing cache..."
            "${SCRIPT_DIR}/monitor_ues__update_cache.sh" > /dev/null 2>&1
            echo "Refresh complete. Redrawing..."
            sleep 0.5
            ;;
        *) 
            # For any other key (including enter), just redraw without updating cache
            continue
            ;;
    esac
done