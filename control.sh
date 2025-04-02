#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source the logo
source scripts/logo.sh

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function draw_menu() {
    clear
    draw_logo
    echo -e "\n${GREEN}=== Rapid5GS Control Panel ===${NC}"
    echo ""
    echo "1. 📊 View EPC Throughput"
    echo "2. 📶 View eNB Status"
    echo "3. 📝 Live Tail MME"
    echo "4. 👋 Exit"
    echo ""
}

# Initial draw
draw_menu

# Main menu
while true; do
    read -p "Enter an option (1-4) and press enter: " choice

    case $choice in
        1)
            sudo bash scripts/speedometer.sh
            draw_menu
            ;;
        2)
            sudo bash scripts/monitor_enbs.sh
            draw_menu
            ;;
        3)
            sudo journalctl -u open5gs-mmed -f
            draw_menu
            ;;
        4)
            echo -e "\n${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-4.${NC}"
            ;;
    esac
done 