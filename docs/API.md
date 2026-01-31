# netadmin v3.0 Script API Reference

This document describes the public API for integrating with netadmin programmatically.

## Core Library: `netadmin-lib.sh`

Source this in your scripts to use netadmin functions:

```bash
. /jffs/scripts/netadmin/core/netadmin-lib.sh
```

### State Machine Functions

#### `get_current_state()`
Returns current state (0-5).

```bash
state=$(get_current_state)
echo "Current: $(state_name "$state")"
```

#### `set_state(new_state)`
Transition to new state. Validates state transitions.

```bash
if set_state "$STATE_ACTIVE"; then
  echo "State changed"
else
  echo "Invalid transition"
fi
```

**Valid Transitions**:
- 0→1, 1→2, 2→3, 3→4, 4→1, 4→3 (normal flow)
- 1→5, 2→5, 3→5, 4→5 (error recovery)
- 0→5 (force safe)

#### `state_name(state_number)`
Return human-readable state name.

```bash
name=$(state_name "$STATE_ACTIVE")
echo "$name"  # Output: ACTIVE
```

### Hardware Detection

#### `check_ctf_status()`
Check if CTF is enabled (1 = enabled, 0 = disabled).

```bash
if [ "$(check_ctf_status)" = "1" ]; then
  echo "CTF is enabled"
fi
```

#### `check_fc_status()`
Check if Flow Accelerator is enabled.

#### `check_runner_status()`
Check if Runner is enabled.

#### `get_hardware_accel_status()`
Return JSON object with all acceleration statuses.

```bash
json=$(get_hardware_accel_status)
echo "$json"  # {"ctf_enabled": 1, "fc_enabled": 1, "runner_enabled": 1}
```

#### `validate_hardware_for_profile(profile)`
Validate that hardware supports profile. Returns 0 on success.

```bash
if validate_hardware_for_profile "verizon-bypass"; then
  echo "Hardware supports profile"
else
  echo "Hardware incompatible"
fi
```

### WAN Monitoring

#### `wan_if_detect()`
Detect WAN interface name (usually eth0).

```bash
wan=$(wan_if_detect)
echo "WAN: $wan"
```

#### `wan_carrier_up(interface)`
Check if interface has carrier (link up).

```bash
if wan_carrier_up "eth0"; then
  echo "Link is UP"
fi
```

#### `wan_has_ip(interface)`
Check if interface has IP address assigned.

```bash
if wan_has_ip "eth0"; then
  echo "IP acquired"
fi
```

#### `wan_has_default_route()`
Check if default route exists.

```bash
if wan_has_default_route; then
  echo "Routing available"
fi
```

#### `wan_gateway_reachable(interface)`
Ping gateway to verify connectivity.

```bash
if wan_gateway_reachable "eth0"; then
  echo "Gateway reachable"
fi
```

#### `wan_tcp_health(host, port)`
Test TCP handshake to remote host.

```bash
if wan_tcp_health "8.8.8.8" "53"; then
  echo "TCP working"
fi
```

#### `wan_is_ready()`
All-in-one health check. Returns 0 if WAN ready.

```bash
if wan_is_ready; then
  echo "WAN fully ready"
else
  echo "WAN degraded"
fi
```

#### `wan_export_health()`
Export health check to JSON file (`/tmp/netadmin_health.json`).

```bash
wan_export_health
jq . /tmp/netadmin_health.json
```

### Rule Management

#### `apply_rules(profile)`
Apply rules for profile (safe, verizon, verizon-bypass).

```bash
if apply_rules "verizon"; then
  echo "Rules applied"
else
  echo "Failed to apply"
fi
```

#### `verify_rules_active(profile)`
Check if rules for profile are currently active.

```bash
if verify_rules_active "verizon"; then
  echo "Rules active"
else
  echo "Rules missing"
fi
```

### NVRAM Helpers

#### `nvram_get(key, [default])`
Get NVRAM value with optional default.

```bash
mode=$(nvram_get "netadmin_mode" "safe")
echo "$mode"  # Returns 'safe' if not set
```

#### `nvram_set(key, value)`
Set NVRAM value (without commit).

```bash
nvram_set "netadmin_debug" "1"
```

#### `nvram_commit()`
Commit NVRAM changes to flash.

```bash
nvram_set "mykey" "myvalue"
nvram_commit
```

### Logging

#### `log_info(message)`
Log info message to system logger.

```bash
log_info "Something happened"
# Appears in logs as: [INFO] Something happened
```

#### `log_warn(message)`
Log warning.

```bash
log_warn "This might be a problem"
```

#### `log_error(message)`
Log error.

```bash
log_error "Something failed"
```

#### `log_debug(message)`
Log debug (only if `netadmin_debug=1`).

```bash
log_debug "Detailed information"
# Only appears if: nvram set netadmin_debug=1
```

## WAN State Query

See current WAN health:

```bash
/jffs/scripts/netadmin/core/wan-state.sh
# Or with netadmin CLI:
netadmin wan-state
```

Output JSON format:

```json
{
  "interface": "eth0",
  "carrier_up": 1,
  "ip_acquired": "192.168.100.1",
  "default_route": 1,
  "gateway_reachable": 1,
  "tcp_health": 1,
  "ready": 1,
  "state": "ACTIVE",
  "timestamp": "2026-01-31T17:05:00Z"
}
```

## Boot Watchdog

#### `increment_boot_attempt()`
Increment boot failure counter.

#### `reset_boot_attempt()`
Reset counter to 0.

#### `get_boot_attempt()`
Get current counter value.

#### `should_fallback_safe()`
Check if 3+ boot failures detected.

```bash
if should_fallback_safe; then
  echo "Triggering fallback"
  apply_rules "safe"
  reset_boot_attempt
fi
```

## Custom Profile Example

Create `/jffs/scripts/netadmin/profiles/custom.sh`:

```bash
#!/bin/sh
. /jffs/scripts/netadmin/core/netadmin-lib.sh

log_info "Applying CUSTOM profile"

# Your custom rules here
iptables -I INPUT -p tcp --dport 22 -j ACCEPT
iptables -I FORWARD -j ACCEPT

log_info "CUSTOM profile applied"
```

Then use:
```bash
netadmin profile custom
```

## Constants

```bash
# State constants
STATE_INIT=0
STATE_WAN_WAIT=1
STATE_RULES_APPLY=2
STATE_ACTIVE=3
STATE_DEGRADED=4
STATE_SAFE=5

# File paths
NETADMIN_STATE_FILE="/tmp/netadmin_state"
NETADMIN_STATE_LOG="/tmp/netadmin_state.log"
NETADMIN_HEALTH_JSON="/tmp/netadmin_health.json"
NETADMIN_BOOT_ATTEMPTS="/tmp/netadmin_boot_attempts"
```
