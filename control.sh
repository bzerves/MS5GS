#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear

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

# Main menu
while true; do
    echo -e "\n${GREEN}=== Rapid5GS Control Panel ===${NC}"
    echo ""
    echo "1. View EPC Throughput"
    echo "2. Exit"
    echo ""
    read -p "Select an option (1-2): " choice

    case $choice in
        1)
            sudo bash scripts/speedometer.sh
            ;;
        2)
            echo -e "\n${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-2.${NC}"
            ;;
    esac
done 