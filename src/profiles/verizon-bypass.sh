#!/bin/sh
# netadmin VERIZON-BYPASS Profile
# Full DPI bypass using zapret (NFQUEUE)

set -u

log_warn "Applying VERIZON-BYPASS profile (DPI bypass)"
log_warn "WARNING: Throughput will reduce to ~200 Mbps due to NFQUEUE bottleneck"
log_warn "See PERFORMANCE.md for details"

# Disable ALL hardware acceleration
log_info "Disabling hardware acceleration (CTF, FC, Runner)"
nvram set ctf_disable=1
nvram set fc_disable=1
nvram set runner_disable_force=1
nvram commit

# Apply TTL spoofing first
log_info "Enabling TTL spoofing layer"
iptables -t mangle -N NETADMIN_TTL_CLAMP 2>/dev/null || true
iptables -t mangle -A NETADMIN_TTL_CLAMP -j TTL --ttl-set 65
iptables -t mangle -I FORWARD -j NETADMIN_TTL_CLAMP 2>/dev/null || true

# Create zapret chain
iptables -t filter -N NETADMIN_ZAPRET 2>/dev/null || true

# Mark packets for NFQUEUE (zapret will intercept)
iptables -t mangle -N NETADMIN_MARK_DPI 2>/dev/null || true
iptables -t mangle -A NETADMIN_MARK_DPI -j MARK --set-mark 1
iptables -t mangle -I FORWARD -j NETADMIN_MARK_DPI 2>/dev/null || true

# Start zapret daemon if not running
if ! pgrep -f nfqws >/dev/null 2>&1; then
    log_info "Starting zapret daemon (nfqws)"
    # Assuming zapret is installed at /opt/zapret or /jffs/zapret
    if [ -x /opt/zapret/nfqws ]; then
        /opt/zapret/nfqws --dpi-desync=ipv4,ssl --dpi-desync-split=2 --dpi-desync-msfix=1 -q 1 &
    elif [ -x /jffs/zapret/nfqws ]; then
        /jffs/zapret/nfqws --dpi-desync=ipv4,ssl --dpi-desync-split=2 --dpi-desync-msfix=1 -q 1 &
    else
        log_error "zapret not found at /opt/zapret or /jffs/zapret"
        log_error "Please install zapret first"
        return 1
    fi
fi

log_info "VERIZON-BYPASS profile applied"
