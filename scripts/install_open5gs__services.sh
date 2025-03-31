#!/bin/bash

# --- Service Management ---
log_step "Restarting and Enabling Open5GS Services"
OPEN5GS_SERVICES=(
    open5gs-nrfd open5gs-udrd open5gs-hssd open5gs-ausfd open5gs-udmd
    open5gs-pcfd open5gs-nssfd open5gs-bsfd open5gs-amfd open5gs-smfd
    open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-upfd
)
for service in "${OPEN5GS_SERVICES[@]}"; do
    if systemctl list-unit-files --type=service | grep -q "^${service}.service"; then
        log_info "Restarting and enabling $service..."
        systemctl stop "$service" 2>/dev/null
        systemctl restart "$service" || log_warn "Failed to restart $service. Check config and logs."
        systemctl enable "$service" || log_warn "Failed to enable $service"
        sleep 1
        if ! systemctl is-active --quiet "$service"; then
            log_warn "$service did not start cleanly after restart. Check logs: journalctl -u $service"
        fi
    else
      if [[ "$service" != "open5gs-bsfd" ]]; then
         log_warn "Service $service not found, skipping. (This might be okay if component is unused)"
      fi
    fi
done
log_info "Open5GS services restart and enable process complete." 