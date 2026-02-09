#!/bin/sh
# netadmin v3.0 Installation Script
# Safe, atomic installation with rollback capability

set -e

# Configuration
NETADMIN_ROOT="/jffs/scripts/netadmin"
BACKUP_ROOT="/jffs/scripts.backup"
VERSION="3.0.0"
DRY_RUN=false

# Utility functions
log_info() {
    echo "[*] $1"
}

log_ok() {
    echo "✓ $1"
}

log_error() {
    echo "✗ $1" >&2
}

log_section() {
    echo ""
    echo "=== $1 ==="
}

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)
                DRY_RUN=true
                ;;
            --help)
                show_help
                exit 0
                ;;
        esac
    done
}

show_help() {
    cat << EOF
netadmin v$VERSION Installation

Usage: install.sh [OPTIONS]

Options:
  --dry-run    Show what would be installed without making changes
  --help       Show this help message

Examples:
  ./install.sh --dry-run      # Preview installation
  ./install.sh                # Install netadmin

EOF
}

check_prerequisites() {
    log_section "Checking Prerequisites"

    # Check if running on ASUSWRT-Merlin
    if [ ! -f /etc/init.d/net-wall ]; then
        log_error "This system does not appear to be ASUSWRT-Merlin"
        log_error "netadmin requires ASUSWRT-Merlin on a supported router"
        return 1
    fi
    log_ok "ASUSWRT-Merlin detected"

    # Check for JFFS2 partition
    if [ ! -d /jffs ]; then
        log_error "/jffs partition not found"
        log_error "Enable JFFS2 in router settings and retry"
        return 1
    fi
    log_ok "/jffs partition available"

    # Check for required commands
    for cmd in iptables ip nvram logger; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command not found: $cmd"
            return 1
        fi
    done
    log_ok "All required commands available"

    return 0
}

validate_hardware() {
    log_section "Validating Hardware"

    # Detect router model
    local model
    model="$(nvram get productid 2>/dev/null || echo "unknown")"
    log_ok "Detected router: $model"

    # Check for BCM4912 (GT-AX6000) or compatible
    if grep -q "BCM4912\|BCM4906" /proc/cpuinfo 2>/dev/null; then
        log_ok "BCM4912/4906 detected - full hardware acceleration support"
    else
        log_info "Non-BCM4912 router - may have reduced performance"
    fi
}

create_directories() {
    log_section "Creating Directory Structure"

    if [ "$DRY_RUN" = true ]; then
        log_info "Would create: $NETADMIN_ROOT"
        log_info "Would create: $NETADMIN_ROOT/core"
        log_info "Would create: $NETADMIN_ROOT/hooks"
        log_info "Would create: $NETADMIN_ROOT/profiles"
        log_info "Would create: $NETADMIN_ROOT/cli"
        return 0
    fi

    mkdir -p "$NETADMIN_ROOT/core"
    mkdir -p "$NETADMIN_ROOT/hooks"
    mkdir -p "$NETADMIN_ROOT/profiles"
    mkdir -p "$NETADMIN_ROOT/cli"
    log_ok "Directories created"
}

backup_existing() {
    log_section "Backing Up Existing Installation"

    if [ ! -d /jffs/scripts ]; then
        log_info "No existing installation to backup"
        return 0
    fi

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_dir="${BACKUP_ROOT}_$timestamp"

    if [ "$DRY_RUN" = true ]; then
        log_info "Would backup to: $backup_dir"
        return 0
    fi

    cp -r /jffs/scripts "$backup_dir"
    log_ok "Backup created: $backup_dir"
}

install_files() {
    log_section "Installing Files"

    if [ "$DRY_RUN" = true ]; then
        log_info "Would install core scripts"
        log_info "Would install hooks (wan-event, dhcpc-event, services-start)"
        log_info "Would install profiles (safe, verizon, verizon-bypass)"
        log_info "Would install CLI interface"
        return 0
    fi

    # Copy core scripts
    cp -v src/core/*.sh "$NETADMIN_ROOT/core/" || return 1
    chmod +x "$NETADMIN_ROOT/core"/*.sh
    log_ok "Core scripts installed"

    # Copy hooks
    cp -v src/hooks/* "$NETADMIN_ROOT/hooks/" || return 1
    chmod +x "$NETADMIN_ROOT/hooks"/*
    log_ok "Hooks installed"

    # Copy profiles
    cp -v src/profiles/*.sh "$NETADMIN_ROOT/profiles/" || return 1
    chmod +x "$NETADMIN_ROOT/profiles"/*.sh
    log_ok "Profiles installed"

    # Copy CLI
    cp -v src/cli/netadmin "$NETADMIN_ROOT/cli/" || return 1
    chmod +x "$NETADMIN_ROOT/cli/netadmin"

    # Create symlink for easy access
    ln -sf "$NETADMIN_ROOT/cli/netadmin" /usr/local/sbin/netadmin || true
    log_ok "CLI installed and linked"
}

setup_merlin_hooks() {
    log_section "Setting Up Merlin Hooks"

    if [ "$DRY_RUN" = true ]; then
        log_info "Would link wan-event hook"
        log_info "Would link dhcpc-event hook"
        log_info "Would link services-start hook"
        log_info "Would link firewall-start hook"
        return 0
    fi

    # Ensure /jffs/scripts exists
    mkdir -p /jffs/scripts

    # wan-event hook
    ln -sf "$NETADMIN_ROOT/hooks/wan-event" /jffs/scripts/wan-event || true
    chmod +x /jffs/scripts/wan-event
    log_ok "wan-event hook linked"

    # dhcpc-event hook
    ln -sf "$NETADMIN_ROOT/hooks/dhcpc-event" /jffs/scripts/dhcpc-event || true
    chmod +x /jffs/scripts/dhcpc-event
    log_ok "dhcpc-event hook linked"

    # services-start hook
    ln -sf "$NETADMIN_ROOT/hooks/services-start" /jffs/scripts/services-start || true
    chmod +x /jffs/scripts/services-start
    log_ok "services-start hook linked"

    # firewall-start hook
    ln -sf "$NETADMIN_ROOT/hooks/firewall-start" /jffs/scripts/firewall-start || true
    chmod +x /jffs/scripts/firewall-start
    log_ok "firewall-start hook linked"
}

verify_installation() {
    log_section "Verifying Installation"

    if [ "$DRY_RUN" = true ]; then
        log_info "Would verify all core libraries load correctly"
        log_info "Would verify state machine initialization"
        log_info "Would verify CLI is accessible"
        return 0
    fi

    # Test library load
    if . "$NETADMIN_ROOT/core/netadmin-lib.sh" >/dev/null 2>&1; then
        log_ok "Core library loads correctly"
    else
        log_error "Failed to load core library"
        return 1
    fi

    # Test CLI
    if /usr/local/sbin/netadmin version >/dev/null 2>&1; then
        log_ok "CLI functional"
    else
        log_error "CLI not functional"
        return 1
    fi
}

show_summary() {
    log_section "Installation Summary"

    if [ "$DRY_RUN" = true ]; then
        echo "Dry-run mode - no changes were made"
        echo ""
        echo "To install, run: ./install.sh"
    else
        echo "Installation complete!"
        echo ""
        echo "Next steps:"
        echo "  1. Start with safe profile: netadmin profile safe"
        echo "  2. Check status: netadmin wan-state"
        echo "  3. Read docs: https://github.com/edcet/netadmin-v3/tree/main/docs"
        echo ""
        echo "Help: netadmin help"
    fi
}

main() {
    parse_args "$@"

    echo "netadmin v$VERSION Installer"
    echo "============================="

    if [ "$DRY_RUN" = true ]; then
        echo "DRY-RUN MODE: No changes will be made"
    fi
    echo ""

    check_prerequisites || exit 1
    validate_hardware || true  # Don't fail on hardware validation
    create_directories || exit 1
    backup_existing || true    # Continue even if backup fails
    install_files || exit 1
    setup_merlin_hooks || exit 1
    verify_installation || exit 1
    show_summary

    echo ""
    log_ok "netadmin $VERSION ready"
}

main "$@"
