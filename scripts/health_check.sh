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

# Function to check and install required package only if missing
check_package() {
    local package=$1
    if ! command -v $package >/dev/null 2>&1; then
        echo -e "${YELLOW}Required package missing: $package${NC}"
        echo -e "${YELLOW}Checking for package updates...${NC}"
        apt-get update
        apt-get install -y $package || {
            echo -e "${RED}✗ Failed to install $package${NC}"
            return 1
        }
        clear
    fi
    return 0
}

# Function to check service status
check_service() {
    local service=$1
    if systemctl is-active --quiet $service; then
        echo -e "${GREEN}✓ $service is running${NC}"
        return 0
    else
        echo -e "${RED}✗ $service is not running${NC}"
        echo -e "${YELLOW}Checking logs for $service:${NC}"
        journalctl -u $service -n 10 --no-pager
        return 1
    fi
}

# Function to check port accessibility
check_port() {
    local port=$1
    local service=$2
    if netstat -tuln | grep -q ":$port "; then
        echo -e "${GREEN}✓ Port $port is open for $service${NC}"
        return 0
    else
        echo -e "${RED}✗ Port $port is not open for $service${NC}"
        return 1
    fi
}

# Function to check what ports a process is listening on
check_process_ports() {
    local process_name=$1
    echo -e "\n${YELLOW}Checking listening ports for $process_name:${NC}"
    # Get the PID of the process
    local pid=$(pgrep -f "$process_name")
    if [ -z "$pid" ]; then
        echo -e "${RED}No process found matching $process_name${NC}"
        return 1
    fi
    
    # Check what ports the process is listening on
    echo -e "Process $pid is listening on:"
    netstat -tulpn 2>/dev/null | grep "$pid" || {
        echo -e "${YELLOW}No listening ports found for process $pid${NC}"
        echo -e "Checking all listening ports:"
        netstat -tulpn 2>/dev/null
    }
}

# Function to check HTTPS accessibility
check_https() {
    local domain=$1
    if curl -s -I "https://$domain" > /dev/null; then
        echo -e "${GREEN}✓ HTTPS is accessible at https://$domain${NC}"
        return 0
    else
        echo -e "${RED}✗ HTTPS is not accessible at https://$domain${NC}"
        return 1
    fi
}

# Function to check web UI status
check_webui() {
    echo -e "\n${YELLOW}Checking Web UI status...${NC}"
    
    # Check if NodeJS is running
    if ! pgrep -x "node" >/dev/null; then
        echo -e "${RED}✗ No NodeJS process is running${NC}"
        return 1
    fi
    
    # Check Web UI service
    check_service open5gs-webui
    
    # Check what ports the Web UI is actually listening on
    check_process_ports "open5gs-webui"
    
    # Check Web UI port
    check_port 3000 "Web UI"
    
    # Check if Web UI is responding
    if curl -s http://localhost:3000 > /dev/null; then
        echo -e "${GREEN}✓ Web UI is responding on localhost:3000${NC}"
    else
        echo -e "${RED}✗ Web UI is not responding on localhost:3000${NC}"
    fi
    
    # Check Web UI process details
    echo -e "\n${YELLOW}Web UI Process Details:${NC}"
    ps aux | grep "node" | grep -v grep
}

# Clear terminal and show header
clear
echo -e "${GREEN}=== Rapid5GS Health Check ===${NC}"

# Load configuration
if [ ! -f "/etc/open5gs/install.conf" ]; then
    echo -e "${RED}Installation configuration not found. Please run the configuration step first.${NC}"
    exit 1
fi

source /etc/open5gs/install.conf

# Function to check system resources
check_system_resources() {
    echo -e "\n${YELLOW}Checking system resources...${NC}"
    echo -e "Memory Usage:"
    free -h
    echo -e "\nDisk Usage:"
    df -h /
    echo -e "\nCPU Usage:"
    top -bn1 | grep "Cpu(s)" | awk '{print $2}'
}

# Function to check network interfaces
check_network_interfaces() {
    echo -e "\n${YELLOW}Checking network interfaces...${NC}"
    ip addr show
}

# Check only essential packages that might be missing
echo -e "${YELLOW}Checking essential packages...${NC}"
check_package net-tools
check_package curl

# Check system resources
check_system_resources

# Check network interfaces
check_network_interfaces

# Check Open5GS services
echo -e "\n${YELLOW}Checking Open5GS services...${NC}"
for service in open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-hssd open5gs-pcrfd open5gs-smfd open5gs-amfd open5gs-sgwc open5gs-upfd open5gs-pcfd open5gs-nssfd open5gs-bsfd open5gs-udmd open5gs-pcscf open5gs-scscf open5gs-icscf; do
    check_service $service
done

# Check Nginx service
echo -e "\n${YELLOW}Checking Nginx service...${NC}"
check_service nginx

# Check port accessibility
echo -e "\n${YELLOW}Checking port accessibility...${NC}"
check_port 443 "HTTPS"
check_port 80 "HTTP"

# Check HTTPS accessibility
echo -e "\n${YELLOW}Checking HTTPS accessibility...${NC}"
if [ ! -z "$DOMAIN_NAME" ]; then
    check_https $DOMAIN_NAME
else
    echo -e "${RED}Domain name not found in configuration${NC}"
fi

# Check MongoDB
echo -e "\n${YELLOW}Checking MongoDB...${NC}"
check_service mongod
check_port 27017 "MongoDB"

# Check Web UI status
check_webui

# Check attached eNBs
echo -e "\n${YELLOW}Checking attached eNBs...${NC}"
if command -v open5gs-mmed >/dev/null 2>&1; then
    open5gs-mmed --version
    open5gs-mmed --show-attached-enb
else
    echo -e "${RED}open5gs-mmed command not found. Open5GS may not be installed.${NC}"
fi

# Check connected UEs
echo -e "\n${YELLOW}Checking connected UEs...${NC}"
if command -v open5gs-mmed >/dev/null 2>&1; then
    open5gs-mmed --show-connected-ue
else
    echo -e "${RED}open5gs-mmed command not found. Open5GS may not be installed.${NC}"
fi

echo -e "\n${GREEN}Health check completed${NC}" 