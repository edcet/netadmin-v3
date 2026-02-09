#!/bin/sh
# Stability Framework: Unified Background Monitor
# Handles: USB Keepalive, Time Drift, Service Health

INTERVAL=30
MAX_FAILS=3
FAIL_COUNT=0
TARGET="8.8.8.8"
TIME_ANCHOR="/jffs/addons/stability/time_anchor.dat"

log() { logger -t "stability-mon" "$1"; }

while :; do
    sleep $INTERVAL

    # --- 1. USB Keepalive ---
    # Detect active interface
    WAN_IF=""
    if ip link show usb0 >/dev/null 2>&1; then
        WAN_IF="usb0"
    elif ip link show eth8 >/dev/null 2>&1; then
        WAN_IF="eth8"
    fi

    if [ -n "$WAN_IF" ]; then
if command -v fping >/dev/null 2>&1; then
    if fping -I "$WAN_IF" -c1 -t2000 "$TARGET" >/dev/null 2>&1; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
else
    if ping -I "$WAN_IF" -c1 -W2 "$TARGET" >/dev/null 2>&1; then
        FAIL_COUNT=0
    else
        FAIL_COUNT=$((FAIL_COUNT+1))
    fi
fi
    fi

    # --- 2. Time Preservation ---
    # Periodically save time to anchor file
    date -u '+%Y-%m-%d %H:%M:%S' > "$TIME_ANCHOR"

    # Check for massive drift (e.g. if NTP failed after reboot)
    # Simple check: if year is 1970, restore from anchor
    CURRENT_YEAR=$(date +%Y)
    if [ "$CURRENT_YEAR" -eq 1970 ] && [ -f "$TIME_ANCHOR" ]; then
        log "Time drift detected (Year 1970) - Restoring from anchor"
        SAVED_TIME=$(cat "$TIME_ANCHOR")
        date -u -s "$SAVED_TIME"
        # Restart NTP to force sync
        service restart_ntp
    fi

done
