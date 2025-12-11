#!/usr/bin/env bats
# Unit tests for version script

load 'test_helper'

setup() {
    setup_test_environment
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# Version function tests
# ============================================================================

@test "version function exists and is callable" {
    source "${SCRIPTS_DIR}/version"
    run version
    [ "$status" -eq 0 ]
}

@test "version returns RHDH_MUST_GATHER_VERSION when set" {
    source "${SCRIPTS_DIR}/version"
    export RHDH_MUST_GATHER_VERSION="1.2.3-test"
    result=$(version)
    [ "$result" = "1.2.3-test" ]
}

@test "version returns git-based version when RHDH_MUST_GATHER_VERSION is unset" {
    source "${SCRIPTS_DIR}/version"
    unset RHDH_MUST_GATHER_VERSION
    result=$(version)
    # Should start with 0.0.0- when no version env var is set
    [[ "$result" =~ ^0\.0\.0- ]]
}

@test "version handles empty RHDH_MUST_GATHER_VERSION" {
    source "${SCRIPTS_DIR}/version"
    export RHDH_MUST_GATHER_VERSION=""
    result=$(version)
    # Empty string should trigger the else branch
    [[ "$result" =~ ^0\.0\.0- ]]
}

@test "version output is non-empty" {
    source "${SCRIPTS_DIR}/version"
    result=$(version)
    [ -n "$result" ]
}

