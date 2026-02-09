#!/bin/sh
# WAN Health Check Tests

Describe 'WAN Health Monitoring'
  Include './src/core/netadmin-lib.sh'

  # Mock system calls for testing
  Mock_sys_class_net() {
    [ -d "/sys/class/net/eth0" ] && return 0
    return 1
  }

  Describe 'WAN Interface Detection'
    It 'should detect eth0 as WAN interface'
      interface=$(wan_if_detect)
      Assert Equals "$interface" "eth0"
    End
  End

  Describe 'Carrier Status'
    It 'should check carrier state'
      # This would normally read /sys/class/net/eth0/carrier
      # Test assumes carrier file exists
      if [ -f /sys/class/net/eth0/carrier ]; then
        wan_carrier_up "eth0"
        Assert Success
      fi
    End
  End

  Describe 'Health Check Functions'
    It 'should have health check functions available'
      Assert Callable wan_has_ip
      Assert Callable wan_has_default_route
      Assert Callable wan_tcp_health
    End
  End
End
