#!/bin/sh
# netadmin SAFE Profile
# Minimal rules: only essential firewall, no throttling bypass

set -u

# This is sourced from apply_rules()
# Don't set -e here to allow partial application

log_info "Applying SAFE profile (minimal rules)"

# Clear any netadmin chains
iptables -t filter -F NETADMIN_INPUT 2>/dev/null || true
iptables -t filter -X NETADMIN_INPUT 2>/dev/null || true
iptables -t mangle -F NETADMIN_TTL_CLAMP 2>/dev/null || true
iptables -t mangle -X NETADMIN_TTL_CLAMP 2>/dev/null || true
iptables -t filter -F NETADMIN_ZAPRET 2>/dev/null || true
iptables -t filter -X NETADMIN_ZAPRET 2>/dev/null || true

log_info "SAFE profile applied"
