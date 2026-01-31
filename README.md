# netadmin v3.0

**Production-Grade WAN Management Framework for ASUSWRT-Merlin Routers**

A self-scaffolding, CI/CD-integrated deployment system with hardware acceleration awareness, state machine monitoring, and observability built for the GT-AX6000 (BCM4912) and compatible Broadcom-based Merlin routers.

## 🎯 Features

### Core Architecture
- **State Machine**: 6-state model (INIT → WAN_WAIT → RULES_APPLY → ACTIVE → DEGRADED/SAFE) with timeout protection
- **Hardware Acceleration Gatekeeper**: Detects CTF/Flow Accelerator/Runner and validates zapret compatibility
- **TCP Health Validation**: Beyond ICMP ping - validates actual data flow with TCP handshake checks
- **Boot-Time Fallback**: Automatic recovery from bad rules via watchdog mechanism
- **DHCP Lifecycle Hooks**: Integrates with Merlin's dhcpc-event for reliable IP acquisition

### Deployment & CI/CD
- **Semantic Versioning**: Automated version bumping via Conventional Commits
- **GitHub Actions**: Free public runners, GHCR container publishing
- **Artifact Management**: Signed releases, changelog generation, backward compatibility checks
- **Safe Upgrade Path**: NVRAM migration, dry-run validation, atomic swap

### Testing & Quality
- **Embedded Systems Testing**: shellspec framework for POSIX-compatible shell scripts
- **Static Analysis**: ShellCheck linting, NVRAM key validation
- **Integration Tests**: Simulated DHCP events, state transitions, rule application
- **Performance Benchmarks**: Throughput validation (CTF enabled vs. disabled vs. zapret)

### Observability
- **State Persistence**: Machine-readable state files in `/tmp/netadmin_*`
- **Metric Export**: JSON outputs for monitoring integrations
- **Boot Watchdog**: Prevents infinite boot loops via counter mechanism
- **Health Checks**: WAN readiness probes, rule validation, hardware acceleration status

## 📦 Quick Start

### Installation

```bash
# SSH to your router
ssh admin@192.168.1.1

# Download and run installer (dry-run first)
curl -fsSL https://github.com/edcet/netadmin-v3/releases/download/latest/install.sh | sh -s -- --dry-run

# Apply installation
curl -fsSL https://github.com/edcet/netadmin-v3/releases/download/latest/install.sh | sh
```

### Profiles

```bash
# Safe mode (minimal rules)
netadmin profile safe

# Standard Verizon throttling bypass
netadmin profile verizon

# Full DPI bypass with zapret
netadmin profile verizon-bypass

# Query current state
netadmin wan-state
netadmin get-state
```

## 🏗️ Architecture

### State Machine

```
INIT(0)
  ↓
WAN_WAIT(1) ←──────────────┐
  ↓                         │ (timeout 60s)
RULES_APPLY(2)              │
  ↓                         │
ACTIVE(3) ─→ DEGRADED(4) ───┘
  ↓
  └─→ SAFE(5) ← error transition
```

### Hardware Acceleration Awareness

| Mode | CTF | FC | Runner | Throughput | Use Case |
|------|-----|----|---------|-----------|-----------|
| Stock | ✅ | ✅ | ✅ | ~2000 Mbps | Normal routing |
| TTL Spoof | ❌ | ❌ | ❌ | ~800 Mbps | Tethering bypass |
| DPI Bypass | ❌ | ❌ | ❌ | ~200 Mbps | Full anti-throttle |

## 🔧 Configuration

### NVRAM Keys (v3.0)

```bash
# Core configuration
netadmin_mode         # Current mode: safe, verizon, verizon-bypass
netadmin_state        # Current state: 0-5 (see state machine)
netadmin_ttl_mode     # TTL spoofing: off, clamp, spoof
netadmin_zapret       # DPI bypass: 0 (disabled), 1 (enabled)
netadmin_wan_primary  # WAN interface: eth0, eth1, etc.
netadmin_boot_attempts # Boot failure counter (auto-reset after safe revert)
```

### Performance Tuning

```bash
# Check current hardware acceleration status
nvram get ctf_disable    # 0 = enabled (default), 1 = disabled
nvram get fc_disable
nvram get runner_disable

# Enable zapret (automatically disables CTF)
netadmin profile verizon-bypass
# Expects: ~200 Mbps throughput (vs. 2000 Mbps baseline)
```

## 📊 Monitoring & Observability

### Health Checks

```bash
# Check WAN readiness (JSON output)
netadmin wan-state

# Output:
# {
#   "interface": "eth0",
#   "carrier": "up",
#   "ip_acquired": "192.168.100.1",
#   "gateway_reachable": true,
#   "tcp_health_1.1.1.1:443": true,
#   "state": "ACTIVE",
#   "rules_active": true,
#   "hardware_accel": {
#     "ctf_enabled": false,
#     "fc_enabled": false,
#     "runner_enabled": false
#   }
# }
```

### State Logs

```bash
# Real-time state transitions
tail -f /tmp/netadmin_state.log

# Boot watchdog counter
cat /tmp/netadmin_boot_attempts
```

## 🚀 Deployment

### Upgrade from v2.1

```bash
# Automatic migration (pre-tested on boot)
netadmin migrate --from-v2.1

# Rollback if needed
netadmin rollback
```

### CI/CD Pipeline (GitHub Actions)

1. **On Commit** (develop):
   - ShellCheck lint analysis
   - Conventional Commit validation
   - Unit tests (shellspec)

2. **On PR**:
   - All above + integration tests
   - Hardware acceleration compatibility check
   - Performance regression detection

3. **On Merge to Main**:
   - Semantic version bump (auto)
   - Release notes generation
   - Signed artifact creation
   - GHCR container push
   - GitHub release publication

## 📈 Performance Benchmarks

### GT-AX6000 (BCM4912) - Real-World Measurements

| Config | WAN→LAN | CPU | Latency | Notes |
|--------|---------|-----|---------|-------|
| Baseline (CTF) | 1.8-2.0 Gbps | 5% | <1ms | Stock Merlin |
| TTL Spoof | 600-900 Mbps | 50% | 2-5ms | iptables mangle |
| Zapret DPI | 150-300 Mbps | 85% | 5-20ms | NFQUEUE bottleneck |

See [PERFORMANCE.md](./PERFORMANCE.md) for detailed analysis.

## 🛠️ Development

### Project Structure

```
netadmin-v3/
├── .github/
│   ├── workflows/
│   │   ├── lint.yml              # ShellCheck, semantic validation
│   │   ├── test.yml              # Unit + integration tests
│   │   ├── release.yml           # Semantic versioning & release
│   │   └── publish.yml           # GHCR container publishing
│   └── dependabot.yml            # Automated dependency updates
├── src/
│   ├── core/
│   │   ├── netadmin-lib.sh       # State machine, hardware checks
│   │   ├── wan-state.sh          # WAN monitoring & health checks
│   │   └── watchdog.sh           # Boot-time protection
│   ├── hooks/
│   │   ├── wan-event             # Merlin WAN state hook
│   │   ├── dhcpc-event           # DHCP lifecycle hook
│   │   └── services-start        # Boot initialization
│   ├── profiles/
│   │   ├── safe.sh               # Safe mode rules
│   │   ├── verizon.sh            # TTL spoofing
│   │   └── verizon-bypass.sh     # Full DPI bypass
│   └── cli/
│       └── netadmin              # Main CLI interface
├── tests/
│   ├── spec/
│   │   ├── state_machine_spec.sh
│   │   ├── hardware_accel_spec.sh
│   │   ├── wan_health_spec.sh
│   │   └── integration_spec.sh
│   ├── fixtures/
│   │   ├── nvram_mock.sh         # Mock NVRAM for testing
│   │   ├── ip_mock.sh            # Mock iproute2 for testing
│   │   └── iptables_mock.sh      # Mock iptables for testing
│   └── bench/
│       └── throughput_test.sh    # Performance benchmarking
├── install/
│   ├── install.sh                # Main installer with dry-run
│   ├── migrate.sh                # v2.1 → v3.0 migration
│   └── rollback.sh               # Emergency rollback
├── docs/
│   ├── ARCHITECTURE.md           # System design
│   ├── PERFORMANCE.md            # Benchmark analysis
│   ├── TROUBLESHOOTING.md        # Debug guide
│   └── API.md                    # Script API reference
├── .releaserc.json               # Semantic release config
├── .shellcheckrc                 # ShellCheck rules
├── Makefile                      # Local development targets
└── VERSION                       # Current version (semantic)
```

### Local Development

```bash
# Install dependencies
make install-dev

# Run tests locally
make test
make lint

# Simulate router environment
make test-router  # Runs in busybox container

# Build release artifacts
make release
```

## 🔒 Security & Stability

### Boot Watchdog (Anti-Brick Protection)

```bash
# Automatic on first boot failure:
# 1. Increment /tmp/netadmin_boot_attempts
# 2. After 3 failures → activate fallback
# 3. Load safe profile + revert to last known good
# 4. Alert user in logs
```

### Rollback Mechanism

```bash
# Atomic NVRAM migration with checkpoint
cp -r /jffs/scripts /jffs/scripts.v3.0.backup
netadmin migrate
# On error: auto-restore from backup
```

## 📝 License

MIT - See LICENSE file

## 🤝 Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/edcet/netadmin-v3/issues)
- **Discussions**: [GitHub Discussions](https://github.com/edcet/netadmin-v3/discussions)
- **Documentation**: [Full Docs](./docs/)
