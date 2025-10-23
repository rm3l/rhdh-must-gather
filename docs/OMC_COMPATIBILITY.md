# OMC Compatibility Guide

## Overview

The RHDH must-gather tool produces output that is **fully compatible** with [OMC (OpenShift Must-Gather Client)](https://github.com/gmeghnag/omc), the standard tool used by Red Hat Support teams for interactive must-gather analysis.

**Status**: ✅ Namespace inspection is now **collected by default** - all must-gather outputs are OMC-compatible without additional flags.

## What is OMC?

OMC is a command-line tool that allows engineers to inspect resources from a must-gather using familiar `kubectl`/`oc` commands, **without needing cluster access**. It's the standard tool used across Red Hat Support for analyzing must-gather data.

### OMC Features

- 🔍 **Interactive Queries**: Use `kubectl`/`oc` syntax on offline data
- 🚀 **Fast Analysis**: Instant results from local files
- 📊 **Advanced Filtering**: Labels, field selectors, JSONPath
- 🎯 **Resource Discovery**: Find resources across namespaces
- 📈 **Comparison**: Compare resources between environments
- 🔐 **Offline**: Analyze sensitive data without cluster connection

## Directory Structure Compatibility

OMC requires a specific directory structure, which the namespace inspection provides:

### Expected Structure (OMC)

```
must-gather-root/
└── namespaces/
    └── <namespace>/
        ├── apps/
        │   ├── deployments.yaml
        │   ├── statefulsets.yaml
        │   └── ...
        ├── core/
        │   ├── pods.yaml
        │   ├── services.yaml
        │   ├── configmaps.yaml
        │   └── ...
        ├── batch/
        └── networking.k8s.io/
```

### Provided Structure (namespace-inspect)

```
namespace-inspect/                  ← OMC root (use this path)
├── namespaces/                     ← OMC recognizes this
│   ├── rhdh-prod/
│   │   ├── apps/
│   │   │   ├── deployments.yaml
│   │   │   └── statefulsets.yaml
│   │   ├── core/
│   │   │   ├── pods.yaml
│   │   │   ├── services.yaml
│   │   │   └── configmaps.yaml
│   │   ├── batch/
│   │   └── networking.k8s.io/
│   ├── rhdh-staging/
│   │   └── [same structure]
│   └── [additional namespaces]
├── aggregated-discovery-api.yaml
├── event-filter.html
└── timestamp
```

**✅ Compatibility**: The `namespaces/` directory structure matches OMC's expectations exactly. All namespaces are collected in one location.

## Usage Guide

### Step 1: Collect Must-Gather Data (namespace inspection included by default)

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
```

### Step 2: Install OMC (if needed)

```bash
# Download latest release
curl -sL https://github.com/gmeghnag/omc/releases/latest/download/omc_$(uname)_$(uname -m).tar.gz | tar xzf - omc

# Make executable and move to PATH
chmod +x ./omc
sudo mv ./omc /usr/local/bin/

# Verify installation
omc version
```

### Step 3: Point OMC to Namespace Inspection

```bash
# Navigate to must-gather output
cd must-gather.local.*/

# Point OMC to the namespace inspection directory (one command for all namespaces)
omc use namespace-inspect

# Verify OMC can see all namespaces
omc get namespaces
```

### Step 4: Query Resources Across All Namespaces

```bash
# List all pods across all namespaces
omc get pods --all-namespaces

# Get pods in specific namespace
omc get pods -n rhdh-prod

# Get pods with wide output
omc get pods -n rhdh-staging -o wide

# Get pods by label
omc get pods -l app.kubernetes.io/name=backstage --all-namespaces

# Get deployment YAML
omc get deployment backstage-bs1 -n rhdh-prod -o yaml

# List all ConfigMaps in a namespace
omc get configmaps -n rhdh-prod

# Check events across all namespaces
omc get events --all-namespaces --sort-by='.lastTimestamp'
```

## Real-World Examples

### Troubleshooting RHDH Deployment

```bash
# Set context (one command for all namespaces)
omc use namespace-inspect

# Find RHDH pods in production
omc get pods -n rhdh-prod -l app.kubernetes.io/name=backstage -o wide

# Check deployment status
omc get deployment -n rhdh-prod -l app.kubernetes.io/name=backstage -o yaml

# Look for recent errors in events
omc get events -n rhdh-prod --sort-by='.lastTimestamp' | tail -20

# Check ConfigMaps for app-config
omc get configmaps -n rhdh-prod -o name | grep app-config

# Get specific ConfigMap content
omc get configmap -n rhdh-prod app-config-rhdh -o yaml
```

### Analyzing Pod Issues

```bash
# Get pod details
POD_NAME=$(omc get pods -n rhdh-prod -l app=backstage -o jsonpath='{.items[0].metadata.name}')
omc get pod -n rhdh-prod $POD_NAME -o yaml

# Check pod events
omc get events -n rhdh-prod --field-selector involvedObject.name=$POD_NAME

# Get all pods in error states across all namespaces
omc get pods --all-namespaces --field-selector status.phase!=Running,status.phase!=Succeeded
```

### Comparing Environments

```bash
# Single OMC context for all environments
omc use namespace-inspect

# Get production deployment
omc get deployment -n rhdh-prod backstage-bs1 -o yaml > prod-deployment.yaml

# Get staging deployment
omc get deployment -n rhdh-staging backstage-bs1 -o yaml > staging-deployment.yaml

# Compare configurations
diff prod-deployment.yaml staging-deployment.yaml
```

### Certificate Inspection

```bash
omc use namespace-inspect

# Inspect all certificates (if OMC version supports it)
omc certs inspect

# Get certificate secrets from specific namespace
omc get secrets -n rhdh-prod -o name | grep cert
```

## Multi-Namespace Analysis

When you collect multiple namespaces, they're all in one OMC-compatible directory (namespace inspection is included by default):

```bash
# Collect multiple namespaces (namespace inspection included by default)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --namespaces rhdh-prod,rhdh-staging

# Result structure
namespace-inspect/
└── namespaces/
    ├── rhdh-prod/     # Production namespace
    └── rhdh-staging/  # Staging namespace

# Point OMC once
omc use namespace-inspect

# Query different namespaces without switching contexts
omc get pods -n rhdh-prod
omc get pods -n rhdh-staging

# Or view all at once
omc get pods --all-namespaces
```

## Advanced OMC Features

### JSONPath Queries

```bash
# Get all pod names
omc get pods -o jsonpath='{.items[*].metadata.name}'

# Get pods with their IPs
omc get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# Get container images
omc get deployments -o jsonpath='{.items[*].spec.template.spec.containers[*].image}'
```

### Field Selectors

```bash
# Get only running pods
omc get pods --field-selector status.phase=Running

# Get events for specific object
omc get events --field-selector involvedObject.kind=Pod,involvedObject.name=backstage-bs1-xyz

# Get failed pods
omc get pods --field-selector status.phase=Failed
```

### Label Selectors

```bash
# Get resources by label
omc get pods -l app.kubernetes.io/name=backstage
omc get all -l app.kubernetes.io/instance=bs1

# Combine multiple labels
omc get pods -l app=backstage,environment=production

# Use label expressions
omc get pods -l 'environment in (production,staging)'
```

## Output Formats

OMC supports multiple output formats:

```bash
# YAML output (full detail)
omc get deployment backstage-bs1 -o yaml

# JSON output (for scripting)
omc get pods -o json | jq '.items[].metadata.name'

# Wide output (more columns)
omc get pods -o wide

# Custom columns
omc get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName

# Name only
omc get pods -o name
```

## Why This Matters for Support

### For Red Hat Support Engineers

1. **Standard Tool**: OMC is the primary tool for must-gather analysis
2. **No Cluster Access**: Analyze customer data without connecting to their cluster
3. **Fast Queries**: Instant results for quick triage
4. **Familiar Commands**: Use the same commands as `kubectl`/`oc`
5. **Case Analysis**: Easily extract specific information for case notes

### For Customers

1. **Share with Support**: Must-gather data is immediately usable by Support
2. **Self-Service**: Customers can use OMC to pre-analyze before opening cases
3. **Validation**: Verify data collection completeness
4. **Documentation**: Generate detailed reports for internal teams

### For RHDH Engineering

1. **Consistent Format**: Output matches standard must-gather structure
2. **Support Ready**: No additional processing needed
3. **Quality Assurance**: Validate collections locally with OMC
4. **Debugging**: Analyze test environment issues offline

## Verification

To verify OMC compatibility:

```bash
# Collect test data (namespace inspection included by default)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --namespaces my-test-ns

# Navigate to output
cd must-gather.local.*/

# Point OMC to namespace-inspect directory
omc use namespace-inspect

# Verify OMC can read the structure
omc get namespaces
omc get pods --all-namespaces
omc get pods -n my-test-ns
omc get all -n my-test-ns

# If these commands work, structure is compatible ✅
```

## Troubleshooting OMC Issues

### Issue: OMC can't find resources

**Symptom**: `omc get pods` returns empty or errors

**Solutions**:
```bash
# Verify you're pointing to the right directory
omc current-context

# Make sure you're using the namespace-inspect directory
omc use namespace-inspect  # ✅ Correct

# Verify namespace-inspect has the namespaces/ subdirectory
ls -la namespace-inspect/namespaces/

# Query with namespace flag
omc get pods -n <namespace-name>
omc get pods --all-namespaces
```

### Issue: OMC shows resources but wrong namespace

**Symptom**: OMC queries show different namespace than expected

**Solution**: Always use the `-n` flag to specify which namespace to query:
```bash
# Query specific namespace
omc get pods -n rhdh-prod

# Or view all namespaces
omc get pods --all-namespaces
```

### Issue: Cannot install OMC

**Solution**: Download appropriate binary for your OS from [releases page](https://github.com/gmeghnag/omc/releases)

## Best Practices

1. **Always verify collection**: Use OMC to verify data after collection
   ```bash
   omc use namespace-inspect
   omc get pods --all-namespaces  # Should list all pods
   omc get pods -n rhdh-prod      # Should list pods in specific namespace
   ```

2. **Document findings**: Use OMC output in case notes
   ```bash
   omc get deployment -n rhdh-prod backstage -o yaml > deployment-config.yaml
   ```

3. **Compare environments**: Use OMC to diff configurations (single context for all)
   ```bash
   omc use namespace-inspect
   omc get deploy -n rhdh-prod backstage -o yaml > prod.yaml
   omc get deploy -n rhdh-staging backstage -o yaml > staging.yaml
   diff prod.yaml staging.yaml
   ```

4. **Script analysis**: Combine OMC with standard tools
   ```bash
   # Find all pods with restart count > 5 across all namespaces
   omc get pods --all-namespaces -o json | jq -r '.items[] | select(.status.containerStatuses[]?.restartCount > 5) | .metadata.name'
   ```

## References

- **OMC GitHub**: https://github.com/gmeghnag/omc
- **OMC Documentation**: https://gmeghnag.github.io/omc/
- **OpenShift Must-Gather**: https://docs.openshift.com/container-platform/latest/support/gathering-cluster-data.html

## Summary

✅ **Full Compatibility**: Namespace inspection output works seamlessly with OMC  
✅ **Standard Structure**: Follows OpenShift must-gather conventions  
✅ **Support Ready**: Red Hat Support can immediately use the output  
✅ **Interactive**: Query resources with familiar kubectl/oc commands  
✅ **Offline**: No cluster access needed for analysis  

The namespace inspection feature produces OMC-compatible output by design, ensuring that Support teams can use their standard tools and workflows.

