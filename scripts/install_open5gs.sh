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
echo -e "${YELLOW}Setting Management IP: $MGMT_IP, User WAN IP: $USER_WAN_IP${NC}"

# Strip any CIDR notation from IP addresses if present
S1_MANAGEMENT_IP_CLEAN=$(echo "$MGMT_IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')
USER_WAN_IP_CLEAN=$(echo "$USER_WAN_IP" | sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+).*/\1/')

# Use awk for all parameter updates
echo -e "${YELLOW}Using awk for all parameter updates...${NC}"

# Create a temporary file for MME config
TMP_FILE=$(mktemp)
cat /etc/open5gs/mme.yaml > $TMP_FILE

# Update all values with a single awk command
awk -v mcc="$MCC" -v mnc="$MNC" -v tac="$TAC" -v mgmt_ip="$S1_MANAGEMENT_IP_CLEAN" -v user_wan_ip="$USER_WAN_IP_CLEAN" '
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

# Update S1AP server address (using management IP)
/address:/ && in_s1ap_server {
    sub(/address: 127\.0\.0\.2/, "address: " mgmt_ip);
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
   grep -q "address: $S1_MANAGEMENT_IP_CLEAN" /etc/open5gs/mme.yaml; then
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

# Check and remove NO_TLS option from freeDiameter config files
echo -e "${YELLOW}Checking and removing NO_TLS option from freeDiameter config files...${NC}"

# Check for MME freeDiameter config
if [ -f /etc/freeDiameter/mme.conf ]; then
    echo -e "${YELLOW}Checking /etc/freeDiameter/mme.conf for NO_TLS option...${NC}"
    
    # Backup the file before making changes
    cp /etc/freeDiameter/mme.conf /etc/freeDiameter/mme.conf.bak
    
    # Remove NO_TLS option from ConnectPeer sections
    sed -i 's/ConnectPeer.*NO_TLS/ConnectPeer/g' /etc/freeDiameter/mme.conf
    
    # Check if changes were made
    if cmp -s /etc/freeDiameter/mme.conf /etc/freeDiameter/mme.conf.bak; then
        echo -e "${GREEN}No NO_TLS option found in mme.conf.${NC}"
    else
        echo -e "${GREEN}Successfully removed NO_TLS option from mme.conf.${NC}"
    fi
else
    echo -e "${YELLOW}/etc/freeDiameter/mme.conf file not found.${NC}"
fi

# Check for HSS freeDiameter config
if [ -f /etc/freeDiameter/hss.conf ]; then
    echo -e "${YELLOW}Checking /etc/freeDiameter/hss.conf for NO_TLS option...${NC}"
    
    # Backup the file before making changes
    cp /etc/freeDiameter/hss.conf /etc/freeDiameter/hss.conf.bak
    
    # Remove NO_TLS option from ConnectPeer sections
    sed -i 's/ConnectPeer.*NO_TLS/ConnectPeer/g' /etc/freeDiameter/hss.conf
    
    # Check if changes were made
    if cmp -s /etc/freeDiameter/hss.conf /etc/freeDiameter/hss.conf.bak; then
        echo -e "${GREEN}No NO_TLS option found in hss.conf.${NC}"
    else
        echo -e "${GREEN}Successfully removed NO_TLS option from hss.conf.${NC}"
    fi
else
    echo -e "${YELLOW}/etc/freeDiameter/hss.conf file not found.${NC}"
fi





# Configure SMF
echo -e "${GREEN}Configuring Open5GS SMF...${NC}"

if [ ! -f /etc/open5gs/smf.yaml ]; then
    echo -e "${RED}SMF configuration file not found at /etc/open5gs/smf.yaml${NC}"
    exit 1
fi

echo -e "${YELLOW}Backing up original SMF configuration...${NC}"
sudo cp /etc/open5gs/smf.yaml /etc/open5gs/smf.yaml.bak

TMP_FILE=$(mktemp)
cat /etc/open5gs/smf.yaml > $TMP_FILE

awk -v mgmt_ip="$S1_MANAGEMENT_IP_CLEAN" '
/smf:/ { in_smf=1 }
/gtpc:/ && in_smf { in_gtpc=1; in_gtpu=0; in_pfcp=0 }
/gtpu:/ && in_smf { in_gtpc=0; in_gtpu=1; in_pfcp=0 }
/pfcp:/ && in_smf { in_gtpc=0; in_gtpu=0; in_pfcp=1 }
/server:/ && in_gtpc { in_gtpc_server=1 }
/server:/ && in_gtpu { in_gtpu_server=1 }
/server:/ && in_pfcp { in_pfcp_server=1 }
/client:/ { in_gtpc_server=0; in_gtpu_server=0; in_pfcp_server=0 }

/address:/ && in_gtpc_server {
    sub(/address:.*/, "address: " mgmt_ip);
    in_gtpc_server=0;
}

/address:/ && in_gtpu_server {
    sub(/address:.*/, "address: 127.0.0.10");
    in_gtpu_server=0;
}

/address:/ && in_pfcp_server {
    sub(/address:.*/, "address: " mgmt_ip);
    in_pfcp_server=0;
}

{ print }
' $TMP_FILE > ${TMP_FILE}.new

sudo cp ${TMP_FILE}.new /etc/open5gs/smf.yaml
echo -e "${GREEN}SMF parameters updated using awk method${NC}"
rm -f $TMP_FILE ${TMP_FILE}.new

# Configure SGW-U
echo -e "${GREEN}Configuring Open5GS SGW-U...${NC}"

if [ ! -f /etc/open5gs/sgwu.yaml ]; then
    echo -e "${RED}SGW-U configuration file not found at /etc/open5gs/sgwu.yaml${NC}"
    exit 1
fi

echo -e "${YELLOW}Backing up original SGW-U configuration...${NC}"
sudo cp /etc/open5gs/sgwu.yaml /etc/open5gs/sgwu.yaml.bak

TMP_FILE=$(mktemp)
cat /etc/open5gs/sgwu.yaml > $TMP_FILE

awk -v mgmt_ip="$S1_MANAGEMENT_IP_CLEAN" -v user_wan_ip="$USER_WAN_IP_CLEAN" '
/sgwu:/ { in_sgwu=1 }
/gtpu:/ && in_sgwu { in_gtpu=1; in_pfcp=0 }
/pfcp:/ && in_sgwu { in_gtpu=0; in_pfcp=1 }
/server:/ && in_gtpu { in_gtpu_server=1 }
/server:/ && in_pfcp { in_pfcp_server=1 }
/client:/ { in_gtpu_server=0; in_pfcp_server=0; in_pfcp_client=1 }

/address:/ && in_gtpu_server {
    sub(/address:.*/, "address: " user_wan_ip);
    in_gtpu_server=0;
}

/address:/ && in_pfcp_server {
    sub(/address:.*/, "address: 127.0.0.6");
    in_pfcp_server=0;
}

/^#.*sgwc:/ && in_pfcp && in_pfcp_client {
    sub(/^#/, "");
}

/^#.*address:.*127\./ && in_pfcp && in_pfcp_client {
    sub(/^#/, "");
    sub(/address:.*/, "address: " mgmt_ip);
}

{ print }
' $TMP_FILE > ${TMP_FILE}.new

sudo cp ${TMP_FILE}.new /etc/open5gs/sgwu.yaml
echo -e "${GREEN}SGW-U parameters updated using awk method${NC}"
rm -f $TMP_FILE ${TMP_FILE}.new







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

# Restart all Open5GS services
echo -e "${GREEN}Restarting all Open5GS services...${NC}"
for service in open5gs-mmed open5gs-sgwcd open5gs-smfd open5gs-amfd open5gs-sgwud open5gs-upfd open5gs-hssd open5gs-pcrfd open5gs-nrfd open5gs-ausfd open5gs-udmd open5gs-pcfd open5gs-nssfd open5gs-bsfd open5gs-udrd; do
    if systemctl is-enabled --quiet $service 2>/dev/null; then
        echo -e "${YELLOW}Restarting $service...${NC}"
        systemctl restart $service
    fi
done

echo -e "${GREEN}Open5GS installation and configuration completed successfully.${NC}"