#!/bin/bash

# --- Colors and Styling ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'    # No Color
BOLD='\033[1m'

# --- UI Constants ---
BOX_WIDTH=25
PADDING=2
COLUMNS=3
ATTACHED_MARK="✅"
DETACHED_MARK="❌"

# --- Helper Functions ---
print_header() {
    echo -e "\n${BOLD}${YELLOW}==============================================${NC}"
    echo -e "${BOLD}${YELLOW}      Open5GS eNB Status Monitor          ${NC}"
    echo -e "${BOLD}${YELLOW}==============================================${NC}\n"
}

draw_box() {
    local id="$1"
    local status="$2"
    local last_seen="$3"
    local width=$BOX_WIDTH
    local status_color=$RED
    local status_mark=$DETACHED_MARK
    
    if [ "$status" = "attached" ]; then
        status_color=$GREEN
        status_mark=$ATTACHED_MARK
    fi

    # Top border
    printf "┌─%s─┐\n" "$(printf '─%.0s' $(seq 1 $width))"
    
    # ID line
    printf "│ %-${width}s │\n" "eNB ID: $id"
    
    # Status line
    printf "│ Status: ${status_color}%-$(($width-8))s${NC} │\n" "$status $status_mark"
    
    # Last Seen line
    printf "│ Last Seen: %-$(($width-12))s │\n" "$last_seen"
    
    # Bottom border
    printf "└─%s─┘\n" "$(printf '─%.0s' $(seq 1 $width))"
}

# Function to extract time from journal log entry
extract_time() {
    local log_entry="$1"
    echo "$log_entry" | awk '{print $1" "$2" "$3}'
}

# --- Main Program ---
print_header

echo -e "${BOLD}Scanning logs for eNB information...${NC}\n"

# Get all eNB related logs from journalctl for all Open5GS services
# Collect logs from both MME (4G) and AMF (5G) which handle eNB connections
enb_logs=$(journalctl -u open5gs-mmed -u open5gs-amfd --no-pager | grep -i "enb")

# Extract eNB IDs and information
declare -A enbs
declare -A enb_status
declare -A enb_last_seen

# Process logs to extract information
while IFS= read -r line; do
    # Extract eNB ID
    if [[ $line =~ eNB\ ID:\ ([0-9]+) ]]; then
        enb_id="${BASH_REMATCH[1]}"
        enbs["$enb_id"]=1
        
        # Extract timestamp
        last_seen=$(extract_time "$line")
        enb_last_seen["$enb_id"]="$last_seen"
        
        # Determine status based on log message
        if [[ $line =~ "Connection established" || $line =~ "connected" ]]; then
            enb_status["$enb_id"]="attached"
        elif [[ $line =~ "Connection closed" || $line =~ "disconnected" ]]; then
            enb_status["$enb_id"]="detached"
        fi
    fi
done <<< "$enb_logs"

# If we found no eNBs, try another approach to find data
if [ ${#enbs[@]} -eq 0 ]; then
    echo -e "${YELLOW}No direct eNB logs found, attempting to find related S1AP/NGAP messages...${NC}\n"
    enb_logs=$(journalctl -u open5gs-mmed -u open5gs-amfd --no-pager | grep -iE 's1ap|ngap|sctp')
    
    while IFS= read -r line; do
        # Look for S1AP/NGAP Setup Request which includes eNB information
        if [[ $line =~ "S1AP|S1 Setup Request" || $line =~ "NGAP|NG Setup Request" ]]; then
            if [[ $line =~ \[([0-9]+)\] ]]; then
                enb_id="${BASH_REMATCH[1]}"
                enbs["$enb_id"]=1
                last_seen=$(extract_time "$line")
                enb_last_seen["$enb_id"]="$last_seen"
                enb_status["$enb_id"]="attached"
            fi
        fi
    done <<< "$enb_logs"
fi

# If still no data, display a message
if [ ${#enbs[@]} -eq 0 ]; then
    echo -e "${RED}No eNB information found in the logs.${NC}"
    echo -e "${YELLOW}This could be because:${NC}"
    echo -e "1. No eNBs have connected to this system yet"
    echo -e "2. Logs have been rotated/cleared"
    echo -e "3. eNB connection information is logged differently in this version"
    exit 0
fi

# Display eNBs in boxes with 3 columns
echo -e "${BOLD}Found ${#enbs[@]} eNBs:${NC}\n"

# Sort eNB IDs numerically
mapfile -t sorted_enbs < <(printf '%s\n' "${!enbs[@]}" | sort -n)

# Calculate how many rows we need
total_enbs=${#sorted_enbs[@]}
rows=$(( (total_enbs + COLUMNS - 1) / COLUMNS ))  # Ceiling division

# Temporary file to store box content
TEMP_FILE=$(mktemp)

# Generate all boxes first
for enb_id in "${sorted_enbs[@]}"; do
    status="${enb_status[$enb_id]:-unknown}"
    last_seen="${enb_last_seen[$enb_id]:-unknown}"
    
    # Store box in a temporary file
    {
        draw_box "$enb_id" "$status" "$last_seen"
        echo ""  # Add a blank line between boxes
    } >> "$TEMP_FILE"
done

# Read box lines
readarray -t box_lines < "$TEMP_FILE"
lines_per_box=5  # Number of lines per box (including spacing)

# Display boxes in columns
for ((row=0; row<rows; row++)); do
    # For each row of boxes
    for ((box_row=0; box_row<lines_per_box; box_row++)); do
        # For each line within the boxes
        for ((col=0; col<COLUMNS; col++)); do
            idx=$((row + col*rows))
            if [ $idx -lt $total_enbs ]; then
                line_idx=$((idx * lines_per_box + box_row))
                if [ $line_idx -lt ${#box_lines[@]} ]; then
                    printf "%-$((BOX_WIDTH+6))s" "${box_lines[$line_idx]}"
                fi
            fi
        done
        echo  # New line after each row of boxes
    done
done

# Clean up
rm -f "$TEMP_FILE"

echo -e "\n${BOLD}${YELLOW}Note:${NC} This report shows eNBs that have connected to the system."
echo -e "Status is based on the most recent event in the logs for each eNB." 