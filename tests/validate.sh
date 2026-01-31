#!/bin/sh
# Pre-commit validation script
# Runs all validation checks before allowing commit

set -e

VALIDATION_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$VALIDATION_ROOT"

log_section() {
    echo ""
    echo "=== $1 ==="
}

log_ok() {
    echo "✓ $1"
}

log_error() {
    echo "✗ $1" >&2
}

# 1. ShellCheck validation
log_section "ShellCheck Validation"
if command -v shellcheck >/dev/null 2>&1; then
    find src tests -name '*.sh' -type f | while read -r file; do
        if shellcheck "$file"; then
            log_ok "$file"
        else
            log_error "ShellCheck failed: $file"
            exit 1
        fi
    done
else
    log_error "shellcheck not installed, skipping"
fi

# 2. Syntax validation
log_section "Shell Syntax Validation"
find src tests install -name '*.sh' -type f -o -name 'netadmin' -o -name '*-event' -o -name '*-start' | while read -r file; do
    if sh -n "$file" 2>/dev/null; then
        log_ok "$file"
    else
        log_error "Syntax error: $file"
        exit 1
    fi
done

# 3. Run unit tests
log_section "Unit Tests"
if command -v shellspec >/dev/null 2>&1; then
    if shellspec tests/spec/*_spec.sh; then
        log_ok "All unit tests passed"
    else
        log_error "Unit tests failed"
        exit 1
    fi
else
    log_error "shellspec not installed, run: tests/setup.sh"
    exit 1
fi

# 4. Documentation links
log_section "Documentation Link Check"
find . -name '*.md' -type f | while read -r file; do
    # Check for broken internal links
    grep -oE '\[.*\]\([^)]+\)' "$file" | grep -oE '\([^)]+\)' | tr -d '()' | while read -r link; do
        if [[ "$link" == ./* ]] || [[ "$link" == /* ]]; then
            if [ ! -f "$link" ] && [ ! -d "$link" ]; then
                log_error "Broken link in $file: $link"
                exit 1
            fi
        fi
    done
    log_ok "$file"
done

# 5. VERSION file consistency
log_section "Version Consistency"
if [ -f VERSION ]; then
    version=$(cat VERSION)
    # Check if version appears in key files
    if grep -q "$version" README.md && grep -q "$version" CHANGELOG.md; then
        log_ok "Version $version consistent across files"
    else
        log_error "Version mismatch detected"
        exit 1
    fi
fi

log_section "Validation Complete"
echo "✓ All checks passed - ready to commit"
