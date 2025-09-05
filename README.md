# RHDH Must-Gather Tool

A specialized diagnostic data collection tool for Red Hat Developer Hub (RHDH) deployments on Kubernetes and OpenShift clusters.

## Overview

This tool helps support teams and engineers collect essential RHDH-specific information to troubleshoot issues effectively. It focuses exclusively on RHDH resources and can be combined with generic cluster information collection. It supports:

- **Multi-platform**: OpenShift and standard Kubernetes (AKS, GKE, EKS)
- **Multi-deployment**: Helm-based and Operator-based RHDH instances
- **RHDH-focused collection**: Only RHDH-specific logs, configurations, and resources
- **Privacy-aware**: Automatic sanitization of secrets, tokens, and sensitive data

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

#### Helm Deployments (gather_helm)
- Helm release information and history
- Values files (user-provided and computed values)
- Deployed manifests and hooks
- Release notes and status
- Application deployment logs and pod details
- Database StatefulSet logs and pod details

#### Operator Deployments (gather_operator)
- OLM (Operator Lifecycle Manager) information including CSVs, subscriptions, and install plans
- Custom Resource Definitions (CRDs) for RHDH
- Backstage Custom Resources and their configurations
- Operator deployment logs and status
- RHDH operator ConfigMaps and secrets in all detected namespaces
- Application and database deployment logs for each Backstage CR

#### Cluster Information (optional)
- Cluster-wide diagnostic dump using `oc cluster-info dump` (enabled with `--cluster-info` flag)

#### Logs and Runtime Data
- Must-gather container logs
- Pod logs with configurable time windows (`MUST_GATHER_SINCE`, `MUST_GATHER_SINCE_TIME`)
- Multi-container and init container logs for all RHDH-related pods

## Privacy and Security

### Automatic Data Sanitization

The tool includes automatic sanitization of sensitive information to make the collected data safe for sharing:

**Automatically Sanitized Data:**
- **Kubernetes Secret data values** - All `data:` fields in Secret resources are replaced with `[REDACTED]`
- **Base64 encoded sensitive data** - Long base64 strings (40+ characters) that likely contain sensitive information
- **JWT tokens** - Complete JWT tokens matching the standard format
- **Bearer tokens** - Authorization headers with bearer tokens
- **SSH private keys** - Complete SSH key blocks from BEGIN to END
- **Database connection strings** - URLs containing embedded credentials
- **URLs with credentials** - HTTP/HTTPS URLs with username:password@ format

**Sanitization Features:**
- **Precision targeting** - Avoids false positives on legitimate data like Kubernetes status fields
- **Structure preservation** - Maintains YAML/JSON structure for diagnostic value
- **Comprehensive coverage** - Processes all YAML, JSON, and text files in the collected data
- **Detailed reporting** - Provides sanitization summary with file and item counts

### Using the Sanitize Script

```bash
# Sanitize collected data (automatically called during collection)
./collection-scripts/sanitize /path/to/must-gather-output

# The script generates a sanitization report at:
# /path/to/must-gather-output/sanitization-report.txt
```

**Important**: While automatic sanitization catches common sensitive patterns, always review the sanitization report and manually check for any domain-specific sensitive information before sharing externally.

## Architecture

The tool consists of specialized collection scripts that gather data from different RHDH deployment methods:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Detection     │    │   Collection    │    │    Output       │
│                 │    │                 │    │                 │
│ • Helm releases │───▶│ • Helm data     │───▶│ • Structured    │
│ • Operator CRDs │    │ • Operator data │    │   output        │
│ • Backstage CRs │    │ • Pod logs      │    │ • Organized by  │
│                 │    │ • Cluster info  │    │   deployment    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Key Components

- **`collection-scripts/gather_rhdh`**: Main orchestrator script that coordinates all collection activities and applies sanitization
- **`collection-scripts/gather_helm`**: Collects Helm-specific RHDH deployment data including releases, values, manifests, and associated pod logs
- **`collection-scripts/gather_operator`**: Collects Operator-specific data including CRDs, Backstage Custom Resources, OLM information, and operator logs
- **`collection-scripts/gather_cluster-info`**: Collects cluster-wide information using `oc cluster-info dump`
- **`collection-scripts/sanitize`**: Automatically sanitizes sensitive data (secrets, tokens, credentials) from collected files
- **`collection-scripts/common.sh`**: Shared utilities, logging functions, and environment setup
- **`collection-scripts/logs.sh`**: Collects must-gather container logs
- **`collection-scripts/version`**: Version information for the tool

## Building the Image

```bash
# Build locally
make build

# Build and push to registry
make build-push REGISTRY=your-registry.com/namespace

# Build and push with custom image name and tag
make build-push REGISTRY=your-registry.com/namespace IMAGE_NAME=my-rhdh-must-gather IMAGE_TAG=v1.0.0
```

## Configuration

### Environment Variables

| Variable                 | Default         | Description                                            |
|--------------------------|-----------------|--------------------------------------------------------|
| `BASE_COLLECTION_PATH`   | `/must-gather`  | Output directory for collected data                    |
| `LOG_LEVEL`              | `info`          | Logging level (info, debug, trace)                     |
| `CMD_TIMEOUT`            | `30`            | Timeout for individual kubectl/helm commands (seconds) |
| `MUST_GATHER_SINCE`      | -               | Relative time for log collection (e.g., "2h", "30m")   |
| `MUST_GATHER_SINCE_TIME` | -               | Absolute timestamp for log collection (RFC3339)        |
| `INSTALLATION_NAMESPACE` | `rhdh-operator` | Default namespace for RHDH operator installation       |

### Command Line Options

The gather script accepts the following options:

```bash
# Default collection (Helm and Operator data)
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather

# With cluster-wide information
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather -- /usr/bin/gather --cluster-info

# With time constraints (last 2 hours)
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather --since=2h

# With debug logging
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather -- LOG_LEVEL=debug /usr/bin/gather

# Help information
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather -- /usr/bin/gather --help
```

## Output Structure

```
/must-gather/
├── version                         # Tool version information
├── must-gather.log                 # Must-gather container logs (if running in pod)
├── sanitization-report.txt         # Data sanitization summary and details
├── cluster-info/                   # Cluster-wide information (if --cluster-info used)
│   └── [cluster-info dump output]
└── rhdh/                           # RHDH-specific data (automatically sanitized)
    ├── helm/                       # Helm deployment data (if RHDH Helm releases found)
    │   ├── all-rhdh-releases.txt   # List of detected RHDH Helm releases
    │   └── releases/               # Per-release data
    │       └── ns=[namespace]/     # Per-namespace organization
    │           └── [release-name]/ # Per-release directory
    │               ├── values.yaml         # User-provided values
    │               ├── all-values.yaml     # All computed values
    │               ├── manifest.yaml       # Deployed manifest
    │               ├── hooks.yaml          # Helm hooks
    │               ├── history.txt         # Release history
    │               ├── status.yaml         # Release status
    │               ├── deployment/         # Application deployment info
    │               │   ├── deployment.yaml
    │               │   ├── logs-deployment.txt
    │               │   └── pods/           # Pod details and logs
    │               └── db-statefulset/     # Database StatefulSet info
    │                   ├── db-statefulset.yaml
    │                   ├── logs-db.txt
    │                   └── pods/           # Database pod details
    └── operator/                   # Operator deployment data (if RHDH operators found)
        ├── all-deployments.txt     # List of all RHDH operator deployments
        ├── olm/                    # OLM information
        │   ├── rhdh-csv-all.txt    # ClusterServiceVersions
        │   ├── rhdh-subscriptions-all.txt # Subscriptions
        │   ├── installplans-all.txt # InstallPlans
        │   └── catalogsources-all.txt # CatalogSources
        ├── crds/                   # Custom Resource Definitions
        │   ├── all-crds.txt        # All CRDs in cluster
        │   └── backstages.rhdh.redhat.com.yaml # RHDH CRD definition
        ├── ns=[namespace]/         # Per-operator-namespace data
        │   ├── all-resources.txt   # All resources in namespace
        │   ├── configs/            # ConfigMaps
        │   ├── deployments/        # Operator deployments
        │   └── logs.txt           # Operator logs
        └── backstage-crs/          # Backstage Custom Resources
            ├── all-backstage-crs.txt # List of all Backstage CRs
            └── ns=[namespace]/     # Per-CR-namespace data
                └── [cr-name]/      # Per-CR directory
                    ├── [cr-name].yaml      # CR definition
                    ├── describe.txt        # CR description
                    ├── configmaps/         # Associated ConfigMaps
                    ├── secrets/            # Associated Secrets
                    ├── deployment/         # Application deployment
                    │   ├── deployment.yaml
                    │   ├── logs-deployment.txt
                    │   └── pods/           # Application pods
                    └── db-statefulset/     # Database StatefulSet
                        ├── db-statefulset.yaml
                        ├── logs-db-statefulset.txt
                        └── pods/           # Database pods
```

> **Note**: The tool automatically detects and collects data for both Helm and Operator-based RHDH deployments. For cluster-wide information, use the `--cluster-info` flag or combine with standard `oc adm must-gather`.

## Troubleshooting

### Common Issues

**No RHDH deployment detected**
- Verify RHDH is running in the cluster
- Check if it's in a non-standard namespace
- Ensure proper RBAC permissions

**Command timeouts**
- Increase `CMD_TIMEOUT` environment variable (default: 30 seconds)
- Check cluster network connectivity
- Verify sufficient resources

**Permission denied errors**
- Ensure the tool has cluster-admin or sufficient RBAC permissions
- Check ServiceAccount configuration in OpenShift

### Getting Help

1. Check the tool output files in `/must-gather/rhdh/` for what was detected
2. Review the `must-gather.log` file for container execution logs
3. Check the `sanitization-report.txt` file for data sanitization summary
4. Check individual script outputs:
   - `/must-gather/rhdh/helm/all-rhdh-releases.txt` for Helm deployment detection
   - `/must-gather/rhdh/operator/all-deployments.txt` for Operator deployment detection
5. Verify cluster connectivity with `kubectl cluster-info`
6. Run with debug logging: `LOG_LEVEL=debug` to see detailed execution information

## Development

### Testing

```bash
# Test locally (requires kubectl access to cluster)
make test-local-all

# Test specific script locally
make test-local-script SCRIPT=helm    # Test only gather_helm
make test-local-script SCRIPT=operator # Test only gather_operator

# Test in container with local cluster access
make test-container-all

# Test with OpenShift using oc adm must-gather
make openshift-test

# Test on regular Kubernetes (non-OpenShift) by creating a Job in the cluster
make k8s-test

# Clean up test artifacts and images
make clean
```

### Available Variables

```bash
# Customize registry and image details
make build REGISTRY=your-registry.com IMAGE_NAME=custom-name IMAGE_TAG=v1.0.0

# Set log level for testing
make test-local-all LOG_LEVEL=debug

# View all available targets
make help
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

Apache License 2.0 - see [LICENSE](LICENSE) for details.