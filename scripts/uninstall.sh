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

# Function to stop and disable service
stop_service() {
    local service=$1
    echo -e "${YELLOW}Stopping and disabling $service...${NC}"
    systemctl stop $service
    systemctl disable $service
    sleep 2
    if systemctl is-active --quiet $service; then
        echo -e "${RED}Failed to stop $service${NC}"
        return 1
    else
        echo -e "${GREEN}✓ $service stopped and disabled${NC}"
        return 0
    fi
}

# List of services to stop
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

# Remove Open5GS packages
echo -e "\n${YELLOW}Removing Open5GS packages...${NC}"
apt-get remove -y open5gs
apt-get autoremove -y

# Remove configuration files
echo -e "\n${YELLOW}Removing configuration files...${NC}"
rm -rf /etc/open5gs
rm -rf /var/log/open5gs

# Remove Nginx configuration if it exists
if [ -f /etc/nginx/sites-available/open5gs ]; then
    echo -e "\n${YELLOW}Removing Nginx configuration...${NC}"
    rm -f /etc/nginx/sites-available/open5gs
    rm -f /etc/nginx/sites-enabled/open5gs
    systemctl restart nginx
fi

# Remove LetsEncrypt certificate if it exists
if [ -d /etc/letsencrypt/live ]; then
    echo -e "\n${YELLOW}Removing LetsEncrypt certificates...${NC}"
    certbot delete --non-interactive
fi

# Remove credentials file if it exists
if [ -f ../credentials.txt ]; then
    echo -e "\n${YELLOW}Removing credentials file...${NC}"
    rm -f ../credentials.txt
fi

# Remove Open5GS PPA
echo -e "\n${YELLOW}Removing Open5GS PPA...${NC}"
add-apt-repository -y --remove ppa:open5gs/latest
apt-get update

# Clean up any remaining files
echo -e "\n${YELLOW}Cleaning up remaining files...${NC}"
find / -name "*open5gs*" -type f -delete 2>/dev/null
find / -name "*open5gs*" -type d -delete 2>/dev/null

echo -e "\n${GREEN}✓ Open5GS has been completely uninstalled${NC}"
echo -e "${YELLOW}Note: You may need to manually remove any custom configurations or data files.${NC}" 