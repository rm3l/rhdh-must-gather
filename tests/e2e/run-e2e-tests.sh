#!/bin/bash
# E2E test script for rhdh-must-gather
# This script runs the must-gather against a Kind cluster and validates the output

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse arguments
FULL_IMAGE_NAME="${1:-}"
OPTS="${2:-}"

if [ -z "$FULL_IMAGE_NAME" ]; then
    log_error "Usage: $0 <full-image-name> [opts]"
    log_error "Example: $0 quay.io/rhdh-community/rhdh-must-gather:pr-123"
    exit 1
fi

log_info "Starting E2E tests with image: $FULL_IMAGE_NAME"

# Extract registry, image name, and tag from full image name
# e.g., quay.io/rhdh-community/rhdh-must-gather:pr-123
REGISTRY=$(echo "$FULL_IMAGE_NAME" | cut -d'/' -f1)
IMAGE_NAME=$(echo "$FULL_IMAGE_NAME" | cut -d':' -f1 | cut -d'/' -f2-)
IMAGE_TAG=$(echo "$FULL_IMAGE_NAME" | cut -d':' -f2)

log_info "Registry: $REGISTRY"
log_info "Image name: $IMAGE_NAME"
log_info "Image tag: $IMAGE_TAG"

# Ensure we're in the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

log_info "Working directory: $PROJECT_ROOT"

# Deploy some instances of RHDH
# Helm
kubectl create namespace my-rhdh-ns
helm -n my-rhdh-ns install my-rhdh-helm backstage --repo https://redhat-developer.github.io/rhdh-chart --set route.enabled=false

# Operator
kubectl apply -f https://raw.githubusercontent.com/redhat-developer/rhdh-operator/refs/heads/main/dist/rhdh/install.yaml
log_info "Waiting for rhdh-operator deployment to be available in rhdh-operator namespace..."
if ! kubectl -n rhdh-operator wait --for=condition=Available deployment/rhdh-operator --timeout=5m; then
    log_error "Timed out waiting for rhdh-operator deployment to be available."
    exit 1
fi
log_info "rhdh-operator deployment is now available."
kubectl -n my-rhdh-ns apply -f - <<EOF
apiVersion: rhdh.redhat.com/v1alpha5
kind: Backstage
metadata:
  name: my-rhdh-operator
EOF
# TODO: wait until the Backstage CR is reconciled

# Run make k8s-test
log_info "Running make k8s-test..."
make k8s-test \
    REGISTRY="$REGISTRY" \
    IMAGE_NAME="$IMAGE_NAME" \
    IMAGE_TAG="$IMAGE_TAG" \
    OPTS="$OPTS"

# Find the output tarball (most recent one)
OUTPUT_TARBALL=$(find . -maxdepth 1 -name 'rhdh-must-gather-output.k8s.*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$OUTPUT_TARBALL" ]; then
    log_error "No output tarball found!"
    exit 1
fi

log_info "Found output tarball: $OUTPUT_TARBALL"

# Extract and validate the output
OUTPUT_DIR="${OUTPUT_TARBALL%.tar.gz}"
log_info "Extracting to: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
tar xzf "$OUTPUT_TARBALL" -C "$OUTPUT_DIR"

# Validation checks
ERRORS=0

check_file_exists() {
    local file="$1"
    local description="$2"
    if [ -f "$file" ]; then
        log_info "✓ Found $description: $file"
    else
        log_error "✗ Missing $description: $file"
        ((ERRORS++))
    fi
}

check_dir_exists() {
    local dir="$1"
    local description="$2"
    if [ -d "$dir" ]; then
        log_info "✓ Found $description: $dir"
    else
        log_error "✗ Missing $description: $dir"
        ((ERRORS++))
    fi
}

log_info ""
log_info "=========================================="
log_info "Validating must-gather output structure"
log_info "=========================================="

# Check required files
check_file_exists "$OUTPUT_DIR/version" "version file"
check_file_exists "$OUTPUT_DIR/sanitization-report.txt" "sanitization report"

# Check required directories
check_dir_exists "$OUTPUT_DIR/platform" "platform directory"
check_dir_exists "$OUTPUT_DIR/namespace-inspect" "namespace-inspect directory"

# Check optional directories (helm and operator - may or may not exist depending on cluster)
if [ -d "$OUTPUT_DIR/helm" ]; then
    log_info "✓ Found helm directory"
else
    log_warn "○ Helm directory not present (expected if no RHDH Helm releases found)"
fi

if [ -d "$OUTPUT_DIR/operator" ]; then
    log_info "✓ Found operator directory"
else
    log_warn "○ Operator directory not present (expected if RHDH operator not installed)"
fi

# Validate version file content
if [ -f "$OUTPUT_DIR/version" ]; then
    VERSION_CONTENT=$(cat "$OUTPUT_DIR/version")
    if [ -n "$VERSION_CONTENT" ]; then
        log_info "✓ Version file contains: $VERSION_CONTENT"
    else
        log_error "✗ Version file is empty"
        ((ERRORS++))
    fi
fi

# Check platform info files (cluster-info collection is opt-in and disabled by default)
if [ -f "$OUTPUT_DIR/platform/cluster-info.json" ]; then
    log_info "✓ Found cluster info JSON"
else
    log_warn "○ Cluster info JSON not present (expected - collection is opt-in)"
fi

if [ -f "$OUTPUT_DIR/platform/cluster-version.txt" ]; then
    log_info "✓ Found cluster version"
else
    log_warn "○ Cluster version not present (expected - collection is opt-in)"
fi

# Check namespace-inspect output
if [ -d "$OUTPUT_DIR/namespace-inspect" ]; then
    check_file_exists "$OUTPUT_DIR/namespace-inspect/event-filter.html" "event filter HTML"
    
    # Check if there's at least one namespace inspected
    if ls "$OUTPUT_DIR/namespace-inspect/namespaces/"* >/dev/null 2>&1; then
        NAMESPACES_COUNT=$(find "$OUTPUT_DIR/namespace-inspect/namespaces" -mindepth 1 -maxdepth 1 -type d | wc -l)
        log_info "✓ Found $NAMESPACES_COUNT namespace(s) inspected"
    else
        log_warn "○ No namespaces found in namespace-inspect (expected if no RHDH namespaces)"
    fi
fi

log_info ""
log_info "=========================================="
log_info "E2E Test Summary"
log_info "=========================================="

if [ $ERRORS -eq 0 ]; then
    log_info "All validation checks passed!"
    exit 0
else
    log_error "$ERRORS validation check(s) failed!"
    exit 1
fi

