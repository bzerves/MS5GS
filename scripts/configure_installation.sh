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

# Function to validate URL format
validate_url() {
    if [[ $1 =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate username format
validate_username() {
    if [[ $1 =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate password strength
validate_password() {
    if [ ${#1} -ge 8 ] && [[ $1 =~ [A-Z] ]] && [[ $1 =~ [a-z] ]] && [[ $1 =~ [0-9] ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate IP address
validate_ip() {
    if [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to list available IP addresses
list_ip_addresses() {
    echo -e "${YELLOW}Available IPv4 addresses:${NC}"
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2, "(" $7 ")"}' | nl
}

# Function to get IP from selection
get_ip_from_selection() {
    local selected_num=$1
    ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2, "(" $7 ")"}' | nl | awk -v num="$selected_num" '$1 == num {print $2}'
}

# Function to get interface from IP
get_interface_from_ip() {
    local ip=$1
    ip -4 -o addr show | awk -v ip="$ip" '$4 ~ ("^" ip "/") {print $2; exit}'
}

# Network Interface Configuration
echo -e "\n${YELLOW}Configuring network interfaces...${NC}"
list_ip_addresses

# Get management IP
echo -e "\n${YELLOW}Select the IP address for S1/Management traffic:${NC}"
echo -e "This IP will be used for MME S1AP, SMF GTPC/PFCP, and WebUI interfaces (control plane)"
while true; do
    read -p "Enter number from list: " mgmt_num
    if [[ $mgmt_num =~ ^[0-9]+$ ]]; then
        mgmt_ip=$(get_ip_from_selection "$mgmt_num")
        if [ ! -z "$mgmt_ip" ]; then
            mgmt_ip_addr=$(echo "$mgmt_ip" | cut -d'/' -f1)
            mgmt_interface=$(get_interface_from_ip "$mgmt_ip_addr")
            break
        else
            echo -e "${RED}Invalid selection. Please choose a number from the list.${NC}"
        fi
    else
        echo -e "${RED}Please enter a number.${NC}"
    fi
done

# Get User WAN IP
echo -e "\n${YELLOW}Select the IP address for User WAN traffic:${NC}"
echo -e "This IP will be used for SMF GTPU and SGW-U GTPU interfaces (user data traffic)"
while true; do
    read -p "Enter number from list: " user_wan_num
    if [[ $user_wan_num =~ ^[0-9]+$ ]]; then
        user_wan_ip=$(get_ip_from_selection "$user_wan_num")
        if [ ! -z "$user_wan_ip" ]; then
            user_wan_ip_addr=$(echo "$user_wan_ip" | cut -d'/' -f1)
            user_wan_interface=$(get_interface_from_ip "$user_wan_ip_addr")
            break
        else
            echo -e "${RED}Invalid selection. Please choose a number from the list.${NC}"
        fi
    else
        echo -e "${RED}Please enter a number.${NC}"
    fi
done

# Get PLMN Configuration
echo -e "\n${YELLOW}Configuring PLMN (Public Land Mobile Network)...${NC}"
echo -e "${GREEN}Tip: Just press Enter to use the default values shown in brackets${NC}"

while true; do
    read -p "Enter Mobile Country Code (MCC, 3 digits) [default: 901]: " mcc
    if [ -z "$mcc" ]; then
        mcc="901"
        echo -e "${GREEN}Using default MCC: 901${NC}"
        break
    elif [[ $mcc =~ ^[0-9]{3}$ ]]; then
        break
    else
        echo -e "${RED}Invalid MCC. Please enter exactly 3 digits.${NC}"
    fi
done

while true; do
    read -p "Enter Mobile Network Code (MNC, 2-3 digits) [default: 70]: " mnc
    if [ -z "$mnc" ]; then
        mnc="70"
        echo -e "${GREEN}Using default MNC: 70${NC}"
        break
    elif [[ $mnc =~ ^[0-9]{2,3}$ ]]; then
        break
    else
        echo -e "${RED}Invalid MNC. Please enter 2 or 3 digits.${NC}"
    fi
done

# Get Tracking Area Code
while true; do
    read -p "Enter Tracking Area Code (TAC, 1-5 digits) [default: 10]: " tac
    if [ -z "$tac" ]; then
        tac="10"
        echo -e "${GREEN}Using default TAC: 10${NC}"
        break
    elif [[ $tac =~ ^[0-9]{1,5}$ ]]; then
        break
    else
        echo -e "${RED}Invalid TAC. Please enter 1-5 digits.${NC}"
    fi
done

# Get HSS Configuration
echo -e "\n${YELLOW}Configuring HSS credentials...${NC}"
while true; do
    read -p "Enter the HSS URL (e.g., https://hss.example.com): " hss_url
    if validate_url "$hss_url"; then
        break
    else
        echo -e "${RED}Invalid URL format. Please include http:// or https://${NC}"
    fi
done

while true; do
    read -p "Enter HSS username (alphanumeric and underscore only): " hss_username
    if validate_username "$hss_username"; then
        break
    else
        echo -e "${RED}Invalid username format. Use only alphanumeric characters and underscores.${NC}"
    fi
done

while true; do
    read -s -p "Enter HSS password (min 8 chars, 1 uppercase, 1 lowercase, 1 number): " hss_password
    echo
    if validate_password "$hss_password"; then
        read -s -p "Confirm password: " hss_password_confirm
        echo
        if [ "$hss_password" = "$hss_password_confirm" ]; then
            break
        else
            echo -e "${RED}Passwords do not match.${NC}"
        fi
    else
        echo -e "${RED}Password does not meet requirements.${NC}"
    fi
done

# Create configuration file
echo -e "\n${YELLOW}Saving configuration...${NC}"

# Create directory if it doesn't exist
mkdir -p /etc/open5gs

cat > /etc/open5gs/install.conf << EOF
# Network Configuration
MGMT_INTERFACE=$mgmt_interface
MGMT_IP=$mgmt_ip
USER_WAN_INTERFACE=$user_wan_interface
USER_WAN_IP=$user_wan_ip

# PLMN Configuration
MCC=$mcc
MNC=$mnc
TAC=$tac

# HSS Configuration
HSS_URL=$hss_url
HSS_USERNAME=$hss_username
HSS_PASSWORD=$(echo -n "$hss_password" | base64)
EOF

# Set proper permissions
chmod 600 /etc/open5gs/install.conf

echo -e "\n${GREEN}✓ Configuration completed successfully${NC}"
echo -e "${YELLOW}Configuration Summary:${NC}"
echo -e "Management Interface: $mgmt_interface ($mgmt_ip)"
echo -e "User WAN Interface: $user_wan_interface ($user_wan_ip)"
echo -e "PLMN: MCC=$mcc, MNC=$mnc, TAC=$tac"
echo -e "HSS URL: $hss_url"
echo -e "${YELLOW}Configuration saved to /etc/open5gs/install.conf${NC}" 
