#!/bin/sh
# Test Environment Setup
# Installs shellspec and prepares test environment

set -e

SHELLSPEC_VERSION="0.28.1"
TEST_ROOT="$(cd "$(dirname "$0")" && pwd)"

log_info() {
    echo "[*] $1"
}

log_ok() {
    echo "✓ $1"
}

log_error() {
    echo "✗ $1" >&2
}

install_shellspec() {
    log_info "Installing shellspec v$SHELLSPEC_VERSION..."

    if command -v shellspec >/dev/null 2>&1; then
        local current_version
        current_version="$(shellspec --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
        if [ "$current_version" = "$SHELLSPEC_VERSION" ]; then
            log_ok "shellspec v$SHELLSPEC_VERSION already installed"
            return 0
        fi
    fi

    # Install to local bin
    local install_dir="$TEST_ROOT/../.local/bin"
    mkdir -p "$install_dir"

    # Download shellspec
    local tmpdir="/tmp/shellspec-install-$$"
    mkdir -p "$tmpdir"
    cd "$tmpdir"

    if command -v wget >/dev/null 2>&1; then
        wget -q "https://github.com/shellspec/shellspec/archive/${SHELLSPEC_VERSION}.tar.gz"
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${SHELLSPEC_VERSION}.tar.gz" \
            "https://github.com/shellspec/shellspec/archive/${SHELLSPEC_VERSION}.tar.gz"
    else
        log_error "wget or curl required"
        return 1
    fi

    tar -xzf "${SHELLSPEC_VERSION}.tar.gz"
    cd "shellspec-${SHELLSPEC_VERSION}"

    # Install
    make install PREFIX="$TEST_ROOT/../.local"

    # Add to PATH
    export PATH="$install_dir:$PATH"

    # Cleanup
    cd /
    rm -rf "$tmpdir"

    log_ok "shellspec v$SHELLSPEC_VERSION installed"
}

setup_mocks() {
    log_info "Setting up mock commands..."

    local mock_dir="$TEST_ROOT/mocks"

    # Verify mocks exist
    for mock in nvram iptables ip logger; do
        if [ ! -f "$mock_dir/$mock" ]; then
            log_error "Mock missing: $mock"
            return 1
        fi
        chmod +x "$mock_dir/$mock"
    done

    log_ok "Mock commands ready"
}

setup_fixtures() {
    log_info "Preparing test fixtures..."

    local fixture_dir="$TEST_ROOT/fixtures"

    # Create fixture directories
    mkdir -p "$fixture_dir/nvram"
    mkdir -p "$fixture_dir/state"
    mkdir -p "$fixture_dir/health"

    # Generate fixture data if not exists
    if [ ! -f "$fixture_dir/nvram/clean_boot.txt" ]; then
        cat > "$fixture_dir/nvram/clean_boot.txt" << 'EOF'
netadmin_mode=safe
netadmin_state=0
netadmin_ttl_mode=off
netadmin_zapret=0
ctf_disable=0
fc_disable=0
runner_disable_force=0
EOF
    fi

    if [ ! -f "$fixture_dir/state/active.state" ]; then
        echo "3" > "$fixture_dir/state/active.state"
    fi

    if [ ! -f "$fixture_dir/health/healthy.json" ]; then
        cat > "$fixture_dir/health/healthy.json" << 'EOF'
{
  "interface": "eth0",
  "carrier_up": 1,
  "ip_acquired": "192.168.100.5",
  "default_route": 1,
  "gateway_reachable": 1,
  "tcp_health": 1,
  "ready": 1,
  "state": "ACTIVE",
  "timestamp": "2026-01-31T17:18:00Z"
}
EOF
    fi

    log_ok "Fixtures prepared"
}

verify_environment() {
    log_info "Verifying test environment..."

    # Check required commands
    for cmd in sh grep sed awk; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Required command missing: $cmd"
            return 1
        fi
    done

    # Check shellspec
    if ! command -v shellspec >/dev/null 2>&1; then
        log_error "shellspec not in PATH"
        return 1
    fi

    # Check test specs exist
    if [ ! -f "$TEST_ROOT/spec/state_machine_spec.sh" ]; then
        log_error "Test specs missing"
        return 1
    fi

    log_ok "Environment verified"
}

show_summary() {
    cat << EOF

========================================
Test Environment Ready
========================================

Run tests:
  make test              # All tests
  make test-unit         # Unit tests only
  make test-integration  # Integration tests

Or directly:
  shellspec tests/spec/
  shellspec tests/spec/state_machine_spec.sh

Mock commands available in: $TEST_ROOT/mocks/
Fixtures available in: $TEST_ROOT/fixtures/

EOF
}

main() {
    echo "netadmin v3.0 Test Environment Setup"
    echo "====================================="
    echo ""

    install_shellspec || exit 1
    setup_mocks || exit 1
    setup_fixtures || exit 1
    verify_environment || exit 1
    show_summary

    log_ok "Setup complete"
}

main "$@"
