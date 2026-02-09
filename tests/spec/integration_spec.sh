#!/bin/sh
# Integration Tests - Full Workflow

Describe 'Integration Tests'
  Include './src/core/netadmin-lib.sh'

  BeforeEach() {
    rm -f /tmp/netadmin_state
    rm -f /tmp/netadmin_state.log
    rm -f /tmp/netadmin_health.json
  }

  Describe 'Boot Sequence'
    It 'should initialize on first boot'
      state=$(get_current_state)
      Assert Equals "$state" "0"
    End

    It 'should track boot attempts'
      increment_boot_attempt
      attempts=$(get_boot_attempt)
      Assert Equals "$attempts" "1"
    End
  End

  Describe 'State Machine Workflow'
    It 'should flow: INIT -> WAN_WAIT -> RULES_APPLY -> ACTIVE'
      set_state "$STATE_WAN_WAIT"
      set_state "$STATE_RULES_APPLY"
      set_state "$STATE_ACTIVE"

      state=$(get_current_state)
      Assert Equals "$state" "$STATE_ACTIVE"
    End

    It 'should allow ACTIVE -> DEGRADED transition'
      set_state "$STATE_ACTIVE"
      set_state "$STATE_DEGRADED"
      state=$(get_current_state)
      Assert Equals "$state" "$STATE_DEGRADED"
    End
  End

  Describe 'Error Recovery'
    It 'should transition to SAFE on error'
      set_state "$STATE_WAN_WAIT"
      set_state "$STATE_SAFE"
      state=$(get_current_state)
      Assert Equals "$state" "$STATE_SAFE"
    End
  End
End
