.PHONY: help install-dev test lint test-router release clean

HELP_INDENT = 15

help: ## Show this help message
	@echo "netadmin v3.0 Development Targets"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-$(HELP_INDENT)s %s\n", $$1, $$2}'

install-dev: ## Install development dependencies
	@echo "Installing dev dependencies..."
	@command -v shellspec >/dev/null 2>&1 || npm install -g shellspec
	@command -v shellcheck >/dev/null 2>&1 || brew install shellcheck || apt-get install shellcheck
	@echo "Done."

lint: ## Run ShellCheck on all scripts
	@echo "Linting scripts..."
	@find src tests -name '*.sh' -type f | xargs shellcheck --config=.shellcheckrc
	@echo "✓ Lint passed"

test: lint ## Run all tests (lint + unit + integration)
	@echo "Running tests..."
	@shellspec -f d

test-router: ## Run tests in BusyBox container (simulated router)
	@echo "Running tests in router environment..."
	@docker run --rm -v $(PWD):/netadmin busybox:latest \
		/bin/sh -c 'cd /netadmin && shellspec -f d'

release: clean lint test ## Build release artifacts
	@echo "Building release..."
	@mkdir -p dist/
	@tar -czf dist/netadmin-v3.tar.gz src/ install/ docs/
	@echo "✓ Release built: dist/netadmin-v3.tar.gz"

clean: ## Clean build artifacts
	@rm -rf dist/
	@echo "✓ Cleaned"
