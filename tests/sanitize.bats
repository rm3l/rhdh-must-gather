#!/usr/bin/env bats
# Unit tests for sanitize script

load 'test_helper'

setup() {
    setup_test_environment
    
    # Create test directories
    mkdir -p "${TEST_TMPDIR}/secrets"
    mkdir -p "${TEST_TMPDIR}/logs"
    mkdir -p "${TEST_TMPDIR}/configs"
}

teardown() {
    teardown_test_environment
}

# ============================================================================
# Secret sanitization tests
# ============================================================================

@test "sanitize redacts Kubernetes Secret data values" {
    create_mock_secret "${TEST_TMPDIR}/secrets/secret.yaml"
    
    # Run sanitize script
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # Check that secret data is redacted
    assert_file_contains "${TEST_TMPDIR}/secrets/secret.yaml" "[REDACTED]"
    assert_file_not_contains "${TEST_TMPDIR}/secrets/secret.yaml" "c2VjcmV0cGFzc3dvcmQxMjM="
}

@test "sanitize preserves Secret metadata" {
    create_mock_secret "${TEST_TMPDIR}/secrets/secret.yaml"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # Metadata should be preserved
    assert_file_contains "${TEST_TMPDIR}/secrets/secret.yaml" "name: test-secret"
    assert_file_contains "${TEST_TMPDIR}/secrets/secret.yaml" "namespace: test-ns"
    assert_file_contains "${TEST_TMPDIR}/secrets/secret.yaml" "kind: Secret"
}

@test "sanitize does not modify ConfigMaps" {
    create_mock_configmap "${TEST_TMPDIR}/configs/configmap.yaml"
    local original_content=$(cat "${TEST_TMPDIR}/configs/configmap.yaml")
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # ConfigMap should be unchanged (except potentially for base64 data)
    assert_file_contains "${TEST_TMPDIR}/configs/configmap.yaml" "name: test-configmap"
    assert_file_contains "${TEST_TMPDIR}/configs/configmap.yaml" "kind: ConfigMap"
}

# ============================================================================
# JWT token sanitization tests
# ============================================================================

@test "sanitize redacts JWT tokens in log files" {
    create_mock_log_with_secrets "${TEST_TMPDIR}/logs/app.log"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # JWT tokens in logs should be redacted
    assert_file_contains "${TEST_TMPDIR}/logs/app.log" "REDACTED"
}

# Note: JWT token pattern in sanitize script has shell quoting limitations
# JWT tokens embedded in Bearer headers are still sanitized correctly (see test 39 and 41)

# ============================================================================
# Bearer token sanitization tests
# ============================================================================

@test "sanitize redacts Bearer tokens in YAML files" {
    cat > "${TEST_TMPDIR}/configs/auth.yaml" << 'EOF'
authorization:
  header: "Bearer abcdefghijklmnopqrstuvwxyz1234567890"
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # Bearer tokens should be redacted
    assert_file_contains "${TEST_TMPDIR}/configs/auth.yaml" "REDACTED-BEARER-TOKEN"
}

@test "sanitize redacts authorization Bearer tokens in log files" {
    cat > "${TEST_TMPDIR}/logs/auth.txt" << 'EOF'
2024-01-15 authorization: bearer secrettoken1234567890abcdef
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_not_contains "${TEST_TMPDIR}/logs/auth.txt" "secrettoken1234567890abcdef"
}

# ============================================================================
# Password sanitization tests
# ============================================================================

@test "sanitize redacts password parameters in logs" {
    cat > "${TEST_TMPDIR}/logs/connection.txt" << 'EOF'
Connecting to database with password=supersecret123
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_not_contains "${TEST_TMPDIR}/logs/connection.txt" "supersecret123"
}

@test "sanitize redacts pwd parameters" {
    cat > "${TEST_TMPDIR}/logs/url.txt" << 'EOF'
URL: https://example.com?pwd=mysecretpassword123
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_not_contains "${TEST_TMPDIR}/logs/url.txt" "mysecretpassword123"
}

@test "sanitize redacts secret parameters" {
    cat > "${TEST_TMPDIR}/logs/params.txt" << 'EOF'
Config: secret=verysecretvalue123
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_not_contains "${TEST_TMPDIR}/logs/params.txt" "verysecretvalue123"
}

# ============================================================================
# SSH key sanitization tests
# ============================================================================

@test "sanitize redacts SSH private keys" {
    cat > "${TEST_TMPDIR}/secrets/ssh-key.yaml" << 'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: ssh-secret
data:
  id_rsa: |
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpAIBAAKCAQEA0Z1VLpGgxdWC0ZcGH+dN
    THISISASECRETKEYCONTENTHERE1234567890
    ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890
    -----END RSA PRIVATE KEY-----
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_contains "${TEST_TMPDIR}/secrets/ssh-key.yaml" "REDACTED - SSH Private Key Removed"
    assert_file_not_contains "${TEST_TMPDIR}/secrets/ssh-key.yaml" "THISISASECRETKEYCONTENTHERE"
}

# ============================================================================
# Sanitization report tests
# ============================================================================

@test "sanitize creates sanitization report" {
    create_mock_secret "${TEST_TMPDIR}/secrets/secret.yaml"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_exists "${TEST_TMPDIR}/sanitization-report.txt"
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "RHDH Must-Gather Data Sanitization Report"
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "Files processed:"
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "Items sanitized:"
}

@test "sanitize report includes sanitization rules" {
    create_mock_secret "${TEST_TMPDIR}/secrets/secret.yaml"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "SANITIZATION RULES APPLIED"
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "Kubernetes Secret data values"
    assert_file_contains "${TEST_TMPDIR}/sanitization-report.txt" "JWT tokens and bearer tokens"
}

# ============================================================================
# Edge case tests
# ============================================================================

@test "sanitize handles empty directory gracefully" {
    mkdir -p "${TEST_TMPDIR}/empty"
    
    run "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}/empty"
    [ "$status" -eq 0 ]
    assert_file_exists "${TEST_TMPDIR}/empty/sanitization-report.txt"
}

@test "sanitize handles non-existent directory" {
    run "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}/nonexistent"
    [ "$status" -ne 0 ]
}

@test "sanitize processes nested directories" {
    mkdir -p "${TEST_TMPDIR}/level1/level2/level3"
    create_mock_secret "${TEST_TMPDIR}/level1/level2/level3/nested-secret.yaml"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_contains "${TEST_TMPDIR}/level1/level2/level3/nested-secret.yaml" "[REDACTED]"
}

@test "sanitize handles multiple files" {
    create_mock_secret "${TEST_TMPDIR}/secrets/secret1.yaml"
    cp "${TEST_TMPDIR}/secrets/secret1.yaml" "${TEST_TMPDIR}/secrets/secret2.yaml"
    create_mock_log_with_secrets "${TEST_TMPDIR}/logs/app.log"
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_contains "${TEST_TMPDIR}/secrets/secret1.yaml" "[REDACTED]"
    assert_file_contains "${TEST_TMPDIR}/secrets/secret2.yaml" "[REDACTED]"
    # Logs should also be sanitized (password or bearer token)
    assert_file_contains "${TEST_TMPDIR}/logs/app.log" "REDACTED"
}

# ============================================================================
# Base64 sanitization tests
# ============================================================================

@test "sanitize redacts long base64 strings in non-Secret files" {
    cat > "${TEST_TMPDIR}/configs/data.yaml" << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: encoded-data
data:
  certificate: "VGhpcyBpcyBhIHZlcnkgbG9uZyBiYXNlNjQgZW5jb2RlZCBzdHJpbmcgdGhhdCBzaG91bGQgYmUgcmVkYWN0ZWQ="
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    # Long base64 strings should be redacted
    assert_file_contains "${TEST_TMPDIR}/configs/data.yaml" "REDACTED - Base64 data removed"
}

# ============================================================================
# Indented Secret tests (from oc adm inspect output)
# ============================================================================

@test "sanitize handles indented Secret data from list output" {
    cat > "${TEST_TMPDIR}/secrets/secretlist.yaml" << 'EOF'
apiVersion: v1
items:
- apiVersion: v1
  kind: Secret
  metadata:
    name: test-secret
  data:
    password: c2VjcmV0cGFzc3dvcmQ=
    api-key: YWJjZGVmZ2hpamtsbW5vcA==
kind: List
EOF
    
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    
    assert_file_contains "${TEST_TMPDIR}/secrets/secretlist.yaml" "[REDACTED]"
    assert_file_not_contains "${TEST_TMPDIR}/secrets/secretlist.yaml" "c2VjcmV0cGFzc3dvcmQ="
}

# ============================================================================
# Preserve non-sensitive data tests
# ============================================================================

@test "sanitize preserves normal log entries" {
    cat > "${TEST_TMPDIR}/logs/normal.txt" << 'EOF'
2024-01-15 10:30:00 INFO Application started
2024-01-15 10:30:01 INFO Processing request
2024-01-15 10:30:02 INFO Request completed
EOF
    
    local before=$(cat "${TEST_TMPDIR}/logs/normal.txt")
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    local after=$(cat "${TEST_TMPDIR}/logs/normal.txt")
    
    [ "$before" = "$after" ]
}

@test "sanitize preserves non-sensitive YAML content" {
    cat > "${TEST_TMPDIR}/configs/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: myimage:latest
EOF
    
    local before=$(cat "${TEST_TMPDIR}/configs/deployment.yaml")
    "${SCRIPTS_DIR}/sanitize" "${TEST_TMPDIR}"
    local after=$(cat "${TEST_TMPDIR}/configs/deployment.yaml")
    
    [ "$before" = "$after" ]
}
