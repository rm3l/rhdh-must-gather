# RHDH Must-Gather Tool

A specialized diagnostic data collection tool for Red Hat Developer Hub (RHDH) deployments on Kubernetes and OpenShift clusters.

## Overview

This tool helps support teams and engineers collect essential RHDH-specific information to troubleshoot issues effectively. It focuses exclusively on RHDH resources and can be combined with generic cluster information collection. It supports:

- **Multi-platform**: OpenShift and standard Kubernetes (AKS, GKE, EKS)
- **Multi-deployment**: Helm-based and Operator-based RHDH instances
- **RHDH-focused collection**: Only RHDH-specific logs, configurations, and resources
- **Privacy-aware**: Automatic sanitization of sensitive data

> **Note**: This tool collects only RHDH-specific data. For cluster-wide information, use the generic OpenShift must-gather: `oc adm must-gather`

## Quick Start

### Using with OpenShift (`oc adm must-gather`)

```bash
# Use the published image
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest

# Collect only logs and events from last 2 hours
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --since=2h

# Collect logs and events since specific time
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --since-time=2025-08-21T20:00:00Z
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
        image: quay.io/asoro/rhdh-must-gather:latest
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

This tool focuses exclusively on RHDH-related resources. For cluster-wide information, combine with generic must-gather.

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

#### Common RHDH Resources
- All resources in RHDH namespaces
- RHDH pod logs (current and previous)
- RHDH-related events
- RHDH services and networking
- RHDH Persistent Volume Claims
- Multi-container and init container logs

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
│ • RHDH namespace│───▶│ • RHDH resources│───▶│ • Remove secrets│
│ • Deploy method │    │ • RHDH logs     │    │ • Mask tokens   │
│ • Multi-instance│    │ • RHDH events   │    │ • Redact PII    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Key Components

- **`collection/gather`**: Main orchestrator script
- **`collection/detect-rhdh`**: RHDH deployment detection
- **`collection/collect-*`**: Specialized collection scripts
- **`collection/sanitize`**: Data sanitization utility
- **`collection/lib/utils.sh`**: Shared utilities and functions

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
| `SINCE` | - | Relative time for log/event collection (e.g., "2h", "30m") |
| `SINCE_TIME` | - | Absolute timestamp for log/event collection (RFC3339) |

### Command Line Options

The gather script accepts the following options:

```bash
# Default collection
/usr/local/bin/gather

# With custom output directory
MUST_GATHER_DIR=/custom/path /usr/local/bin/gather

# With debug logging
LOG_LEVEL=DEBUG /usr/local/bin/gather

# With time constraints
SINCE=2h /usr/local/bin/gather
```

## Output Structure

```
must-gather/
├── collection-summary.txt          # Summary of what was collected
├── sanitization-report.txt         # Details of data sanitization
├── rhdh-deployment-details.txt     # RHDH deployment detection results
├── rhdh-instances.env              # All detected RHDH instances
├── rhdh/                           # RHDH-specific data
│   ├── helm/                       # Helm deployment data (if detected)
│   │   ├── releases.yaml
│   │   ├── values.yaml
│   │   └── manifests/
│   ├── operator/                   # Operator deployment data (if detected)
│   │   ├── deployments.yaml
│   │   ├── backstage-crs.yaml
│   │   └── operator-logs/
│   └── resources/                  # RHDH namespace resources
│       ├── [namespace]/            # Per-namespace resources
│       └── all-resources.yaml
├── logs/                           # RHDH pod logs only
│   ├── [namespace]/                # Per-namespace logs
│   │   └── [pod-name]/             # Per-pod logs
│   └── collection-summary.txt
└── events/                         # RHDH-related events only
    ├── events-[namespace].txt      # Per-namespace events
    ├── warning-events-*.txt        # Warning events
    └── error-events-*.txt          # Error events
```

> **Note**: For cluster-wide information (nodes, storage classes, etc.), use: `oc adm must-gather`

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