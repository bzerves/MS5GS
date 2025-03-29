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

# Check for configuration file
if [ ! -f /etc/open5gs/install.conf ]; then
    echo -e "${RED}Configuration file not found. Please run configure_installation.sh first.${NC}"
    exit 1
fi

# Load configuration
source /etc/open5gs/install.conf

# Detect OS and set repository accordingly
echo -e "\n${YELLOW}Detecting OS and adding Open5GS repository...${NC}"
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        echo -e "${YELLOW}Detected Ubuntu. Adding Open5GS PPA...${NC}"
        apt-get install -y software-properties-common
        add-apt-repository -y ppa:open5gs/latest
    elif [[ "$ID" == "debian" ]]; then
        echo -e "${YELLOW}Detected Debian. Adding Open5GS repository...${NC}"
        apt-get install -y wget gnupg
        mkdir -p /etc/apt/keyrings
        wget -qO - https://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/Debian_12/Release.key | gpg --dearmor -o /etc/apt/keyrings/open5gs.gpg
        echo "deb [signed-by=/etc/apt/keyrings/open5gs.gpg] http://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/Debian_12/ ./" > /etc/apt/sources.list.d/open5gs.list
    else
        echo -e "${RED}Unsupported OS: $ID${NC}"
        exit 1
    fi
else
    echo -e "${RED}Could not determine OS type${NC}"
    exit 1
fi

echo -e "${YELLOW}Updating package lists...${NC}"
apt update || {
    echo -e "${RED}Failed to update package lists${NC}"
    exit 1
}

echo -e "${YELLOW}Installing Open5GS...${NC}" 
apt install -y open5gs || {
    echo -e "${RED}Failed to install Open5GS${NC}"
    exit 1
}

# Configure Open5GS
echo -e "${GREEN}Configuring Open5GS MME...${NC}"

# Check if the configuration files exist
if [ ! -f /etc/open5gs/mme.yaml ]; then
    echo -e "${RED}MME configuration file not found at /etc/open5gs/mme.yaml${NC}"
    exit 1
fi

# Backup the original configuration
echo -e "${YELLOW}Backing up original MME configuration...${NC}"
sudo cp /etc/open5gs/mme.yaml /etc/open5gs/mme.yaml.bak

# Update mme.yaml with values from install.conf
echo -e "${YELLOW}Setting MCC: $MCC, MNC: $MNC, TAC: $TAC${NC}"
echo -e "${YELLOW}Setting S1AP IP: $S1_IP, GTPU IP: $MGMT_IP${NC}"

# Strip any CIDR notation from IP addresses if present
S1_IP_CLEAN=$(echo "$S1_IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')
MGMT_IP_CLEAN=$(echo "$MGMT_IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')

# Use awk for all parameter updates
echo -e "${YELLOW}Using awk for all parameter updates...${NC}"

# Create a temporary file for MME config
TMP_FILE=$(mktemp)
cat /etc/open5gs/mme.yaml > $TMP_FILE

# Update all values with a single awk command
awk -v mcc="$MCC" -v mnc="$MNC" -v tac="$TAC" -v s1_ip="$S1_IP_CLEAN" -v mgmt_ip="$MGMT_IP_CLEAN" '
# Track context within the YAML structure
/mme:/ { in_mme=1 }
/s1ap:/ && in_mme { in_s1ap=1; in_gummei=0; in_tai=0 }
/gtpc:/ && in_mme { in_s1ap=0; in_gtpc=1; in_gummei=0; in_tai=0 }
/gummei:/ && in_mme { in_s1ap=0; in_gtpc=0; in_gummei=1; in_tai=0 }
/tai:/ && in_mme { in_s1ap=0; in_gtpc=0; in_gummei=0; in_tai=1 }
/server:/ && in_s1ap { in_s1ap_server=1 }
/server:/ && in_gtpc { in_gtpc_server=1 }
/client:/ { in_s1ap_server=0; in_gtpc_server=0 }
/security:/ { in_gummei=0; in_tai=0 }

# Update MCC in gummei section
/mcc:/ && in_gummei {
    sub(/mcc: [0-9]+/, "mcc: " mcc);
    in_plmn_id_gummei_done=1;
}

# Update MNC in gummei section
/mnc:/ && in_gummei && in_plmn_id_gummei_done {
    sub(/mnc: [0-9]+/, "mnc: " mnc);
    in_plmn_id_gummei_done=0;
}

# Update MCC in tai section
/mcc:/ && in_tai {
    sub(/mcc: [0-9]+/, "mcc: " mcc);
    in_plmn_id_tai_done=1;
}

# Update MNC in tai section
/mnc:/ && in_tai && in_plmn_id_tai_done {
    sub(/mnc: [0-9]+/, "mnc: " mnc);
    in_plmn_id_tai_done=0;
}

# Update TAC value
/tac:/ && in_tai {
    sub(/tac: [0-9]+/, "tac: " tac);
}

# Update S1AP server address
/address:/ && in_s1ap_server {
    sub(/address: 127\.0\.0\.2/, "address: " s1_ip);
    in_s1ap_server=0;  # Only replace first address in s1ap section
}

# Print the current line (modified or not)
{ print }
' $TMP_FILE > ${TMP_FILE}.new

# Apply the changes
sudo cp ${TMP_FILE}.new /etc/open5gs/mme.yaml
echo -e "${GREEN}All parameters updated using awk method${NC}"

# Clean up temporary files
rm -f $TMP_FILE ${TMP_FILE}.new

# Verify the changes
if grep -q "mcc: $MCC" /etc/open5gs/mme.yaml && \
   grep -q "mnc: $MNC" /etc/open5gs/mme.yaml && \
   grep -q "tac: $TAC" /etc/open5gs/mme.yaml && \
   grep -q "address: $S1_IP_CLEAN" /etc/open5gs/mme.yaml && \
   grep -q "address: $MGMT_IP_CLEAN" /etc/open5gs/mme.yaml; then
    echo -e "${GREEN}MME configuration updated successfully.${NC}"
else
    echo -e "${RED}Failed to update some MME configuration values. Please check /etc/open5gs/mme.yaml manually.${NC}"
    echo -e "${YELLOW}A backup of the original configuration is available at /etc/open5gs/mme.yaml.bak${NC}"
    # Debug output to show what was updated
    echo -e "${YELLOW}Current MME configuration values:${NC}"
    echo -e "MCC: $(grep -o 'mcc: [0-9]\+' /etc/open5gs/mme.yaml | head -1)"
    echo -e "MNC: $(grep -o 'mnc: [0-9]\+' /etc/open5gs/mme.yaml | head -1)"
    echo -e "TAC: $(grep -o 'tac: [0-9]\+' /etc/open5gs/mme.yaml | head -1)"
    echo -e "S1AP Address: $(grep -A 2 's1ap:' /etc/open5gs/mme.yaml | grep 'address:')"
    echo -e "GTPC Address: $(grep -A 2 'gtpc:' /etc/open5gs/mme.yaml | grep 'address:')"
fi

# Restart Open5GS services
echo -e "${GREEN}Restarting Open5GS services...${NC}"
sudo systemctl restart open5gs-mmed
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Open5GS MME service restarted successfully.${NC}"
else
    echo -e "${RED}Failed to restart Open5GS MME service. Please check the service status.${NC}"
fi

# Check and install iptables if needed (especially for Debian)
echo -e "${YELLOW}Checking if iptables is installed...${NC}"
if ! command -v iptables &> /dev/null; then
    echo -e "${YELLOW}iptables not found. Installing iptables and related packages...${NC}"
    # Set non-interactive frontend to avoid prompts
    export DEBIAN_FRONTEND=noninteractive
    # Pre-set answers for iptables-persistent
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    # Install packages
    apt install -y iptables iptables-persistent netfilter-persistent || {
        echo -e "${RED}Failed to install iptables${NC}"
        exit 1
    }
    # Create rules directories if they don't exist
    mkdir -p /etc/iptables
fi

# Configure IP forwarding and firewall rules
echo -e "${GREEN}Configuring IP forwarding and firewall rules...${NC}"

# Enable IPv4/IPv6 forwarding
echo -e "${YELLOW}Enabling IPv4/IPv6 forwarding...${NC}"
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1

# Make IP forwarding persistent
echo "net.ipv4.ip_forward=1" | tee /etc/sysctl.d/30-ipforward.conf
echo "net.ipv6.conf.all.forwarding=1" | tee -a /etc/sysctl.d/30-ipforward.conf

# Add NAT rules
echo -e "${YELLOW}Adding NAT rules...${NC}"
iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
ip6tables -t nat -A POSTROUTING -s 2001:db8:cafe::/48 ! -o ogstun -j MASQUERADE

# Configure firewall
echo -e "${YELLOW}Configuring firewall...${NC}"
if command -v ufw >/dev/null 2>&1; then
    echo -e "${YELLOW}Disabling UFW firewall...${NC}"
    ufw disable
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ UFW firewall disabled successfully${NC}"
    else
        echo -e "${RED}Failed to disable UFW firewall${NC}"
    fi
fi

# Add security rules
echo -e "${YELLOW}Adding security rules...${NC}"
iptables -I INPUT -i ogstun -j ACCEPT
iptables -I INPUT -s 10.45.0.0/16 -j DROP
ip6tables -I INPUT -s 2001:db8:cafe::/48 -j DROP

# Make iptables rules persistent
echo -e "${YELLOW}Making iptables rules persistent...${NC}"
if command -v netfilter-persistent &> /dev/null; then
    echo -e "${YELLOW}Using netfilter-persistent to save rules...${NC}"
    netfilter-persistent save || {
        echo -e "${RED}Failed to save firewall rules using netfilter-persistent${NC}"
    }
elif command -v iptables-save &> /dev/null; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    echo -e "${GREEN}✓ Firewall rules saved successfully${NC}"
else
    echo -e "${RED}Neither netfilter-persistent nor iptables-save found. Firewall rules will not persist after reboot${NC}"
fi