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

echo -e "${YELLOW}Restarting Open5GS services...${NC}"

# Detect OS type
if [ -f /etc/os-release ]; then
    source /etc/os-release
fi

# List of all Open5GS services to restart
OPEN5GS_SERVICES=(
    "open5gs-mmed"
    "open5gs-sgwcd"
    "open5gs-smfd"
    "open5gs-amfd"
    "open5gs-sgwud"
    "open5gs-upfd"
    "open5gs-hssd"
    "open5gs-pcrfd"
    "open5gs-nrfd"
    "open5gs-ausfd"
    "open5gs-udmd"
    "open5gs-pcfd"
    "open5gs-nssfd"
    "open5gs-bsfd"
    "open5gs-udrd"
    "open5gs-scpd"
)

# Restart function for systemd (Linux)
restart_systemd() {
    for service in "${OPEN5GS_SERVICES[@]}"; do
        echo -e "Restarting ${service}..."
        systemctl restart $service
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}${service} restarted successfully${NC}"
        else
            echo -e "${YELLOW}${service} not available or failed to restart${NC}"
        fi
    done
}

# Restart function for launchd (macOS)
restart_launchd() {
    for service in "${OPEN5GS_SERVICES[@]}"; do
        # Convert systemd service name to probable launchd service name
        launchd_service=$(echo $service | sed 's/open5gs-/com.open5gs./')
        echo -e "Restarting ${launchd_service}..."
        launchctl stop $launchd_service
        launchctl start $launchd_service
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}${launchd_service} restarted successfully${NC}"
        else
            echo -e "${YELLOW}${launchd_service} not available or failed to restart${NC}"
        fi
    done
}

# Determine the init system and restart services accordingly
if command -v systemctl >/dev/null 2>&1; then
    echo -e "${YELLOW}Using systemd to restart services...${NC}"
    restart_systemd
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${YELLOW}Detected macOS, using launchctl to restart services...${NC}"
    restart_launchd
else
    echo -e "${RED}Unsupported init system. Please restart Open5GS services manually.${NC}"
    exit 1
fi

echo -e "${GREEN}All Open5GS services reboot process completed!${NC}"
