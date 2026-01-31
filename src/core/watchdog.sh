#!/bin/sh
# Boot Watchdog and State Machine Watchdog
# Runs in background from services-start
# Prevents boot loops and ensures state machine consistency

set -u

. /jffs/scripts/netadmin/core/netadmin-lib.sh

# Configuration
WATCHDOG_INTERVAL=30      # Check every 30 seconds
STATE_TIMEOUT=60          # Wait max 60s in WAN_WAIT state
HEALTH_CHECK_INTERVAL=60  # Health check every 60 seconds

# Store PID for cleanup
echo $$ > /tmp/netadmin_watchdog.pid

# Trap signals for graceful shutdown
trap 'cleanup' TERM INT EXIT

cleanup() {
    log_info "Watchdog shutting down"
    rm -f /tmp/netadmin_watchdog.pid
    exit 0
}

# Boot watchdog: prevent infinite boot loops
boot_watchdog() {
    local attempts
    attempts="$(get_boot_attempt)"
    
    if should_fallback_safe; then
        log_error "Boot failures detected ($attempts attempts), activating SAFE profile"
        apply_rules "safe"
        reset_boot_attempt
        set_state "$STATE_SAFE"
        nvram_set "netadmin_mode" "safe"
        nvram_commit
        exit 0
    fi
    
    # Arm watchdog: if system survives this boot, counter will be reset
    increment_boot_attempt
}

# State machine watchdog: enforce timeouts and consistency
state_machine_watchdog() {
    while true; do
        local current_state state_age timestamp
        current_state="$(get_current_state)"
        timestamp="$(stat -c %Y "$NETADMIN_STATE_FILE" 2>/dev/null || echo 0)"
        state_age=$(($(date +%s) - timestamp))
        
        case "$current_state" in
            $STATE_WAN_WAIT)
                # Timeout after 60s waiting for IP
                if [ "$state_age" -gt "$STATE_TIMEOUT" ]; then
                    log_warn "WAN_WAIT timeout ($state_age > $STATE_TIMEOUT), reverting to SAFE"
                    apply_rules "safe"
                    set_state "$STATE_SAFE"
                fi
                ;;
            
            $STATE_ACTIVE)
                # Verify rules are still present
                local current_profile
                current_profile="$(nvram_get netadmin_mode safe)"
                if ! verify_rules_active "$current_profile"; then
                    log_error "Rules disappeared, re-applying $current_profile"
                    apply_rules "$current_profile"
                fi
                ;;
        esac
        
        sleep "$WATCHDOG_INTERVAL"
    done
}

# Health check watchdog: periodic validation
health_check_watchdog() {
    while true; do
        # Run health check
        /jffs/scripts/netadmin/core/wan-state.sh >/dev/null 2>&1
        
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

main() {
    log_info "Starting netadmin watchdog"
    
    # Boot watchdog runs once
    boot_watchdog
    
    # Start background watchdogs
    state_machine_watchdog &
    STATE_WATCHDOG_PID=$!
    
    health_check_watchdog &
    HEALTH_WATCHDOG_PID=$!
    
    # Keep main process alive
    wait
}

main
