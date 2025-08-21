# RHDH Must-Gather Tool

A comprehensive diagnostic data collection tool for Red Hat Developer Hub (RHDH) deployments on Kubernetes and OpenShift clusters.

## Overview

This tool helps support teams and engineers collect essential information from RHDH deployments to troubleshoot issues effectively. It supports:

- **Multi-platform**: OpenShift and standard Kubernetes (AKS, GKE, EKS)
- **Multi-deployment**: Helm-based and Operator-based RHDH instances
- **Comprehensive collection**: Cluster info, logs, configurations, and resources
- **Privacy-aware**: Automatic sanitization of sensitive data

## Quick Start

### Using with OpenShift (`oc adm must-gather`)

```bash
# Use the published image
oc adm must-gather --image=quay.io/rhdh/rhdh-must-gather:latest

# Use a specific namespace (if RHDH is not in default locations)
oc adm must-gather --image=quay.io/rhdh/rhdh-must-gather:latest -- /usr/local/bin/gather
```

### Using with Kubernetes

```bash
# Run as a Job
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: rhdh-must-gather
spec:
  template:
    spec:
      containers:
      - name: must-gather
        image: quay.io/rhdh/rhdh-must-gather:latest
        volumeMounts:
        - name: output
          mountPath: /must-gather
      volumes:
      - name: output
        emptyDir: {}
      restartPolicy: Never
EOF

# Copy the results
kubectl cp rhdh-must-gather-<pod-name>:/must-gather ./must-gather-output
```

### Local Development/Testing

```bash
# Clone the repository
git clone <repository-url>
cd rhdh-must-gather

# Run locally (requires kubectl access)
make test-local

# Build and test in container
make build test-container
```

## What Data is Collected

### Cluster Information
- Node details and status
- Kubernetes/OpenShift version
- Storage classes and network policies
- RBAC configurations
- Cluster operators (OpenShift)

### RHDH-Specific Data

#### Helm Deployments
- Helm release information
- Values files and configurations
- Deployed manifests
- Release history

#### Operator Deployments
- Operator logs and status
- Custom Resource Definitions (CRDs)
- Backstage Custom Resources
- Operand configurations and status

#### Common Resources
- All resources in RHDH namespace
- Pod logs (current and previous)
- Events and descriptions
- Services and networking
- Persistent Volume Claims

## Privacy and Security

The tool includes automatic sanitization to protect sensitive information:

- **Passwords and secrets** are masked
- **Tokens and API keys** are redacted
- **Base64 encoded data** is marked as redacted
- **JWT tokens** are identified and masked
- **URLs with credentials** are sanitized
- **Kubernetes secret data** sections are removed

Original files are backed up before sanitization for debugging if needed.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Detection     │    │   Collection    │    │  Sanitization   │
│                 │    │                 │    │                 │
│ • Cluster type  │───▶│ • Cluster info  │───▶│ • Remove secrets│
│ • RHDH namespace│    │ • RHDH resources│    │ • Mask tokens   │
│ • Deploy method │    │ • Logs & events │    │ • Redact PII    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Key Components

- **`collection/gather`**: Main collection script
- **`collection/sanitize`**: Data sanitization utility
- **`Dockerfile`**: Container image definition
- **`Makefile`**: Build and test automation

## Building the Image

```bash
# Build locally
make build

# Build and push to registry
make build-push REGISTRY=your-registry.com/namespace
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MUST_GATHER_DIR` | `/must-gather` | Output directory for collected data |
| `LOG_LEVEL` | `INFO` | Logging level (INFO, WARN, ERROR) |
| `COLLECTION_TIMEOUT` | `300` | Timeout for individual commands (seconds) |

### Command Line Options

The gather script accepts the following options:

```bash
# Default collection
/usr/local/bin/gather

# With custom output directory
MUST_GATHER_DIR=/custom/path /usr/local/bin/gather

# With debug logging
LOG_LEVEL=DEBUG /usr/local/bin/gather
```

## Output Structure

```
must-gather/
├── collection-summary.txt          # Summary of what was collected
├── sanitization-report.txt         # Details of data sanitization
├── cluster-info/                   # Cluster-wide information
│   ├── cluster-info.txt
│   ├── nodes.yaml
│   ├── storageclasses.yaml
│   └── ...
├── rhdh/                           # RHDH-specific data
│   ├── helm/                       # Helm deployment data
│   │   ├── releases.yaml
│   │   ├── values.yaml
│   │   └── manifest.yaml
│   ├── operator/                   # Operator deployment data
│   │   ├── deployments.yaml
│   │   ├── backstage-crd.yaml
│   │   └── logs-*.log
│   └── resources/                  # RHDH namespace resources
│       ├── all-resources.yaml
│       ├── services.yaml
│       └── ...
├── logs/                           # Pod logs
│   ├── backstage-*.log
│   └── ...
└── events/                         # Kubernetes events
    ├── all-events.txt
    └── rhdh-events.txt
```

## Troubleshooting

### Common Issues

**No RHDH deployment detected**
- Verify RHDH is running in the cluster
- Check if it's in a non-standard namespace
- Ensure proper RBAC permissions

**Command timeouts**
- Increase `COLLECTION_TIMEOUT` environment variable
- Check cluster network connectivity
- Verify sufficient resources

**Permission denied errors**
- Ensure the tool has cluster-admin or sufficient RBAC permissions
- Check ServiceAccount configuration in OpenShift

### Getting Help

1. Check the `collection-summary.txt` for what was detected
2. Review logs for error messages
3. Verify cluster connectivity with `kubectl cluster-info`

## Development

### Testing

```bash
# Test locally
make test-local

# Test in container
make test-container

# Test with OpenShift
make openshift-test
```

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Submit a pull request

## Requirements

- Kubernetes 1.19+ or OpenShift 4.6+
- `kubectl` or `oc` CLI access
- Cluster-admin or equivalent permissions
- Container runtime (for building images)

## License

Apache License 2.0 - see [LICENSE](licenses/LICENSE) for details.