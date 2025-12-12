#!/usr/bin/env bash
#
# Run RHDH must-gather on a standard Kubernetes cluster using Kustomize.
#
# Usage:
#   ./hack/k8s-test.sh [IMAGE] [OPTS...]
#
# Arguments:
#   IMAGE   - Full image name (default: quay.io/rhdh-community/rhdh-must-gather:next)
#   OPTS    - Additional options to pass to the gather script
#
# Examples:
#   ./hack/k8s-test.sh
#   ./hack/k8s-test.sh quay.io/myorg/rhdh-must-gather:v1.0.0
#   ./hack/k8s-test.sh quay.io/myorg/rhdh-must-gather:v1.0.0 --with-secrets --namespaces my-ns
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUSTOMIZE_BASE="${REPO_ROOT}/deploy/kustomize/base"

# Default image
DEFAULT_IMAGE="quay.io/rhdh-community/rhdh-must-gather:next"

# Parse arguments
IMAGE="${1:-${DEFAULT_IMAGE}}"
shift || true
OPTS=("$@")

# Extract image components
IMAGE_NAME="${IMAGE%:*}"
IMAGE_TAG="${IMAGE##*:}"
if [[ "${IMAGE_TAG}" == "${IMAGE_NAME}" ]]; then
    IMAGE_TAG="latest"
fi

# Generate unique namespace
TIMESTAMP=$(date +%s)
NAMESPACE="rhdh-must-gather-${TIMESTAMP}"
OUTPUT_FILE="rhdh-must-gather-output.k8s.${TIMESTAMP}.tar.gz"

# Create temporary overlay directory
TMP_OVERLAY=$(mktemp -d)
trap 'rm -rf "${TMP_OVERLAY}"' EXIT

echo "Testing against a regular K8s cluster..."
echo ""

# Check for kubectl
if ! command -v kubectl &>/dev/null; then
    echo "Error: kubectl command not found."
    exit 1
fi

echo "Preparing must-gather resources in namespace: ${NAMESPACE}"

# Create symlink to base directory (Kustomize requires relative paths)
ln -s "${KUSTOMIZE_BASE}" "${TMP_OVERLAY}/base"

# Generate kustomization.yaml
cat > "${TMP_OVERLAY}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

resources:
  - base

images:
  - name: quay.io/rhdh-community/rhdh-must-gather
    newName: ${IMAGE_NAME}
    newTag: ${IMAGE_TAG}

patches:
  - target:
      kind: Namespace
      name: rhdh-must-gather
    patch: |
      - op: replace
        path: /metadata/name
        value: ${NAMESPACE}
  - target:
      kind: ClusterRoleBinding
      name: rhdh-must-gather
    patch: |
      - op: replace
        path: /subjects/0/namespace
        value: ${NAMESPACE}
EOF

# Add args patch if OPTS provided
if [[ ${#OPTS[@]} -gt 0 ]]; then
    cat >> "${TMP_OVERLAY}/kustomization.yaml" <<EOF
  - target:
      kind: Job
      name: rhdh-must-gather
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args
        value:
EOF
    for opt in "${OPTS[@]}"; do
        echo "          - \"${opt}\"" >> "${TMP_OVERLAY}/kustomization.yaml"
    done
fi

# Create resources
echo "Creating must-gather resources using this Kustomization overlay (${TMP_OVERLAY}/)..."
echo "---"
cat "${TMP_OVERLAY}/kustomization.yaml"
echo "---"
echo ""
kubectl apply -k "${TMP_OVERLAY}"
echo ""

# Wait for job completion
echo "Waiting for job to complete (timeout: 600s)..."
if ! kubectl -n "${NAMESPACE}" wait --for=condition=complete job/rhdh-must-gather --timeout=600s 2>&1; then
    echo "Error: Job did not complete within timeout"
    echo ""
    echo "Job logs:"
    kubectl -n "${NAMESPACE}" logs job/rhdh-must-gather --tail=50 || true
    exit 1
fi
echo "Job completed successfully"
echo ""

# Wait for data retriever pod
echo "Waiting for data retriever pod to be ready (timeout: 60s)..."
if ! kubectl -n "${NAMESPACE}" wait --for=condition=ready pod/rhdh-must-gather-data-retriever --timeout=60s 2>&1; then
    echo "Error: Data retriever pod did not become ready within timeout"
    echo ""
    kubectl -n "${NAMESPACE}" describe pod/rhdh-must-gather-data-retriever || true
    exit 1
fi
echo "Data retriever pod is ready"
echo ""

# Pull data
echo "Pulling must-gather data from pod..."
kubectl -n "${NAMESPACE}" exec rhdh-must-gather-data-retriever -- tar czf - -C /data . > "${OUTPUT_FILE}"
echo ""

# Cleanup
echo "Cleaning up resources..."
kubectl delete -k "${TMP_OVERLAY}" --wait=false 2>/dev/null || true
echo ""

echo "✓ Must-gather data saved to: ${OUTPUT_FILE}"
echo ""
echo "To extract the data, run:"
echo "  tar xzf ${OUTPUT_FILE}"

