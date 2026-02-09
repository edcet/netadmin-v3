# Netadmin v3 + Stability Framework v2.0

**Production-Grade WAN Management & Tethering Cloak for ASUS GT-AX6000**

This repository contains two complementary frameworks for the ASUS GT-AX6000 (HND Platform):
1.  **Netadmin v3**: A robust WAN state management and profile system (Safe, Verizon, Verizon Bypass).
2.  **Stability Framework v2.0**: A canonical ASUSWRT-Merlin Addon for USB Tethering Cloaking (TTL/HL/MSS/NAT66) and System Monitoring (USB Keepalive, Time Preservation).

## 🚀 Stability Framework v2.0 (New!)
The Stability Framework is a dedicated addon that transforms your router into a stealth tethering appliance. It handles TTL normalization, MSS clamping, and IPv6 NAT66 to bypass hotspot detection, while ensuring connection stability through active monitoring.

### Key Features
- **Tether Cloak**: IPv4 TTL=65, IPv6 HL=65, MSS Clamping (MTU-40/60), NAT66.
- **System Stability**: USB Keepalive (ping check + reset), Time Preservation (flash anchor), USB Flap Handling.
- **Canonical Integration**: Native Merlin Web UI (`Tools` -> `Stability Framework`), standard hooks (`firewall-start`, `wan-event`).

### Installation
Upload `src/addons/stability/stability.sh` to your router:

```sh
scp src/addons/stability/stability.sh admin@192.168.50.1:/jffs/addons/
ssh admin@192.168.50.1
chmod +x /jffs/addons/stability.sh
/jffs/addons/stability.sh install
```

Access the Web UI at: `http://192.168.50.1/user/stability.asp`

---

## 🌐 Netadmin v3 (Core)
Netadmin is the foundational WAN management system.

### Features
- **State Machine**: Monitors WAN health and transitions between states (INIT -> ACTIVE -> DEGRADED).
- **Hardware Acceleration Control**: Automatically manages CTF/Flow Cache based on active profiles.
- **Profiles**:
    - `safe`: Standard routing, full acceleration.
    - `verizon`: Basic TTL spoofing.
    - `verizon-bypass`: Full DPI bypass with Zapret (if installed).

### Installation
```bash
curl -fsSL https://github.com/edcet/netadmin-v3/releases/download/latest/install.sh | sh
```

## 📂 Repository Structure
```
src/
├── addons/
│   └── stability/       # Stability Framework v2.0 (Canonical Addon)
│       ├── stability.sh # Manager Script
│       ├── scripts/     # Hooks & Monitor
│       └── www/         # Web UI
├── core/                # Netadmin Core Logic
├── hooks/               # Netadmin Hooks
└── profiles/            # Netadmin Profiles
```

## ⚠️ Compatibility Note
If installing both, the **Stability Framework** will manage `firewall-start` rules for Tether Cloaking. Netadmin profiles can be used alongside it to manage hardware acceleration (CTF/FC) settings.
