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

# Check if credentials file exists
if [ ! -f ../credentials.txt ]; then
    echo -e "${RED}Credentials file not found. Please run the HSS configuration first.${NC}"
    exit 1
fi

# Source credentials
source ../credentials.txt

# Install required packages
echo -e "\n${YELLOW}Installing required packages...${NC}"
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx

# Update Nginx configuration with the correct server name
echo -e "\n${YELLOW}Updating Nginx configuration...${NC}"
sed -i "s/server_name _;/server_name ${HSS_URL#https://};/" /etc/nginx/sites-available/open5gs-webui

# Test Nginx configuration
echo -e "\n${YELLOW}Testing Nginx configuration...${NC}"
nginx -t

# Restart Nginx
systemctl restart nginx

# Get SSL certificate
echo -e "\n${YELLOW}Obtaining SSL certificate from LetsEncrypt...${NC}"
certbot --nginx -d ${HSS_URL#https://} --non-interactive --agree-tos --email admin@${HSS_URL#https://}

# Configure automatic renewal
echo -e "\n${YELLOW}Configuring automatic certificate renewal...${NC}"
systemctl enable certbot.timer
systemctl start certbot.timer

# Verify SSL configuration
echo -e "\n${YELLOW}Verifying SSL configuration...${NC}"
if curl -s -I "$HSS_URL" | grep -q "HTTP/1.1 200 OK"; then
    echo -e "${GREEN}✓ SSL setup completed successfully${NC}"
    echo -e "${GREEN}✓ Web UI is accessible via HTTPS${NC}"
else
    echo -e "${RED}✗ SSL setup may have issues. Please check the configuration.${NC}"
fi

# Show certificate information
echo -e "\n${YELLOW}Certificate Information:${NC}"
certbot certificates

echo -e "\n${GREEN}✓ SSL setup completed${NC}"
echo -e "${YELLOW}Note: Your SSL certificate will automatically renew before expiration.${NC}"
echo -e "${YELLOW}Web UI is now accessible at: $HSS_URL${NC}" 