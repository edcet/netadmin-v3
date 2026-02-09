# netadmin v3.0 Observability Guide

This document explains how to monitor netadmin using Prometheus, Grafana, and AlertManager.

## Metrics Export

### Enabling Metrics

```bash
# Export metrics once (updates /tmp/netadmin_metrics.txt)
netadmin metrics export

# Start HTTP server for Prometheus scraping
netadmin metrics start-http
# Accessible at: http://router-ip:8080/metrics
```

### Available Metrics

| Metric | Type | Description |
|--------|------|-------------|
| `netadmin_state_current` | Gauge | State machine state (0-5) |
| `netadmin_wan_ready` | Gauge | WAN readiness (0=down, 1=ready) |
| `netadmin_wan_carrier` | Gauge | Carrier status (0=down, 1=up) |
| `netadmin_wan_ip_acquired` | Gauge | IP acquired (0=no, 1=yes) |
| `netadmin_wan_gateway_reachable` | Gauge | Gateway reachable (0=no, 1=yes) |
| `netadmin_wan_tcp_health` | Gauge | TCP health (0=fail, 1=pass) |
| `netadmin_hardware_ctf_enabled` | Gauge | CTF status (0=off, 1=on) |
| `netadmin_hardware_fc_enabled` | Gauge | Flow Cache status |
| `netadmin_hardware_runner_enabled` | Gauge | Runner status |
| `netadmin_boot_attempts` | Counter | Boot failure counter |
| `netadmin_zapret_running` | Gauge | Zapret status (0=stopped, 1=running) |
| `netadmin_uptime_seconds` | Counter | Uptime since initialization |
| `netadmin_profile_*` | Gauge | Active profile indicators |

### Example Metrics Output

```prometheus
# HELP netadmin_state_current Current state machine state (0-5)
# TYPE netadmin_state_current gauge
netadmin_state_current{state="ACTIVE"} 3

# HELP netadmin_wan_ready WAN readiness (0=down, 1=ready)
# TYPE netadmin_wan_ready gauge
netadmin_wan_ready 1

netadmin_wan_carrier 1
netadmin_wan_ip_acquired 1
netadmin_wan_gateway_reachable 1
netadmin_wan_tcp_health 1

netadmin_hardware_ctf_enabled 0
netadmin_hardware_fc_enabled 0
netadmin_hardware_runner_enabled 1

netadmin_boot_attempts 0
netadmin_zapret_running 1
netadmin_uptime_seconds 3600

netadmin_profile_safe 0
netadmin_profile_verizon 0
netadmin_profile_verizon_bypass 1
```

## Prometheus Configuration

### Scrape Config

Add to `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'netadmin'
    static_configs:
      - targets: ['router-ip:8080']
        labels:
          instance: 'home-router'
          environment: 'production'
    scrape_interval: 30s
    scrape_timeout: 10s
```

### Alternative: File-based Scraping

If HTTP server not available:

```bash
# On router: export metrics every 30s
echo '* * * * * sh /jffs/scripts/netadmin/core/metrics.sh export' | crontab -

# On monitoring server: fetch via SSH
ssh router 'cat /tmp/netadmin_metrics.txt' > /var/lib/prometheus/textfile/netadmin.prom
```

## Grafana Dashboard

### Import Dashboard

1. Copy `docs/observability/grafana-dashboard.json`
2. In Grafana: Dashboards → Import → Upload JSON
3. Select Prometheus datasource
4. Save

### Dashboard Panels

- **State Machine** - Current state with color coding
- **WAN Ready** - Overall WAN health gauge
- **WAN Health Checks** - Time series of all health checks
- **Hardware Acceleration** - CTF/FC/Runner status
- **Zapret Running** - DPI bypass service status
- **Boot Attempts** - Failure counter (alerts at 3)
- **Uptime** - Time since initialization

## AlertManager

### Deploy Alert Rules

```bash
# Copy rules
cp docs/observability/alertmanager-rules.yml /etc/prometheus/rules/

# Reload Prometheus
killall -HUP prometheus
```

### Alert Definitions

| Alert | Condition | Severity |
|-------|-----------|----------|
| NetadminWANDown | WAN down for 5min | Critical |
| NetadminStateMachineStuck | Not ACTIVE after 5min | Warning |
| NetadminBootLoopDetected | 3+ boot failures | Critical |
| NetadminTCPHealthFailed | TCP fails despite carrier up | Warning |
| NetadminZapretCrashed | Zapret stopped unexpectedly | Warning |
| NetadminStateFlapping | Rapid state changes | Warning |

### Notification Channels

Configure in AlertManager:

```yaml
receivers:
  - name: 'netadmin-alerts'
    email_configs:
      - to: 'admin@example.com'
    slack_configs:
      - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK'
        channel: '#netadmin-alerts'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_KEY'

route:
  group_by: ['alertname']
  routes:
    - match:
        severity: critical
      receiver: 'netadmin-alerts'
      continue: true
```

## Querying Metrics

### Useful PromQL Queries

```promql
# WAN uptime percentage (last 24h)
(sum_over_time(netadmin_wan_ready[24h]) / count_over_time(netadmin_wan_ready[24h])) * 100

# Average boot attempts (rolling 1h)
avg_over_time(netadmin_boot_attempts[1h])

# Time in each state (last 1h)
sum by (state) (changes(netadmin_state_current{state=~".+"}[1h]))

# Zapret uptime percentage
(sum_over_time(netadmin_zapret_running[24h]) / count_over_time(netadmin_zapret_running[24h])) * 100
```

## Troubleshooting

### Metrics not updating

**Check if HTTP server is running:**
```bash
netstat -tlnp | grep 8080
```

**Check metrics file:**
```bash
cat /tmp/netadmin_metrics.txt
ls -lh /tmp/netadmin_metrics.txt  # Check timestamp
```

**Force export:**
```bash
netadmin metrics export
netadmin metrics show
```

### Prometheus not scraping

**Check Prometheus targets:**
- Open http://prometheus:9090/targets
- Verify netadmin target is UP

**Test connectivity:**
```bash
curl http://router-ip:8080/metrics
```

**Check firewall:**
```bash
iptables -L INPUT -n | grep 8080
```

### Grafana dashboard empty

**Verify Prometheus datasource:**
- Grafana → Configuration → Data Sources
- Test connection to Prometheus

**Check query syntax:**
- Edit panel
- Run query manually
- Check for errors

## Integration Examples

### Nagios/Icinga Check

```bash
#!/bin/bash
# Nagios check for netadmin WAN

STATE=$(curl -s http://router:8080/metrics | grep 'netadmin_wan_ready' | awk '{print $2}')

if [ "$STATE" = "1" ]; then
    echo "OK: WAN is ready"
    exit 0
else
    echo "CRITICAL: WAN is down"
    exit 2
fi
```

### Datadog Integration

```yaml
# datadog-agent/conf.d/prometheus.d/conf.yaml
init_config:

instances:
  - prometheus_url: http://router:8080/metrics
    namespace: "netadmin"
    metrics:
      - netadmin_*
```

### InfluxDB Export

```bash
# Telegraf input plugin
[[inputs.prometheus]]
  urls = ["http://router:8080/metrics"]
  metric_version = 2
```

## Best Practices

1. **Scrape Interval**: Use 30s (matches watchdog interval)
2. **Retention**: Keep 7 days of metrics minimum
3. **Alerting**: Set up PagerDuty for critical alerts
4. **Backup**: Export Grafana dashboard JSON regularly
5. **Testing**: Trigger test alerts to verify notification flow

## References

- Prometheus: https://prometheus.io/docs/
- Grafana: https://grafana.com/docs/
- AlertManager: https://prometheus.io/docs/alerting/latest/alertmanager/
