#!/bin/sh
# Verizon Bypass Profile (Zapret DPI Bypass)
# Uses nfqws to bypass Verizon's DPI throttling
# WARNING: Significant performance impact (~90% throughput reduction)

set -u

. /jffs/scripts/netadmin/core/netadmin-lib.sh
. /jffs/scripts/netadmin/core/zapret-manager.sh

log_info "Applying VERIZON-BYPASS profile (Zapret DPI bypass)"

# 1. Hardware acceleration MUST be disabled for NFQUEUE
log_info "Disabling hardware acceleration (required for NFQUEUE)..."
nvram set ctf_disable=1
nvram set fc_disable=1
nvram set runner_disable_force=1
nvram commit

# Reload acceleration settings
if command -v fc >/dev/null 2>&1; then
    fc disable 2>/dev/null || true
fi

# 2. Create netadmin chains
log_info "Creating netadmin iptables chains..."

# Mangle table for NFQUEUE
iptables -t mangle -N NETADMIN_ZAPRET 2>/dev/null || true
iptables -t mangle -F NETADMIN_ZAPRET

# 3. Start zapret service
log_info "Starting zapret DPI bypass..."
if zapret_start; then
    log_info "Zapret started successfully"
else
    log_error "Failed to start zapret"
    log_error "Falling back to safe profile"
    # Fallback to safe
    . /jffs/scripts/netadmin/profiles/safe.sh
    return 1
fi

# 4. Verify rules applied
if zapret_verify; then
    log_info "VERIZON-BYPASS profile applied successfully"
    log_warn "Performance impact: ~90% throughput reduction expected"
    log_info "Monitor with: netadmin show-hardware"
else
    log_error "Zapret verification failed"
    return 1
fi

return 0
