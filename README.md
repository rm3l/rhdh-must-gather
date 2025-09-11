# RHDH Must-Gather Tool

A specialized diagnostic data collection tool for Red Hat Developer Hub (RHDH) deployments on Kubernetes and OpenShift clusters.

## Overview

This tool helps support teams and engineers collect essential RHDH-specific information to troubleshoot issues effectively. It focuses exclusively on RHDH resources and can be combined with generic cluster information collection. It supports:

- **Multi-platform**: OpenShift and standard Kubernetes (AKS, GKE, EKS)
- **Multi-deployment**: Helm-based and Operator-based RHDH instances
- **RHDH-focused collection**: Only RHDH-specific logs, configurations, and resources
- **Privacy-aware**: Automatic sanitization of secrets, tokens, and sensitive data (WIP)

> **Note**: This tool collects only RHDH-specific data. For cluster-wide general information, use the generic OpenShift must-gather: `oc adm must-gather`

## Quick Start

### Using with OpenShift (`oc adm must-gather`)

```bash
# Use the published image
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Collect only logs and events from last 2 hours
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=2h

# Collect logs and events since specific time
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since-time=2025-08-21T20:00:00Z
```

### Using with Kubernetes (WIP)

#### Option 1: Using PersistentVolume (Recommended)

```bash
# Create PVC for persistent storage
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rhdh-must-gather-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: batch/v1
kind: Job
metadata:
  name: rhdh-must-gather
spec:
  template:
    spec:
      containers:
      - name: must-gather
        image: ghcr.io/rm3l/rhdh-must-gather:main
        volumeMounts:
        - name: output
          mountPath: /must-gather
      volumes:
      - name: output
        persistentVolumeClaim:
          claimName: rhdh-must-gather-pvc
      restartPolicy: Never
EOF

# Wait for job completion
kubectl wait --for=condition=complete job/rhdh-must-gather --timeout=600s

# Create a temporary pod to access the data
kubectl run data-retriever --image=busybox --rm -i --tty \
  --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"rhdh-must-gather-pvc"}}],"containers":[{"name":"data-retriever","image":"busybox","volumeMounts":[{"name":"data","mountPath":"/data"}],"stdin":true,"tty":true}]}}' \
  -- tar -czf - -C /data . > must-gather-output.tar.gz

# Clean up
kubectl delete job rhdh-must-gather
kubectl delete pvc rhdh-must-gather-pvc
```

#### Option 2: Using initContainer with Shared Volume

```bash
# Use an init container pattern with a long-running sidecar
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: rhdh-must-gather
spec:
  template:
    spec:
      initContainers:
      - name: must-gather
        image: ghcr.io/rm3l/rhdh-must-gather:main
        volumeMounts:
        - name: output
          mountPath: /must-gather
      containers:
      - name: data-holder
        image: busybox
        command: ["sleep", "3600"]  # Sleep for 1 hour
        volumeMounts:
        - name: output
          mountPath: /must-gather
      volumes:
      - name: output
        emptyDir: {}
      restartPolicy: Never
EOF

# Wait for init container to complete
kubectl wait --for=condition=initialized pod -l job-name=rhdh-must-gather --timeout=600s

# Copy the results
POD_NAME=$(kubectl get pods -l job-name=rhdh-must-gather -o jsonpath='{.items[0].metadata.name}')
kubectl cp $POD_NAME:/must-gather ./must-gather-output

# Clean up
kubectl delete job rhdh-must-gather
```

### Local Development/Testing

```bash
# Clone the repository
git clone <repository-url>
cd rhdh-must-gather

# Run locally (requires kubectl access)
make test-local-all

# Build and test in container
make build test-container
```

## What Data is Collected

This tool focuses exclusively on RHDH-related resources. For cluster-wide information, combine with generic must-gather.

### Platform Information (gather_platform)
- **Platform Detection**: Automatically identifies the Kubernetes platform type:
    - **OpenShift**: OCP, ROSA (Red Hat OpenShift Service on AWS), ARO (Azure Red Hat OpenShift), ROKS (Red Hat OpenShift on IBM Cloud)
    - **Managed Kubernetes**: EKS (AWS), GKE (Google Cloud), AKS (Azure)
    - **Vanilla Kubernetes**: Standard Kubernetes installations
- **Infrastructure Detection**: Identifies underlying cloud providers (AWS, GCP, Azure, IBM Cloud, vSphere)
- **Version Information**: Collects OpenShift and Kubernetes version details

### RHDH-Specific Data

#### Helm Deployments (gather_helm)
- **Release Information**: Helm releases, history, status (text and YAML formats)
- **Configuration**: User-provided values, computed values, manifests, hooks, and notes
- **Kubernetes Resources**: Deployments, StatefulSets with full YAML definitions and descriptions
- **[Application Runtime Data](#application-runtime-data-extracted-from-running-containers)**
- **Namespace Resources**: All ConfigMaps and Secrets (sanitized) with descriptions

#### Operator Deployments (gather_operator)
- **OLM Information**: ClusterServiceVersions, Subscriptions, InstallPlans, OperatorGroups, CatalogSources
- **Custom Resources**: Backstage CRDs with definitions and descriptions
- **Backstage Custom Resources**: Full CR configurations and status
- **Operator Infrastructure**: Deployments, logs, and configurations in operator namespaces
- **[Application Runtime Data](#application-runtime-data-extracted-from-running-containers)**
- **Namespace Resources**: ConfigMaps and Secrets (sanitized) for each namespace containing Backstage CRs

#### Application Runtime Data (extracted from running containers)
- **RHDH version information**: `backstage.json` contains Backstage version
- **Build metadata**: `build-metadata.json` with RHDH version, Backstage version, upstream/midstream sources, and build timestamp
- **Node.js version**: Runtime Node.js version from `node --version`
- **Container user ID**: Security context information from `id` command
- **Dynamic plugins structure**: Directory listing of `dynamic-plugins-root` filesystem
- **Generated app-config**: `app-config.dynamic-plugins.yaml` created by the dynamic plugins installer

#### Dynamic Plugins and Configuration
- **Dynamic plugins root directory** structure from filesystem (`ls -lhrta dynamic-plugins-root`)
- **Generated app-config** from dynamic plugins installer (`app-config.dynamic-plugins.yaml`)
- **ConfigMaps** containing app configurations and dynamic plugin definitions
- **Plugin dependencies** and configurations including installed dynamic plugins like:
  - Red Hat Developer Hub plugins (global-header, quickstart, dynamic-home-page, marketplace)
  - Backstage community plugins (techdocs, scaffolder modules, analytics providers)
  - Backend modules and frontend components

#### Logs and Runtime Data
- **Container logs** with configurable time windows (`MUST_GATHER_SINCE`, `MUST_GATHER_SINCE_TIME`)
- **Multi-container logs**: Separate logs for `backstage-backend` and `install-dynamic-plugins` containers
- **Database logs** from PostgreSQL StatefulSets
- **Must-gather container logs** (when running in pod)

#### RHDH Kubernetes Resources (Detailed)
- **Deployments and StatefulSets**: Full YAML definitions and kubectl describe output
- **Pods**: Complete pod specifications, status, and logs for all related pods
- **ConfigMaps**: Application configurations, dynamic plugins, and other config data
- **Secrets**: Sanitized secret resources (data fields redacted for security)
- **Services, Routes, Ingresses**: Network configurations for RHDH access

### Cluster Information (optional)
- **Cluster-wide diagnostic dump** using `oc cluster-info dump` (enabled with `--cluster-info` flag)

## Privacy and Security (WIP)

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

**Important**: While automatic sanitization catches common sensitive patterns, always review the sanitization report and manually check for any domain-specific sensitive information before sharing externally.

## Configuration

### Environment Variables

| Variable                 | Default         | Description                                            |
|--------------------------|-----------------|--------------------------------------------------------|
| `BASE_COLLECTION_PATH`   | `/must-gather`  | Output directory for collected data                    |
| `LOG_LEVEL`              | `info`          | Logging level (info, debug, trace)                     |
| `CMD_TIMEOUT`            | `30`            | Timeout for individual kubectl/helm commands (seconds) |
| `MUST_GATHER_SINCE`      | -               | Relative time for log collection (e.g., "2h", "30m")   |
| `MUST_GATHER_SINCE_TIME` | -               | Absolute timestamp for log collection (RFC3339)        |

### Command Line Options

The gather script accepts the following options:

```bash
# Default collection (Helm and Operator data)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather

# With cluster-wide information
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --cluster-info

# With time constraints (last 2 hours)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather --since=2h

# With debug logging
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- LOG_LEVEL=debug /usr/bin/gather

# Help information
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --help
```

## Output Structure

```
/must-gather/
├── version                         # Tool version information (e.g., "rhdh/must-gather 0.0.0-unknown")
├── must-gather.log                 # Must-gather container logs (if running in pod)
├── sanitization-report.txt         # Data sanitization summary and details
├── cluster-info/                   # Cluster-wide information (if --cluster-info used)
│   └── [cluster-info dump output]
└── rhdh/                           # RHDH-specific data (automatically sanitized)
    ├── platform/                   # Platform and infrastructure information
    │   ├── platform.json           # Structured platform data (platform, underlying, versions)
    │   └── platform.txt            # Human-readable platform summary
    ├── helm/                       # Helm deployment data (if RHDH Helm releases found)
    │   ├── all-rhdh-releases.txt   # List of detected RHDH Helm releases with namespaces, revisions, status
    │   └── releases/               # Per-release data
    │       └── ns=[namespace]/     # Per-namespace organization
    │           ├── _configmaps/    # Namespace-wide ConfigMaps with both formats
    │           │   ├── [configmap-name].yaml               # Full ConfigMap YAML
    │           │   └── [configmap-name].describe.txt       # kubectl describe output
    │           ├── _secrets/       # Namespace-wide Secrets (sanitized) with describe only
    │           │   └── [secret-name].describe.txt          # kubectl describe output (data redacted)
    │           └── [release-name]/ # Per-release directory
    │               ├── values.yaml         # User-provided values
    │               ├── all-values.yaml     # All computed values (25KB+ files)
    │               ├── manifest.yaml       # Deployed manifest (18KB+ files)
    │               ├── hooks.yaml          # Helm hooks
    │               ├── history.txt         # Release history
    │               ├── history.yaml        # Release history (YAML)
    │               ├── status.txt          # Release status (text)
    │               ├── status.yaml         # Release status (YAML, 21KB+ files)
    │               ├── notes.txt           # Release notes
    │               ├── deployment/         # Application deployment info
    │               │   ├── deployment.yaml
    │               │   ├── deployment.describe.txt
    │               │   ├── app-container-userid.txt      # "uid=1001 gid=0(root) groups=0(root)"
    │               │   ├── backstage.json              # {"version": "1.39.1"}
    │               │   ├── build-metadata.json         # RHDH version, Backstage version, source repos, build time
    │               │   ├── node-version.txt            # "v22.16.0"
    │               │   ├── dynamic-plugins-root.fs.txt # Directory listing with plugin packages
    │               │   ├── app-config.dynamic-plugins.yaml # Generated app config (9KB files)
    │               │   ├── logs-app.txt                # All container logs (2MB+ files)
    │               │   ├── logs-app--backstage-backend.txt # Backend logs (2MB+ files)
    │               │   ├── logs-app--install-dynamic-plugins.txt # Init container logs (17KB files)
    │               │   └── pods/           # Pod details and logs
    │               │       ├── pods.txt
    │               │       ├── pods.yaml
    │               │       └── pods.describe.txt
    │               └── db-statefulset/     # Database StatefulSet info (if database enabled)
    │                   ├── db-statefulset.yaml
    │                   ├── db-statefulset.describe.txt
    │                   ├── logs-db.txt     # Database logs
    │                   └── pods/           # Database pod details
    │                       ├── pods.txt
    │                       ├── pods.yaml
    │                       └── pods.describe.txt
    └── operator/                   # Operator deployment data (if RHDH operators found)
        ├── all-deployments.txt     # List of all RHDH operator deployments
        ├── olm/                    # OLM information
        │   ├── rhdh-csv-all.txt    # ClusterServiceVersions
        │   ├── rhdh-subscriptions-all.txt # Subscriptions
        │   ├── installplans-all.txt # InstallPlans
        │   ├── operatorgroups-all.txt # OperatorGroups
        │   └── catalogsources-all.txt # CatalogSources
        ├── crds/                   # Custom Resource Definitions
        │   ├── all-crds.txt        # All CRDs in cluster
        │   ├── backstages.rhdh.redhat.com.yaml # RHDH CRD definition
        │   └── backstages.rhdh.redhat.com.describe.txt # CRD description
        ├── ns=[operator-namespace]/ # Per-operator-namespace data (e.g., ns=rhdh-operator)
        │   ├── all-resources.txt   # All resources in namespace
        │   ├── configs/            # ConfigMaps with both formats
        │   │   ├── all-configmaps.txt
        │   │   ├── [configmap-name].yaml       # Full ConfigMap YAML
        │   │   └── [configmap-name].describe.txt # kubectl describe output
        │   ├── deployments/        # Operator deployments
        │   │   ├── all-deployments.txt
        │   │   ├── [deployment-selector].yaml
        │   │   └── [deployment-selector].describe.txt
        │   └── logs.txt           # Operator logs
        └── backstage-crs/          # Backstage Custom Resources
            ├── all-backstage-crs.txt # List of all Backstage CRs
            └── ns=[cr-namespace]/  # Per-CR-namespace data (where Backstage CRs are deployed)
                ├── _configmaps/    # Namespace-wide ConfigMaps with both formats
                │   ├── [configmap-name].yaml               # Full ConfigMap YAML
                │   └── [configmap-name].describe.txt       # kubectl describe output
                ├── _secrets/       # Namespace-wide Secrets (sanitized) with describe only
                │   └── [secret-name].describe.txt          # kubectl describe output (data redacted)
                └── [cr-name]/      # Per-CR directory
                    ├── [cr-name].yaml      # CR definition
                    ├── describe.txt        # CR description
                    ├── deployment/         # Application deployment (same structure as Helm)
                    │   ├── deployment.yaml
                    │   ├── deployment.describe.txt
                    │   ├── app-container-userid.txt      # "uid=1001 gid=0(root) groups=0(root)"
                    │   ├── backstage.json              # {"version": "1.39.1"}
                    │   ├── build-metadata.json         # RHDH version, Backstage version, source repos, build time
                    │   ├── node-version.txt            # "v22.16.0"
                    │   ├── dynamic-plugins-root.fs.txt # Directory listing with plugin packages
                    │   ├── app-config.dynamic-plugins.yaml # Generated app config (9KB files)
                    │   ├── logs-app.txt                # All container logs (2MB+ files)
                    │   ├── logs-app--backstage-backend.txt # Backend logs (2MB+ files)
                    │   ├── logs-app--install-dynamic-plugins.txt # Init container logs (17KB files)
                    │   └── pods/           # Application pods
                    │       ├── pods.txt
                    │       ├── pods.yaml
                    │       └── pods.describe.txt
                    └── db-statefulset/     # Database StatefulSet (if database enabled)
                        ├── db-statefulset.yaml
                        ├── db-statefulset.describe.txt
                        ├── logs-db.txt     # Database logs
                        └── pods/           # Database pods
                            ├── pods.txt
                            ├── pods.yaml
                            └── pods.describe.txt
```

> **Note**: The tool automatically detects and collects data for both Helm and Operator-based RHDH deployments. For cluster-wide information, use the `--cluster-info` flag or combine with standard `oc adm must-gather`.

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

### Building the Image

```bash
# Build locally
make build

# Build and push to registry
make build-push REGISTRY=your-registry.com/namespace

# Build and push with custom image name and tag
make build-push REGISTRY=your-registry.com/namespace IMAGE_NAME=my-rhdh-must-gather IMAGE_TAG=v1.0.0
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

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
