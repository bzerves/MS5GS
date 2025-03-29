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

# Update system and install required packages
echo -e "\n${YELLOW}Updating system and installing dependencies...${NC}"
apt-get update
apt-get install -y gnupg curl

# Import MongoDB public key
echo -e "\n${YELLOW}Importing MongoDB public key...${NC}"
curl -fsSL https://pgp.mongodb.com/server-8.0.asc | gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor || {
    echo -e "${RED}✗ Failed to import MongoDB public key${NC}"
    exit 1
}

# Detect OS and set repository accordingly
echo -e "\n${YELLOW}Detecting OS and adding MongoDB repository...${NC}"
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/8.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-8.0.list || {
            echo -e "${RED}✗ Failed to create MongoDB repository list${NC}"
            exit 1
        }
    elif [[ "$ID" == "debian" ]]; then
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/8.0 main" | tee /etc/apt/sources.list.d/mongodb-org-8.0.list || {
            echo -e "${RED}✗ Failed to create MongoDB repository list${NC}"
            exit 1
        }
    else
        echo -e "${RED}✗ Unsupported OS: $ID${NC}"
        exit 1
    fi
else
    echo -e "${RED}✗ Could not determine OS type${NC}"
    exit 1
fi

# Update package list and install MongoDB
echo -e "\n${YELLOW}Installing MongoDB...${NC}"
apt-get update
apt-get install -y mongodb-org || {
    echo -e "${RED}✗ MongoDB installation failed${NC}"
    exit 1
}

# Start and enable MongoDB service
echo -e "\n${YELLOW}Starting MongoDB service...${NC}"
systemctl start mongod || {
    echo -e "${RED}✗ Failed to start MongoDB service${NC}"
    exit 1
}

systemctl enable mongod || {
    echo -e "${RED}✗ Failed to enable MongoDB service${NC}"
    exit 1
}

# Verify MongoDB is running
echo -e "\n${YELLOW}Verifying MongoDB status...${NC}"
if systemctl is-active --quiet mongod; then
    echo -e "${GREEN}✓ MongoDB is running${NC}"
else
    echo -e "${RED}✗ MongoDB failed to start${NC}"
    echo -e "${YELLOW}Checking MongoDB logs:${NC}"
    journalctl -u mongod -n 50 --no-pager
    exit 1
fi

echo -e "\n${GREEN}✓ MongoDB installation completed successfully${NC}" 