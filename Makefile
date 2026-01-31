# netadmin v3.0 Makefile
# Development and testing tasks

.PHONY: help test test-unit test-integration test-setup validate lint clean install

help:
	@echo "netadmin v3.0 Development Tasks"
	@echo "================================"
	@echo ""
	@echo "Testing:"
	@echo "  make test              Run all tests"
	@echo "  make test-unit         Run unit tests only"
	@echo "  make test-integration  Run integration tests"
	@echo "  make test-setup        Setup test environment"
	@echo ""
	@echo "Validation:"
	@echo "  make validate          Run pre-commit validation"
	@echo "  make lint              Run ShellCheck"
	@echo ""
	@echo "Installation:"
	@echo "  make install           Install netadmin (requires root)"
	@echo "  make install-zapret    Install zapret DPI bypass"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean             Remove build artifacts"

test-setup:
	@echo "Setting up test environment..."
	sh tests/setup.sh

test-unit: test-setup
	@echo "Running unit tests..."
	PATH="tests/mocks:$$PATH" shellspec tests/spec/*_spec.sh

test-integration: test-setup
	@echo "Running integration tests..."
	PATH="tests/mocks:$$PATH" shellspec tests/spec/integration_spec.sh

test: test-unit test-integration
	@echo "✓ All tests passed"

lint:
	@echo "Running ShellCheck..."
	@find src tests install -name '*.sh' -type f -o -name 'netadmin' | xargs shellcheck

validate:
	@echo "Running validation checks..."
	sh tests/validate.sh

install:
	@echo "Installing netadmin v3.0..."
	@if [ "$$(id -u)" != "0" ]; then \
		echo "ERROR: Must run as root"; \
		exit 1; \
	fi
	sh install/install.sh

install-zapret:
	@echo "Installing zapret DPI bypass..."
	@if [ "$$(id -u)" != "0" ]; then \
		echo "ERROR: Must run as root"; \
		exit 1; \
	fi
	sh install/zapret-setup.sh

clean:
	@echo "Cleaning build artifacts..."
	rm -rf .local/
	rm -f /tmp/nvram_mock_*
	rm -f /tmp/iptables_mock_*
	rm -f /tmp/ip_mock_*
	rm -f /tmp/mock_syslog_*
	@echo "✓ Clean complete"
