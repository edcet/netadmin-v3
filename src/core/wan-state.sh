#!/bin/sh
# WAN State Health Check
# Called periodically to validate WAN connectivity

set -u

. /jffs/scripts/netadmin/core/netadmin-lib.sh

main() {
    local wan_if
    wan_if="$(wan_if_detect)" || {
        log_error "Cannot detect WAN interface"
        exit 1
    }
    
    # Export current health to JSON
    wan_export_health
    
    # Check if WAN is ready
    if ! wan_is_ready; then
        local current_state
        current_state="$(get_current_state)"
        
        # If we were active, degrade
        if [ "$current_state" = "$STATE_ACTIVE" ]; then
            set_state "$STATE_DEGRADED"
            log_warn "WAN degraded, moved to DEGRADED state"
        fi
    else
        local current_state
        current_state="$(get_current_state)"
        
        # If degraded, recover
        if [ "$current_state" = "$STATE_DEGRADED" ]; then
            set_state "$STATE_ACTIVE"
            log_info "WAN recovered, moved to ACTIVE state"
        fi
    fi
    
    # Output health for queries
    if [ "${1:-}" = "--json" ]; then
        cat "$NETADMIN_HEALTH_JSON"
    fi
}

main "$@"
