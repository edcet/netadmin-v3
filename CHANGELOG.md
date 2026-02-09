# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/en/2.0.0.html).

## [3.0.0] - 2026-01-31

### Added
- Complete state machine implementation (6-state model with timeout protection)
- Hardware acceleration gatekeeper (CTF/FC/Runner detection and validation)
- TCP health validation beyond ICMP ping for blackhole WAN detection
- Boot-time fallback mechanism (auto-recovery from bad rules)
- DHCP lifecycle integration (wan-event, dhcpc-event hooks)
- Comprehensive WAN monitoring with JSON export
- Multi-profile system (safe, verizon, verizon-bypass)
- Full CLI interface with operational commands
- Semantic versioning and automated releases
- GitHub Actions CI/CD pipeline (lint, test, release, publish)
- GHCR container publishing
- Complete test suite (shellspec unit + integration tests)
- Observability: state machine logging, health metrics
- Safe upgrade path from v2.1 with automatic migration
- Rollback mechanism for emergency recovery
- Docker support for containerized deployment
- Comprehensive documentation (architecture, performance, troubleshooting, API)

### Changed
- Migrated from reactive v2.1 to predictive v3.0 state machine
- Refactored WAN monitoring with TCP-level checks
- Improved performance (~1% CPU overhead reduction)
- Enhanced logging with state transition tracking

### Fixed
- Boot loop protection with 3-attempt watchdog
- Race conditions in rule application
- DHCP renewal handling
- Hardware acceleration conflicts with DPI bypass

## [2.1.0] - Earlier

See git history for v2.1 changes.
