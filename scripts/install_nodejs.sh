#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Update package list and install prerequisites
echo -e "${YELLOW}Updating package list and installing prerequisites...${NC}"
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# Create keyrings directory and import NodeSource GPG key
echo -e "${YELLOW}Importing NodeSource GPG key...${NC}"
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg

# Create deb repository for NodeJS 20
echo -e "${YELLOW}Setting up NodeJS repository...${NC}"
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list

# Update package list and install NodeJS
echo -e "${YELLOW}Installing NodeJS...${NC}"
sudo apt update
sudo apt install nodejs -y

# Verify installation
echo -e "${YELLOW}Verifying NodeJS installation...${NC}"
node_version=$(node --version)
npm_version=$(npm --version)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}NodeJS installation successful!${NC}"
    echo -e "${GREEN}NodeJS version: $node_version${NC}"
    echo -e "${GREEN}npm version: $npm_version${NC}"
else
    echo -e "${RED}NodeJS installation failed. Please check the errors above.${NC}"
    exit 1
fi 