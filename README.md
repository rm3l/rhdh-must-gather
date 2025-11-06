# RHDH Must-Gather Tool (WIP)

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

### Namepace's inspect (collected by default)
- **Deep namespace resource inspection** using `oc adm inspect namespace` (included by default for OMC compatibility)
- **Auto-detects RHDH namespaces**:
  - Namespaces with Helm-based RHDH deployments
  - Namespaces with Backstage Custom Resources (operator-based)
  - **RHDH operator namespace(s)** automatically included
- **OMC-compatible output** - works with [OpenShift Must-Gather Client (OMC)](https://github.com/gmeghnag/omc) for interactive analysis
- **Comprehensive resource collection** including:
  - All Kubernetes resources in YAML format
  - Pod logs (current and previous containers)
  - Events timeline for troubleshooting
  - Resource descriptions and status
  - Network configurations
  - Standard must-gather directory structure
- **Can be disabled** with `--without-namespace-inspect` flag (not recommended - removes OMC compatibility)

### Heap Dumps (opt-in, disabled by default)
- **Memory diagnostics** from running backstage-backend containers using `--with-heap-dumps`
- **Integrated collection**: Heap dumps are collected automatically **right after pod logs** for each Helm release and Backstage CR
- **Per-deployment context**: Each heap dump is stored within its deployment/CR directory for easy correlation with logs
- **Automatic detection**: 
  - Finds all running backstage-backend pods for each deployment
  - Targets only the `backstage-backend` container (skips all sidecars automatically)
  - Detects Node.js process PID using portable methods (`ps` command or `/proc` filesystem)
  - Works with minimal container images without `pidof` or `pgrep` utilities
- **Collection method**:
  - **SIGUSR2 signal** sent directly to the backstage-backend container via `kubectl exec`
  - Works if Node.js is started with `--heapsnapshot-signal=SIGUSR2` (recommended) or if application has heapdump module/custom SIGUSR2 handler
  - Simple, reliable, and works with any Kubernetes version
- **Process metadata**: Memory usage, Node.js version, disk space, and process information collected alongside dumps
- **Use cases**: Memory leak troubleshooting, performance analysis, and OOM investigations
- **File format**: `.heapsnapshot` files compatible with Chrome DevTools and other heap analysis tools
- **Important limitations**:
  - Requires application to handle SIGUSR2 signal. Choose ONE of:
    - ⭐ `NODE_OPTIONS="--heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp"` (built-in Node.js, recommended - no image rebuild!)
    - `NODE_OPTIONS="--require heapdump"` with heapdump module in image
    - Custom SIGUSR2 signal handler in application code
  - **Note**: `--diagnostic-dir=/tmp` is required for containers with read-only root filesystems
  - Heap dumps can be very large (100MB-1GB+ per pod) and take several minutes per deployment
  - Success rate depends on application instrumentation

### Cluster Information (optional)
- **Cluster-wide diagnostic dump** using `oc cluster-info dump` (enabled with `--cluster-info` flag)

## Using with OMC (OpenShift Must-Gather Client)

The Namepace's inspect output is fully compatible with [OMC (OpenShift Must-Gather Client)](https://github.com/gmeghnag/omc), a powerful tool for interactive must-gather analysis used by Support teams.

**Note**: Namepace's inspect is now **collected by default**, so all must-gather outputs are OMC-compatible.

### Setup

1. **Collect data** (Namepace's inspect included by default):
   ```bash
   oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
   ```

2. **Install OMC** (if not already installed):
   ```bash
   curl -sL https://github.com/gmeghnag/omc/releases/latest/download/omc_$(uname)_$(uname -m).tar.gz | tar xzf - omc
   chmod +x ./omc
   sudo mv ./omc /usr/local/bin/
   ```

### Using OMC with Namepace's inspect Data

Point OMC to the Namepace's inspect directory:

```bash
# Navigate to your must-gather output
cd must-gather.local.*/

# Use OMC with the Namepace's inspect directory
omc use namespace-inspect

# Now query resources interactively (OMC will see all inspected namespaces)
omc get pods --all-namespaces
omc get pods -n rhdh-prod
omc get deployments -n rhdh-staging -o wide
omc get events --sort-by='.lastTimestamp'
```

### OMC Examples for RHDH Troubleshooting

```bash
# List all pods with their node assignments
omc get pods -o wide

# Get pods by label
omc get pods -l app.kubernetes.io/name=backstage

# Retrieve deployment details
omc get deployment backstage-bs1 -o yaml

# Check events for a specific pod
omc get events --field-selector involvedObject.name=<pod-name>

# Get all resources of a specific type
omc get configmaps -o name

# Use JSONPath queries
omc get pods -o jsonpath="{.items[*].metadata.name}"

# Check certificate details (if OMC certs command is available)
omc certs inspect
```

### Multi-Namespace Analysis

With a single OMC context, you can query across all collected namespaces:

```bash
# Point OMC to the inspection directory once
omc use namespace-inspect

# Query different namespaces
omc get pods -n rhdh-prod
omc get pods -n rhdh-staging

# Or view all namespaces at once
omc get pods --all-namespaces
omc get namespaces
```

### OMC Benefits

- 🔍 **Interactive queries**: Use familiar `kubectl`/`oc` commands on offline data
- 🚀 **Fast analysis**: Query resources without cluster access
- 📊 **Advanced filtering**: Labels, field selectors, JSONPath
- 🔐 **Secure**: Analyze sensitive data offline
- 📈 **Resource comparison**: Compare resources across namespaces or time periods

### Directory Structure for OMC

The Namepace's inspect creates OMC-compatible directory structures:

```
namespace-inspect/            # ← Point OMC here: omc use namespace-inspect
├── namespaces/               # All inspected namespaces in one place
│   ├── rhdh-prod/           # First namespace
│   │   ├── apps/            # Deployments, StatefulSets, etc.
│   │   ├── core/            # Pods, Services, ConfigMaps, Secrets
│   │   ├── batch/           # Jobs, CronJobs
│   │   └── networking.k8s.io/
│   ├── rhdh-staging/        # Second namespace
│   │   └── [same structure]
│   └── ...                  # Additional namespaces
├── event-filter.html
└── aggregated-discovery-apis.yaml
```

**Tip**: Single OMC context for all namespaces - no need to switch contexts when analyzing multiple environments.

## Analyzing Heap Dumps

When heap dumps are collected using `--with-heap-dumps`, they can be analyzed using various tools to investigate memory leaks, high memory usage, and performance issues.

### Prerequisites for Heap Dump Collection

**Important**: Heap dump collection from running Node.js processes requires either:

1. **Node.js Built-in Signal Handler** (⭐ Recommended - Simplest!):
   
   Use Node.js's built-in `--heapsnapshot-signal` flag (available since Node.js v12.0.0):
   
   ```yaml
   # In your Deployment or Backstage CR
   spec:
     template:
       spec:
         containers:
         - name: backstage-backend
           env:
           - name: NODE_OPTIONS
             value: "--heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp"
   ```
   
   Or modify the command directly:
   ```yaml
           command: ["node", "--heapsnapshot-signal=SIGUSR2", "--diagnostic-dir=/tmp", "dist/index.js"]
   ```
   
   **Important**: The `--diagnostic-dir=/tmp` flag is required for containers with read-only root filesystems. Without it, heap snapshots cannot be written to the default current working directory.
   
   **Advantages:**
   - ✅ Built into Node.js - no external dependencies or modules!
   - ✅ No image rebuild required
   - ✅ No source code changes needed
   - ✅ Works immediately with must-gather `--with-heap-dumps`
   - ✅ Heap snapshots written to `/tmp/Heap.<timestamp>.heapsnapshot` automatically
   - ✅ Works with read-only root filesystems (common security best practice)
   
   **How it works:** When Node.js receives SIGUSR2 signal, it automatically writes a heap snapshot to `Heap.<timestamp>.heapsnapshot` in the directory specified by `--diagnostic-dir` (or current working directory if not specified).
   
   **Reference:** [Node.js CLI Documentation](https://nodejs.org/docs/latest-v22.x/api/cli.html#--heapsnapshot-signalsignal)

2. **Application Instrumentation** (Alternative if you need custom behavior):
   
   **With source code access:**
   ```javascript
   // In your backend/src/index.ts or similar
   require('heapdump');  // Enables SIGUSR2 signal handler for heap dumps
   ```
   
   Or add a custom signal handler:
   ```javascript
   process.on('SIGUSR2', () => {
     const v8 = require('v8');
     const path = require('path');
     const filename = path.join('/tmp', `heapdump-${Date.now()}.heapsnapshot`);
     v8.writeHeapSnapshot(filename);
     console.log(`Heap dump written to ${filename}`);
   });
   ```
   
   **Without source code access** (requires image rebuild):
   
   1. Add heapdump to your `package.json`:
      ```json
      {
        "dependencies": {
          "heapdump": "^1.3.0"
        }
      }
      ```
   
   2. Rebuild and push your container image:
      ```bash
      docker build -t your-registry/rhdh:custom .
      docker push your-registry/rhdh:custom
      ```
   
   3. Update your Deployment or Backstage CR:
      ```yaml
      spec:
        template:
          spec:
            containers:
            - name: backstage-backend
              image: your-registry/rhdh:custom  # Use your custom image
              env:
              - name: NODE_OPTIONS
                value: "--require heapdump"
      ```
   
   4. Redeploy and the application will automatically handle SIGUSR2 for heap dumps
   
   **Note**: If you see "Cannot find module 'heapdump'" error, the module is not in your container image. You must rebuild the image with heapdump included.

**Without instrumentation**, heap dump collection will fail with an informative message explaining how to enable it for future troubleshooting.

### ⚠️ Important: No "Quick Fix" Without Instrumentation

**There is no way to extract a heap dump from a running Node.js process without prior instrumentation.**

Common misconceptions:
- ❌ `kubectl exec ... node --eval 'v8.writeHeapSnapshot(...)'` - This spawns a **new** Node.js process, not the running one
- ❌ Sending signals without handlers - Only works if the app has SIGUSR2 handlers configured
- ❌ Attaching debuggers after the fact - Requires `--inspect` to be enabled at startup

**The reality:** You must plan ahead by:
1. ⭐ **Starting Node.js with `--heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp`** (built into Node.js, no modules needed!), **OR**
2. Adding `heapdump` module to your container image, **OR**
3. Modifying source code to add custom SIGUSR2 signal handlers

**Recommended**: Use Node.js's built-in `--heapsnapshot-signal=SIGUSR2 --diagnostic-dir=/tmp` flags - it's the simplest and most reliable method with zero dependencies and no image rebuild required! The `--diagnostic-dir=/tmp` is essential for containers with read-only root filesystems.

### Heap Dump Files

Heap dumps are saved as `.heapsnapshot` files within each deployment/CR directory, right alongside the logs:

```
# For Helm deployments:
helm/releases/ns=my-ns/my-release/deployment/heap-dumps/
└── pod=backstage-xyz/
    └── container=backstage-backend/
        ├── heapdump-20250105-143022.heapsnapshot  (500MB)
        ├── process-info.txt
        ├── heap-dump.log
        └── pod-spec.yaml

# For Operator deployments:
operator/backstage-crs/ns=my-ns/my-backstage-cr/deployment/heap-dumps/
└── pod=backstage-my-backstage-cr-xyz/
    └── container=backstage-backend/
        ├── heapdump-20250105-143022.heapsnapshot  (500MB)
        ├── process-info.txt
        ├── heap-dump.log
        └── pod-spec.yaml
```

This structure makes it easy to correlate heap dumps with the corresponding logs and deployment information.

### Analysis Tools

#### 1. Chrome DevTools (Recommended)

Chrome DevTools provides a powerful, visual interface for analyzing heap snapshots:

```bash
# Open Chrome and navigate to DevTools
# 1. Open Chrome browser
# 2. Press F12 or Ctrl+Shift+I to open DevTools
# 3. Go to the "Memory" tab
# 4. Click "Load" button
# 5. Select the .heapsnapshot file from must-gather output

# Or use Chrome DevTools from command line
google-chrome --auto-open-devtools-for-tabs
```

**Chrome DevTools Features:**
- **Summary view**: Object types, counts, and sizes
- **Comparison view**: Compare multiple snapshots to find memory leaks
- **Containment view**: Object references and retention paths
- **Statistics**: Memory distribution by type

#### 2. Node.js CLI Analysis

```bash
# Install heap snapshot utilities
npm install -g heapsnapshot-parser

# Parse and analyze heap dump
heapsnapshot-parser heapdump-20250105-143022.heapsnapshot
```

#### 3. MemLab (Facebook's Memory Leak Detector)

```bash
# Install MemLab
npm install -g @memlab/cli

# Analyze heap snapshot
memlab analyze heapdump-20250105-143022.heapsnapshot
```

### Common Analysis Workflows

#### Finding Memory Leaks

1. **Collect multiple snapshots over time** (optional, not done automatically):
   ```bash
   # Collect initial snapshot
   oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --with-heap-dumps
   
   # Wait 30 minutes for memory to grow
   # Collect second snapshot
   oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --with-heap-dumps
   ```

2. **Compare snapshots in Chrome DevTools**:
   - Load first snapshot
   - Take note of baseline memory usage
   - Load second snapshot
   - Use "Comparison" view to see what grew

3. **Look for growing object counts**:
   - Arrays that keep growing
   - Event listeners not being removed
   - Cached data not being cleaned up

#### Investigating High Memory Usage

1. **Load snapshot in Chrome DevTools**
2. **Sort by "Retained Size"** to find largest objects
3. **Check "Distance" column** to see how far objects are from GC roots
4. **Inspect retention paths** to understand why objects aren't being freed

### Heap Dump Metadata

Each heap dump collection includes metadata files:

- **`process-info.txt`**: Node.js version, process details, memory usage at collection time
- **`heap-dump.log`**: Collection logs, any errors or warnings
- **`pod-spec.yaml`**: Complete pod specification for context

### Tips and Best Practices

- **Application instrumentation**: For reliable heap dump collection, instrument your Backstage application with `heapdump` module or signal handlers (see Prerequisites above)
- **Large files**: Heap dumps can be 100MB-1GB+. Ensure sufficient disk space and bandwidth for analysis.
- **Privacy**: Heap dumps may contain sensitive data from memory. Handle them securely and apply sanitization if sharing.
- **Timing**: Collect heap dumps when memory usage is high or after OOM events for best results.
- **Comparison**: Multiple snapshots over time help identify memory leaks vs. normal memory growth.
- **Node.js version**: Ensure your analysis tools support the Node.js version used by the application.
- **Collection methods**: The tool tries multiple approaches (kubectl debug, inspector, signals) but success depends on cluster permissions and application setup.
- **Troubleshooting failures**: If collection fails, check `heap-dump.log` and `collection-failed.txt` for specific guidance on enabling heap dumps.

## Privacy and Security

### Secret Collection (Opt-In by Default)

**By default, Kubernetes Secrets are NOT collected** to enhance privacy and security. To collect secrets (which will be automatically sanitized), use the `--with-secrets` flag:

```bash
# Default: secrets excluded
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather

# Opt-in: include secrets (will be sanitized)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --with-secrets
```

When secrets are excluded (default behavior):
- Secret resources are removed from Namepace's inspect data
- Secret resources are filtered from Helm manifests
- Secret collection is skipped in helm/operator data gathering
- ConfigMaps and other resources are still collected normally

When secrets are included (`--with-secrets`):
- Secrets are collected from all sources
- All secret data values are automatically sanitized (see below)
- Secret metadata (names, labels, annotations) is preserved for diagnostic purposes

### Automatic Data Sanitization

When secrets are collected (`--with-secrets`), the tool includes automatic sanitization of sensitive information to make the collected data safe for sharing. **All collected data is sanitized**, including:

**Data Sources Sanitized:**
- **Helm release data** - ConfigMaps, Secrets, and deployed manifests
- **Operator resources** - Backstage CRs, operator configs, and secrets
- **Namepace's inspect data** - All resources collected by `oc adm inspect` (Secrets, ConfigMaps, pod specs, etc.)
- **Platform information** - System and cluster metadata
- **Log files** - Container logs and must-gather execution logs

**Automatically Sanitized Sensitive Content:**
- **Kubernetes Secret data values** - All `data:` fields in Secret resources (including nested/indented Secrets from `oc adm inspect` output) are replaced with `[REDACTED]`
- **Base64 encoded sensitive data** - Long base64 strings (40+ characters) that likely contain tokens, passwords, or certificates
- **JWT tokens** - Complete JWT tokens matching the standard format (`eyXXX.eyXXX.XXX`)
- **Bearer tokens** - Authorization headers with bearer tokens
- **SSH private keys and TLS certificates** - Complete key blocks from BEGIN to END
- **Database connection strings** - PostgreSQL and other DB URLs containing embedded credentials
- **OAuth tokens and API keys** - Authentication tokens and client secrets
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
# Default collection (all RHDH data: platform, helm, operator, routes, ingresses, namespace-inspect)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather

# Exclude specific data collection types
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-operator
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-helm
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-platform
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-route
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-ingress
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-namespace-inspect  # Not recommended

# Collect only specific deployment types
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-operator  # Helm only
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-helm      # Operator only

# Minimal collection (platform info only, no Namepace's inspect)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-operator --without-helm --without-route --without-ingress --without-namespace-inspect

# With cluster-wide information (Namepace's inspect included by default)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --cluster-info

# Combine exclusion flags with other options
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --without-operator --cluster-info

# Combine namespace filtering (Namepace's inspect included by default)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --namespaces rhdh-prod

# Collect from specific namespaces only
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --namespaces rhdh-prod,rhdh-staging
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --namespaces=my-rhdh-namespace

# Combine namespace filtering with component exclusions
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --namespaces rhdh-ns --without-operator
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --namespaces prod-ns,staging-ns --without-helm

# With time constraints (last 2 hours)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather --since=2h

# Collect heap dumps for memory troubleshooting (opt-in, generates large files)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --with-heap-dumps

# Full diagnostic collection (secrets + heap dumps)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --with-secrets --with-heap-dumps

# With debug logging
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- LOG_LEVEL=debug /usr/bin/gather

# Help information
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather -- /usr/bin/gather --help
```

#### Available Exclusion Flags

| Flag | Description | Use Case |
|------|-------------|----------|
| `--without-operator` | Skip operator-based RHDH deployment data | When you know RHDH is deployed via Helm only |
| `--without-helm` | Skip Helm-based RHDH deployment data | When you know RHDH is deployed via Operator only |
| `--without-platform` | Skip platform detection and information | For minimal collections when platform info is not needed |
| `--without-route` | Skip OpenShift route collection | For non-OpenShift clusters or when routes are not relevant |
| `--without-ingress` | Skip Kubernetes ingress collection | When ingresses are not used for RHDH access |
| `--without-namespace-inspect` | Skip deep Namepace's inspect | **Not recommended** - removes OMC compatibility. Use only for minimal/quick collections |

#### Namespace Filtering

| Flag | Description | Use Case |
|------|-------------|----------|
| `--namespaces ns1,ns2` | Limit collection to specified comma-separated namespaces | When RHDH is deployed in specific known namespaces |
| `--namespaces=ns1,ns2` | Alternative syntax for namespace filtering | Same as above with equals syntax |

**Examples:**
- `--namespaces rhdh-prod,rhdh-staging` - Collect only from production and staging namespaces
- `--namespaces=my-rhdh-ns` - Collect only from a single namespace
- Combine with exclusions: `--namespaces prod-ns --without-helm` - Only operator data from prod-ns

#### Optional Feature Flags

| Flag | Description | Use Case |
|------|-------------|----------|
| `--cluster-info` | Collect cluster-wide diagnostic information | For comprehensive cluster analysis |
| `--with-secrets` | Include Kubernetes Secrets (sanitized) | For detailed troubleshooting requiring secret metadata |
| `--with-heap-dumps` | Collect heap dumps from backstage-backend containers | For memory leak investigation and performance analysis |

**Heap Dump Details:**
- **Collection time**: 2-5 minutes per pod (depends on heap size)
- **File size**: 100MB-1GB+ per pod (varies with memory usage)
- **Analysis tools**: Chrome DevTools, MemLab, heap-snapshot utilities
- **Use cases**: Memory leaks, OOM crashes, high memory usage troubleshooting
- **Limitations**: Requires Node.js runtime in containers, sufficient disk space

**Examples:**
- `--with-heap-dumps` - Collect heap dumps for all backstage-backend pods
- `--with-secrets --with-heap-dumps` - Full diagnostic collection
- `--namespaces prod-ns --with-heap-dumps` - Heap dumps from specific namespace only

## Output Structure

```
/must-gather/
├── version                         # Tool version information (e.g., "rhdh/must-gather 0.0.0-unknown")
├── sanitization-report.txt         # Data sanitization summary and details
├── all-routes.txt                  # All OpenShift routes cluster-wide
├── all-ingresses.txt               # All Kubernetes ingresses cluster-wide
├── must-gather.log                 # Must-gather container logs (if running in pod)
├── cluster-info/                   # Cluster-wide information (if --cluster-info used)
│   └── [cluster-info dump output]
├── namespace-inspect/              # Deep Namepace's inspect (collected by default)
│   ├── inspect.log                 # Inspection command logs
│   ├── inspection-summary.txt      # Summary of inspected namespaces and data collected
│   ├── namespaces/                 # All inspected namespaces (OMC-compatible structure)
│   │   ├── [namespace-1]/          # First namespace (e.g., "rhdh-prod")
│   │   │   ├── [namespace].yaml    # Namespace definition
│   │   │   ├── apps/               # Application resources (Deployments, StatefulSets, etc.)
│   │   │   ├── core/               # Core resources (ConfigMaps, Secrets, Services, etc.)
│   │   │   ├── networking.k8s.io/  # Network policies and configurations
│   │   │   ├── batch/              # Jobs and CronJobs
│   │   │   ├── autoscaling/        # HPA and scaling configurations
│   │   │   └── pods/               # Detailed pod information with logs
│   │   │       └── [pod-name]/
│   │   │           ├── [pod-name].yaml
│   │   │           └── [container-name]/
│   │   │               └── logs/
│   │   │                   ├── current.log
│   │   │                   ├── previous.log
│   │   │                   └── previous.insecure.log
│   │   ├── [namespace-2]/          # Second namespace (e.g., "rhdh-staging")
│   │   │   └── [same structure as above]
│   │   └── [namespace-N]/          # Additional namespaces...
│   ├── aggregated-discovery-api.yaml
│   ├── aggregated-discovery-apis.yaml
│   └── event-filter.html           # Events visualization
├── platform/                       # Platform and infrastructure information
│   ├── platform.json               # Structured platform data (platform, underlying, versions)
│   └── platform.txt                # Human-readable platform summary
├── helm/                           # Helm deployment data (if RHDH Helm releases found)
│   ├── all-rhdh-releases.txt       # List of detected RHDH Helm releases with namespaces, revisions, status
│   └── releases/                   # Per-release data
│       └── ns=[namespace]/         # Per-namespace organization
│           ├── _configmaps/        # Namespace-wide ConfigMaps with both formats
│           │   ├── [configmap-name].yaml               # Full ConfigMap YAML
│           │   └── [configmap-name].describe.txt       # kubectl describe output
│           ├── _secrets/           # Namespace-wide Secrets (sanitized)
│           │   ├── [secret-name].yaml                  # Full Secret YAML (sanitized)
│           │   └── [secret-name].describe.txt          # kubectl describe output (data redacted)
│           └── [release-name]/     # Per-release directory
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
│               │   ├── heap-dumps/     # Memory heap dumps (if --with-heap-dumps used)
│               │   │   └── pod=[pod-name]/         # Per-pod directory
│               │   │       └── container=[container-name]/
│               │   │           ├── heapdump-[timestamp].heapsnapshot  # Heap dump (100MB-1GB+)
│               │   │           ├── process-info.txt        # Process and memory info
│               │   │           ├── heap-dump.log           # Collection logs
│               │   │           └── pod-spec.yaml           # Pod specification
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
└── operator/                       # Operator deployment data (if RHDH operators found)
    ├── all-deployments.txt         # List of all RHDH operator deployments
    ├── olm/                        # OLM information
    │   ├── rhdh-csv-all.txt        # ClusterServiceVersions
    │   ├── rhdh-subscriptions-all.txt # Subscriptions
    │   ├── installplans-all.txt     # InstallPlans
    │   ├── operatorgroups-all.txt   # OperatorGroups
    │   └── catalogsources-all.txt   # CatalogSources
    ├── crds/                       # Custom Resource Definitions
    │   ├── all-crds.txt            # All CRDs in cluster
    │   ├── backstages.rhdh.redhat.com.yaml # RHDH CRD definition
    │   └── backstages.rhdh.redhat.com.describe.txt # CRD description
    ├── ns=[operator-namespace]/     # Per-operator-namespace data (e.g., ns=rhdh-operator)
    │   ├── all-resources.txt       # All resources in namespace
    │   ├── configs/                # ConfigMaps with both formats
    │   │   ├── all-configmaps.txt
    │   │   ├── [configmap-name].yaml       # Full ConfigMap YAML
    │   │   └── [configmap-name].describe.txt # kubectl describe output
    │   ├── deployments/            # Operator deployments
    │   │   ├── all-deployments.txt
    │   │   ├── [deployment-selector].yaml
    │   │   └── [deployment-selector].describe.txt
    │   └── logs.txt               # Operator logs
    └── backstage-crs/              # Backstage Custom Resources
        ├── all-backstage-crs.txt   # List of all Backstage CRs
        └── ns=[cr-namespace]/      # Per-CR-namespace data (where Backstage CRs are deployed)
            ├── _configmaps/        # Namespace-wide ConfigMaps with both formats
            │   ├── [configmap-name].yaml               # Full ConfigMap YAML
            │   └── [configmap-name].describe.txt       # kubectl describe output
            ├── _secrets/           # Namespace-wide Secrets (sanitized)
            │   ├── [secret-name].yaml                  # Full Secret YAML (sanitized)
            │   └── [secret-name].describe.txt          # kubectl describe output (data redacted)
            └── [cr-name]/          # Per-CR directory
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
                │   ├── heap-dumps/     # Memory heap dumps (if --with-heap-dumps used)
                │   │   └── pod=[pod-name]/         # Per-pod directory
                │   │       └── container=[container-name]/
                │   │           ├── heapdump-[timestamp].heapsnapshot  # Heap dump (100MB-1GB+)
                │   │           ├── process-info.txt        # Process and memory info
                │   │           ├── heap-dump.log           # Collection logs
                │   │           └── pod-spec.yaml           # Pod specification
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

See the [examples](examples) folder for sample outputs on various platforms.

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
