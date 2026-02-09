#!/bin/sh
# /jffs/addons/stability/stability.sh - HND Platform Addon API v1.2.0
# Stability Framework v2.0 - The Canonical Integration
# Merges USB Tether Cloak with System Stability Monitors

VERSION="2.0.0"
ADDON_NAME="stability"
# Canonical Merlin settings location
CUSTOM_SETTINGS="/jffs/addons/custom_settings.txt"
# Addon installation path
ADDON_DIR="/jffs/addons/$ADDON_NAME"
# Scripts path
SCRIPTS_DIR="/jffs/scripts"

log_msg() {
    logger -t "$ADDON_NAME" "$*"
    printf "[%s] %s\n" "$ADDON_NAME" "$*"
}

# === MERLIN SETTINGS API ===
# Reads/Writes directly to /jffs/addons/custom_settings.txt
settings_set() {
    local key="$1"
    local val="$2"
    # Remove existing key
    if [ -f "$CUSTOM_SETTINGS" ]; then
        grep -v "^$key=" "$CUSTOM_SETTINGS" > /tmp/settings.tmp 2>/dev/null || true
        mv /tmp/settings.tmp "$CUSTOM_SETTINGS"
    fi
    # Append new key=value
    printf '%s=%s\n' "$key" "$val" >> "$CUSTOM_SETTINGS"
}

settings_get() {
    local key="$1"
    local default="$2"
    local val=""
    if [ -f "$CUSTOM_SETTINGS" ]; then
        val=$(grep "^$key=" "$CUSTOM_SETTINGS" 2>/dev/null | cut -d= -f2-)
    fi
    if [ -n "$val" ]; then
        echo "$val"
    else
        echo "$default"
    fi
}

# === INSTALL SEQUENCE ===
install_addon() {
    log_msg "Installing Stability Framework v$VERSION (armv8/HND)"

    # Phase 1: Entware validation (Critical Requirement)
    if [ ! -d /opt/bin ]; then
        log_msg "ERROR: Entware not found! Please install via AMTM -> 1"
        exit 1
    fi

    # Phase 2: HND kernel modules (GT-AX6000 specific)
    # These modules are often not auto-loaded but required for tethering NAT/Mangle
    log_msg "Loading kernel modules..."
    modprobe ip6table_nat 2>/dev/null
    # Find xt_HL.ko if not loaded
    find /lib/modules -name xt_HL.ko -exec insmod {} \; 2>/dev/null

    # Phase 3: Package idempotency (Install dependencies)
    log_msg "Installing dependencies via opkg..."
    opkg update >/dev/null 2>&1
    # Core networking tools
    for pkg in iptables-mod-ipopt ip6tables-mod-ipopt ip6tables-mod-nat kmod-ipt-nat6 fping mtr; do
        if ! opkg list-installed | grep -q "^$pkg "; then
            log_msg "Installing $pkg..."
            opkg install "$pkg"
        fi
    done

    # Phase 4: Default Settings (Merlin canonical)
    log_msg "Configuring default settings..."
    # Tether Cloak Defaults
    settings_set stability_enabled 1
    settings_set stability_ttl_ipv4 65
    settings_set stability_hl_ipv6 65
    settings_set stability_mtu 1428
    settings_set stability_profile iphone-usb
    # Time Preservation Defaults
    settings_set stability_time_preservation 1
    settings_set stability_max_drift 900
    # Service Monitor Defaults
    settings_set stability_service_monitor 1

    # Phase 5: Deploy Core Components
    mkdir -p "$ADDON_DIR/scripts"
    mkdir -p "$ADDON_DIR/www"

    deploy_core_hooks
    deploy_monitor_script
    deploy_webui

    # Phase 6: Start Services
    # Run firewall-start to apply rules immediately
    sh "$SCRIPTS_DIR/firewall-start"
    # Start monitor via services-start logic (manually triggered for now)
    nohup "$ADDON_DIR/scripts/stability-monitor.sh" >/dev/null 2>&1 &

    log_msg "Installation Complete. Stability Framework Active."
    log_msg "Access Web UI at: http://$(nvram get lan_ipaddr)/user/stability.asp"
}

# === CORE HOOKS DEPLOYMENT ===
deploy_core_hooks() {
    log_msg "Deploying JFFS hooks..."

    # 1. firewall-start: The heavy lifter for Tether Cloak & Rules
    # Uses 'cat' to create the file. Idempotent logic inside.
    cat > "$SCRIPTS_DIR/firewall-start" << 'HOOK_FW'
#!/bin/sh
# Stability Framework: Firewall Start Hook
# Handles Tether Cloak (TTL/HL/MSS) and Time Preservation Rules

# Wait for ipheth module (USB tether) - Critical timing for GT-AX6000
timeout=30
while [ $timeout -gt 0 ] && ! lsmod | grep -q ipheth; do
    sleep 1; timeout=$((timeout-1))
done

CUSTOM_SETTINGS="/jffs/addons/custom_settings.txt"
[ ! -f "$CUSTOM_SETTINGS" ] && exit 0

# Parse settings (Merlin API - direct grep for speed in hook)
eval "$(awk -F= '/^stability_/ {gsub(/[^a-zA-Z0-9_=-]/, "", $0); print $1"=\""$2"\""}' "$CUSTOM_SETTINGS")"

# Defaults if settings missing
TTL4=${stability_ttl_ipv4:-65}
HL6=${stability_hl_ipv6:-65}
MTU=${stability_mtu:-1428}

# WAN interface detection (usb0/eth8 fallback)
WAN_IF=""
# Check for active link on common tether interfaces
for ifname in usb0 eth8; do
    ip link show "$ifname" >/dev/null 2>&1 && { WAN_IF="$ifname"; break; }
done

# If no tether interface, fallback to NVRAM wan0 (for standard WAN stability)
if [ -z "$WAN_IF" ]; then
    WAN_IF=$(nvram get wan0_ifname)
fi
[ -z "$WAN_IF" ] && exit 0

MSS4=$((MTU-40))
MSS6=$((MTU-60))

# --- Module 1: Tether Cloak (Mangle Rules) ---
# IPv4 TTL
iptables -t mangle -D POSTROUTING -o "$WAN_IF" -j TTL --ttl-set "$TTL4" 2>/dev/null
if ! iptables -t mangle -A POSTROUTING -o "$WAN_IF" -j TTL --ttl-set "$TTL4"; then
    logger -t stability "CRITICAL: Failed to add TTL rule, firewall state inconsistent"
    exit 1
fi

# IPv6 Hop Limit
ip6tables -t mangle -D POSTROUTING -o "$WAN_IF" -j HL --hl-set "$HL6" 2>/dev/null
ip6tables -t mangle -A POSTROUTING -o "$WAN_IF" -j HL --hl-set "$HL6"

# MSS Clamping (TCP Signature Evasion)
iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --set-mss "$MSS4" 2>/dev/null
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --set-mss "$MSS4"

ip6tables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --set-mss "$MSS6" 2>/dev/null
ip6tables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o "$WAN_IF" -j TCPMSS --set-mss "$MSS6"

# --- Module 2: NAT66 (IPv6 Masquerade) ---
# Essential for carrier grade NAT bypass on cellular
sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null
sysctl -w "net.ipv6.conf.$WAN_IF.forwarding=1" 2>/dev/null
ip6tables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null
ip6tables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE

# --- Module 3: Connectivity & Mesh ---
# Allow Tailscale UDP (41641) if present
iptables -D INPUT -i "$WAN_IF" -p udp --dport 41641 -j ACCEPT 2>/dev/null
iptables -I INPUT -i "$WAN_IF" -p udp --dport 41641 -j ACCEPT 2>/dev/null
ip6tables -D INPUT -i "$WAN_IF" -p udp --dport 41641 -j ACCEPT 2>/dev/null
ip6tables -I INPUT -i "$WAN_IF" -p udp --dport 41641 -j ACCEPT 2>/dev/null

logger -t stability "Firewall rules applied on $WAN_IF [TTL:$TTL4 HL:$HL6 MTU:$MTU]"
HOOK_FW
    chmod +x "$SCRIPTS_DIR/firewall-start"

    # 2. service-event: WebUI restart trigger
    # Append if not exists to avoid clobbering other addons
    if ! grep -q "stability_restart" "$SCRIPTS_DIR/service-event" 2>/dev/null; then
        cat >> "$SCRIPTS_DIR/service-event" << 'HOOK_SE'

# BEGIN STABILITY FRAMEWORK
if [ "$1" = "restart" ] && [ "$2" = "stability_addon" ]; then
    logger -t stability "WebUI triggered restart"
    /jffs/scripts/firewall-start
fi
# END STABILITY FRAMEWORK
HOOK_SE
        chmod +x "$SCRIPTS_DIR/service-event"
    fi

    # 3. wan-event: USB Flap Handling
    # Re-apply rules on disconnect/connect cycles
    cat > "$SCRIPTS_DIR/wan-event" << 'HOOK_WAN'
#!/bin/sh
# Stability Framework: WAN Event Hook
INTERFACE="$1"
ACTION="$2"

if [ "$ACTION" = "disconnected" ]; then
    logger -t stability "WAN $INTERFACE disconnected - Triggering resync"
    # Sleep to allow driver to settle
    sleep 10
    /jffs/scripts/firewall-start
fi
HOOK_WAN
    chmod +x "$SCRIPTS_DIR/wan-event"

    # 4. services-start: Background Monitor
    # Ensures the stability monitor runs on boot
    if ! grep -q "stability-monitor" "$SCRIPTS_DIR/services-start" 2>/dev/null; then
        cat >> "$SCRIPTS_DIR/services-start" << 'HOOK_SS'

# BEGIN STABILITY FRAMEWORK
pkill -f stability-monitor.sh 2>/dev/null
nohup /jffs/addons/stability/scripts/stability-monitor.sh >/dev/null 2>&1 &
# END STABILITY FRAMEWORK
HOOK_SS
        chmod +x "$SCRIPTS_DIR/services-start"
    fi
}

# === MONITOR SCRIPT DEPLOYMENT ===
deploy_monitor_script() {
    log_msg "Deploying Stability Monitor..."
    cat > "$ADDON_DIR/scripts/stability-monitor.sh" << 'MONITOR'
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
            fping -I "$WAN_IF" -c1 -t2000 "$TARGET" >/dev/null 2>&1 || FAIL_COUNT=$((FAIL_COUNT+1))
        else
            ping -I "$WAN_IF" -c1 -W2 "$TARGET" >/dev/null 2>&1 || FAIL_COUNT=$((FAIL_COUNT+1))
        fi

        if [ $FAIL_COUNT -ge $MAX_FAILS ]; then
            log "Interface flap detected on $WAN_IF - Resetting"
            ifconfig "$WAN_IF" down
            sleep 2
            ifconfig "$WAN_IF" up
            FAIL_COUNT=0
            # Trigger re-application of rules
            /jffs/scripts/firewall-start
        else
            # On success, reset count
            FAIL_COUNT=0
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
MONITOR
    chmod +x "$ADDON_DIR/scripts/stability-monitor.sh"
}

# === WEB UI DEPLOYMENT ===
deploy_webui() {
    log_msg "Deploying Web UI..."

    # 1. Create the ASP file
    # Uses the HND Platform Addon API headers
    cat > "$ADDON_DIR/www/stability.asp" << 'ASP_PAGE'
<%@ page language="C" contentType="text/html; charset=UTF-8"%>
<!DOCTYPE html>
<html>
<head>
<title>Stability Framework</title>
<meta http-equiv="X-UA-Compatible" content="IE=Edge"/>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
<meta HTTP-EQUIV="Expires" CONTENT="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script>
// Merlin Canonical Settings Injection
var custom_settings = <% get_custom_settings(); %>;
</script>
<style>
.status-card { background: #fdfdfd; border: 1px solid #ccc; padding: 15px; border-radius: 5px; margin-bottom: 10px; }
.ok { color: #28a745; font-weight: bold; }
.fail { color: #dc3545; font-weight: bold; }
.metric { font-size: 1.2em; font-family: monospace; }
</style>
</head>
<body>
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>

<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

<form method="post" name="form" action="apply.cgi" target="hidden_frame">
<input type="hidden" name="current_page" value="stability.asp">
<input type="hidden" name="next_page" value="stability.asp">
<input type="hidden" name="action_mode" value="apply">
<input type="hidden" name="action_script" value="restart_stability_addon">
<input type="hidden" name="action_wait" value="5">

<table class="content_bg" cellpadding="0" cellspacing="0">
    <tr>
        <td width="17">&nbsp;</td>
        <td valign="top" width="202">
            <div id="mainMenu"></div>
            <div id="subMenu"></div>
        </td>
        <td valign="top">
            <div id="tabMenu" class="submenuBlock"></div>

            <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
                <tr>
                    <td valign="top">
                        <h2>Stability Framework v2.0</h2>

                        <div class="status-card">
                            <h3>Tether Cloak Status</h3>
                            <table width="100%">
                                <tr><td>IPv4 TTL:</td><td id="ttl" class="metric">Loading...</td></tr>
                                <tr><td>IPv6 Hop Limit:</td><td id="hl" class="metric">Loading...</td></tr>
                                <tr><td>WAN MTU:</td><td id="mtu" class="metric">Loading...</td></tr>
                                <tr><td>Active Interface:</td><td id="wan" class="metric">Loading...</td></tr>
                            </table>
                        </div>

                        <div class="status-card">
                            <h3>System Health</h3>
                            <table width="100%">
                                <tr><td>Time Sync:</td><td id="time_status" class="metric">Checking...</td></tr>
                                <tr><td>Service Monitor:</td><td id="svc_status" class="metric">Active</td></tr>
                            </table>
                        </div>

                        <div style="margin-top: 10px;">
                            <input type="button" class="button_gen" onclick="reloadRules()" value="Reload Rules">
                        </div>
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</form>

<script>
function reloadRules() {
    document.form.submit();
    setTimeout(function() { location.reload(); }, 2000);
}

function checkStatus() {
    // Check TTL Rule Presence
    var xhr = new XMLHttpRequest();
    xhr.open('GET', 'shell.cgi?cmd=iptables -t mangle -L POSTROUTING -n | grep -c "TTL set"', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState == 4) {
            var active = parseInt(xhr.responseText) > 0;
            document.getElementById('ttl').innerHTML = active ? '<span class="ok">ACTIVE</span>' : '<span class="fail">INACTIVE</span>';
        }
    };
    xhr.send();

    // Check Interface
    var xhr2 = new XMLHttpRequest();
    xhr2.open('GET', 'shell.cgi?cmd=ip link show usb0 >/dev/null 2>&1 && echo usb0 || echo eth8', true);
    xhr2.onreadystatechange = function() {
        if (xhr2.readyState == 4) {
            document.getElementById('wan').innerText = xhr2.responseText.trim() || "None";
        }
    };
    xhr2.send();
}

// Initial Load
setInterval(checkStatus, 5000);
checkStatus();
</script>
</body>
</html>
ASP_PAGE

    # 2. Symlink to user web dir (Required for access)
    mkdir -p /www/user
    ln -sf "$ADDON_DIR/www/stability.asp" /www/user/stability.asp

    # 3. Create Mount Marker (Not strictly standard but good for some firmwares)
    touch "$ADDON_DIR/www/.aspx_mount_marker"
}

# === DISPATCH ===
case "${1:-status}" in
    install)
        install_addon
        ;;
    uninstall)
        log_msg "Uninstalling Stability Framework..."
        rm -f "$SCRIPTS_DIR/firewall-start" "$SCRIPTS_DIR/wan-event"

        # Clean up hooks
        if [ -f "$SCRIPTS_DIR/services-start" ]; then
            sed -i '/# BEGIN STABILITY FRAMEWORK/,/# END STABILITY FRAMEWORK/d' "$SCRIPTS_DIR/services-start"
        fi
        if [ -f "$SCRIPTS_DIR/service-event" ]; then
            sed -i '/# BEGIN STABILITY FRAMEWORK/,/# END STABILITY FRAMEWORK/d' "$SCRIPTS_DIR/service-event"
        fi

        rm -rf "$ADDON_DIR"
        rm -f /www/user/stability.asp
        # Clean settings
        grep -v "stability_" "$CUSTOM_SETTINGS" > /tmp/settings.tmp 2>/dev/null && mv /tmp/settings.tmp "$CUSTOM_SETTINGS"
        log_msg "Uninstalled."
        ;;
    status)
        printf "=== %s v%s ===\n" "$ADDON_NAME" "$VERSION"
        grep "^stability_" "$CUSTOM_SETTINGS" 2>/dev/null || echo "No settings found."
        echo "--- Active Rules ---"
        iptables -t mangle -L POSTROUTING -n | grep -E "(TTL|TCPMSS)" | head -3 || echo "No rules active"
        ;;
    *)
        printf "Usage: %s {install|uninstall|status}\n" "$0"
        exit 1
        ;;
esac
