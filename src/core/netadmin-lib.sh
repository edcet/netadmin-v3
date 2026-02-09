#!/bin/sh
# netadmin v3.0 Core Library
# State machine, hardware acceleration checks, WAN monitoring
# POSIX-compatible for ASUSWRT-Merlin

set -u

# ===== State Machine =====
NETADMIN_STATE_FILE="/tmp/netadmin_state"
NETADMIN_STATE_LOG="/tmp/netadmin_state.log"
NETADMIN_BOOT_ATTEMPTS="/tmp/netadmin_boot_attempts"
NETADMIN_HEALTH_JSON="/tmp/netadmin_health.json"

# State constants
STATE_INIT=0
STATE_WAN_WAIT=1
STATE_RULES_APPLY=2
STATE_ACTIVE=3
STATE_DEGRADED=4
STATE_SAFE=5

# State names for logging
state_name() {
    case "$1" in
        0) echo "INIT" ;;
        1) echo "WAN_WAIT" ;;
        2) echo "RULES_APPLY" ;;
        3) echo "ACTIVE" ;;
        4) echo "DEGRADED" ;;
        5) echo "SAFE" ;;
        *) echo "UNKNOWN" ;;
    esac
}

get_current_state() {
    cat "$NETADMIN_STATE_FILE" 2>/dev/null || echo "$STATE_INIT"
}

set_state() {
    local new_state="$1"
    local old_state
    old_state="$(get_current_state)"

    # Validate state transition (whitelist valid transitions)
    # Normal flow: 0-1, 1-2, 2-3, 3-4, 4-1, 4-3
    # Error recovery: 1-5, 2-5, 3-5, 4-5
    # Force safe: 0-5, 2-0, 5-1
    case "$old_state-$new_state" in
        0-1|1-2|2-3|3-4|4-1|4-3|1-5|2-5|3-5|4-5|0-5|2-0|5-1)
            echo "$new_state" > "$NETADMIN_STATE_FILE"
            _log_state_change "$old_state" "$new_state"
            logger -t netadmin "STATE: $(state_name "$old_state") → $(state_name "$new_state")"
            return 0
            ;;
        *)
            logger -t netadmin "ERROR: Invalid state transition $old_state → $new_state"
            return 1
            ;;
    esac
}

_log_state_change() {
    local old="$1" new="$2"
    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "$timestamp: $old → $new" >> "$NETADMIN_STATE_LOG"
}

# ===== Hardware Acceleration Detection =====

check_ctf_status() {
    local ctf_disable
    ctf_disable="$(nvram get ctf_disable 2>/dev/null || echo "0")"
    if [ "$ctf_disable" = "0" ]; then
        echo "1"  # CTF is ENABLED
    else
        echo "0"  # CTF is DISABLED
    fi
}

check_fc_status() {
    local fc_disable
    fc_disable="$(nvram get fc_disable 2>/dev/null || echo "0")"
    if [ "$fc_disable" = "0" ]; then
        echo "1"  # FC is ENABLED
    else
        echo "0"  # FC is DISABLED
    fi
}

check_runner_status() {
    local runner_disable_force
    runner_disable_force="$(nvram get runner_disable_force 2>/dev/null || echo "0")"
    if [ "$runner_disable_force" = "0" ]; then
        echo "1"  # Runner is ENABLED
    else
        echo "0"  # Runner is DISABLED
    fi
}

get_hardware_accel_status() {
    local ctf fc runner
    ctf="$(check_ctf_status)"
    fc="$(check_fc_status)"
    runner="$(check_runner_status)"

    # Return JSON
    cat << EOF
{"ctf_enabled": $ctf, "fc_enabled": $fc, "runner_enabled": $runner}
EOF
}

validate_hardware_for_profile() {
    local profile="$1"
    local ctf fc runner
    ctf="$(check_ctf_status)"
    fc="$(check_fc_status)"
    runner="$(check_runner_status)"

    case "$profile" in
        safe)
            # Safe mode works with any hardware config
            return 0
            ;;
        verizon)
            # TTL spoofing requires iptables mangle, needs CTF off
            if [ "$ctf" = "1" ]; then
                logger -t netadmin "WARNING: TTL spoof with CTF enabled, throughput may degrade"
                return 0  # Warn but allow
            fi
            return 0
            ;;
        verizon-bypass)
            # Zapret requires CTF, FC, Runner all disabled
            if [ "$ctf" = "1" ] || [ "$fc" = "1" ] || [ "$runner" = "1" ]; then
                logger -t netadmin "ERROR: Zapret requires CTF, FC, Runner disabled"
                logger -t netadmin "Current: CTF=$ctf FC=$fc Runner=$runner"
                return 1
            fi
            return 0
            ;;
        *)
            logger -t netadmin "ERROR: Unknown profile: $profile"
            return 1
            ;;
    esac
}

# ===== WAN Interface Detection =====

wan_if_detect() {
    # Try standard locations first
    local wan_if
    wan_if="$(nvram get wan0_ifname 2>/dev/null)"
    if [ -n "$wan_if" ] && [ -d "/sys/class/net/$wan_if" ]; then
        echo "$wan_if"
        return 0
    fi

    # Fallback to eth0
    if [ -d /sys/class/net/eth0 ]; then
        echo "eth0"
        return 0
    fi

    logger -t netadmin "ERROR: Cannot detect WAN interface"
    return 1
}

wan_carrier_up() {
    local wan_if="$1"
    local carrier

    carrier="$(cat "/sys/class/net/$wan_if/carrier" 2>/dev/null || echo "0")"
    [ "$carrier" = "1" ]
}

wan_has_ip() {
    local wan_if="$1"
    ip -4 addr show dev "$wan_if" 2>/dev/null | grep -q "inet "
}

wan_has_default_route() {
    ip -4 route show | grep -q "^default "
}

wan_gateway_reachable() {
    local wan_if="$1"
    local gateway

    gateway="$(ip -4 route show dev "$wan_if" | grep -oE 'via [^ ]*' | awk '{print $2}')"
    if [ -z "$gateway" ]; then
        gateway="$(ip -4 route show | grep '^default' | awk '{print $3}')"
    fi

    if [ -z "$gateway" ]; then
        return 1
    fi

    ping -c 1 -W 2 "$gateway" >/dev/null 2>&1
}

wan_tcp_health() {
    local target="${1:-1.1.1.1}" port="${2:-443}" timeout=3

    # Try TCP handshake using /dev/tcp if available
    if command -v timeout >/dev/null; then
        timeout "$timeout" bash -c "echo > /dev/tcp/$target/$port" 2>/dev/null
        return $?
    fi

    # Fallback: try with busybox nc (netcat)
    if command -v nc >/dev/null; then
        nc -zv -w 2 "$target" "$port" >/dev/null 2>&1
        return $?
    fi

    # If neither available, skip TCP check
    return 0
}

# ===== Health Check State Machine =====

wan_is_ready() {
    local wan_if
    wan_if="$(wan_if_detect)" || return 1

    # All checks must pass
     wan_carrier_up "$wan_if" || return 1
    wan_has_ip "$wan_if" || return 1
    wan_has_default_route || return 1
    wan_gateway_reachable "$wan_if" || return 1

    # TCP health (one of two DNS or HTTPS should work)
    wan_tcp_health "8.8.8.8" "53" || wan_tcp_health "1.1.1.1" "443" || return 1

    return 0
}

wan_export_health() {
    local wan_if
    wan_if="$(wan_if_detect)" || wan_if="unknown"

    local carrier ip default_gw gateway_ok tcp_ok ready
    carrier="$(wan_carrier_up "$wan_if" && echo 1 || echo 0)"
    ip="$(ip -4 addr show dev "$wan_if" 2>/dev/null | grep -oE 'inet [0-9.]+' | awk '{print $2}')"
    default_gw="$(wan_has_default_route && echo 1 || echo 0)"
    gateway_ok="$(wan_gateway_reachable "$wan_if" && echo 1 || echo 0)"
    tcp_ok="$(wan_tcp_health "8.8.8.8" "53" && echo 1 || echo 0)"
    ready="$(wan_is_ready && echo 1 || echo 0)"

    cat > "$NETADMIN_HEALTH_JSON" << EOF
{
  "interface": "$wan_if",
  "carrier_up": $carrier,
  "ip_acquired": "${ip:-null}",
  "default_route": $default_gw,
  "gateway_reachable": $gateway_ok,
  "tcp_health": $tcp_ok,
  "ready": $ready,
  "state": "$(state_name "$(get_current_state)")",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# ===== Boot Watchdog =====

increment_boot_attempt() {
    local current
    current="$(cat "$NETADMIN_BOOT_ATTEMPTS" 2>/dev/null || echo "0")"
    echo "$((current + 1))" > "$NETADMIN_BOOT_ATTEMPTS"
}

reset_boot_attempt() {
    echo "0" > "$NETADMIN_BOOT_ATTEMPTS"
}

get_boot_attempt() {
    cat "$NETADMIN_BOOT_ATTEMPTS" 2>/dev/null || echo "0"
}

should_fallback_safe() {
    local attempts
    attempts="$(get_boot_attempt)"
    [ "$attempts" -ge 3 ]
}

# ===== NVRAM Helpers =====

nvram_get() {
    local key="$1" default="${2:-}"
    local value
    value="$(nvram get "$key" 2>/dev/null || echo "")"
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

nvram_set() {
    local key="$1" value="$2"
    nvram set "$key=$value"
}

nvram_commit() {
    nvram commit
}

# ===== Rules Management =====

apply_rules() {
    local profile="$1"
    local result=0

    logger -t netadmin "Applying rules for profile: $profile"

    # Validate before applying
    validate_hardware_for_profile "$profile" || {
        logger -t netadmin "ERROR: Hardware validation failed for $profile"
        return 1
    }

    # Source profile script
    if [ -f "/jffs/scripts/netadmin/profiles/$profile.sh" ]; then
        # shellcheck source=/dev/null
        . "/jffs/scripts/netadmin/profiles/$profile.sh" || result=$?
    else
        logger -t netadmin "ERROR: Profile script not found: $profile"
        return 1
    fi

    return $result
}

verify_rules_active() {
    local profile="$1"
    # Check if critical rules are present in iptables
    case "$profile" in
        verizon)
            iptables -t mangle -L NETADMIN_TTL_CLAMP >/dev/null 2>&1 || return 1
            ;;
        verizon-bypass)
            iptables -t filter -L NETADMIN_ZAPRET >/dev/null 2>&1 || return 1
            ;;
    esac
    return 0
}

# ===== Logging Helpers =====

log_info() {
    local msg="$1"
    logger -t netadmin "[INFO] $msg"
}

log_warn() {
    local msg="$1"
    logger -t netadmin "[WARN] $msg"
}

log_error() {
    local msg="$1"
    logger -t netadmin "[ERROR] $msg"
}

log_debug() {
    local msg="$1"
    if [ "$(nvram_get netadmin_debug 0)" = "1" ]; then
        logger -t netadmin "[DEBUG] $msg"
    fi
}
