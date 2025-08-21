# Using RHDH Must-Gather with OpenShift

This document provides specific examples for using the RHDH must-gather tool with OpenShift clusters.

## Basic Usage

### Standard Collection

```bash
# Basic must-gather collection
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest

# Collection with custom output directory
oc adm must-gather --dest-dir=./rhdh-diagnostics --image=quay.io/asoro/rhdh-must-gather:latest
```

### Advanced Usage

```bash
# Collect from specific node
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --node-name=worker-1

# Collect with timeout
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --timeout=10m

# Collect with custom source directory
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --source-dir=/tmp/rhdh-data
```

## OpenShift-Specific Features

The tool automatically detects OpenShift and collects additional information:

- **Cluster Version**: OpenShift version and update status
- **Cluster Operators**: Status of all cluster operators
- **Routes**: OpenShift routes for RHDH services
- **Image Streams**: Custom image streams used by RHDH
- **Security Context Constraints**: SCCs relevant to RHDH

## RBAC Requirements

The must-gather tool requires cluster-admin privileges or equivalent permissions:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rhdh-must-gather
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
- apiGroups: ["security.openshift.io"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
- apiGroups: ["route.openshift.io"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
- apiGroups: ["image.openshift.io"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
- apiGroups: ["config.openshift.io"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
- apiGroups: ["operator.openshift.io"]
  resources: ["*"]
  verbs: ["get", "list", "describe"]
```

## Example Scenarios

### Scenario 1: RHDH Performance Issues

```bash
# Collect comprehensive diagnostics
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest

# Focus on specific namespace if known
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest -- \
  bash -c "RHDH_NAMESPACE=my-rhdh-namespace /usr/local/bin/gather"
```

### Scenario 2: RHDH Not Starting

```bash
# Collect data with debug logging
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest -- \
  bash -c "LOG_LEVEL=DEBUG /usr/local/bin/gather"
```

### Scenario 3: Network Connectivity Issues

```bash
# Standard collection (includes network policies, routes, services)
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest

# Additionally, you might want to collect network diagnostics
oc adm must-gather --image=registry.redhat.io/openshift4/network-tools-rhel8:latest
```

## Output Analysis

### Key Files for OpenShift

After collection, focus on these OpenShift-specific files:

```
must-gather/
├── cluster-info/
│   ├── clusterversion.yaml         # OpenShift version
│   ├── clusteroperators.yaml       # Operator status
│   └── routes.yaml                 # RHDH routes
├── rhdh/
│   └── resources/
│       ├── routes.yaml             # RHDH-specific routes
│       └── imagestreams.yaml       # Custom images
└── logs/
    └── cluster-operators/          # Operator logs
```

### Common OpenShift Issues

1. **Image Pull Issues**
   - Check `imagestreams.yaml` for image references
   - Verify registry connectivity in cluster operators

2. **Route Access Problems**
   - Review `routes.yaml` for hostname and TLS configuration
   - Check ingress controller status

3. **SCC Violations**
   - Look for SCC-related events in events files
   - Check pod security context in resource descriptions

## Integration with OpenShift Console

The collected data can be analyzed using OpenShift console tools:

1. Upload logs to OpenShift logging stack
2. Import events into monitoring dashboards
3. Use configuration data for automated analysis

## Troubleshooting Collection Issues

### Must-Gather Pod Fails to Start

```bash
# Check must-gather pod status
oc get pods -n openshift-must-gather-*

# Get pod logs
oc logs -n openshift-must-gather-* <pod-name>

# Describe pod for events
oc describe pod -n openshift-must-gather-* <pod-name>
```

### Insufficient Permissions

```bash
# Check current user permissions
oc auth can-i "*" "*" --all-namespaces

# Use system:admin if needed (for cluster administrators)
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --as=system:admin
```

### Collection Timeout

```bash
# Increase timeout for large clusters
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest --timeout=20m

# Or use environment variables
oc adm must-gather --image=quay.io/asoro/rhdh-must-gather:latest -- \
  bash -c "COLLECTION_TIMEOUT=600 /usr/local/bin/gather"
```