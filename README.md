# Stability Framework v2.0 (HND Platform)

**Production-Grade Tether Cloak & System Monitor for ASUS GT-AX6000**

This framework is a **canonical ASUSWRT-Merlin Addon** designed for the GT-AX6000 (HND Platform). It unifies USB Tethering concealment (TTL/HL/MSS) with system stability monitoring (Time Drift, USB Keepalive) into a single, cohesive module.

## 🎯 Core Features

### 1. USB Tethering Cloak (Carrier Grade)
- **TTL/HL Mangling**: Normalizes IPv4 TTL and IPv6 Hop Limit to 65 (evades hotspot detection).
- **MSS Clamping**: Clamps TCP MSS to MTU-40/60 to prevent DPI fingerprinting.
- **NAT66**: Enables kernel-native IPv6 Masquerade for cellular networks.
- **Tailscale Integration**: Allows Tailscale UDP (41641) through the tethered interface.

### 2. Stability Monitor (Background)
- **USB Keepalive**: Pings target (8.8.8.8) every 30s. Automatically resets the USB interface (`usb0` or `eth8`) if 3 consecutive failures occur.
- **Time Preservation**: Periodically saves system time to non-volatile storage. Automatically restores time if the system clock resets to 1970 (common on reboot without RTC battery).
- **USB Flap Handling**: Re-applies firewall rules automatically if the USB interface disconnects and reconnects.

### 3. Canonical Merlin Integration
- **Settings API**: Uses `/jffs/addons/custom_settings.txt` for configuration.
- **Web UI**: Native `.asp` page integrated into the Merlin web interface (`Tools` -> `Stability Framework`).
- **Hooks**: Uses `firewall-start`, `wan-event`, `service-event`, and `services-start` strictly according to the HND Platform Addon API.

## 📦 Installation

### Prerequisites
1. **ASUSWRT-Merlin Firmware** (3006.102.7+ recommended).
2. **Entware** installed (via AMTM).
3. **JFFS Scripts** enabled in `Administration` -> `System`.

### One-Line Install
Upload `stability.sh` to your router and run:

```sh
# Copy script to router
scp stability/stability.sh admin@192.168.50.1:/jffs/addons/

# SSH into router and install
ssh admin@192.168.50.1
chmod +x /jffs/addons/stability.sh
/jffs/addons/stability.sh install
```

### Verification
- **Web UI**: Go to `http://192.168.50.1/user/stability.asp`
- **CLI**: Run `/jffs/addons/stability/stability.sh status`

## 🛠 Architecture

```
/jffs/addons/stability/
├── stability.sh          # Monolithic Manager (Install/Uninstall/Status)
├── scripts/
│   └── stability-monitor.sh  # Background Loop (Keepalive/Time)
└── www/
    └── stability.asp     # Web UI Source
```

**Hooks Deployed to `/jffs/scripts/`:**
- `firewall-start`: Applies Mangle rules & NAT66.
- `wan-event`: Detects USB disconnects.
- `service-event`: Handles Web UI restarts.
- `services-start`: Launches the background monitor.

## ⚙️ Configuration

Settings are stored in `/jffs/addons/custom_settings.txt`. You can edit them manually or via the Web UI (future feature).

```properties
stability_enabled=1
stability_ttl_ipv4=65
stability_hl_ipv6=65
stability_mtu=1428
stability_profile=iphone-usb
stability_time_preservation=1
```

## ⚠️ Critical Notes for GT-AX6000
- **Interface Naming**: The addon automatically detects if the tethered phone is on `usb0` or `eth8`.
- **Kernel Modules**: It loads `ip6table_nat` and `xt_HL` which are required for Tethering but often unloaded.
- **Dependencies**: Requires `iptables-mod-ipopt`, `kmod-ipt-nat6`, `fping`. These are installed automatically via `opkg`.

---
*Developed for the ASUSWRT-Merlin HND Platform.*
