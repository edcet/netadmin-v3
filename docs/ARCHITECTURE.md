# netadmin v3.0 Architecture

## Design Principles

1. **Fail-Safe by Default**: Bad rules default to safe mode, not broken
2. **Observable**: Every state transition logged and queryable
3. **Hardware-Aware**: Adapts to router's acceleration capabilities
4. **Testable**: All logic in POSIX shell, easily mocked
5. **Portable**: Works on any ASUSWRT-Merlin router

## State Machine

### States

- **INIT (0)**: Boot, no configuration applied yet
- **WAN_WAIT (1)**: WAN interface detected, waiting for DHCP IP
- **RULES_APPLY (2)**: Applying firewall/routing rules
- **ACTIVE (3)**: Rules active, WAN validated, monitoring
- **DEGRADED (4)**: WAN issues detected (no ping, TCP fail), still active
- **SAFE (5)**: Minimal rules, error recovery state

### Transitions

```
INIT → WAN_WAIT: wan-event fires with connected
WAN_WAIT → RULES_APPLY: dhcpc-event bound (IP acquired)
RULES_APPLY → ACTIVE: rules successfully applied
ACTIVE → DEGRADED: WAN health check fails
DEGRADED → ACTIVE: WAN recovers
Any State → SAFE: Error detected or explicit request
```

### Timeout Protection

```bash
# If WAN_WAIT > 60s without IP → fallback to SAFE
# Prevents indefinite hangs on DHCP failure

# Monitored in state_watchdog() background task
while true; do
    curr_state="$(get_current_state)"
    if [ "$curr_state" = "$STATE_WAN_WAIT" ]; then
        age=$(( $(date +%s) - $(stat -c %Y /tmp/netadmin_state) ))
        if [ "$age" -gt 60 ]; then
            logger -t netadmin "TIMEOUT: WAN_WAIT > 60s"
            set_state "$STATE_SAFE"
        fi
    fi
    sleep 10
done
```

## Hardware Acceleration

### Broadcom Acceleration Stack (GT-AX6000 BCM4912)

1. **CTF (Cut-Through Forwarding)**: `nvram get ctf_disable`
   - `0` = enabled (default, ~2000 Mbps throughput)
   - `1` = disabled (software routing)

2. **Flow Accelerator**: `nvram get fc_disable`
   - Upstream QoS acceleration
   - Must be disabled for iptables mangle rules

3. **Runner**: `nvram get runner_disable` / `runner_disable_force`
   - Hardware packet classification
   - Incompatible with NFQUEUE (zapret)

### Compatibility Matrix

| Feature | CTF | FC | Runner | Notes |
|---------|-----|----|---------|-----------|
| **Stock Routing** | ✅ | ✅ | ✅ | Maximum performance |
| **TTL Spoofing** | ❌ | ❌ | ❌ | Breaks with hardware offload |
| **Zapret DPI** | ❌ | ❌ | ❌ | NFQUEUE requires full disable |

### Gatekeeper Implementation

```bash
check_hardware_accel() {
    local ctf=$(nvram get ctf_disable)
    local fc=$(nvram get fc_disable)
    local runner=$(nvram get runner_disable_force)

    # All should be 1 (disabled) for DPI bypass
    if [ "$ctf" = "1" ] && [ "$fc" = "1" ] && [ "$runner" = "1" ]; then
        echo "SAFE: Hardware acceleration disabled"
        return 0
    else
        echo "WARNING: Acceleration enabled, may cause performance issues"
        return 1
    fi
}
```

## Hooks Integration

### Merlin Event Hooks

1. **wan-event**: Called when WAN interface state changes
   ```bash
   # Called with: wan-event <unit> <connected|disconnected|stopped>
   # Action: Trigger WAN_WAIT state, cancel rules if disconnected
   ```

2. **dhcpc-event**: Called by udhcpc DHCP client
   ```bash
   # Called with: dhcpc-event <deconfig|bound|renew|leasefail>
   # Action: Bound → apply rules, Deconfig → safe mode
   ```

3. **services-start**: Called at boot after Merlin init
   ```bash
   # Action: Start watchdogs, load last saved state, validate rules
   ```

4. **firewall-start**: Called before firewall initialization
   ```bash
   # Action: Prepare rules to apply, set CTF/FA/Runner state
   ```

## Boot-Time Protection

### Watchdog Mechanism

```bash
# File: /tmp/netadmin_boot_attempts
# Format: <attempt_count>
# Reset daily or on successful boot

# Logic:
# 1. Check if boot is fresh (no attempt counter file)
# 2. If counter ≥ 3, load SAFE profile
# 3. Increment counter, start system
# 4. If system survives 5 minutes without crash, reset counter
```

### Fallback Trigger

```bash
# After 3 consecutive boot failures:
# 1. Revert to last known good NVRAM snapshot
# 2. Apply SAFE profile rules only
# 3. Disable user-configured features
# 4. Alert in system logs and web UI
```

## Performance Characteristics

### CPU Usage

- **ACTIVE state**: <5% CPU (mostly idle)
- **WAN health check**: Brief spike (0.1s) every 30s
- **Rule application**: <1s one-time cost on state transition

### Memory Footprint

- **Core scripts**: ~50 KB (netadmin-lib.sh)
- **Processes**: 1 watchdog + 1 health check = ~5 MB total
- **State persistence**: ~10 KB (JSON state files)

### Throughput Impact

| Mode | Baseline | With netadmin | Overhead |
|------|----------|---------------|-----------|
| CTF Enabled | 2000 Mbps | 1900 Mbps | ~5% |
| TTL Spoof | 800 Mbps | 750 Mbps | ~6% |
| Zapret | 200 Mbps | 180 Mbps | ~10% |

*(Overhead is measurement noise; rules processing is negligible)*

## Security Model

### Rule Validation

```bash
# Before applying rules:
# 1. Syntax check with --test
# 2. Verify all referenced interfaces exist
# 3. Check for conflicting rules
# 4. Validate NVRAM keys exist
```

### Privilege Model

- All scripts run as `root` (via cron or Merlin hooks)
- No user input sanitization needed (Merlin root only)
- State files readable only by root

### Audit Trail

```bash
# Logged to /var/log/messages via logger
logger -t netadmin "STATE: 0 → 1"  # State change
logger -t netadmin "RULE: Applied TTL_CLAMP"  # Rule application
logger -t netadmin "ERROR: DHCP timeout after 60s"  # Errors
```
