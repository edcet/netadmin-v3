#!/bin/sh
# State Machine Unit Tests (shellspec)

Describe 'State Machine'
  Include './src/core/netadmin-lib.sh'

  BeforeEach() {
    # Reset state for each test
    rm -f /tmp/netadmin_state
    rm -f /tmp/netadmin_state.log
  }

  Describe 'State Initialization'
    It 'should start in INIT state'
      state=$(get_current_state)
      Assert Equals "$state" "0"
    End
  End

  Describe 'State Transitions'
    It 'should transition from INIT to WAN_WAIT'
      set_state "$STATE_WAN_WAIT"
      state=$(get_current_state)
      Assert Equals "$state" "$STATE_WAN_WAIT"
    End

    It 'should transition from WAN_WAIT to RULES_APPLY'
      set_state "$STATE_WAN_WAIT"
      set_state "$STATE_RULES_APPLY"
      state=$(get_current_state)
      Assert Equals "$state" "$STATE_RULES_APPLY"
    End

    It 'should reject invalid transitions'
      set_state "$STATE_ACTIVE"
      result=$(set_state "$STATE_RULES_APPLY" 2>&1)
      # Should fail (return non-zero)
      Assert Failure
    End
  End

  Describe 'State Names'
    It 'should return correct state names'
      name=$(state_name "0")
      Assert Equals "$name" "INIT"

      name=$(state_name "3")
      Assert Equals "$name" "ACTIVE"

      name=$(state_name "5")
      Assert Equals "$name" "SAFE"
    End
  End
End
