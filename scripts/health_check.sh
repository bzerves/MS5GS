#!/bin/bash

# --- Configuration ---
INSTALL_CONF="/etc/open5gs/install.conf"

# --- Colors and Emojis ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m' # Added Cyan for info
NC='\033[0m'    # No Color / Reset all attributes
BOLD='\033[1m'
# BLINK variable removed

CHECK_MARK="✅"
CROSS_MARK="❌"
WARNING_MARK="⚠️"
INFO_MARK="ℹ️" # Added Info Mark

# --- Global Variables for Summary ---
mongo_state=2 # Default to offline
mongo_status_text="${CROSS_MARK} ${RED}MongoDB status not checked yet${NC}"
total_svcs=0; healthy_svcs=0; warning_svcs=0; offline_svcs=0;

# Define the typical Open5GS Hybrid Core Services
OPEN5GS_CORE_SERVICES=(
    "open5gs-nrfd" "open5gs-ausfd" "open5gs-udmd" "open5gs-udrd" "open5gs-pcfd"
    "open5gs-nssfd" "open5gs-bsfd" "open5gs-amfd" "open5gs-smfd" "open5gs-upfd"
    "open5gs-hssd" "open5gs-mmed" "open5gs-sgwcd" "open5gs-sgwud" "open5gs-pcrfd"
)

# --- Pre-checks ---
if [ "$EUID" -ne 0 ]; then echo -e "${RED}Please run as root (use sudo)${NC}"; exit 1; fi

# Check for bc dependency and install if missing
# Works for Debian/Ubuntu based systems
if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}${INFO_MARK} 'bc' command not found. Attempting installation (requires internet)...${NC}"
    apt update > /dev/null 2>&1
    if apt install -y bc > /dev/null 2>&1; then
        echo -e "${GREEN}${CHECK_MARK} 'bc' installed successfully.${NC}"
    else
        echo -e "${RED}${CROSS_MARK} Failed to install 'bc'. Please install it manually:${NC}"
        echo -e "${RED}   sudo apt update && sudo apt install bc${NC}"
        exit 1
    fi
fi

# Detect MongoDB Service Name
MONGO_SERVICE_NAME=""
if systemctl list-units --full -all | grep -q "mongod.service"; then MONGO_SERVICE_NAME="mongod"; fi
if [[ -z "$MONGO_SERVICE_NAME" ]] && systemctl list-units --full -all | grep -q "mongodb.service"; then MONGO_SERVICE_NAME="mongodb"; fi
if [ -z "$MONGO_SERVICE_NAME" ]; then
    mongo_state=2
    mongo_status_text="${CROSS_MARK} ${RED}MongoDB service (mongod/mongodb) not found.${NC}"
fi

# --- Helper Functions ---
print_header() {
    echo -e "\n${BOLD}${YELLOW}==============================================${NC}"
    echo -e "${BOLD}${YELLOW}      Open5GS Core Health Check          ${NC}"
    echo -e "${BOLD}${YELLOW}==============================================${NC}\n"
}

# --- Check Functions ---

check_mongodb() {
    echo -e "${BOLD}Database Service:${NC}"
    if [ -z "$MONGO_SERVICE_NAME" ]; then echo -e "   $mongo_status_text"; return; fi

    if systemctl is-active --quiet "$MONGO_SERVICE_NAME"; then
        mongo_state=0
        mongo_status_text="${CHECK_MARK} ${GREEN}MongoDB ($MONGO_SERVICE_NAME) is online${NC}"
        echo -e "   $mongo_status_text"
    else
        mongo_state=2
        mongo_status_text="${CROSS_MARK} ${RED}MongoDB ($MONGO_SERVICE_NAME) is offline${NC} - ${BOLD}Required!${NC}"
        echo -e "   $mongo_status_text"
    fi
}

check_network() {
    echo -e "\n${BOLD}Network Interfaces (from $INSTALL_CONF):${NC}"
    if [ ! -f "$INSTALL_CONF" ]; then echo -e "   ${CROSS_MARK} ${RED}Config not found: $INSTALL_CONF${NC}"; return; fi

    # Source the configuration file directly
    # Clear potential pre-existing variables before sourcing to avoid conflicts
    unset MGMT_IP USER_WAN_IP
    source "$INSTALL_CONF"

    local mgmt_ip_addr="" user_wan_ip_addr=""

    if [[ -n "${MGMT_IP}" ]]; then
         mgmt_ip_addr=$(echo "$MGMT_IP" | cut -d'/' -f1)
    fi
    if [[ -n "${USER_WAN_IP}" ]]; then
        user_wan_ip_addr=$(echo "$USER_WAN_IP" | cut -d'/' -f1)
    fi

    if [[ -n "$mgmt_ip_addr" ]]; then
        if ip -4 addr show | grep -qwo "$mgmt_ip_addr"; then echo -e "   ${CHECK_MARK} ${GREEN}Management IP ($mgmt_ip_addr) present${NC}"; else echo -e "   ${CROSS_MARK} ${RED}Management IP ($mgmt_ip_addr) NOT present${NC}"; fi
    else
        echo -e "   ${YELLOW}MGMT_IP not defined in $INSTALL_CONF${NC}";
    fi

    if [[ -n "$user_wan_ip_addr" ]]; then
        if ip -4 addr show | grep -qwo "$user_wan_ip_addr"; then echo -e "   ${CHECK_MARK} ${GREEN}User WAN IP ($user_wan_ip_addr) present${NC}"; else echo -e "   ${CROSS_MARK} ${RED}User WAN IP ($user_wan_ip_addr) NOT present${NC}"; fi
    else
        echo -e "   ${YELLOW}USER_WAN_IP not defined in $INSTALL_CONF${NC}";
    fi
}

check_system_resources() {
    echo -e "\n${BOLD}System Resource Usage:${NC}"
    local disk_avail_gb=$(df -BG --output=avail / | tail -n 1 | sed 's/G//')
    local disk_used_pct=$(df -h --output=pcent / | tail -n 1 | sed 's/ //g')
    echo -e "   ${INFO_MARK} ${CYAN}Disk (Root /): Available: ${disk_avail_gb} GB | Used: ${disk_used_pct}${NC}"
    local mem_info=$(free -m | awk '/^Mem:/ { total=$2; avail=$7; used_pct=sprintf("%.0f", (total-avail)*100/total); avail_gb=sprintf("%.1f", avail/1024); printf "%.1f %.0f", avail_gb, used_pct }')
    local mem_avail_gb=$(echo "$mem_info" | cut -d' ' -f1)
    local mem_used_pct=$(echo "$mem_info" | cut -d' ' -f2)
    echo -e "   ${INFO_MARK} ${CYAN}Memory: Available: ${mem_avail_gb} GB | Used: ${mem_used_pct}%${NC}"
    local cpu_used_pct=$(top -bn1 | grep '^%Cpu' | head -n 1 | awk '{ printf "%.1f", 100 - $8 }')
    echo -e "   ${INFO_MARK} ${CYAN}CPU Usage: ${cpu_used_pct}%${NC}"
}

check_throughput() {
    echo -e "\n${BOLD}Network Throughput (1 sec sample):${NC}"
    if [ ! -f "$INSTALL_CONF" ]; then echo -e "   ${YELLOW}Cannot check throughput: $INSTALL_CONF not found.${NC}"; return; fi

    # Source config - ensure variables aren't lingering from check_network
    unset MGMT_IP USER_WAN_IP USER_WAN_INTERFACE
    source "$INSTALL_CONF"
    local mgmt_ip_addr="" wan_ip_addr="" wan_if_name="" mgmt_if="" wan_if=""

    if [[ -n "$MGMT_IP" ]]; then
        mgmt_ip_addr=$(echo "$MGMT_IP" | cut -d'/' -f1)
        mgmt_if=$(ip -o -4 addr show | awk -v ip="$mgmt_ip_addr" '$4 ~ ("^" ip "/") {print $2; exit}')
        if [ -z "$mgmt_if" ]; then echo -e "   ${YELLOW}Could not resolve Management Interface for IP $mgmt_ip_addr${NC}"; fi
    else
         echo -e "   ${YELLOW}MGMT_IP not defined, skipping Management throughput.${NC}"
    fi

    wan_if_name="${USER_WAN_INTERFACE:-}"
    if [[ -n "$USER_WAN_IP" ]]; then wan_ip_addr=$(echo "$USER_WAN_IP" | cut -d'/' -f1); fi

    if [[ "$wan_if_name" == "dynamic" && -n "$wan_ip_addr" ]]; then
        wan_if=$(ip -o -4 addr show | awk -v ip="$wan_ip_addr" '$4 ~ ("^" ip "/") {print $2; exit}')
         if [ -z "$wan_if" ]; then echo -e "   ${YELLOW}Could not dynamically resolve User WAN Interface for IP $wan_ip_addr${NC}"; fi
    elif [[ -n "$wan_if_name" && "$wan_if_name" != "dynamic" ]]; then
        if ip link show "$wan_if_name" > /dev/null 2>&1; then
             wan_if="$wan_if_name"
        else
             echo -e "   ${YELLOW}User WAN Interface '$wan_if_name' not found.${NC}"
        fi
    else
         echo -e "   ${YELLOW}User WAN Interface not configured sufficiently to determine, skipping throughput.${NC}"
    fi

    for if_name in "$mgmt_if" "$wan_if"; do
        if [[ -n "$if_name" && -e "/sys/class/net/$if_name/statistics/rx_bytes" ]]; then
            local rx1=$(cat "/sys/class/net/$if_name/statistics/rx_bytes")
            local tx1=$(cat "/sys/class/net/$if_name/statistics/tx_bytes")
            sleep 1
            local rx2=$(cat "/sys/class/net/$if_name/statistics/rx_bytes")
            local tx2=$(cat "/sys/class/net/$if_name/statistics/tx_bytes")
            local rx_bps=$((rx2 - rx1))
            local tx_bps=$((tx2 - tx1))

            if command -v bc &> /dev/null; then
                local rx_mbps=$(echo "scale=2; $rx_bps * 8 / 1000000" | bc)
                local tx_mbps=$(echo "scale=2; $tx_bps * 8 / 1000000" | bc)
            else
                local rx_mbps="N/A (bc missing)"
                local tx_mbps="N/A (bc missing)"
                echo -e "   ${RED}${CROSS_MARK} 'bc' command is unexpectedly missing for throughput calculation!${NC}"
            fi

            local if_label="$if_name"
            [[ "$if_name" == "$mgmt_if" ]] && if_label+=" (Mgmt)"
            [[ "$if_name" == "$wan_if" ]] && if_label+=" (WAN)"
            echo -e "   ${INFO_MARK} ${CYAN}Interface ${if_label}: RX: ${rx_mbps} Mbps | TX: ${tx_mbps} Mbps${NC}"
        fi
    done
     if [[ -z "$mgmt_if" && -z "$wan_if" ]]; then
        echo -e "   ${YELLOW}No valid Management or WAN interfaces found to measure throughput.${NC}"
    fi
}

# --- NEW FUNCTION START ---
check_external_ping() {
    echo -e "\n${BOLD}External Connectivity Ping Test:${NC}"
    local targets=("1.1.1.1" "8.8.8.8")
    local names=("Cloudflare DNS (1.1.1.1)" "Google DNS (8.8.8.8)")

    # Check if ping command exists
    if ! command -v ping &> /dev/null; then
        echo -e "   ${YELLOW}${WARNING_MARK} 'ping' command not found. Skipping external connectivity test.${NC}"
        return
    fi

    for i in "${!targets[@]}"; do
        local target="${targets[$i]}"
        local name="${names[$i]}"
        echo -e "   ${INFO_MARK} ${CYAN}Pinging ${name}...${NC}"

        # Execute ping command, capture output and status
        local ping_output
        local ping_status
        ping_output=$(ping -c 3 -W 1 "$target" 2>&1) # 3 Pings, Wait 1 sec per packet
        ping_status=$?

        if [ $ping_status -eq 0 ]; then
            # Ping command succeeded (might have partial loss)
            local times=()
            # Extract individual round-trip times
            while IFS= read -r line; do
                 time_val=$(echo "$line" | grep -o 'time=[0-9.]*' | cut -d'=' -f2)
                 if [[ -n "$time_val" ]]; then
                     times+=("$time_val")
                 fi
            done < <(echo "$ping_output" | grep 'icmp_seq=')

            # Extract average time from summary
            local avg_time
            avg_time=$(echo "$ping_output" | grep 'rtt min/avg/max/mdev' | cut -d '=' -f 2 | cut -d '/' -f 2 | sed 's/ //g') # Extract avg

            # Display individual pings
            local count=1
            for t in "${times[@]}"; do
                echo -e "      ${CYAN}Ping ${count}: ${t} ms${NC}"
                count=$((count + 1))
            done

            # If fewer than 3 replies were received, mark the missing ones
            while [ $count -le 3 ]; do
                echo -e "      ${YELLOW}Ping ${count}: Timeout/Lost${NC}"
                 count=$((count + 1))
            done

            # Display average if successfully parsed
            if [[ -n "$avg_time" ]]; then
                echo -e "      ${GREEN}Average: ${avg_time} ms${NC}"
            else
                 # Handle cases where avg couldn't be parsed (e.g., 100% loss but ping exit 0?)
                 if [[ ${#times[@]} -eq 0 ]]; then
                      echo -e "      ${RED}Average: N/A (No replies received)${NC}"
                 else
                      echo -e "      ${YELLOW}Average: Could not determine (parsing error?)${NC}"
                 fi
            fi

        else
            # Ping command failed entirely
            local error_reason="General failure"
             # Try to get a more specific reason
            if echo "$ping_output" | grep -q "Network is unreachable"; then
                error_reason="Network is unreachable"
            elif echo "$ping_output" | grep -q "100% packet loss"; then
                 error_reason="100% packet loss / Timeout"
            elif echo "$ping_output" | grep -q "unknown host"; then
                 error_reason="Unknown host (DNS issue?)"
            else
                # Get last line as a generic error hint if possible
                 error_reason=$(echo "$ping_output" | tail -n 1)
            fi
             echo -e "   ${CROSS_MARK} ${RED}Pinging ${name}: FAILED${NC}"
             echo -e "     ${RED}Reason: ${error_reason}${NC}"
        fi
         echo "" # Add a blank line for readability between targets
    done
}
# --- NEW FUNCTION END ---


check_service_status() {
    local service=$1
    local error_context=""

    if systemctl is-active --quiet "$service"; then
        error_context=$(journalctl -u "$service" -n 15 --no-pager | grep -Ei ' NRF |sbi|fail|fatal|critical|error|217/USER|exit-code' | tail -1)
        if [ -z "$error_context" ]; then
            echo -e "   ${CHECK_MARK} ${GREEN}${service} is online${NC}"
            return 0 # Healthy
        else
            echo -e "   ${WARNING_MARK} ${YELLOW}${service} is online but has warnings/errors${NC}"
            echo -e "     ${YELLOW}Recent Log: ...${error_context#*]: }${NC}"
            return 1 # Warning
        fi
    else
        error_context=$(journalctl -u "$service" -n 15 --no-pager | grep -Ei 'fail|fatal|critical|error|217/USER|exit-code' | tail -1)
        if [ -z "$error_context" ]; then
             echo -e "   ${CROSS_MARK} ${RED}${service} is offline${NC}"
        else
             echo -e "   ${CROSS_MARK} ${RED}${service} is offline${NC}"
             echo -e "     ${RED}Recent Log: ...${error_context#*]: }${NC}"
        fi
        return 2 # Offline
    fi
}

check_open5gs_services() {
    echo -e "\n${BOLD}Open5GS Core Services:${NC}"
    local service_checked=false

    for service in "${OPEN5GS_CORE_SERVICES[@]}"; do
        if systemctl list-unit-files --type=service | grep -q "^$service.service"; then
             service_checked=true
             total_svcs=$((total_svcs + 1))
             check_service_status "$service"
             local status=$?
             case $status in
                 0) healthy_svcs=$((healthy_svcs + 1)) ;;
                 1) warning_svcs=$((warning_svcs + 1)) ;;
                 2) offline_svcs=$((offline_svcs + 1)) ;;
             esac
        fi
    done

    if ! $service_checked; then
         echo -e "   ${YELLOW}No Open5GS services from the list found installed.${NC}"
    fi
}

display_summary() {
    echo -e "\n${BOLD}${YELLOW}System Health Summary:${NC}"
    echo -e "Database: $mongo_status_text"

    if [ $total_svcs -gt 0 ]; then
        echo -e "Core Services: ${GREEN}$healthy_svcs Healthy${NC}, ${YELLOW}$warning_svcs Warning${NC}, ${RED}$offline_svcs Offline${NC} (Total Checked: $total_svcs)"
    else
        echo -e "Core Services: No services checked/found installed."
    fi

    echo -n "Overall Status: "
    if [[ "$mongo_state" -ne 0 ]]; then
         echo -e "${BOLD}${RED}CRITICAL - MongoDB is offline!${NC}"
    elif [[ "$offline_svcs" -gt 0 ]]; then
         echo -e "${BOLD}${RED}Critical Issues Detected (${offline_svcs} service(s) offline)${NC}"
    elif [[ "$warning_svcs" -gt 0 ]]; then
         echo -e "${BOLD}${YELLOW}Potential Issues Detected (${warning_svcs} service(s) with warnings)${NC}"
    elif [[ "$total_svcs" -gt 0 ]]; then
         echo -e "${BOLD}${GREEN}All Checked Services Running without recent errors${NC}"
    else
         echo -e "${BOLD}${YELLOW}No Open5GS services were checked.${NC}"
    fi
}

# --- Main Execution ---
print_header
check_mongodb
check_network
check_system_resources
check_throughput
check_external_ping
check_open5gs_services
display_summary

echo -e "\n${BOLD}${YELLOW}Health check completed.${NC}"

exit 0