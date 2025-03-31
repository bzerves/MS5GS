#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

# Enable error handling
set -e
trap 'echo -e "${RED}Error occurred on line $LINENO${NC}"; exit 1' ERR

check_dependencies() {
    local missing_packages=()
    for package in bc ifstat ip; do
        if ! command -v "$package" &>/dev/null; then
            missing_packages+=("$package")
        fi
    done

    if [ "${#missing_packages[@]}" -ne 0 ]; then
        echo -e "${YELLOW}Installing missing packages: ${missing_packages[*]}${NC}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${missing_packages[@]}"
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y "${missing_packages[@]}"
        else
            echo -e "${RED}Unsupported package manager. Install manually:${NC}"
            printf '%s\n' "${missing_packages[@]}"
            exit 1
        fi
    fi
}

check_dependencies

CONFIG_FILE="/etc/open5gs/install.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Missing config: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Please run configure_installation.sh first${NC}"
    exit 1
fi

WAN_IP=$(grep "^USER_WAN_IP=" "$CONFIG_FILE" | cut -d'=' -f2 | cut -d'/' -f1)
MGMT_IP=$(grep "^MGMT_IP=" "$CONFIG_FILE" | cut -d'=' -f2 | cut -d'/' -f1)

[ -z "$WAN_IP" ] || [ -z "$MGMT_IP" ] && {
    echo -e "${RED}Missing WAN or MGMT IP in config${NC}"
    exit 1
}

WAN_IF=$(ip -o -4 addr show | grep "$WAN_IP" | awk '{print $2}' | head -n1)
MGMT_IF=$(ip -o -4 addr show | grep "$MGMT_IP" | awk '{print $2}' | head -n1)

[ -z "$WAN_IF" ] && echo -e "${RED}WAN interface not found${NC}" && exit 1
[ -z "$MGMT_IF" ] && echo -e "${RED}MGMT interface not found${NC}" && exit 1

kb_to_mbps() {
    echo "scale=2; $1 * 8 / 1024" | bc
}

get_color() {
    local mbps=$1
    local usage_pct=$(echo "$mbps * 100 / 1000" | bc)

    if (( usage_pct < 30 )); then
        echo "$GREEN"
    elif (( usage_pct < 70 )); then
        echo "$YELLOW"
    else
        echo "$RED"
    fi
}

draw_bar() {
    local label=$1
    local mbps=$2
    local max_mbps=1000
    local width=50

    local fill_len=$(echo "$mbps * $width / $max_mbps" | bc | awk '{printf "%d", $0}')
    [ "$fill_len" -gt "$width" ] && fill_len=$width
    local empty_len=$((width - fill_len))

    local color=$(get_color "$mbps")
    local filled=$(printf "%${fill_len}s" | tr ' ' '#')
    local empty=$(printf "%${empty_len}s" | tr ' ' '-')

    printf "%-20s [${color}%s${NC}%s] %6.2f Mbps\n" "$label" "$filled" "$empty" "$mbps"
}

display_logo() {
cat << "EOF"

  _____                    _       _   _____    _____    _____ 
 |  __ \                  (_)     | | | ____|  / ____|  / ____|
 | |__) |   __ _   _ __    _    __| | | |__   | |  __  | (___  
 |  _  /   / _\`| | '_ \  | |  / _\`| |___ \  | | |_ |  \___  \ 
 | | \ \  | (_| | | |_) | | | | (_| |  ___) | | |__| |  ____) |
 |_|  \_\  \__,_| | .__/  |_|  \__,_| |____/   \_____| |_____/ 
                  | |                                          
                  |_|                                          

EOF
}

display_throughput() {
    clear
    display_logo
    echo                      # 1 line after logo
    echo -e "${BLUE}\033[1mEPC Throughput Monitor${NC}"  # Bold title
    echo                      # 1 line after title
    echo -e "${YELLOW}Monitoring: \033[38;5;214m$WAN_IF${NC} (WAN, $WAN_IP) | \033[38;5;214m$MGMT_IF${NC} (MGMT, $MGMT_IP)"
    echo                      # Padding before bars

    # Initial layout space (4 bars + 3 spacer + 1 exit line = 8 lines)
    for _ in {1..8}; do echo; done

    tput civis

    while true; do
        read -t 0.25 -n 1 key && [[ "$key" == "q" ]] && break

        stats=$(ifstat -i "$WAN_IF","$MGMT_IF" 0.5 1 2>/dev/null | tail -n 1)
        read -r wan_rx wan_tx mgmt_rx mgmt_tx <<< "$stats"

        wan_rx_mbps=$(kb_to_mbps "$wan_rx")
        wan_tx_mbps=$(kb_to_mbps "$wan_tx")
        mgmt_rx_mbps=$(kb_to_mbps "$mgmt_rx")
        mgmt_tx_mbps=$(kb_to_mbps "$mgmt_tx")

        # Move cursor up 8 lines to redraw bars + spacer + footer
        tput cuu 8

        draw_bar "WAN Download" "$wan_rx_mbps"
        draw_bar "WAN Upload" "$wan_tx_mbps"
        draw_bar "MGMT Download" "$mgmt_rx_mbps"
        draw_bar "MGMT Upload" "$mgmt_tx_mbps"
        echo                       # Spacer line 1
        echo                       # Spacer line 2
        echo                       # Spacer line 3
        echo -e "${WHITE}\033[1mPRESS Q TO EXIT${NC}"
    done

    tput cnorm

    echo -e "${YELLOW}Exiting throughput monitor...${NC}"
    sleep 1
}

display_throughput