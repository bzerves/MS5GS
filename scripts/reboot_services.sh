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

# Function to stop service
stop_service() {
    local service=$1
    echo -e "${YELLOW}Stopping $service...${NC}"
    systemctl stop $service
    sleep 2
    if systemctl is-active --quiet $service; then
        echo -e "${RED}Failed to stop $service${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $service stopped successfully${NC}"
        return 0
    fi
}

# Function to start service
start_service() {
    local service=$1
    echo -e "${YELLOW}Starting $service...${NC}"
    systemctl start $service
    sleep 2
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service started successfully${NC}"
        return 0
    else
        echo -e "${RED}Failed to start $service${NC}"
        return 1
    fi
}

# List of services to restart
services=(
    "open5gs-hssd"
    "open5gs-mmed"
    "open5gs-sgwcd"
    "open5gs-sgwud"
    "open5gs-pgwd"
    "open5gs-smfd"
    "open5gs-amfd"
    "open5gs-pcrfd"
    "open5gs-nssfd"
    "open5gs-bsfd"
    "open5gs-ausfd"
    "open5gs-udmd"
    "open5gs-pcfd"
    "open5gs-udrd"
)

# Stop all services
echo -e "\n${YELLOW}Stopping all Open5GS services...${NC}"
for service in "${services[@]}"; do
    stop_service "$service"
done

# Wait for all services to stop
echo -e "\n${YELLOW}Waiting for services to fully stop...${NC}"
sleep 5

# Start all services
echo -e "\n${YELLOW}Starting all Open5GS services...${NC}"
for service in "${services[@]}"; do
    start_service "$service"
done

# Verify all services are running
echo -e "\n${YELLOW}Verifying service status...${NC}"
all_running=true
for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service is running${NC}"
    else
        echo -e "${RED}✗ $service is not running${NC}"
        all_running=false
    fi
done

if [ "$all_running" = true ]; then
    echo -e "\n${GREEN}✓ All services have been successfully restarted${NC}"
else
    echo -e "\n${RED}✗ Some services failed to start. Please check the logs for more information.${NC}"
    echo -e "${YELLOW}Checking logs for failed services...${NC}"
    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet $service; then
            echo -e "\n${YELLOW}Logs for $service:${NC}"
            journalctl -u $service -n 10 --no-pager
        fi
    done
fi 