# Zapret DPI Bypass Integration

This document explains the Zapret integration in netadmin v3.0 for bypassing Verizon's Deep Packet Inspection (DPI) throttling.

## Overview

Zapret is a DPI circumvention tool that uses packet fragmentation and disorder techniques to bypass ISP traffic shaping. In netadmin v3.0, Zapret powers the `verizon-bypass` profile.

## Architecture

### Components

1. **nfqws** - Main binary (netfilter queue processor)
2. **NFQUEUE** - Linux netfilter queue mechanism
3. **zapret-manager.sh** - Service lifecycle management
4. **verizon-bypass.sh** - Profile integration

### How It Works

```
Packet Flow:
1. Packet enters FORWARD chain
2. iptables sends to NFQUEUE (queue 200)
3. nfqws processes packet:
   - Splits HTTP requests
   - Fragments TLS SNI
   - Reorders packet sequence
4. Modified packet continues to destination
```

## Installation

### Automatic Setup

```bash
# Run zapret setup (requires Entware)
sh /jffs/scripts/netadmin/install/zapret-setup.sh
```

**Prerequisites:**
- Entware installed (`opkg install entware`)
- Compiler tools: `opkg install gcc make git`
- ~50MB free space in `/jffs`

### Manual Binary Installation

If you have a pre-compiled binary:

```bash
# Copy binary
cp nfqws /jffs/bin/nfqws
chmod +x /jffs/bin/nfqws

# Test
/jffs/bin/nfqws --help
```

## Usage

### Enable DPI Bypass

```bash
netadmin profile verizon-bypass
```

**What happens:**
1. Hardware acceleration disabled (CTF, FC, Runner)
2. NFQUEUE rules created in iptables mangle table
3. nfqws daemon started
4. State transitions to ACTIVE

### Disable DPI Bypass

```bash
netadmin profile safe
# or
netadmin profile verizon  # TTL-only bypass
```

**What happens:**
1. nfqws daemon stopped
2. NFQUEUE rules removed
3. Hardware acceleration can be re-enabled (if desired)

## Service Management

### Manual Control

```bash
# Check status
sh /jffs/scripts/netadmin/core/zapret-manager.sh status

# Start/stop manually
sh /jffs/scripts/netadmin/core/zapret-manager.sh start
sh /jffs/scripts/netadmin/core/zapret-manager.sh stop

# Verify operation
sh /jffs/scripts/netadmin/core/zapret-manager.sh verify
```

### Monitoring

```bash
# View nfqws log
tail -f /tmp/nfqws.log

# Check NFQUEUE statistics
cat /proc/net/netfilter/nfnetlink_queue

# Monitor CPU usage
top -b -n 1 | grep nfqws
```

## Performance Impact

### Expected Throughput

| Profile | Throughput | CPU Usage |
|---------|------------|----------|
| safe | 2500 Mbps | ~1% |
| verizon | 1000 Mbps | ~3% |
| verizon-bypass | **200 Mbps** | **~40%** |

**Why so slow?**
- NFQUEUE processing in userspace (not kernel)
- Per-packet processing overhead
- Hardware acceleration disabled
- Single-threaded nfqws on BCM4912

### Optimization Tips

1. **Use selectively** - Only enable when experiencing throttling
2. **Limit NFQUEUE scope** - Edit `zapret-manager.sh` to only process specific ports
3. **Monitor temperature** - High CPU can cause thermal throttling

## Troubleshooting

### nfqws won't start

**Symptom:** `netadmin profile verizon-bypass` fails

**Check:**
```bash
# Binary exists?
ls -lh /jffs/bin/nfqws

# Executable?
/jffs/bin/nfqws --help

# Hardware acceleration disabled?
nvram get ctf_disable  # Should be 1
nvram get fc_disable   # Should be 1
```

**Fix:**
```bash
# Reinstall zapret
sh /jffs/scripts/netadmin/install/zapret-setup.sh

# Or download pre-compiled binary
wget -O /jffs/bin/nfqws https://github.com/bol-van/zapret/releases/download/v67/nfqws-aarch64
chmod +x /jffs/bin/nfqws
```

### Throughput still slow

**Symptom:** Speed tests show <200 Mbps even with verizon-bypass

**Cause:** This is expected behavior. NFQUEUE is inherently slow.

**Options:**
1. Switch to `netadmin profile verizon` (TTL-only, 1000 Mbps)
2. Use VPN on specific devices only
3. Upgrade to faster hardware (if available)

### nfqws crashes/restarts

**Symptom:** nfqws keeps restarting in logs

**Check:**
```bash
# Memory available?
free -m

# Temperature OK?
nvram get temp_cpu

# Check kernel messages
dmesg | tail -20
```

**Fix:**
```bash
# Reduce NFQUEUE scope (edit zapret-manager.sh)
# Only process HTTPS:
iptables -t mangle -D FORWARD -p tcp --dport 80 -j NFQUEUE --queue-num 200

# Restart
netadmin profile verizon-bypass
```

### Rules disappear after reboot

**Symptom:** verizon-bypass works until reboot

**Cause:** Profile not set in NVRAM

**Fix:**
```bash
# After enabling profile
nvram set netadmin_mode=verizon-bypass
nvram commit

# Verify
nvram get netadmin_mode
```

## Advanced Configuration

### Custom nfqws Parameters

Edit `src/core/zapret-manager.sh` and modify `NFQWS_PARAMS`:

```bash
# Example: More aggressive splitting
NFQWS_PARAMS="\
    --qnum=200 \
    --daemon \
    --split-http-req=method \
    --split-pos=1 \
    --split-tls=sni \
    --split-pos=3 \
    --disorder \
    --disorder-fake-packets=2"
```

### Domain-Specific Bypass

Create a domain list:

```bash
# Add domains to bypass
cat > /jffs/zapret/lists/throttled.txt << EOF
youtube.com
netflix.com
twitch.tv
EOF

# Modify zapret-manager.sh to use list
# (requires custom nfqws configuration)
```

### Alternative Techniques

If Zapret doesn't work:

1. **TTL Spoofing** - Use `netadmin profile verizon` instead
2. **VPN** - WireGuard/OpenVPN on router
3. **DNS over HTTPS** - Enable DoH to hide SNI
4. **ECN manipulation** - Experimental iptables rules

## Security Considerations

### Binary Trust

The zapret setup script compiles from source (GitHub: bol-van/zapret). To verify:

```bash
# Check source code
cd /tmp/zapret-build-*/zapret
less nfqws/nfqws.c

# Build with debug symbols
export CFLAGS="-g -O0"
make
```

### Network Visibility

- Zapret modifies packets but doesn't encrypt them
- ISP can still see traffic (just can't parse DPI)
- Use HTTPS/TLS for actual encryption
- Consider VPN for full privacy

## References

- Zapret GitHub: https://github.com/bol-van/zapret
- NFQUEUE documentation: https://netfilter.org/projects/libnetfilter_queue/
- DPI Circumvention: https://github.com/ValdikSS/GoodbyeDPI

## Version History

- v3.0.0 (2026-01-31): Initial Zapret integration
  - nfqws v67
  - ARM64 build support
  - Service manager
  - Profile integration
