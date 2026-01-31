#!/bin/sh
# Zapret Service Manager
# Manages nfqws lifecycle for DPI bypass

set -u

NFQWS_BIN="${NFQWS_BIN:-/jffs/bin/nfqws}"
NFQWS_PID="/var/run/nfqws.pid"
ZAPRET_DIR="${ZAPRET_DIR:-/jffs/zapret}"
NFQWS_LOG="/tmp/nfqws.log"

# Default nfqws parameters (optimized for Verizon)
NFQWS_PARAMS="\
    --qnum=200 \
    --daemon \
    --pidfile=$NFQWS_PID \
    --disorder \
    --disorder-fake-packets=1 \
    --split-http-req=method \
    --split-pos=2 \
    --split-tls=sni \
    --oob"

. /jffs/scripts/netadmin/core/netadmin-lib.sh

zapret_is_running() {
    if [ -f "$NFQWS_PID" ]; then
        local pid
        pid="$(cat "$NFQWS_PID")"
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        else
            # Stale PID file
            rm -f "$NFQWS_PID"
            return 1
        fi
    fi
    
    # Check by process name as backup
    if pgrep -x nfqws >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

zapret_start() {
    if zapret_is_running; then
        log_warn "nfqws already running"
        return 0
    fi
    
    if [ ! -x "$NFQWS_BIN" ]; then
        log_error "nfqws not found: $NFQWS_BIN"
        log_error "Run: /jffs/scripts/netadmin/install/zapret-setup.sh"
        return 1
    fi
    
    log_info "Starting nfqws..."
    
    # Create NFQUEUE rule
    iptables -t mangle -I FORWARD -p tcp --dport 80 -j NFQUEUE --queue-num 200
    iptables -t mangle -I FORWARD -p tcp --dport 443 -j NFQUEUE --queue-num 200
    
    # Start nfqws
    $NFQWS_BIN $NFQWS_PARAMS > "$NFQWS_LOG" 2>&1
    
    # Wait for startup
    sleep 2
    
    if zapret_is_running; then
        log_info "nfqws started (PID $(cat "$NFQWS_PID"))"
        return 0
    else
        log_error "nfqws failed to start"
        log_error "Check log: $NFQWS_LOG"
        return 1
    fi
}

zapret_stop() {
    if ! zapret_is_running; then
        log_info "nfqws not running"
        return 0
    fi
    
    log_info "Stopping nfqws..."
    
    # Remove NFQUEUE rules
    iptables -t mangle -D FORWARD -p tcp --dport 80 -j NFQUEUE --queue-num 200 2>/dev/null || true
    iptables -t mangle -D FORWARD -p tcp --dport 443 -j NFQUEUE --queue-num 200 2>/dev/null || true
    
    # Kill process
    if [ -f "$NFQWS_PID" ]; then
        local pid
        pid="$(cat "$NFQWS_PID")"
        kill "$pid" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local timeout=5
        while [ $timeout -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            timeout=$((timeout - 1))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        
        rm -f "$NFQWS_PID"
    fi
    
    # Cleanup any remaining nfqws processes
    pkill -9 nfqws 2>/dev/null || true
    
    log_info "nfqws stopped"
}

zapret_restart() {
    zapret_stop
    sleep 1
    zapret_start
}

zapret_status() {
    if zapret_is_running; then
        local pid
        pid="$(cat "$NFQWS_PID" 2>/dev/null || pgrep -x nfqws)"
        
        echo "Status: RUNNING"
        echo "PID: $pid"
        
        # Show process info
        if [ -d "/proc/$pid" ]; then
            echo "CPU: $(ps -p "$pid" -o %cpu= 2>/dev/null || echo 'N/A')"
            echo "MEM: $(ps -p "$pid" -o %mem= 2>/dev/null || echo 'N/A')"
        fi
        
        # Show NFQUEUE stats
        if [ -f /proc/net/netfilter/nfnetlink_queue ]; then
            echo ""
            echo "NFQUEUE Stats:"
            cat /proc/net/netfilter/nfnetlink_queue | grep -E 'queue|packets' || echo "No stats available"
        fi
        
        return 0
    else
        echo "Status: STOPPED"
        return 1
    fi
}

zapret_verify() {
    # Verify nfqws is working correctly
    if ! zapret_is_running; then
        echo "ERROR: nfqws not running"
        return 1
    fi
    
    # Check NFQUEUE rules exist
    if ! iptables -t mangle -L FORWARD -n | grep -q 'NFQUEUE.*queue 200'; then
        echo "ERROR: NFQUEUE rules missing"
        return 1
    fi
    
    # Check for errors in log
    if [ -f "$NFQWS_LOG" ]; then
        if grep -qi 'error\|fail' "$NFQWS_LOG"; then
            echo "WARNING: Errors found in log"
            tail -5 "$NFQWS_LOG"
        fi
    fi
    
    echo "Zapret verification: OK"
    return 0
}

zapret_export_metrics() {
    # Export metrics for observability (POSIX-compliant)
    if zapret_is_running; then
        printf "netadmin_zapret_running 1\n"
        
        local pid
        pid="$(cat "$NFQWS_PID" 2>/dev/null || echo '0')"
        printf "netadmin_zapret_pid %s\n" "$pid"
        
        # CPU/Memory if available
        if [ -d "/proc/$pid" ]; then
            local cpu mem
            cpu="$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo '0')"
            mem="$(ps -p "$pid" -o %mem= 2>/dev/null | tr -d ' ' || echo '0')"
            printf "netadmin_zapret_cpu %s\n" "$cpu"
            printf "netadmin_zapret_mem %s\n" "$mem"
        fi
    else
        printf "netadmin_zapret_running 0\n"
    fi
}

case "${1:-status}" in
    start)
        zapret_start
        ;;
    stop)
        zapret_stop
        ;;
    restart)
        zapret_restart
        ;;
    status)
        zapret_status
        ;;
    verify)
        zapret_verify
        ;;
    metrics)
        zapret_export_metrics
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|verify|metrics}"
        exit 1
        ;;
esac
