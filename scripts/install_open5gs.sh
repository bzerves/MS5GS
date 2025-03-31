#!/bin/bash

# Script to Install and Configure Open5GS for a 4G/5G Hybrid Core
# with a Two-Interface Setup (Management + User Plane WAN)

# --- Configuration (Defaults, can be overridden by install.conf) ---
DEFAULT_UE_SUBNET="10.45.0.0/16"
DEFAULT_DNN="internet" # Default Data Network Name

INSTALL_CONF="/etc/open5gs/install.conf"
OPEN5GS_CONFIG_DIR="/etc/open5gs"
NODE_UTIL_SCRIPT="/usr/local/sbin/open5gs-edit-yaml.js" # Path to save the Node.js utility

# --- Colors for output ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Source the presetup script ---
source ./scripts/install_open5gs__presetup.sh

# --- Source the packages script ---
source ./scripts/install_open5gs__packages.sh

# --- Source the YAML editing script ---
source ./scripts/install_open5gs__yaml_editing.sh

# --- Source the networking script ---
source ./scripts/install_open5gs__networking.sh

# --- Source the services script ---
source ./scripts/install_open5gs__services.sh

# --- Final Message ---
# (Keep this section as is)
log_step "Installation and Configuration Complete!"
echo -e "${GREEN}Open5GS should now be configured and running.${NC}"
echo -e "Management/Control Plane IP: ${GREEN}$MGMT_IP_ADDR${NC}"
echo -e "User Plane WAN Interface: ${GREEN}$EFFECTIVE_USER_WAN_IF${NC} (IP: ${GREEN}$USER_WAN_IP_ADDR${NC})"
echo -e "UE Subnet: ${GREEN}$UE_SUBNET${NC}"
echo -e "DNN: ${GREEN}${DNN:-Not Set}${NC}"
echo -e "PLMN: ${GREEN}$MCC/$MNC${NC}, TAC: ${GREEN}$TAC_NUM${NC}"
echo -e "Ensure your eNodeBs/gNodeBs are configured to connect to S1AP/NGAP interface at: ${YELLOW}$MGMT_IP_ADDR${NC}"
echo -e "Firewall Note: Ensure necessary ports are open on $MGMT_IP_ADDR (e.g., S1AP:36412/sctp, NGAP:38412/sctp, GTP-C:2123/udp, PFCP:8805/udp) and potentially on $USER_WAN_IP_ADDR (GTP-U:2152/udp) if a host firewall is active."
echo -e "Check service status with: ${YELLOW}systemctl status 'open5gs-*'${NC}"
echo -e "Check logs with: ${YELLOW}journalctl -u <service_name>${NC} (e.g., journalctl -u open5gs-amfd)"

exit 0