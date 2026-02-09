# Contributing to netadmin v3.0

## Commit Message Format

We use Conventional Commits for semantic versioning:

```
type(scope): subject

body

footer
```

### Types
- `feat`: New feature (→ minor version bump)
- `fix`: Bug fix (→ patch version bump)
- `perf`: Performance improvement (→ patch version bump)
- `refactor`: Code refactoring with no behavior change
- `docs`: Documentation only
- `test`: Test additions or fixes
- `ci`: CI/CD pipeline changes
- `chore`: Build or dependency updates

### Examples

```
feat(state-machine): add timeout protection for WAN_WAIT state

Implements automatic fallback to SAFE profile after 60s
without IP acquisition. Prevents indefinite hangs on DHCP
failure.

Fixes #42
```

```
fix(hardware-accel): detect Runner acceleration correctly

Previously checking 'runner_disable' but should check
'runner_disable_force'. Now correctly identifies when
Runner is active.
```

## Pull Request Process

1. Create feature branch from `develop`
2. Make changes with descriptive commit messages
3. Run `make test` locally
4. Push and create PR against `develop`
5. Ensure all CI checks pass
6. Request review from maintainers
7. After approval, squash and merge to `develop`
8. When ready, PR from `develop` → `main` to trigger release

## Testing Requirements

- All new code must have unit tests (shellspec)
- Integration tests required for state machine changes
- Performance benchmarks for throughput-affecting changes
- ShellCheck must pass with no warnings

## Code Style

```bash
# Use functions liberally
my_function() {
    local var1="$1"  # Always quote
    local var2="$2"

    # Use [[ ]] in bash, [ ] in POSIX
    if [ "$var1" = "value" ]; then
        echo "match"
    fi
}

# Proper error handling
set -e  # Exit on error
set -u  # Exit on undefined variable

# Use || true for expected failures
some_command || true

# Always use local in functions
function_using_var() {
    local result
    result="$(command)"
    echo "$result"
}
```

## Issue Reporting

Include:
- Router model (e.g., GT-AX6000)
- Merlin firmware version
- Current netadmin version
- Steps to reproduce
- Expected vs. actual behavior
- Relevant logs from `/tmp/netadmin_*`
