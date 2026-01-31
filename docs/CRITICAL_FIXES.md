# Critical Fixes - v3.0.1

This document details critical bugs fixed in the initial v3.0 release.

## Shell Scripting Issues

### 1. httpd Backgrounding Bug

**Problem:**
```bash
httpd -p "$METRICS_PORT" -h "$metrics_dir" -f
echo $! > "$httpd_pid"
```

- The `-f` flag runs httpd in **foreground**
- `$!` captures the PID of `echo`, not `httpd`
- Result: Wrong PID written to file, can't stop server

**Fix:**
```bash
httpd -p "$METRICS_PORT" -h "$metrics_dir" &
local pid=$!
echo "$pid" > "$httpd_pid"
```

### 2. stat Command Portability

**Problem:**
```bash
stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null
```

- GNU stat uses `-c`
- BSD stat uses `-f`
- BusyBox stat may not support either
- Result: Uptime calculation fails on ASUSWRT-Merlin

**Fix:**
```bash
if file_time="$(stat -c %Y "$file" 2>/dev/null)"; then
    : # GNU worked
elif file_time="$(stat -f %m "$file" 2>/dev/null)"; then
    : # BSD worked
elif file_time="$(date -r "$file" +%s 2>/dev/null)"; then
    : # BusyBox date -r worked
else
    file_time="$now"  # Fallback
fi
```

### 3. echo -e Non-Portability

**Problem:**
```bash
echo -e "metric1\nmetric2\n"
```

- `-e` flag is **not POSIX**
- BusyBox's built-in `echo` behavior varies by configuration
- May print literal `\n` instead of newlines
- Result: Malformed Prometheus metrics

**Fix:**
```bash
printf "metric1\n"
printf "metric2\n"
```

### 4. JSON Parsing Fragility

**Problem:**
```bash
ready="$(grep '"ready"' "$file" | grep -oE '[0-9]+')"
```

- Captures **any** digit, including from field names
- Example: `"ready_time": 123` would match `123`
- Result: Wrong value extracted

**Fix:**
```bash
ready="$(grep '"ready"' "$file" | grep -oE '[01]' | tail -1)"
```
- Only match valid boolean values (0 or 1)
- Use `tail -1` to get last match (the actual value)

### 5. Missing Error Handling

**Problem:**
```bash
mv "$METRICS_FILE.tmp" "$METRICS_FILE"
```

- No check if move succeeded
- Orphaned `.tmp` files on failure
- Stale metrics served

**Fix:**
```bash
mv "$METRICS_FILE.tmp" "$METRICS_FILE" || {
    log_error "Failed to write metrics file"
    rm -f "$METRICS_FILE.tmp"
    return 1
}
```

## Impact Analysis

### High Severity

1. **httpd backgrounding** - Metrics endpoint unusable
2. **echo -e** - Prometheus scraping fails

### Medium Severity

3. **stat portability** - Uptime metric always 0
4. **JSON parsing** - Wrong health metrics

### Low Severity

5. **Error handling** - Orphaned temp files

## Testing Checklist

### Metrics Export

```bash
# Export metrics
netadmin metrics export
cat /tmp/netadmin_metrics.txt
# Verify: All metrics present, no literal \n, values correct

# Start HTTP server
netadmin metrics start-http
netstat -tlnp | grep 8080
# Verify: PID matches, server listening

# Scrape endpoint
curl http://router:8080/metrics
# Verify: Valid Prometheus format

# Stop server
netadmin metrics stop-http
netstat -tlnp | grep 8080
# Verify: Port released
```

### Uptime Calculation

```bash
# Check uptime
netadmin metrics show | grep uptime
# Verify: Non-zero value after first boot

# Check file timestamp
ls -l /tmp/netadmin_state
date +%s
# Calculate manually and compare
```

### Zapret Metrics

```bash
# Start zapret
sh /jffs/scripts/netadmin/core/zapret-manager.sh start

# Export metrics
sh /jffs/scripts/netadmin/core/zapret-manager.sh metrics
# Verify: netadmin_zapret_running 1

# Check format
sh /jffs/scripts/netadmin/core/zapret-manager.sh metrics | od -c
# Verify: Actual \n characters (0x0a), not literal \\n
```

### Health JSON Parsing

```bash
# Create test JSON with edge cases
cat > /tmp/netadmin_health.json << 'EOF'
{
  "ready": 1,
  "ready_time": 123,
  "carrier_up": 0,
  "ip_acquired": "null"
}
EOF

# Export metrics
netadmin metrics export
grep 'netadmin_wan' /tmp/netadmin_metrics.txt
# Verify: ready=1, carrier=0, ip_acquired=0 (not 123!)
```

## Validation

### Pre-Deployment

1. Run shellcheck on all modified scripts
2. Test on actual ASUSWRT-Merlin router
3. Verify Prometheus scrapes successfully
4. Check syslog for errors

### Post-Deployment

1. Monitor Prometheus targets page
2. Verify Grafana dashboard updates
3. Check AlertManager for false alerts
4. Review router syslog for warnings

## Lessons Learned

### Shell Scripting Best Practices

1. **Always test backgrounding**: `cmd &; pid=$!` pattern
2. **Use printf over echo**: POSIX compliance
3. **Handle platform differences**: Provide fallbacks
4. **Validate assumptions**: Test JSON parsing with edge cases
5. **Error handling**: Every critical operation needs checks

### Router-Specific Considerations

1. **BusyBox limitations**: Not all GNU tools available
2. **No package managers**: Can't install better tools
3. **Limited debugging**: No strace, gdb, etc.
4. **NVRAM fragility**: Always commit after sets
5. **Firmware updates**: Test across versions

## References

- [POSIX Shell Specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)
- [BusyBox Command Reference](https://busybox.net/downloads/BusyBox.html)
- [Prometheus Text Format](https://prometheus.io/docs/instrumenting/exposition_formats/)
- [ASUSWRT-Merlin Wiki](https://github.com/RMerl/asuswrt-merlin.ng/wiki)
