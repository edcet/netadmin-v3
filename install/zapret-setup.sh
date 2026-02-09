#!/bin/sh
# Zapret DPI Bypass Setup
# Downloads, compiles, and installs zapret for ASUSWRT-Merlin

set -e

ZAPRET_VERSION="v67"
ZAPRET_REPO="https://github.com/bol-van/zapret"
INSTALL_DIR="/jffs/bin"
ZAPRET_DIR="/jffs/zapret"
BUILD_DIR="/tmp/zapret-build-$$"

log_info() {
    echo "[*] $1"
}

log_ok() {
    echo "✓ $1"
}

log_error() {
    echo "✗ $1" >&2
}

detect_architecture() {
    local arch
    arch="$(uname -m)"

    case "$arch" in
        aarch64|arm64)
            echo "aarch64"
            ;;
        armv7l|armv7)
            echo "armv7"
            ;;
        x86_64|amd64)
            echo "x86_64"
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check for required tools
    for tool in gcc make git; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            log_error "Install Entware: opkg install $tool"
            return 1
        fi
    done

    log_ok "Prerequisites satisfied"
}

download_zapret() {
    log_info "Downloading zapret $ZAPRET_VERSION..."

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if command -v git >/dev/null 2>&1; then
        git clone --depth 1 --branch "$ZAPRET_VERSION" "$ZAPRET_REPO" zapret
    else
        # Fallback to tarball
        local tarball="${ZAPRET_VERSION}.tar.gz"
        if command -v wget >/dev/null 2>&1; then
            wget -q "${ZAPRET_REPO}/archive/refs/tags/${tarball}"
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL -o "$tarball" "${ZAPRET_REPO}/archive/refs/tags/${tarball}"
        else
            log_error "git, wget, or curl required"
            return 1
        fi
        tar -xzf "$tarball"
        mv "zapret-${ZAPRET_VERSION#v}" zapret
    fi

    cd zapret
    log_ok "Downloaded zapret $ZAPRET_VERSION"
}

build_zapret() {
    log_info "Building zapret for $(detect_architecture)..."

    cd "$BUILD_DIR/zapret"

    # Build nfqws (main binary)
    cd nfqws

    # Set compiler flags for embedded ARM
    export CFLAGS="-O2 -march=native -mtune=native"
    export LDFLAGS="-s"

    if make; then
        log_ok "nfqws built successfully"
    else
        log_error "Build failed"
        return 1
    fi

    # Verify binary
    if [ -f nfqws ]; then
        chmod +x nfqws
        log_ok "Binary ready: $(ls -lh nfqws | awk '{print $5}')"
    else
        log_error "Binary not found after build"
        return 1
    fi
}

install_zapret() {
    log_info "Installing zapret..."

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$ZAPRET_DIR/lists"

    # Install binary
    cp "$BUILD_DIR/zapret/nfqws/nfqws" "$INSTALL_DIR/nfqws"
    chmod +x "$INSTALL_DIR/nfqws"
    log_ok "Installed nfqws to $INSTALL_DIR"

    # Install helper scripts
    if [ -d "$BUILD_DIR/zapret/init.d" ]; then
        cp -r "$BUILD_DIR/zapret/init.d" "$ZAPRET_DIR/"
    fi

    # Create default lists directory
    cat > "$ZAPRET_DIR/lists/README.txt" << 'EOF'
Zapret Domain Lists
===================

Place domain lists here for selective DPI bypass.

Examples:
- verizon-throttled.txt: Domains throttled by Verizon
- streaming-services.txt: Video streaming domains

Format: One domain per line
  example.com
  *.youtube.com
  reddit.com
EOF

    log_ok "Zapret installed to $ZAPRET_DIR"
}

cleanup_build() {
    log_info "Cleaning up build directory..."
    cd /
    rm -rf "$BUILD_DIR"
    log_ok "Cleanup complete"
}

verify_installation() {
    log_info "Verifying installation..."

    if [ -x "$INSTALL_DIR/nfqws" ]; then
        local version
        version="$($INSTALL_DIR/nfqws --help 2>&1 | head -1 || echo 'unknown')"
        log_ok "nfqws installed: $version"
    else
        log_error "nfqws not executable"
        return 1
    fi

    if [ -d "$ZAPRET_DIR" ]; then
        log_ok "Zapret directory created"
    else
        log_error "Zapret directory missing"
        return 1
    fi
}

show_usage() {
    cat << EOF

Zapret Installation Complete
============================

Binary: $INSTALL_DIR/nfqws
Config: $ZAPRET_DIR/

Usage:
  netadmin profile verizon-bypass    # Enable DPI bypass
  netadmin profile safe              # Disable DPI bypass

Advanced:
  # Test nfqws manually
  $INSTALL_DIR/nfqws --help

  # Add custom domain lists
  echo 'youtube.com' >> $ZAPRET_DIR/lists/streaming.txt

Note: verizon-bypass profile will automatically start/stop nfqws.

EOF
}

main() {
    echo "Zapret DPI Bypass Setup"
    echo "======================="
    echo ""

    check_prerequisites || exit 1
    download_zapret || exit 1
    build_zapret || exit 1
    install_zapret || exit 1
    cleanup_build
    verify_installation || exit 1
    show_usage

    log_ok "Zapret setup complete"
}

main "$@"
