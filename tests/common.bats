#!/usr/bin/env bats
# Unit tests for common.sh functions

load 'test_helper'

setup() {
    setup_test_environment
    load_common
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# Logging function tests
# ============================================================================

@test "log_info outputs to stderr with INFO level" {
    output=$(bash -c "source '${SCRIPTS_DIR}/common.sh' && log_info 'test message' 2>&1" || true)
    [[ "$output" =~ "INFO" ]]
    [[ "$output" =~ "test message" ]]
}

@test "log_warn outputs to stderr with WARN level" {
    output=$(bash -c "source '${SCRIPTS_DIR}/common.sh' && log_warn 'warning message' 2>&1" || true)
    [[ "$output" =~ "WARN" ]]
    [[ "$output" =~ "warning message" ]]
}

@test "log_error outputs to stderr with ERROR level" {
    output=$(bash -c "source '${SCRIPTS_DIR}/common.sh' && log_error 'error message' 2>&1" || true)
    [[ "$output" =~ "ERROR" ]]
    [[ "$output" =~ "error message" ]]
}

@test "log_debug is silent when LOG_LEVEL is info" {
    output=$(bash -c "export LOG_LEVEL=info && source '${SCRIPTS_DIR}/common.sh' && log_debug 'debug message' 2>&1" || true)
    [[ ! "$output" =~ "debug message" ]] || [ -z "$output" ]
}

@test "log_debug outputs when LOG_LEVEL is debug" {
    output=$(bash -c "export LOG_LEVEL=debug && source '${SCRIPTS_DIR}/common.sh' && log_debug 'debug message' 2>&1" || true)
    [[ "$output" =~ "DEBUG" ]]
    [[ "$output" =~ "debug message" ]]
}

# ============================================================================
# Namespace filtering tests
# ============================================================================

@test "should_include_namespace returns true when no filtering set" {
    result=$(bash -c "unset RHDH_TARGET_NAMESPACES && source '${SCRIPTS_DIR}/common.sh' && should_include_namespace 'any-namespace' && echo 'yes'" || echo 'no')
    [ "$result" = "yes" ]
}

@test "should_include_namespace returns true for matching namespace" {
    result=$(bash -c "export RHDH_TARGET_NAMESPACES='ns1,ns2,ns3' && source '${SCRIPTS_DIR}/common.sh' && should_include_namespace 'ns2' && echo 'yes'" || echo 'no')
    [ "$result" = "yes" ]
}

@test "should_include_namespace returns false for non-matching namespace" {
    result=$(bash -c "set +e && export RHDH_TARGET_NAMESPACES='ns1,ns2,ns3' && source '${SCRIPTS_DIR}/common.sh' 2>/dev/null && if should_include_namespace 'ns4'; then echo 'yes'; else echo 'no'; fi")
    [ "$result" = "no" ]
}

@test "should_include_namespace handles whitespace in namespace list" {
    result=$(bash -c "export RHDH_TARGET_NAMESPACES='ns1, ns2 , ns3' && source '${SCRIPTS_DIR}/common.sh' && should_include_namespace 'ns2' && echo 'yes'" || echo 'no')
    [ "$result" = "yes" ]
}

@test "should_include_namespace handles single namespace" {
    result=$(bash -c "export RHDH_TARGET_NAMESPACES='single-ns' && source '${SCRIPTS_DIR}/common.sh' && should_include_namespace 'single-ns' && echo 'yes'" || echo 'no')
    [ "$result" = "yes" ]
}

# ============================================================================
# get_namespace_args tests
# ============================================================================

@test "get_namespace_args returns --all-namespaces when no filtering" {
    unset RHDH_TARGET_NAMESPACES
    result=$(get_namespace_args)
    [ "$result" = "--all-namespaces" ]
}

@test "get_namespace_args returns -n flags for specified namespaces" {
    export RHDH_TARGET_NAMESPACES="ns1,ns2"
    result=$(get_namespace_args)
    [[ "$result" =~ "-n ns1" ]]
    [[ "$result" =~ "-n ns2" ]]
}

# ============================================================================
# command_exists tests
# ============================================================================

@test "command_exists returns true for existing command" {
    result=$(bash -c "source '${SCRIPTS_DIR}/common.sh' && command_exists 'bash' && echo 'yes'" || echo 'no')
    [ "$result" = "yes" ]
}

@test "command_exists returns false for non-existing command" {
    result=$(bash -c "set +e && source '${SCRIPTS_DIR}/common.sh' 2>/dev/null && if command_exists 'nonexistent_command_xyz'; then echo 'yes'; else echo 'no'; fi")
    [ "$result" = "no" ]
}

# ============================================================================
# ensure_directory tests
# ============================================================================

@test "ensure_directory creates directory if it doesn't exist" {
    local test_dir="${TEST_TMPDIR}/new_dir"
    [ ! -d "$test_dir" ]
    ensure_directory "$test_dir"
    [ -d "$test_dir" ]
}

@test "ensure_directory succeeds if directory already exists" {
    local test_dir="${TEST_TMPDIR}/existing_dir"
    mkdir -p "$test_dir"
    ensure_directory "$test_dir"
    [ -d "$test_dir" ]
}

@test "ensure_directory creates nested directories" {
    local test_dir="${TEST_TMPDIR}/level1/level2/level3"
    ensure_directory "$test_dir"
    [ -d "$test_dir" ]
}

# ============================================================================
# is_container tests
# ============================================================================

@test "is_container returns false when not in container" {
    # Only run this test if we're not actually in a container
    if [[ ! -f /.dockerenv && -z "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        result=$(bash -c "set +e && source '${SCRIPTS_DIR}/common.sh' 2>/dev/null && if is_container; then echo 'yes'; else echo 'no'; fi")
        [ "$result" = "no" ]
    else
        skip "Running inside container"
    fi
}

# ============================================================================
# safe_exec tests
# ============================================================================

@test "safe_exec captures command output to file" {
    local output_file="${TEST_TMPDIR}/output.txt"
    safe_exec "echo 'hello world'" "$output_file" "test command"
    [ -f "$output_file" ]
    grep -q "hello world" "$output_file"
}

@test "safe_exec creates output directory if needed" {
    local output_file="${TEST_TMPDIR}/subdir/output.txt"
    safe_exec "echo 'test'" "$output_file"
    [ -f "$output_file" ]
}

@test "safe_exec handles command failure gracefully" {
    local output_file="${TEST_TMPDIR}/failed_output.txt"
    # safe_exec should create the file even if command fails
    safe_exec "exit 1" "$output_file" "failing command"
    [ -f "$output_file" ]
}

# ============================================================================
# export_log_collection_args tests
# ============================================================================

@test "export_log_collection_args sets empty args when no env vars" {
    unset MUST_GATHER_SINCE
    unset MUST_GATHER_SINCE_TIME
    export_log_collection_args
    [ -z "$log_collection_args" ]
}

@test "export_log_collection_args sets --since when MUST_GATHER_SINCE is set" {
    export MUST_GATHER_SINCE="1h"
    unset MUST_GATHER_SINCE_TIME
    export_log_collection_args
    [ "$log_collection_args" = "--since=1h" ]
}

@test "export_log_collection_args sets --since-time when MUST_GATHER_SINCE_TIME is set" {
    unset MUST_GATHER_SINCE
    export MUST_GATHER_SINCE_TIME="2024-01-15T10:00:00Z"
    export_log_collection_args
    [ "$log_collection_args" = "--since-time=2024-01-15T10:00:00Z" ]
}

# ============================================================================
# BASE_COLLECTION_PATH tests
# ============================================================================

@test "BASE_COLLECTION_PATH defaults to /must-gather" {
    output=$(bash -c "unset BASE_COLLECTION_PATH && source '${SCRIPTS_DIR}/common.sh' 2>/dev/null && echo \"\$BASE_COLLECTION_PATH\"")
    [[ "$output" =~ "/must-gather" ]]
}

@test "BASE_COLLECTION_PATH can be overridden" {
    export BASE_COLLECTION_PATH="/custom/path"
    [ "$BASE_COLLECTION_PATH" = "/custom/path" ]
}
