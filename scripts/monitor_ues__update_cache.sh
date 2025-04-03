#!/bin/bash

LOG_FILE="/var/log/open5gs/smf.log"
CACHE_FILE="/var/lib/rapid5gs/ue_cache.json"

# Make sure the cache file exists and is a JSON object
[ -f "$CACHE_FILE" ] || echo '{}' > "$CACHE_FILE"

# DEBUG: Create debug log
DEBUG_LOG="/tmp/monitor_ues_debug.log"
echo "\n--- $(date -u) ---" >> "$DEBUG_LOG"
echo "Reading last 1000 lines from $LOG_FILE..." >> "$DEBUG_LOG"

# Process recent lines from SMF log
tail -n 1000 "$LOG_FILE" | awk -v debug_log="$DEBUG_LOG" '
BEGIN { event_count = 0 }
/UE IMSI/ && /APN/ {
    match($0, /IMSI\[([0-9]+)\]/, imsi_arr)
    match($0, /APN\[([^\]]+)\]/, apn_arr)
    match($0, /IPv4\[([0-9.]+)\]/, ip_arr)
    match($0, /IPv6\[([0-9a-fA-F:.]*)\]/, ipv6_arr)
    if (imsi_arr[1] && apn_arr[1] && ip_arr[1]) {
        event_count++
        print "MATCH ATTACH: " $0 >> debug_log
        print "ATTACH|" imsi_arr[1] "|" apn_arr[1] "|" ip_arr[1] "|" ipv6_arr[1]
    }
}
/Removed Session: UE IMSI:/ {
    match($0, /IMSI:\[([0-9]+)\]/, imsi_arr)
    match($0, /DNN:\[([^:]+):[0-9]+\]/, apn_arr)
    if (imsi_arr[1] && apn_arr[1]) {
        event_count++
        print "MATCH DETACH: " $0 >> debug_log
        print "DETACH|" imsi_arr[1] "|" apn_arr[1]
    }
}
END {
    print "Total parsed events: " event_count >> debug_log
}
' | while IFS="|" read -r action imsi apn ipv4 ipv6; do

    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "EVENT: $action IMSI=$imsi APN=$apn IP=$ipv4 IPV6=$ipv6 TIME=$now" >> "$DEBUG_LOG"

    if [[ "$action" == "ATTACH" ]]; then
        echo "--> Processing ATTACH for $imsi [$apn]" >> "$DEBUG_LOG"
        jq --arg imsi "$imsi" \
           --arg apn "$apn" \
           --arg ip "$ipv4" \
           --arg ipv6 "$ipv6" \
           --arg now "$now" \
           '
           .[$imsi] |= (
               . // {
                   first_seen: $now,
                   status: "attached",
                   last_seen: $now,
                   sessions: {}
               } |
               .status = "attached" |
               .last_seen = $now |
               .sessions[$apn] |= (
                   . // {
                       status: "attached",
                       ipv4: $ip,
                       ipv6: ($ipv6 | select(. != "") // null),
                       first_seen: $now,
                       last_seen: $now
                   } |
                   .status = "attached" |
                   .ipv4 = $ip |
                   .ipv6 = ($ipv6 | select(. != "") // null) |
                   .last_seen = $now
               )
           )
           ' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        echo "--> JSON updated for ATTACH" >> "$DEBUG_LOG"
    fi

    if [[ "$action" == "DETACH" ]]; then
        echo "--> Processing DETACH for $imsi [$apn]" >> "$DEBUG_LOG"
        jq --arg imsi "$imsi" \
           --arg apn "$apn" \
           --arg now "$now" \
           '
           if .[$imsi] and .[$imsi].sessions[$apn] then
               .[$imsi].sessions[$apn].status = "detached" |
               .[$imsi].sessions[$apn].last_seen = $now |
               .[$imsi].last_seen = $now |
               (
                   if ([.[$imsi].sessions[] | select(.status == "attached")] | length) == 0 then
                       .[$imsi].status = "detached"
                   else
                       .
                   end
               )
           else
               .
           end
           ' "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
        echo "--> JSON updated for DETACH" >> "$DEBUG_LOG"
    fi

done