# netadmin v3.0 Troubleshooting Guide

## Common Issues

### Issue: "Rules disappeared" errors in logs

**Symptom**: Logger shows "WATCHDOG: Rules disappeared!"

**Cause**: Firewall was restarted and rules weren't reapplied.

**Solution**:
```bash
# Manually reapply rules
netadmin verify

# Or restart netadmin
sh /jffs/scripts/netadmin/hooks/firewall-start
```

### Issue: WAN_WAIT timeout

**Symptom**: State stuck in WAN_WAIT, no IP acquired after 60s

**Cause**: DHCP client not getting IP from ISP

**Solution**:
```bash
# Check DHCP status
logger udhcpc -e 0 -t eth0

# Check gateway
ip route

# Restart WAN interface
ip link set eth0 down && sleep 2 && ip link set eth0 up

# Force DHCP renewal
killall -SIGUSR1 udhcpc
```

### Issue: Boot loop (multiple "boot attempts" errors)

**Symptom**: Router reboots repeatedly after installing netadmin

**Cause**: Bad firewall rule crashes kernel or Merlin

**Solution**:
1. Router will auto-fallback to SAFE profile after 3 attempts
2. Wait for auto-recovery, then:
```bash
netadmin profile safe
logger /tmp/netadmin_boot_attempts
```

If still looping, restore from backup:
```bash
# SSH into router recovery mode
rm -rf /jffs/scripts/netadmin
mv /jffs/scripts.v3.0.backup /jffs/scripts
reboot
```

### Issue: Throughput drops to 200 Mbps with verizon profile

**Symptom**: Speed test shows massive throughput reduction

**Cause**: This is expected with zapret (verizon-bypass) due to NFQUEUE bottleneck

**Solution**:
- If you need full throughput, use `netadmin profile verizon` (TTL spoof) instead
- Or switch to `netadmin profile safe` if not being throttled
- See PERFORMANCE.md for benchmark data

### Issue: TCP health check fails

**Symptom**: `netadmin health-check` fails at "TCP handshake"

**Cause**: Firewall blocking outbound connections or DNS failure

**Solution**:
```bash
# Check if DNS working
nslookup google.com

# Test DNS manually
echo > /dev/tcp/8.8.8.8/53

# Check firewall rules
iptables -L -n | grep -i reject

# If firewall blocks, add exception
iptables -I OUTPUT -d 8.8.8.8 -p tcp --dport 53 -j ACCEPT
```

### Issue: NVRAM setting not persisting

**Symptom**: Setting changes with `nvram set` but revert after reboot

**Cause**: `nvram commit` not called

**Solution**:
```bash
# Always commit after setting
nvram set mykey=myvalue
nvram commit

# Verify
nvram get mykey
```

## Debug Commands

### Check Current State

```bash
# Get state machine state
netadmin get-state

# Get full health JSON
netadmin wan-state

# Show configuration
netadmin show-config

# Show hardware status
netadmin show-hardware
```

### View Logs

```bash
# State machine transitions
netadmin logs

# Follow logs in real-time
tail -f /tmp/netadmin_state.log

# Full system logs
logger -f /var/log/messages | grep netadmin
```

### Manual Health Check

```bash
# Run comprehensive health check
netadmin health-check

# Check individual components
sh /jffs/scripts/netadmin/core/wan-state.sh --json
```

### Verify Rules

```bash
# Check if netadmin chains exist
iptables -t mangle -L | grep NETADMIN

# Check if TTL clamping active
iptables -t mangle -L NETADMIN_TTL_CLAMP -n

# Check if Zapret running
pgrep -a nfqws
```

## Performance Debugging

### Check Hardware Acceleration State

```bash
# CTF status (0 = enabled, 1 = disabled)
nvram get ctf_disable

# Flow Accelerator
nvram get fc_disable

# Runner
nvram get runner_disable_force
```

### Monitor CPU Usage

```bash
# Watch CPU during rule application
top -b -n 5 | grep -E 'CPU|netadmin'

# Check CPU temperature
nvram get temp_cpu
```

### Check Throughput

```bash
# Simple iperf3 test (install on external host)
iperf3 -c router-ip -R -t 10

# With netstat monitoring
watch -n 1 'netstat -i | grep eth0'
```

## Factory Reset (Last Resort)

If netadmin has corrupted your router configuration:

```bash
# SSH into router
ssh admin@router

# Remove netadmin
rm -rf /jffs/scripts/netadmin*

# Restore from backup if available
if [ -d /jffs/scripts.backup ]; then
  rm -rf /jffs/scripts
  mv /jffs/scripts.backup /jffs/scripts
fi

# Reboot
reboot
```

If Merlin web UI is broken:
```bash
# Reset NVRAM to defaults
nvram erase
nvram commit
reboot
```

## Getting Help

1. **Check logs first**: `netadmin logs`
2. **Run diagnostics**: `netadmin health-check`
3. **Review documentation**: Read ARCHITECTURE.md and PERFORMANCE.md
4. **Search issues**: https://github.com/edcet/netadmin-v3/issues
5. **Create issue**: Include logs, router model, and exact error
