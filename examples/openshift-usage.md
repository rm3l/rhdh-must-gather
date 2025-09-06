# Using RHDH Must-Gather with OpenShift

This document provides specific examples for using the RHDH must-gather tool with OpenShift clusters. This tool collects only RHDH-specific data; combine with generic must-gather for complete cluster diagnostics.

## Basic Usage

### Standard Collection

```bash
# Basic RHDH-specific collection
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# RHDH collection with custom output directory
oc adm must-gather --dest-dir=./rhdh-diagnostics --image=ghcr.io/rm3l/rhdh-must-gather:main

# For complete diagnostics, combine with generic cluster collection
oc adm must-gather --dest-dir=./complete-diagnostics
oc adm must-gather --dest-dir=./complete-diagnostics --image=ghcr.io/rm3l/rhdh-must-gather:main
```

### Advanced Usage

```bash
# Collect from specific node
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --node-name=worker-1

# Collect with timeout
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --timeout=10m

# Collect with custom source directory
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --source-dir=/tmp/rhdh-data

# Collect logs and events from last 2 hours only
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=2h

# Collect logs and events from last 30 minutes only
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=30m

# Collect logs and events since specific timestamp
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since-time=2025-08-21T20:00:00Z
```

## OpenShift-Specific Features

The tool automatically detects OpenShift and collects RHDH-related information:

- **RHDH Routes**: OpenShift routes specific to RHDH services
- **RHDH Image Streams**: Custom image streams used by RHDH
- **RHDH Security Context Constraints**: SCCs relevant to RHDH workloads
- **Operator Data**: RHDH operator information if using operator deployment

> **Note**: For cluster operators, cluster version, and cluster-wide information, use the generic must-gather command

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
# Collect RHDH-specific diagnostics
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Also collect cluster information for complete picture
oc adm must-gather

# Focus on recent logs (last hour)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=1h
```

### Scenario 2: RHDH Not Starting

```bash
# Collect data with debug logging
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  bash -c "LOG_LEVEL=DEBUG /usr/local/bin/gather"
```

### Scenario 3: Network Connectivity Issues

```bash
# Collect RHDH network resources (routes, services, network policies)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# For complete network diagnostics, also collect cluster-wide network data
oc adm must-gather --image=registry.redhat.io/openshift4/network-tools-rhel8:main
```

## Output Analysis

### Key Files for OpenShift

After collection, focus on these RHDH-specific OpenShift files:

```
must-gather/
├── rhdh-deployment-details.txt     # RHDH deployment summary
├── rhdh/
│   ├── resources/
│   │   ├── [namespace]/
│   │   │   ├── routes.yaml         # RHDH routes
│   │   │   ├── imagestreams.yaml   # RHDH image streams
│   │   │   └── securitycontextconstraints.yaml
│   │   └── operator/               # If operator-based
│   └── helm/                       # If Helm-based
└── logs/
    └── [namespace]/                # RHDH pod logs
```

> **Note**: For cluster version, cluster operators, and cluster-wide routes, use the generic must-gather output

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
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --as=system:admin
```

### Collection Timeout

```bash
# Increase timeout for large clusters
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --timeout=20m

# Or use environment variables
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  bash -c "COLLECTION_TIMEOUT=600 /usr/local/bin/gather"
```