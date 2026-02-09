#!/bin/sh
# netadmin VERIZON Profile
# TTL spoofing for throttling bypass

set -u

log_info "Applying VERIZON profile (TTL spoofing)"

# Disable CTF if it's enabled (required for iptables mangle)
if [ "$(check_ctf_status)" = "1" ]; then
    log_warn "Disabling CTF for TTL spoofing"
    nvram set ctf_disable=1
    nvram set fc_disable=1
    nvram commit
fi

# Create TTL clamping chain
iptables -t mangle -N NETADMIN_TTL_CLAMP 2>/dev/null || true

# Clamp outgoing TTL to 65 (prevents bypass detection)
iptables -t mangle -A NETADMIN_TTL_CLAMP -j TTL --ttl-set 65

# Apply to all outgoing traffic
iptables -t mangle -I FORWARD -j NETADMIN_TTL_CLAMP 2>/dev/null || true
iptables -t mangle -I OUTPUT -j NETADMIN_TTL_CLAMP 2>/dev/null || true

log_info "VERIZON profile applied"
