#!/bin/bash

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${YELLOW}>>> Step: $1...${NC}"; }

# --- Check Prerequisites ---
log_step "Checking Prerequisites"
if [ "$EUID" -ne 0 ]; then log_error "Please run as root (use sudo)"; exit 1; fi
if [ ! -f "$INSTALL_CONF" ]; then log_error "Configuration file not found: $INSTALL_CONF. Please create it."; exit 1; fi
log_info "Prerequisites met."

# --- Load Configuration ---
log_step "Loading Configuration from $INSTALL_CONF"
DEFAULT_UE_SUBNET="10.45.0.0/16"
DEFAULT_DNN="internet" # Default Data Network Name
MGMT_INTERFACE="dynamic"
USER_WAN_INTERFACE="dynamic"
MCC=""
MNC=""
TAC=""
MGMT_IP=""
USER_WAN_IP=""
UE_SUBNET=""
DNN=""
source "$INSTALL_CONF"
UE_SUBNET="${UE_SUBNET:-$DEFAULT_UE_SUBNET}"
DNN="${DNN:-$DEFAULT_DNN}" # Use DNN from conf or default
log_info "Configuration loaded."
log_info "Using UE Subnet: $UE_SUBNET"
log_info "Using DNN: $DNN"

# --- Validate Core Configuration Variables ---
log_step "Validating Core Configuration"
if [ -z "$MGMT_IP" ] || [ -z "$USER_WAN_INTERFACE" ] || \
   [ -z "$MCC" ] || [ -z "$MNC" ] || [ -z "$TAC" ] || [ -z "$USER_WAN_IP" ] ; then
    log_error "Required variable missing in $INSTALL_CONF (Need MGMT_IP, USER_WAN_INTERFACE, USER_WAN_IP, MCC, MNC, TAC)"
    exit 1
fi
MGMT_IP_ADDR=$(echo "$MGMT_IP" | cut -d'/' -f1)
if ! [[ "$MGMT_IP_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid MGMT_IP format: $MGMT_IP. Should be an IP address (CIDR optional)."
    exit 1
fi
USER_WAN_IP_ADDR=$(echo "$USER_WAN_IP" | cut -d'/' -f1)
if ! [[ "$USER_WAN_IP_ADDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid USER_WAN_IP format: $USER_WAN_IP. Should be an IP address (CIDR optional)."
    exit 1
fi
TAC_NUM=$(printf '%d' "$TAC" 2>/dev/null)
if [ -z "$TAC_NUM" ] || [ "$TAC_NUM" -lt 0 ] || [ "$TAC_NUM" -gt 16777215 ]; then # TAC is 3 octets (24 bits)
    log_error "Invalid TAC value '$TAC'. Must be a number between 0 and 16777215."
    exit 1
fi
if ! [[ "$MCC" =~ ^[0-9]{3}$ ]]; then log_error "Invalid MCC format '$MCC'. Must be 3 digits."; exit 1; fi
if ! [[ "$MNC" =~ ^[0-9]{2,3}$ ]]; then log_error "Invalid MNC format '$MNC'. Must be 2 or 3 digits."; exit 1; fi

# --- Interface Name Resolution ---
EFFECTIVE_USER_WAN_IF="$USER_WAN_INTERFACE"
if [[ "$MGMT_INTERFACE" == "dynamic" ]]; then
    log_info "Resolving MGMT_INTERFACE from MGMT_IP ($MGMT_IP_ADDR)..."
    RESOLVED_MGMT_IF=$(ip -4 -o addr show | awk -v ip="$MGMT_IP_ADDR" '$4 ~ ("^" ip "/") {print $2; exit}')
    if [ -n "$RESOLVED_MGMT_IF" ]; then
        if [[ "$RESOLVED_MGMT_IF" == "lo" ]]; then log_warn "Resolved management interface for IP $MGMT_IP_ADDR is 'lo'. This might be okay if intended."; fi
        log_info "Resolved MGMT_INTERFACE to: $RESOLVED_MGMT_IF (Note: IP $MGMT_IP_ADDR will be used for binding)"
    else
         log_warn "Could not resolve interface name for management IP $MGMT_IP_ADDR using 'ip addr show'."
    fi
else
    log_info "Configured MGMT_INTERFACE name: $MGMT_INTERFACE (Note: IP $MGMT_IP_ADDR will be used for binding)"
fi
if [[ "$USER_WAN_INTERFACE" == "dynamic" ]]; then
    log_info "Resolving USER_WAN_INTERFACE from USER_WAN_IP ($USER_WAN_IP_ADDR)..."
    RESOLVED_IF=$(ip -4 -o addr show | awk -v ip="$USER_WAN_IP_ADDR" '$4 ~ ("^" ip "/") {print $2; exit}')
    if [ -n "$RESOLVED_IF" ]; then
        if [[ "$RESOLVED_IF" == "lo" ]]; then log_error "Resolved user WAN interface for IP $USER_WAN_IP_ADDR is 'lo'. Check IP assignment."; exit 1; fi
        log_info "Resolved USER_WAN_INTERFACE to: $RESOLVED_IF"
        EFFECTIVE_USER_WAN_IF="$RESOLVED_IF"
    else
        log_error "Could not resolve interface name for user WAN IP $USER_WAN_IP_ADDR using 'ip addr show'. Cannot proceed with NAT/UPF setup."
        exit 1
    fi
else
    log_info "Using configured USER_WAN_INTERFACE: $USER_WAN_INTERFACE"
fi
log_info "Target Management IP (for Core Bindings): $MGMT_IP_ADDR"
log_info "Effective User WAN Interface (for NAT/SGi): $EFFECTIVE_USER_WAN_IF" 
log_info "Target PLMN: $MCC/$MNC, TAC: $TAC_NUM"