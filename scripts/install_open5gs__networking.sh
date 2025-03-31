#!/bin/bash

# --- Network Configuration (NAT & IP Forwarding) ---
log_step "Configuring Network Settings (IP Forwarding and NAT)"
log_info "Enabling IP forwarding..."
SYSCTL_CONF="/etc/sysctl.conf"
SYSCTL_D_CONF="/etc/sysctl.d/99-open5gs-forward.conf"
echo "net.ipv4.ip_forward=1" > "$SYSCTL_D_CONF" || { log_error "Failed to write sysctl config to $SYSCTL_D_CONF"; exit 1; }
log_info "Created/Updated $SYSCTL_D_CONF with net.ipv4.ip_forward=1"
if grep -q "net.ipv4.ip_forward" "$SYSCTL_CONF"; then
    log_info "Removing net.ipv4.ip_forward entry from main $SYSCTL_CONF (managed in .d file now)."
    sed -i '/^net.ipv4.ip_forward/d' "$SYSCTL_CONF"
    sed -i '/^#net.ipv4.ip_forward/d' "$SYSCTL_CONF"
fi
if command -v systemctl &> /dev/null && systemctl is-active systemd-sysctl.service &> /dev/null; then
  systemctl restart systemd-sysctl.service || log_warn "systemd-sysctl restart failed, changes might require reboot"
else
  sysctl -p "$SYSCTL_D_CONF" || sysctl -p || log_warn "sysctl -p failed, changes might require reboot"
fi
log_info "Configuring NAT rules for UE subnet $UE_SUBNET via $EFFECTIVE_USER_WAN_IF..."
IPTABLES_RULES_FILE="/etc/iptables/rules.v4"
IP6TABLES_RULES_FILE="/etc/iptables/rules.v6"
mkdir -p /etc/iptables
log_warn "Flushing existing NAT POSTROUTING and all FORWARD rules before applying new ones."
iptables -t nat -F POSTROUTING
iptables -F FORWARD
if ! iptables -t nat -C POSTROUTING -s "$UE_SUBNET" -o "$EFFECTIVE_USER_WAN_IF" -j MASQUERADE &> /dev/null; then
    iptables -t nat -A POSTROUTING -s "$UE_SUBNET" -o "$EFFECTIVE_USER_WAN_IF" -j MASQUERADE || { log_error "Failed to add iptables MASQUERADE rule"; exit 1; }
    log_info "Added MASQUERADE rule."
else
    log_info "MASQUERADE rule already exists."
fi
FORWARD_RULE_1="-s $UE_SUBNET -o $EFFECTIVE_USER_WAN_IF -j ACCEPT"
FORWARD_RULE_2="-d $UE_SUBNET -i $EFFECTIVE_USER_WAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT"
if ! iptables -C FORWARD $FORWARD_RULE_1 &> /dev/null; then
    iptables -A FORWARD $FORWARD_RULE_1 || { log_error "Failed to add FORWARD rule (UE to WAN)"; exit 1; }
    log_info "Added FORWARD rule (UE to WAN)."
else
     log_info "FORWARD rule (UE to WAN) already exists."
fi
if ! iptables -C FORWARD $FORWARD_RULE_2 &> /dev/null; then
    iptables -A FORWARD $FORWARD_RULE_2 || { log_error "Failed to add FORWARD rule (WAN to UE established)"; exit 1; }
    log_info "Added FORWARD rule (WAN to UE established)."
else
    log_info "FORWARD rule (WAN to UE established) already exists."
fi
log_info "Saving iptables rules..."
if ! netfilter-persistent save > /dev/null 2>&1; then
    log_warn "netfilter-persistent save command failed. Attempting fallback using iptables-save..."
    iptables-save > "$IPTABLES_RULES_FILE" || log_error "Fallback iptables-save failed. Rules may not persist reboot."
    [ -f "$IP6TABLES_RULES_FILE" ] || touch "$IP6TABLES_RULES_FILE"
else
     log_info "iptables rules saved via netfilter-persistent."
fi
log_info "Network configuration finished." 