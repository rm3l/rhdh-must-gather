# Kustomize Deployment for RHDH Must-Gather

This directory contains Kustomize configurations for deploying the RHDH must-gather tool on standard Kubernetes clusters.

## Directory Structure

```
kustomize/
├── base/                       # Base configuration (all required resources)
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── serviceaccount.yaml
│   ├── rbac.yaml
│   ├── pvc.yaml
│   ├── job.yaml
│   └── data-retriever-pod.yaml
└── overlays/                   # Example customization overlays
    ├── custom-namespace/       # Deploy to a custom namespace
    ├── debug-mode/             # Enable debug logging with increased resources
    ├── with-heap-dumps/        # Enable heap dump collection
    ├── specific-namespaces/    # Collect from specific namespaces only
    └── custom-image/           # Use a custom image or tag
```

## Quick Start

### Basic Deployment

```bash
# Deploy using the base configuration
kubectl apply -k base/

# Or directly from GitHub
kubectl apply -k https://github.com/redhat-developer/rhdh-must-gather/deploy/kustomize/base?ref=main
```

### Using Pre-built Overlays

```bash
# Deploy with debug logging enabled
kubectl apply -k overlays/debug-mode/

# Deploy with heap dump collection
kubectl apply -k overlays/with-heap-dumps/
```

## Available Overlays

| Overlay | Description | Key Changes |
|---------|-------------|-------------|
| `custom-namespace` | Deploy to a different namespace | Changes namespace from `rhdh-must-gather` |
| `debug-mode` | Enable verbose logging | Sets `LOG_LEVEL=DEBUG`, increases memory limits |
| `with-heap-dumps` | Collect heap dumps | Adds `--with-heap-dumps` arg, 10Gi PVC, 2h timeout |
| `specific-namespaces` | Target specific namespaces | Adds `--namespaces` arg to filter collection |
| `custom-image` | Use different image/tag | Updates image reference for custom builds |

## Creating Your Own Overlay

Create a new directory with a `kustomization.yaml` that references the base:

```yaml
# my-overlay/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../base
  # Or reference from GitHub:
  # - https://github.com/redhat-developer/rhdh-must-gather/deploy/kustomize/base?ref=main

# Customize namespace
namespace: my-namespace

# Customize image
images:
  - name: quay.io/rhdh-community/rhdh-must-gather
    newTag: v1.0.0

# Add patches for further customization
patches:
  - target:
      kind: Job
      name: rhdh-must-gather
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args
        value:
          - "--with-secrets"
          - "--namespaces"
          - "my-rhdh-namespace"
```

## Common Customizations

### Change the image tag

```yaml
images:
  - name: quay.io/rhdh-community/rhdh-must-gather
    newTag: v1.2.3
```

### Change PVC storage size

```yaml
patches:
  - target:
      kind: PersistentVolumeClaim
      name: rhdh-must-gather-pvc
    patch: |
      - op: replace
        path: /spec/resources/requests/storage
        value: 5Gi
```

### Add command-line arguments

```yaml
patches:
  - target:
      kind: Job
      name: rhdh-must-gather
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/args
        value:
          - "--namespaces"
          - "ns1,ns2"
          - "--without-operator"
```

### Change environment variables

```yaml
patches:
  - target:
      kind: Job
      name: rhdh-must-gather
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/env/2/value
        value: "DEBUG"
```

### Change resource limits

```yaml
patches:
  - target:
      kind: Job
      name: rhdh-must-gather
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "1Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "1"
```

### Use a custom storage class

```yaml
patches:
  - target:
      kind: PersistentVolumeClaim
      name: rhdh-must-gather-pvc
    patch: |
      - op: add
        path: /spec/storageClassName
        value: my-storage-class
```

## Retrieving the Output

After the job completes, retrieve the collected data:

```bash
# Wait for job completion
kubectl -n rhdh-must-gather wait --for=condition=complete job/rhdh-must-gather --timeout=600s

# Wait for the data retriever pod to be ready
kubectl -n rhdh-must-gather wait --for=condition=ready pod/rhdh-must-gather-data-retriever --timeout=60s

# Download the archive
kubectl -n rhdh-must-gather exec rhdh-must-gather-data-retriever -- tar czf - -C /data . > rhdh-must-gather-output.tar.gz
```

## Cleanup

```bash
# Using base
kubectl delete -k base/

# Using an overlay
kubectl delete -k overlays/debug-mode/

# From GitHub
kubectl delete -k https://github.com/redhat-developer/rhdh-must-gather/deploy/kustomize/base?ref=main
```

