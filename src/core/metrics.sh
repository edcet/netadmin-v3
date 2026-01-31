#!/bin/sh
# Prometheus Metrics Exporter
# Exports netadmin state in Prometheus text format

set -u

METRICS_FILE="${METRICS_FILE:-/tmp/netadmin_metrics.txt}"
METRICS_PORT="${METRICS_PORT:-8080}"

. /jffs/scripts/netadmin/core/netadmin-lib.sh

# Metric generation functions

metric_header() {
    cat << 'EOF'
# HELP netadmin_state_current Current state machine state (0-5)
# TYPE netadmin_state_current gauge
# HELP netadmin_wan_ready WAN readiness (0=down, 1=ready)
# TYPE netadmin_wan_ready gauge
# HELP netadmin_wan_carrier Carrier status (0=down, 1=up)
# TYPE netadmin_wan_carrier gauge
# HELP netadmin_wan_ip_acquired IP acquisition status (0=no, 1=yes)
# TYPE netadmin_wan_ip_acquired gauge
# HELP netadmin_wan_gateway_reachable Gateway reachability (0=no, 1=yes)
# TYPE netadmin_wan_gateway_reachable gauge
# HELP netadmin_wan_tcp_health TCP health check (0=fail, 1=pass)
# TYPE netadmin_wan_tcp_health gauge
# HELP netadmin_hardware_ctf_enabled CTF acceleration (0=disabled, 1=enabled)
# TYPE netadmin_hardware_ctf_enabled gauge
# HELP netadmin_hardware_fc_enabled Flow Cache acceleration (0=disabled, 1=enabled)
# TYPE netadmin_hardware_fc_enabled gauge
# HELP netadmin_hardware_runner_enabled Runner acceleration (0=disabled, 1=enabled)
# TYPE netadmin_hardware_runner_enabled gauge
# HELP netadmin_boot_attempts Boot attempt counter
# TYPE netadmin_boot_attempts counter
# HELP netadmin_zapret_running Zapret nfqws status (0=stopped, 1=running)
# TYPE netadmin_zapret_running gauge
# HELP netadmin_uptime_seconds Netadmin uptime in seconds
# TYPE netadmin_uptime_seconds counter
EOF
}

metric_state() {
    local state
    state="$(get_current_state)"
    echo "netadmin_state_current{state=\"$(state_name "$state")\"} $state"
}

metric_wan_health() {
    # Read from health JSON if available
    if [ -f "$NETADMIN_HEALTH_JSON" ]; then
        local ready carrier ip_acquired gateway tcp_health
        
        # Parse JSON (poor man's parser - works on BusyBox)
        ready="$(grep '"ready"' "$NETADMIN_HEALTH_JSON" | grep -oE '[0-9]+')"
        carrier="$(grep '"carrier_up"' "$NETADMIN_HEALTH_JSON" | grep -oE '[0-9]+')"
        ip_acquired="$(grep '"ip_acquired"' "$NETADMIN_HEALTH_JSON" | grep -q 'null' && echo 0 || echo 1)"
        gateway="$(grep '"gateway_reachable"' "$NETADMIN_HEALTH_JSON" | grep -oE '[0-9]+')"
        tcp_health="$(grep '"tcp_health"' "$NETADMIN_HEALTH_JSON" | grep -oE '[0-9]+')"
        
        echo "netadmin_wan_ready ${ready:-0}"
        echo "netadmin_wan_carrier ${carrier:-0}"
        echo "netadmin_wan_ip_acquired ${ip_acquired:-0}"
        echo "netadmin_wan_gateway_reachable ${gateway:-0}"
        echo "netadmin_wan_tcp_health ${tcp_health:-0}"
    else
        # Fallback: assume healthy if state is ACTIVE
        local state
        state="$(get_current_state)"
        if [ "$state" = "$STATE_ACTIVE" ]; then
            echo "netadmin_wan_ready 1"
            echo "netadmin_wan_carrier 1"
            echo "netadmin_wan_ip_acquired 1"
            echo "netadmin_wan_gateway_reachable 1"
            echo "netadmin_wan_tcp_health 1"
        else
            echo "netadmin_wan_ready 0"
            echo "netadmin_wan_carrier 0"
            echo "netadmin_wan_ip_acquired 0"
            echo "netadmin_wan_gateway_reachable 0"
            echo "netadmin_wan_tcp_health 0"
        fi
    fi
}

metric_hardware() {
    local ctf fc runner
    ctf="$(check_ctf_status)"
    fc="$(check_fc_status)"
    runner="$(check_runner_status)"
    
    echo "netadmin_hardware_ctf_enabled $ctf"
    echo "netadmin_hardware_fc_enabled $fc"
    echo "netadmin_hardware_runner_enabled $runner"
}

metric_boot_attempts() {
    local attempts
    attempts="$(get_boot_attempt)"
    echo "netadmin_boot_attempts $attempts"
}

metric_zapret() {
    # Check if zapret-manager exists
    if [ -f /jffs/scripts/netadmin/core/zapret-manager.sh ]; then
        . /jffs/scripts/netadmin/core/zapret-manager.sh
        zapret_export_metrics
    else
        echo "netadmin_zapret_running 0"
    fi
}

metric_uptime() {
    # Calculate uptime since first state file creation
    if [ -f "$NETADMIN_STATE_FILE" ]; then
        local now file_time uptime
        now="$(date +%s)"
        file_time="$(stat -c %Y "$NETADMIN_STATE_FILE" 2>/dev/null || stat -f %m "$NETADMIN_STATE_FILE" 2>/dev/null || echo "$now")"
        uptime=$((now - file_time))
        echo "netadmin_uptime_seconds $uptime"
    else
        echo "netadmin_uptime_seconds 0"
    fi
}

metric_profile() {
    local profile
    profile="$(nvram_get netadmin_mode safe)"
    
    # Encode profile as labels
    echo "netadmin_profile_safe $([ "$profile" = 'safe' ] && echo 1 || echo 0)"
    echo "netadmin_profile_verizon $([ "$profile" = 'verizon' ] && echo 1 || echo 0)"
    echo "netadmin_profile_verizon_bypass $([ "$profile" = 'verizon-bypass' ] && echo 1 || echo 0)"
}

export_metrics() {
    # Generate Prometheus metrics
    {
        metric_header
        metric_state
        metric_wan_health
        metric_hardware
        metric_boot_attempts
        metric_zapret
        metric_uptime
        metric_profile
    } > "$METRICS_FILE.tmp"
    
    # Atomic move
    mv "$METRICS_FILE.tmp" "$METRICS_FILE"
}

start_http_server() {
    # Start busybox httpd for metrics endpoint
    local httpd_pid="/var/run/netadmin_httpd.pid"
    
    # Check if already running
    if [ -f "$httpd_pid" ] && kill -0 "$(cat "$httpd_pid")" 2>/dev/null; then
        log_info "Metrics HTTP server already running on port $METRICS_PORT"
        return 0
    fi
    
    # Create metrics directory
    local metrics_dir="/tmp/netadmin_metrics"
    mkdir -p "$metrics_dir"
    
    # Create symlink for /metrics endpoint
    ln -sf "$METRICS_FILE" "$metrics_dir/metrics"
    
    # Start httpd
    if command -v httpd >/dev/null 2>&1; then
        httpd -p "$METRICS_PORT" -h "$metrics_dir" -f
        echo $! > "$httpd_pid"
        log_info "Metrics HTTP server started on port $METRICS_PORT"
        log_info "Access at: http://$(nvram get lan_ipaddr):$METRICS_PORT/metrics"
    else
        log_warn "httpd not available, metrics only accessible via file: $METRICS_FILE"
    fi
}

stop_http_server() {
    local httpd_pid="/var/run/netadmin_httpd.pid"
    
    if [ -f "$httpd_pid" ]; then
        kill "$(cat "$httpd_pid")" 2>/dev/null || true
        rm -f "$httpd_pid"
        log_info "Metrics HTTP server stopped"
    fi
}

show_metrics() {
    if [ -f "$METRICS_FILE" ]; then
        cat "$METRICS_FILE"
    else
        echo "# No metrics available yet"
        echo "# Run: netadmin metrics export"
    fi
}

case "${1:-export}" in
    export)
        export_metrics
        ;;
    
    start-http)
        export_metrics
        start_http_server
        ;;
    
    stop-http)
        stop_http_server
        ;;
    
    show)
        show_metrics
        ;;
    
    *)
        echo "Usage: $0 {export|start-http|stop-http|show}"
        exit 1
        ;;
esac
