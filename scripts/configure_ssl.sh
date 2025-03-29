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

# Load configuration
if [ ! -f "/etc/open5gs/install.conf" ]; then
    echo -e "${RED}Installation configuration not found. Please run the configuration step first.${NC}"
    exit 1
fi

source /etc/open5gs/install.conf

# Validate domain name from config
if [ -z "$DOMAIN_NAME" ]; then
    echo -e "${RED}Domain name not found in configuration. Please run the configuration step first.${NC}"
    exit 1
fi

# Install required packages
echo -e "\n${YELLOW}Installing required packages...${NC}"
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx || {
    echo -e "${RED}✗ Failed to install required packages${NC}"
    exit 1
}

# Create Nginx configuration
echo -e "\n${YELLOW}Creating Nginx configuration...${NC}"
cat > /etc/nginx/sites-available/open5gs-hss << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable the site
echo -e "\n${YELLOW}Enabling Nginx site...${NC}"
ln -sf /etc/nginx/sites-available/open5gs-hss /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
echo -e "\n${YELLOW}Testing Nginx configuration...${NC}"
nginx -t || {
    echo -e "${RED}✗ Nginx configuration test failed${NC}"
    exit 1
}

# Restart Nginx
echo -e "\n${YELLOW}Restarting Nginx...${NC}"
systemctl restart nginx || {
    echo -e "${RED}✗ Failed to restart Nginx${NC}"
    exit 1
}

# Obtain SSL certificate
echo -e "\n${YELLOW}Obtaining SSL certificate from Let's Encrypt...${NC}"
certbot --nginx -d $DOMAIN_NAME --non-interactive --agree-tos --email admin@$DOMAIN_NAME || {
    echo -e "${RED}✗ Failed to obtain SSL certificate${NC}"
    exit 1
}

# Update Open5GS web UI configuration
echo -e "\n${YELLOW}Updating Open5GS web UI configuration...${NC}"

# Strip any CIDR notation from IP addresses if present
S1_MANAGEMENT_IP_CLEAN=$(echo "$MGMT_IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')

cat > /etc/open5gs/webui.yaml << EOF
server:
  port: 3000
  bind: 127.0.0.1
  secret: $(openssl rand -hex 32)

logger:
  file: /var/log/open5gs/webui.log
  level: info

open5gs:
  mme:
    addr: $S1_MANAGEMENT_IP_CLEAN
    port: 36412
  sgw:
    addr: $S1_MANAGEMENT_IP_CLEAN
    port: 2123
  pgw:
    addr: $S1_MANAGEMENT_IP_CLEAN
    port: 2123
  hss:
    addr: $S1_MANAGEMENT_IP_CLEAN
    port: 3868
EOF

# Restart Open5GS web UI service
echo -e "\n${YELLOW}Restarting Open5GS web UI service...${NC}"
systemctl restart open5gs-webui || {
    echo -e "${RED}✗ Failed to restart Open5GS web UI service${NC}"
    exit 1
}

# Set up automatic certificate renewal
echo -e "\n${YELLOW}Setting up automatic certificate renewal...${NC}"
echo "0 0,12 * * * root python -c 'import random; import time; time.sleep(random.random() * 3600)' && certbot renew -q" | tee -a /etc/crontab > /dev/null

echo -e "\n${GREEN}✓ SSL configuration completed successfully${NC}"
echo -e "${YELLOW}You can now access the HSS web interface securely at: https://$DOMAIN_NAME${NC}" 