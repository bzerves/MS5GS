#!/bin/bash

# Script to Install and Configure Open5GS for a 4G/5G Hybrid Core
# with a Two-Interface Setup (Management + User Plane WAN)

# --- Configuration (Defaults, can be overridden by install.conf) ---
DEFAULT_UE_SUBNET="10.45.0.0/16"
# DEFAULT_DNN is not used for configuration in this smf.yaml format
INSTALL_CONF="/etc/open5gs/install.conf"
OPEN5GS_CONFIG_DIR="/etc/open5gs"

# Define standard loopback IPs for internal communication
SMF_PFCP_IP="127.0.0.4" # SMF listens for PFCP here
UPF_PFCP_IP="127.0.0.7" # UPF listens for PFCP here

# --- Colors for output ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${YELLOW}>>> Step: $1...${NC}"; }

# --- Check Prerequisites ---
log_step "Checking Prerequisites"
# ... (Checks remain the same) ...
if [ "$EUID" -ne 0 ]; then log_error "Please run as root (use sudo)"; exit 1; fi
if [ ! -f "$INSTALL_CONF" ]; then log_error "Configuration file not found: $INSTALL_CONF."; exit 1; fi
log_info "Prerequisites met."

# --- Load Configuration ---
log_step "Loading Configuration from $INSTALL_CONF"
source "$INSTALL_CONF"
log_info "Configuration loaded."
UE_SUBNET="${UE_SUBNET:-$DEFAULT_UE_SUBNET}" # Use value from conf or default
log_info "Using UE Subnet: $UE_SUBNET"

# --- Validate Core Configuration Variables ---
log_step "Validating Core Configuration"
if [ -z "$MGMT_IP" ] || [ -z "$USER_WAN_INTERFACE" ] || \
   [ -z "$MCC" ] || [ -z "$MNC" ] || [ -z "$TAC" ] || [ -z "$USER_WAN_IP" ] ; then
    log_error "Required variable missing in $INSTALL_CONF (Need MGMT_IP, USER_WAN_INTERFACE, USER_WAN_IP, MCC, MNC, TAC)"
    exit 1
fi
MGMT_IP_ADDR=$(echo "$MGMT_IP" | cut -d'/' -f1); if [ -z "$MGMT_IP_ADDR" ]; then log_error "Invalid MGMT_IP"; exit 1; fi
USER_WAN_IP_ADDR=$(echo "$USER_WAN_IP" | cut -d'/' -f1); if [ -z "$USER_WAN_IP_ADDR" ]; then log_error "Invalid USER_WAN_IP"; exit 1; fi
TAC_NUM=$(printf '%d' "$TAC" 2>/dev/null); if [ -z "$TAC_NUM" ]; then log_error "Invalid TAC value '$TAC'"; exit 1; fi

# --- Interface Name Resolution ---
EFFECTIVE_USER_WAN_IF="$USER_WAN_INTERFACE"
if [[ "$USER_WAN_INTERFACE" == "dynamic" ]]; then
    log_info "Resolving USER_WAN_INTERFACE from USER_WAN_IP ($USER_WAN_IP_ADDR)..."
    RESOLVED_IF=$(ip -4 -o addr show | awk -v ip="$USER_WAN_IP_ADDR" '$4 ~ ("^" ip "/") {print $2; exit}')
    if [ -n "$RESOLVED_IF" ]; then
        if [[ "$RESOLVED_IF" == "lo" ]]; then log_error "Resolved interface for IP $USER_WAN_IP_ADDR is 'lo'. Check IP assignment."; exit 1; fi
        log_info "Resolved USER_WAN_INTERFACE to: $RESOLVED_IF"
        EFFECTIVE_USER_WAN_IF="$RESOLVED_IF"
    else
        log_error "Could not resolve interface name for IP $USER_WAN_IP_ADDR using 'ip addr show'."; exit 1;
    fi
else log_info "Using configured USER_WAN_INTERFACE: $USER_WAN_INTERFACE"; fi

log_info "Target Management IP: $MGMT_IP_ADDR"
log_info "Effective User WAN Interface: $EFFECTIVE_USER_WAN_IF"
log_info "Target PLMN: $MCC/$MNC, TAC: $TAC_NUM"


# --- OS Detection and Repository Setup ---
log_step "Detecting OS and Setting up Open5GS Repository"
if [ -f /etc/os-release ]; then source /etc/os-release; if [[ "$ID" == "ubuntu" ]]; then log_info "Detected Ubuntu ($VERSION_ID). Adding Open5GS PPA"; apt-get update -y >/dev/null 2>&1 || log_warn "..."; apt-get install -y software-properties-common || exit 1; add-apt-repository -y ppa:open5gs/latest || exit 1; elif [[ "$ID" == "debian" ]]; then log_info "Detected Debian ($VERSION_ID). Adding Open5GS repository"; apt-get update -y >/dev/null 2>&1 || log_warn "..."; apt-get install -y wget gnupg || exit 1; rm -f /etc/apt/keyrings/open5gs.gpg; mkdir -p /etc/apt/keyrings; wget -qO - https://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/Debian_12/Release.key | gpg --dearmor -o /etc/apt/keyrings/open5gs.gpg || exit 1; echo "deb [signed-by=/etc/apt/keyrings/open5gs.gpg] http://download.opensuse.org/repositories/home:/acetcom:/open5gs:/latest/Debian_12/ ./" > /etc/apt/sources.list.d/open5gs.list; else log_error "Unsupported OS: $ID"; exit 1; fi; else log_error "Could not determine OS type"; exit 1; fi; log_info "Repository setup complete."

# --- Package Installation ---
log_step "Updating Package Lists"; apt-get update || { log_error "Failed to update package lists"; exit 1; }; log_info "Package lists updated."
log_step "Installing Open5GS Packages"; apt-get install -y open5gs || { log_error "Failed to install Open5GS meta-package"; exit 1; }; log_info "Open5GS packages installed."
log_step "Installing Required Utilities (yq, iptables, persistence tools)"; apt-get install -y yq iptables iptables-persistent || { log_error "Failed to install required utilities"; exit 1; }; if ! command -v yq &> /dev/null; then log_error "yq command still not found."; exit 1; fi; if ! command -v iptables &> /dev/null; then log_error "iptables command still not found."; exit 1; fi; log_info "Required utilities are installed."

# --- Open5GS Configuration ---
log_step "Applying Open5GS Configuration via yq"

MME_CONF="$OPEN5GS_CONFIG_DIR/mme.yaml"
SGWU_CONF="$OPEN5GS_CONFIG_DIR/sgwu.yaml"
SMF_CONF="$OPEN5GS_CONFIG_DIR/smf.yaml"
UPF_CONF="$OPEN5GS_CONFIG_DIR/upf.yaml"

log_info "Backing up existing configuration files (*.yaml -> *.yaml.bak)"
for conf_file in "$MME_CONF" "$SGWU_CONF" "$SMF_CONF" "$UPF_CONF"; do if [ -f "$conf_file" ]; then cp "$conf_file" "${conf_file}.bak" || { log_error "Failed to backup $conf_file"; exit 1; }; else log_warn "File $conf_file not found, skipping backup."; fi; done
log_info "Backups complete."

log_info "Modifying YAML configuration files..."

# Configure MME
if [ -f "$MME_CONF" ]; then
    log_info "Configuring MME: PLMN, TAC, S1AP Interface"
    yq -i -y --arg mcc_val "$MCC" '.mme.plmn_id[0].mcc = $mcc_val' "$MME_CONF" || log_warn "MME MCC update failed"
    yq -i -y --arg mnc_val "$MNC" '.mme.plmn_id[0].mnc = $mnc_val' "$MME_CONF" || log_warn "MME MNC update failed"
    yq -i -y --argjson tac_val "$TAC_NUM" '.mme.tai_support[0].tac = $tac_val' "$MME_CONF" || log_warn "MME TAC update failed"
    yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.mme.s1ap.server[0].address = $mgmt_ip' "$MME_CONF" || log_warn "MME S1AP address update failed"
fi

# Configure SGW-U
if [ -f "$SGWU_CONF" ]; then
    log_info "Configuring SGW-U: GTP-U Interface"
    if ! yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.sgwu.gtpu.server[0].address = $mgmt_ip' "$SGWU_CONF"; then
        yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.gtpu.server[0].address = $mgmt_ip' "$SGWU_CONF" || log_warn "SGW-U GTP-U address update failed (both paths)"
    fi
fi

# Configure SMF
if [ -f "$SMF_CONF" ]; then
    log_info "Configuring SMF: GTP-C Interface, UE Subnet (Session), PFCP"

    yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.smf.gtpc.server[0].address = $mgmt_ip' "$SMF_CONF" || log_warn "SMF GTP-C address update failed (path: .smf.gtpc...)"

    # --- *** UPDATED: Target .smf.session[0].subnet instead of dnn_list *** ---
    log_info "Setting SMF Session Subnet to $UE_SUBNET"
    yq -i -y --arg ue_sub "$UE_SUBNET" '.smf.session[0].subnet = $ue_sub' "$SMF_CONF" || \
        log_warn "SMF Session Subnet update failed. Check '.smf.session[0].subnet' path in $SMF_CONF."

    # Internal PFCP Config
    log_info "Setting SMF PFCP server address to $SMF_PFCP_IP"
    yq -i -y --arg ip "$SMF_PFCP_IP" '.smf.pfcp.server[0].address = $ip' "$SMF_CONF" || \
       yq -i -y --arg ip "$SMF_PFCP_IP" '.pfcp.server[0].address = $ip' "$SMF_CONF" || log_warn "SMF PFCP server address update failed"

     log_info "Setting SMF UPF Node address to $UPF_PFCP_IP"
     yq -i -y --arg ip "$UPF_PFCP_IP" '.smf.upf.node[0].address = $ip' "$SMF_CONF" || log_warn "SMF UPF node address update failed (assuming node[0])"
fi

# Configure UPF
if [ -f "$UPF_CONF" ]; then
    log_info "Configuring UPF: GTP-U Interface, N6 Device, UE Subnet, PFCP"
    if ! yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.upf.gtpu.server[0].address = $mgmt_ip' "$UPF_CONF"; then
         yq -i -y --arg mgmt_ip "$MGMT_IP_ADDR" '.gtpu.server[0].address = $mgmt_ip' "$UPF_CONF" || log_warn "UPF GTP-U address update failed"
    fi
    if ! yq -i -y --arg wan_if "$EFFECTIVE_USER_WAN_IF" '.upf.pdn[0].dev = $wan_if' "$UPF_CONF"; then
         yq -i -y --arg wan_if "$EFFECTIVE_USER_WAN_IF" '.pdn[0].dev = $wan_if' "$UPF_CONF" || log_warn "UPF N6 device update failed"
    fi
    # *** UPDATED: Target .upf.session[0].subnet similar to SMF? Check UPF structure ***
    if ! yq -i -y --arg ue_sub "$UE_SUBNET" '.upf.ue_subnet = $ue_sub' "$UPF_CONF"; then
        yq -i -y --arg ue_sub "$UE_SUBNET" '.ue_subnet = $ue_sub' "$UPF_CONF" || log_warn "UPF UE subnet update failed (tried .upf.ue_subnet and .ue_subnet)"
    fi

    log_info "Setting UPF PFCP server address to $UPF_PFCP_IP"
    yq -i -y --arg ip "$UPF_PFCP_IP" '.upf.pfcp.server[0].address = $ip' "$UPF_CONF" || \
       yq -i -y --arg ip "$UPF_PFCP_IP" '.pfcp.server[0].address = $ip' "$UPF_CONF" || log_warn "UPF PFCP server address update failed"
fi

log_info "YAML configuration modifications attempted."

# --- Configure Networking ---
log_step "Configuring System Networking"; log_info "Enabling IPv4 Forwarding"
if sysctl net.ipv4.ip_forward | grep -q "net.ipv4.ip_forward = 1"; then log_info "IP forwarding is already enabled."; else log_info "Enabling IP forwarding now..."; sysctl -w net.ipv4.ip_forward=1 || log_warn "..."; if grep -qE "^#?net.ipv4.ip_forward\s*=" /etc/sysctl.conf; then sed -i -E 's/^#?net.ipv4.ip_forward\s*=\s*[01]/net.ipv4.ip_forward=1/' /etc/sysctl.conf; else echo -e "\nnet.ipv4.ip_forward=1" >> /etc/sysctl.conf; fi; log_info "IP forwarding persistent."; sysctl -p > /dev/null; fi
log_info "Setting up NAT Rule for UE Subnet $UE_SUBNET via $EFFECTIVE_USER_WAN_IF"
if ! iptables -t nat -C POSTROUTING -s "$UE_SUBNET" -o "$EFFECTIVE_USER_WAN_IF" -j MASQUERADE &> /dev/null; then log_info "Adding iptables MASQUERADE rule..."; iptables -t nat -A POSTROUTING -s "$UE_SUBNET" -o "$EFFECTIVE_USER_WAN_IF" -j MASQUERADE || { log_error "..."; exit 1; }; log_info "Attempting to persist iptables rules..."; if command -v netfilter-persistent > /dev/null; then if systemctl is-active --quiet netfilter-persistent; then netfilter-persistent save || log_warn "..."; log_info "Used netfilter-persistent save."; else log_warn "netfilter-persistent inactive..."; iptables-save > /etc/iptables/rules.v4 || log_warn "..."; ip6tables-save > /etc/iptables/rules.v6 || log_warn "..."; systemctl enable netfilter-persistent &>/dev/null; systemctl start netfilter-persistent &>/dev/null; fi; else log_warn "netfilter-persistent not found."; fi; else log_info "iptables MASQUERADE rule already exists."; fi
log_info "Networking configuration complete."

# --- Check Dependencies ---
log_step "Checking Dependencies"; MONGO_SERVICE_NAME=""; if systemctl list-units --full -all | grep -q "mongod.service"; then MONGO_SERVICE_NAME="mongod"; fi; if systemctl list-units --full -all | grep -q "mongodb.service"; then MONGO_SERVICE_NAME="mongodb"; fi
if [ -n "$MONGO_SERVICE_NAME" ]; then if ! systemctl is-active --quiet "$MONGO_SERVICE_NAME"; then log_error "MongoDB service ($MONGO_SERVICE_NAME) is installed but not running."; log_error "... Please start MongoDB manually ..."; exit 1; else log_info "MongoDB service ($MONGO_SERVICE_NAME) is running."; fi; else log_warn "MongoDB service not found."; fi

# --- Restart Open5GS Services ---
log_step "Restarting Open5GS Services"; CORE_SERVICES=( open5gs-nrfd open5gs-ausfd open5gs-udmd open5gs-udrd open5gs-hssd open5gs-pcrfd open5gs-mmed open5gs-sgwcd open5gs-amfd open5gs-smfd open5gs-sgwud open5gs-upfd ); RESTART_FAILED=0; FAILED_SERVICES=(); for service in "${CORE_SERVICES[@]}"; do if systemctl list-units --full -all | grep -q "$service.service"; then log_info "Restarting $service..."; systemctl restart "$service" || { log_warn "..."; RESTART_FAILED=1; FAILED_SERVICES+=($service); }; sleep 0.5; else log_info "Service $service not found..."; fi; done; log_info "Core service restart attempted."; if [ $RESTART_FAILED -ne 0 ]; then log_warn "One or more services failed to restart."; fi

# --- Completion ---
log_step "Configuration Complete"
echo -e "${GREEN}==============================================================="
echo -e " Open5GS Installation and Configuration Summary"
echo -e "===============================================================${NC}"
echo -e "* Installation & Configuration Attempt Summary:"
echo -e "  - YAML Configs (PLMN/TAC/Network/PFCP/Session): Applied (Check warnings)"
echo -e ""
echo -e "${YELLOW}IMPORTANT NEXT STEPS & WARNINGS:${NC}"
echo -e "* Verify configuration file changes (originals *.bak)."
echo -e "* ${YELLOW}Note:${NC} UE Subnet configuration was applied to '.smf.session[0].subnet'."
echo -e "* Check Open5GS service status: ${GREEN}sudo systemctl status 'open5gs-*'${NC}"
if [ ${#FAILED_SERVICES[@]} -ne 0 ]; then echo -e "* ${RED}Check failed services:${NC} ${FAILED_SERVICES[*]} using ${GREEN}sudo journalctl -xeu <service_name>${NC}"; fi
echo -e "* Monitor logs: ${GREEN}tail -f /var/log/open5gs/*.log${NC}"
echo -e "* Check eNodeB/gNodeB config."
echo -e "* Test UE connectivity."
echo -e "${GREEN}===============================================================${NC}"

log_info "Script finished."
exit 0