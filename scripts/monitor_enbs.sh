#!/bin/bash

# Configuration
CACHE_FILE="/var/lib/rapid5gs/enb_cache.json"
NUM_COLUMNS=8

# --- Define Column Widths (including padding/borders) ---
ROW_NUM_COL_WIDTH=5
IP_COL_WIDTH=17
STATUS_COL_WIDTH=12
LAST_SEEN_COL_WIDTH=21
PING_COL_WIDTH=9
declare -A FIXED_WIDTH_COLS=(
    [0]=$ROW_NUM_COL_WIDTH [1]=$IP_COL_WIDTH [3]=$STATUS_COL_WIDTH
    [6]=$LAST_SEEN_COL_WIDTH [7]=$PING_COL_WIDTH
)
DYNAMIC_COL_INDICES=(2 4 5)
NUM_DYNAMIC_COLS=${#DYNAMIC_COL_INDICES[@]}
MIN_COL_WIDTH=5

# --- Get Script Directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOGO_FILE="${SCRIPT_DIR}/logo.sh"

# ==============================================
# --- Run Cache Update Script & Clear Screen ---
# ==============================================
echo "Updating cache..." # Simple status message (optional)
# Execute the update script silently (suppress output/errors)
"${SCRIPT_DIR}/monitor_enbs__update_cache.sh" > /dev/null 2>&1
# If you *want* to see output/errors from the update script, use this instead:
# "${SCRIPT_DIR}/monitor_enbs__update_cache.sh"

# Clear the screen after running the update script
clear
# ==============================================

# --- Terminal Dimensions ---
get_terminal_dimensions() {
    stty size
}

# --- Drawing Functions (ASCII Version) ---
draw_ascii_line() {
    local widths=("$@")
    local line="+"
    for i in "${!widths[@]}"; do
        local w=${widths[$i]}
        [ "$w" -lt 0 ] && w=0 # Ensure width is not negative
        line+=$(printf '%*s' "$w" '' | tr ' ' '-')
        line+="+"
    done
    echo "$line"
}


# --- awk Scripts ---
# (awk scripts remain the same)
awk_header_script=$(cat <<'EOF'
BEGIN {
    split(widths_var, widths_arr, " ")
    h_contents[1]="#"; h_contents[2]="IP Address"; h_contents[3]="Name"; h_contents[4]="Status"; h_contents[5]="Brand"; h_contents[6]="Model"; h_contents[7]="Last Seen"; h_contents[8]="Ping";
    header_row = "|"
    for (i=1; i<=8; i++) {
        content = h_contents[i]; width = widths_arr[i]; inner_width = width - 2
        if (inner_width < 0) inner_width = 0
        truncated_content = content
        if (length(content) > inner_width) {
             if (inner_width <= 1) { truncated_content = substr(content, 1, inner_width) }
             else { truncated_content = sprintf("%s…", substr(content, 1, inner_width - 1)) }
        }
        header_row = header_row sprintf(" %-*s |", inner_width, truncated_content)
    }
    print header_row
}
EOF
)
awk_data_script=$(cat <<'EOF'
BEGIN { FS = "\t" }
{
    ip = ($1 != "") ? $1 : "-"; name = ($2 != "") ? $2 : "-"; status = ($3 != "") ? $3 : "-"; brand = ($4 != "") ? $4 : "-"; model = ($5 != "") ? $5 : "-"; last_seen = ($6 != "") ? $6 : "-"; ping = ($7 != "") ? $7 : "-";
    row = "|"; split(widths_var, widths_arr, " ")
    contents[1]=NR; contents[2]=ip; contents[3]=name; contents[4]=status; contents[5]=brand; contents[6]=model; contents[7]=last_seen; contents[8]=ping;
    for (i=1; i<=8; i++) {
        content = contents[i]; width = widths_arr[i]; inner_width = width - 2
        if (inner_width < 0) inner_width = 0
        truncated_content = content
        if (length(content) > inner_width) {
            if (inner_width <= 1) { truncated_content = substr(content, 1, inner_width) }
            else { truncated_content = sprintf("%s…", substr(content, 1, inner_width - 1)) }
        }
         row = row sprintf(" %-*s |", inner_width, truncated_content)
    }
    print row; print separator_line_var
}
EOF
)

# --- Table Drawing ---
# (draw_table function remains the same)
draw_table() {
    local term_width=$1; local term_height=$2; local table_output=""; local header_section=""
    if [ -r "$LOGO_FILE" ]; then
        local logo_content; logo_content=$( ( . "$LOGO_FILE" && draw_logo ) 2>/dev/null )
        if [ -n "$logo_content" ]; then header_section+="${logo_content}\n\n\n"; else header_section+="\n"; fi
    else echo "Warning: Logo file not found or not readable at $LOGO_FILE" >&2; header_section+="\n"; fi
    local formatted_title="\e[1;97m📶  eNB STATUS MONITOR\e[0m"; header_section+="${formatted_title}\n\n"
    local col_widths=(); local total_fixed_width=0; local num_fixed_cols=0
    for index in "${!FIXED_WIDTH_COLS[@]}"; do
        width=${FIXED_WIDTH_COLS[$index]}; [[ "$width" -lt "$MIN_COL_WIDTH" ]] && width=$MIN_COL_WIDTH
        col_widths[$index]=$width; total_fixed_width=$((total_fixed_width + width)); ((num_fixed_cols++))
    done
    local total_available_width=$term_width; local separator_width=$((NUM_COLUMNS + 1)); local available_content_width=$((total_available_width - separator_width))
    local remaining_width_for_dynamic=$((total_available_width - total_fixed_width - separator_width)); local min_dynamic_width_needed=$((NUM_DYNAMIC_COLS * (MIN_COL_WIDTH -1) ))
    if [ "$remaining_width_for_dynamic" -lt "$min_dynamic_width_needed" ]; then clear; echo "Terminal too narrow." >&2; echo -e "\n\n\e[1;97mPRESS Q TO QUIT\e[0m"; return 1; fi
    if [ "$NUM_DYNAMIC_COLS" -gt 0 ]; then
        local base_dynamic_col_width=$((remaining_width_for_dynamic / NUM_DYNAMIC_COLS)); local remainder=$((remaining_width_for_dynamic % NUM_DYNAMIC_COLS))
        for index in "${DYNAMIC_COL_INDICES[@]}"; do
            col_widths[$index]=$base_dynamic_col_width
            if [ $remainder -gt 0 ]; then ((col_widths[$index]++)); ((remainder--)); fi
            [ "${col_widths[$index]}" -lt "$MIN_COL_WIDTH" ] && col_widths[$index]=$MIN_COL_WIDTH
        done
    fi
    local current_total_width=0
    for i in $(seq 0 $((NUM_COLUMNS - 1))); do
       if [[ -z "${col_widths[$i]}" ]] || [[ "${col_widths[$i]}" -lt "$MIN_COL_WIDTH" ]]; then
           is_dynamic=false; for dyn_idx in "${DYNAMIC_COL_INDICES[@]}"; do [[ $i -eq $dyn_idx ]] && is_dynamic=true; break; done
           if $is_dynamic || [[ -z "${FIXED_WIDTH_COLS[$i]}" ]]; then col_widths[$i]=$MIN_COL_WIDTH; fi
       fi
       if [[ -n "${col_widths[$i]}" ]]; then current_total_width=$((current_total_width + ${col_widths[$i]})); else col_widths[$i]=$MIN_COL_WIDTH; current_total_width=$((current_total_width + ${col_widths[$i]})); fi
    done
    current_total_width=$((current_total_width + separator_width))
    local width_diff=$((total_available_width - current_total_width))
    if [ "$NUM_DYNAMIC_COLS" -gt 0 ] && [ "$width_diff" -ne 0 ]; then
        local last_dynamic_idx=${DYNAMIC_COL_INDICES[-1]}; local adjusted_width=$(( ${col_widths[$last_dynamic_idx]} + width_diff ))
        if [[ "$adjusted_width" -ge "$MIN_COL_WIDTH" ]]; then col_widths[$last_dynamic_idx]=$adjusted_width; fi
    fi
    local widths_str=""; for width in "${col_widths[@]}"; do widths_str+="$width "; done; widths_str=$(echo "$widths_str" | sed 's/ $//')
    local separator_line; separator_line=$(draw_ascii_line "${col_widths[@]}")
    table_output+="$separator_line\n"; local header_row; header_row=$(echo "" | awk -v widths_var="$widths_str" "$awk_header_script"); table_output+="$header_row\n"; table_output+="$separator_line\n"
    local data_rows_final="";
    if [ -f "$CACHE_FILE" ]; then
        local jq_output; jq_output=$(jq -r '.[] | [.cell_ip_address // "-", .cell_name // "-", .cell_status // "-", .cell_brand // "-", .cell_model // "-", .cell_last_seen // "-", .cell_ping // "-"] | @tsv' "$CACHE_FILE" 2>/dev/null)
        if [ -n "$jq_output" ]; then
            local data_rows_with_separators; data_rows_with_separators=$(echo "$jq_output" | awk -v widths_var="$widths_str" -v separator_line_var="$separator_line" "$awk_data_script")
            if [ -n "$data_rows_with_separators" ]; then
                 mapfile -t lines < <(echo -e "$data_rows_with_separators")
                 if [[ "${#lines[@]}" -gt 0 && "${lines[-1]}" == "$separator_line" ]]; then unset 'lines[-1]'; data_rows_final=$(printf "%s\n" "${lines[@]}"); data_rows_final=${data_rows_final%'\n'}; else data_rows_final=$(echo -e "$data_rows_with_separators"); data_rows_final=${data_rows_final%'\n'}; fi
                 if [[ -n "$data_rows_final" ]]; then table_output+="$data_rows_final"; fi
            else local colspan_width=$((term_width - 2)); local message="No eNB data found in cache."; local msg_padding=$(( (colspan_width - ${#message}) / 2 )); [ "$msg_padding" -lt 0 ] && msg_padding=0; table_output+=$(printf "|%*s%s%*s|" "$msg_padding" '' "$message" "$((colspan_width - msg_padding - ${#message}))" ''); fi
        else local colspan_width=$((term_width - 2)); local message="Cache file is empty or contains no valid data."; local msg_padding=$(( (colspan_width - ${#message}) / 2 )); [ "$msg_padding" -lt 0 ] && msg_padding=0; table_output+=$(printf "|%*s%s%*s|" "$msg_padding" '' "$message" "$((colspan_width - msg_padding - ${#message}))" ''); fi
    else local colspan_width=$((term_width - 2)); local message="Cache file not found: $CACHE_FILE"; local msg_padding=$(( (colspan_width - ${#message}) / 2 )); [ "$msg_padding" -lt 0 ] && msg_padding=0; table_output+=$(printf "|%*s%s%*s|" "$msg_padding" '' "$message" "$((colspan_width - msg_padding - ${#message}))" ''); fi
    table_output+="\n"
    if [[ "$table_output" == *"|"* ]]; then table_output+=$(draw_ascii_line "${col_widths[@]}"); table_output+="\n"; fi
    local footer_left="Last Updated: $(date '+%Y-%m-%d %H:%M:%S')"; table_output+="${footer_left}"
    echo -e "${header_section}${table_output}"; return 0
}


# --- Check dependencies ---
if ! command -v jq &> /dev/null; then echo "Error: 'jq' command not found." >&2; exit 1; fi
if ! command -v awk &> /dev/null; then echo "Error: 'awk' command not found." >&2; exit 1; fi
if ! command -v sed &> /dev/null; then echo "Error: 'sed' command not found." >&2; exit 1; fi
if ! command -v stty &> /dev/null; then echo "Error: 'stty' command not found." >&2; exit 1; fi
if ! command -v mapfile &> /dev/null; then echo "Error: 'mapfile' command not found (requires Bash 4+)." >&2; exit 1; fi


# --- Cleanup on Exit ---
cleanup() {
    echo # Print a newline to avoid messing up the prompt
    stty sane # Restore terminal settings
    exit 0
}
trap cleanup TERM EXIT # Handle normal termination and regular exit
trap '' INT             # Ignore Ctrl+C (SIGINT)


# --- Main Loop ---
while true; do
    term_size=$(get_terminal_dimensions 2>/dev/null)
    read -r rows cols <<< "$term_size"
    if [[ -z "$rows" || "$rows" -eq 0 || -z "$cols" || "$cols" -eq 0 ]]; then
        rows=24; cols=80
    fi

    # Clear screen inside the loop BEFORE drawing table for each refresh/keypress
    clear

    # Draw the table content
    if draw_table "$cols" "$rows"; then
        # Print the prompt only if draw_table succeeded
        echo # Add one blank line
        echo -e "\e[1;97mPRESS Q TO QUIT, OR R TO REFRESH\e[0m"
    fi

    # Wait for single key press
    read -n 1 -s -r key

    # Process the key
    case "$key" in
        q|Q) cleanup ;; # Exit cleanly
        r|R)
           # Run the update script again on refresh request
           echo "Refreshing cache..." # Optional message
           "${SCRIPT_DIR}/monitor_enbs__update_cache.sh" > /dev/null 2>&1
           # Use just "${SCRIPT_DIR}/monitor_enbs__update_cache.sh" if you want to see output
           echo "Refresh complete. Redrawing..." # Optional
           sleep 0.5 # Tiny pause to see message if desired
           continue
           ;; # Loop again to refresh the display
        *) continue ;;   # Ignore other keys and wait for next input
    esac
done