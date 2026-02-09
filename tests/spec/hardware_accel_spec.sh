#!/bin/sh
# Hardware Acceleration Detection Tests

Describe 'Hardware Acceleration'
  Include './src/core/netadmin-lib.sh'

  # Mock nvram for testing
  Mock_nvram() {
    case "$1 $2" in
      'get ctf_disable')
        echo "${MOCK_CTF:-0}"
        ;;
      'get fc_disable')
        echo "${MOCK_FC:-0}"
        ;;
      'get runner_disable_force')
        echo "${MOCK_RUNNER:-0}"
        ;;
      'set '*'='*')')
        eval "${2#*=}=$(echo "$2" | cut -d= -f2)"
        ;;
    esac
  }

  Describe 'CTF Status Detection'
    It 'should detect CTF enabled'
      MOCK_CTF=0
      status=$(check_ctf_status)
      Assert Equals "$status" "1"
    End

    It 'should detect CTF disabled'
      MOCK_CTF=1
      status=$(check_ctf_status)
      Assert Equals "$status" "0"
    End
  End

  Describe 'Hardware Profiles'
    It 'should validate safe profile with any hardware'
      MOCK_CTF=0
      MOCK_FC=0
      MOCK_RUNNER=0
      validate_hardware_for_profile "safe"
      Assert Success
    End

    It 'should validate verizon-bypass only with all disabled'
      MOCK_CTF=1
      MOCK_FC=1
      MOCK_RUNNER=1
      validate_hardware_for_profile "verizon-bypass"
      Assert Success
    End

    It 'should reject verizon-bypass with CTF enabled'
      MOCK_CTF=0
      MOCK_FC=1
      MOCK_RUNNER=1
      validate_hardware_for_profile "verizon-bypass"
      Assert Failure
    End
  End
End
