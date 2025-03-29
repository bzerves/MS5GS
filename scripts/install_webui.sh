#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for root privileges
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Check if NodeJS is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}NodeJS is not installed. Please install NodeJS first using the menu option.${NC}"
    exit 1
fi

# Check if configuration file exists
if [ ! -f "/etc/open5gs/install.conf" ]; then
    echo -e "${RED}Installation configuration file not found. Please run the Configure Installation option first.${NC}"
    exit 1
fi

curl -fsSL https://open5gs.org/open5gs/assets/webui/install | sudo -E bash -