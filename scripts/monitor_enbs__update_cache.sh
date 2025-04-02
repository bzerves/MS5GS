#!/bin/bash

# Ensure this script is run as root
if [[ "$EUID" -ne 0 ]]; then
  echo "[ERROR] This script must be run as root. Use: sudo $0"
  exit 1
fi

# Ensure gawk is installed and available
if ! command -v gawk >/dev/null 2>&1; then
    echo "[INFO] gawk not found. Installing..."
    apt update && apt install -y gawk
    if ! command -v gawk >/dev/null 2>&1; then
        echo "[ERROR] gawk installation failed. Exiting."
        exit 1
    fi
fi

CACHE_FILE="/var/lib/rapid5gs/enb_cache.json"
TMP_LOG=$(mktemp /tmp/enb_log.XXXXXX)
PING_TIMEOUT=2
JOURNAL_LINES=5000

echo "[INFO] Starting monitor_enbs__update_cache.sh..."

# Create the data directory if needed, and set correct permissions
if [ ! -d "/var/lib/rapid5gs" ]; then
    echo "[INFO] Creating cache directory..."
    mkdir -p /var/lib/rapid5gs
    chown root:root /var/lib/rapid5gs
    chmod 755 /var/lib/rapid5gs
fi

# Initialize the JSON cache file if it doesn't exist
if [ ! -f "$CACHE_FILE" ]; then
    echo "[INFO] Creating new cache file at $CACHE_FILE"
    echo "[]" > "$CACHE_FILE"
    chmod 644 "$CACHE_FILE"
fi

# Ensure cache file is writable by the current user (root)
if [ ! -w "$CACHE_FILE" ]; then
    echo "[ERROR] Cache file is not writable: $CACHE_FILE"
    exit 1
fi

echo "[INFO] Using TMP_LOG: $TMP_LOG"

update_enb_cache() {
    local cell_ip="$1"
    local cell_status="$2"
    local timestamp="$3"

    echo "[INFO] Updating cache: $cell_ip → $cell_status at $timestamp"

    if ! jq empty "$CACHE_FILE" >/dev/null 2>&1; then
        echo "[WARN] Cache file is not valid JSON. Resetting it."
        echo "[]" > "$CACHE_FILE"
    fi

    local cache_content
    cache_content=$(cat "$CACHE_FILE")

    echo "[DEBUG] Existing cache content:"
    echo "$cache_content" | jq .

    local updated
    updated=$(echo "$cache_content" | jq --arg ip "$cell_ip" --arg status "$cell_status" --arg time "$timestamp" '
        if any(.[]; .cell_ip_address == $ip) then
            map(if .cell_ip_address == $ip then . + {
                cell_status: $status,
                cell_last_seen: $time
            } else . end)
        else
            . + [{
                cell_ip_address: $ip,
                cell_name: "",
                cell_status: $status,
                cell_brand: "",
                cell_model: "",
                cell_last_seen: $time,
                cell_ping: 0
            }]
        end
    ')

    echo "[DEBUG] Updated cache content:"
    echo "$updated" | jq .

    if [ -n "$updated" ]; then
        echo "$updated" | jq . > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        echo "[INFO] Cache successfully written"
    else
        echo "[ERROR] Failed to generate updated JSON."
    fi

}

update_ping_times() {
    echo "[INFO] Updating ping times..."
    local cache_content
    cache_content=$(cat "$CACHE_FILE")

    # Check if the cache is empty or invalid JSON array before proceeding
    if ! echo "$cache_content" | jq -e '. | length > 0 and type=="array"' > /dev/null 2>&1; then
        # Also check if it's actually an array
        if ! echo "$cache_content" | jq -e 'type=="array"' > /dev/null 2>&1; then
             echo "[WARN] Cache content is not a valid JSON array. Resetting cache."
             echo "[]" > "$CACHE_FILE" # Reset if fundamentally invalid
        else
             echo "[INFO] Cache is empty. Skipping ping updates."
        fi
        # No need to return 1, just proceed; the loop below won't run if cache is empty.
        # return 1 # Exit the function early - removed, let it write empty if needed
    fi

    local updated_json_lines=() # Use a bash array to store modified JSON lines

    # Use process substitution to feed compact JSON objects to the loop
    while IFS= read -r enb_json_line; do
        # Validate the line is valid JSON before proceeding (paranoia check)
        if ! echo "$enb_json_line" | jq empty > /dev/null 2>&1; then
            echo "[WARN] Skipping invalid JSON line from cache: $enb_json_line"
            continue
        fi

        local ip
        ip=$(echo "$enb_json_line" | jq -r '.cell_ip_address // empty') # Use // empty for safety

        if [[ -z "$ip" ]]; then
            echo "[WARN] Skipping cache entry with missing IP: $enb_json_line"
            continue
        fi

        local ping_time_str
        local ping_exit_code

        # Execute ping, capture output AND exit code.
        ping_time_str=$(ping -c 1 -W "$PING_TIMEOUT" "$ip" 2>&1) # Capture stderr too
        ping_exit_code=$?

        local ping_value="0" # Default to numeric 0

        if [[ $ping_exit_code -eq 0 ]]; then
            # More robust grep for time=, handles variations
            ping_value=$(echo "$ping_time_str" | grep -oP 'time=\K\d+(\.\d+)?')

            if [[ -z "$ping_value" ]]; then
                 echo "[DEBUG] Ping successful for $ip, but couldn't parse time. Output: $ping_time_str"
                 ping_value="0" # Default back to 0 if parsing fails
            else
                 # Ensure it's treated as a number by jq later
                 # No conversion needed here if jq uses --argjson
                 echo "[DEBUG] Ping successful for $ip: ${ping_value}ms"
            fi
        else
            echo "[DEBUG] Ping failed or timed out for $ip (Exit code: $ping_exit_code)"
            ping_value="0"
        fi

        # --- Core Change: Modify the single object and store it ---
        local modified_enb
        # Use jq to add/update the cell_ping field for the *current* object
        modified_enb=$(echo "$enb_json_line" | jq --argjson ping "$ping_value" '. + {"cell_ping": $ping}')

        local jq_modify_exit_code=$?
        if [[ $jq_modify_exit_code -ne 0 ]]; then
            echo "[ERROR] jq failed (code $jq_modify_exit_code) modifying entry for IP $ip. Input: $enb_json_line"
            # Optionally skip adding this entry if jq failed
            continue
        fi

        # Add the successfully modified JSON line to the bash array
        updated_json_lines+=("$modified_enb")
        # --- End Core Change ---

    done < <(echo "$cache_content" | jq -c '.[]? // empty') # Use .[]? to avoid error on non-array/empty

    # --- Assemble the final JSON array *once* ---
    local final_updated_json
    if [ ${#updated_json_lines[@]} -gt 0 ]; then
        # Use printf to feed lines to jq -s (slurp) to create the array
        final_updated_json=$(printf '%s\n' "${updated_json_lines[@]}" | jq -s '.')
    else
        echo "[INFO] No entries processed or cache was empty. Resulting cache will be empty array."
        final_updated_json="[]" # Default to empty array if nothing was processed
    fi
    # --- End Assembly ---

    echo "[DEBUG] Final updated JSON before writing:"
    # Use jq '.' for pretty printing the final result for debugging
    echo "$final_updated_json" | jq .

    # Validate the *final* assembled JSON before writing
    if echo "$final_updated_json" | jq empty > /dev/null 2>&1; then
        # Write the whole new array atomically
        echo "$final_updated_json" > "${CACHE_FILE}.tmp" && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
        echo "[INFO] Ping times updated and cache written"
    else
        echo "[ERROR] Final assembled JSON is not valid. Not overwriting cache."
        # echo "[DEBUG] Invalid final JSON content:"
        # echo "$final_updated_json" # Uncomment to see the bad JSON if this happens
    fi
}

echo "[INFO] Parsing logs..."

sudo journalctl -u open5gs-mmed --since "24 hours ago" --output=short-unix | \
grep -E 'eNB-S1 accepted\[[0-9\.]+(:[0-9]+)?\]|eNB-S1 accepted\[[0-9\.]+\]:[0-9]+|eNB-S1\[[0-9\.]+\] (connection refused|max_num_of_ostreams)' | \
gawk '
{
    ts = strftime("%Y-%m-%d %H:%M:%S", $1);  # convert UNIX timestamp to readable format
    line = substr($0, index($0,$2))          # get the message part

    if (match(line, /eNB-S1 accepted\[([0-9\.]+)(:[0-9]+)?\]/, m)) {
        ip = m[1]; state = "ATTACHED"
    } else if (match(line, /eNB-S1 accepted\[([0-9\.]+)\]:[0-9]+/, m)) {
        ip = m[1]; state = "ATTACHED"
    } else if (match(line, /eNB-S1\[([0-9\.]+)\] connection refused/, m)) {
        ip = m[1]; state = "DETACHED"
    } else if (match(line, /eNB-S1\[([0-9\.]+)\] max_num_of_ostreams/, m)) {
        ip = m[1]; state = "ATTACHED"
    } else {
        next
    }

    print ts, ip, state
}' > "$TMP_LOG"

echo "[DEBUG] TMP_LOG contents:"
cat "$TMP_LOG"

tac "$TMP_LOG" | awk '!seen[$3]++' | while read -r date time ip status; do
    timestamp="${date} ${time}"
    update_enb_cache "$ip" "$(echo "$status" | tr A-Z a-z)" "$timestamp"
done

update_ping_times

rm -f "$TMP_LOG"