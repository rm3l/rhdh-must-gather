# Namespace Inspection Integration

## Overview

This document describes the integration of `oc adm inspect namespace` functionality into the RHDH must-gather tool. This enhancement provides deep, comprehensive namespace-level resource inspection for RHDH deployments.

**Status**: Namespace inspection is now **collected by default** to ensure all must-gather outputs are OMC-compatible for Red Hat Support analysis.

## What Was Added

### 1. New Collection Script: `gather_namespace-inspect`

**Location**: `collection-scripts/gather_namespace-inspect`

**Purpose**: Provides deep inspection of namespaces containing RHDH deployments using the OpenShift `oc adm inspect` command.

**Key Features**:
- **Auto-detection**: Automatically finds namespaces with RHDH Helm releases or Backstage Custom Resources
- **Namespace filtering**: Respects `RHDH_TARGET_NAMESPACES` for targeted collection
- **Time constraints**: Supports `MUST_GATHER_SINCE` and `MUST_GATHER_SINCE_TIME` parameters
- **Graceful fallback**: Skips inspection if `oc` command is not available (Kubernetes-only clusters)
- **Comprehensive logging**: Provides detailed logging and summary reports

**Data Collected**:
- All Kubernetes resource definitions (YAML format)
- Pod logs (current and previous containers)
- Events timeline for troubleshooting
- Resource descriptions and status information
- Network configurations
- Organized by namespace and resource type

### 2. Integration with Main Orchestrator

**Modified**: `collection-scripts/must_gather`

**Changes**:
- Added `namespace-inspect` to optional scripts list
- Added `--namespace-inspect` flag to enable the feature
- Updated help text with examples and documentation
- Maintains backward compatibility (opt-in feature)

### 3. Documentation Updates

**Modified**: `README.md`

**Additions**:
- New "Namespace Inspection (optional)" section describing the feature
- Usage examples with `--namespace-inspect` flag
- Output structure documentation showing the inspection data hierarchy
- Combined usage examples (e.g., with namespace filtering)

## Usage Examples

### Basic Usage (namespace inspection included by default)

Collect all RHDH data including namespace inspection:

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
```

### With Namespace Filtering

Inspect specific namespaces only:

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- /usr/bin/gather --namespaces rhdh-prod
```

### With Time Constraints

Collect logs from the last 2 hours:

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=2h
```

### Combined with Other Options

Full collection with namespace inspection (default) and cluster info:

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- /usr/bin/gather --cluster-info
```

### Disabling Namespace Inspection (not recommended)

If you need to disable namespace inspection:

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- /usr/bin/gather --without-namespace-inspect
```

**Note**: Disabling namespace inspection removes OMC compatibility, which may impact Support team analysis.

## Output Structure

The namespace inspection creates the following directory structure:

```
/must-gather/
└── namespace-inspect/                  # Single directory for all namespaces
    ├── inspect.log                     # Command logs
    ├── inspection-summary.txt          # Summary of inspection
    ├── namespaces/                     # All inspected namespaces
    │   ├── <namespace-1>/             # e.g., "rhdh-prod"
    │   │   ├── <namespace>.yaml       # Namespace definition
    │   │   ├── apps/                  # Deployments, StatefulSets, DaemonSets
    │   │   ├── core/                  # ConfigMaps, Secrets, Services, Pods
    │   │   ├── networking.k8s.io/     # NetworkPolicies, Ingresses
    │   │   ├── batch/                 # Jobs, CronJobs
    │   │   ├── autoscaling/           # HPA configurations
    │   │   └── pods/
    │   │       └── <pod-name>/
    │   │           ├── <pod-name>.yaml
    │   │           └── <container>/
    │   │               └── logs/
    │   │                   ├── current.log
    │   │                   ├── previous.log
    │   │                   └── previous.insecure.log
    │   ├── <namespace-2>/             # e.g., "rhdh-staging"
    │   │   └── [same structure]
    │   └── <namespace-N>/             # Additional namespaces
    ├── aggregated-discovery-api.yaml
    ├── aggregated-discovery-apis.yaml
    └── event-filter.html              # Events visualization
```

## Key Benefits

### 1. **Comprehensive Resource Collection**
- Captures ALL resources in RHDH namespaces, not just selected ones
- Includes historical pod logs (previous containers)
- Provides complete resource definitions for debugging

### 2. **Event Timeline**
- Visual event filtering with `event-filter.html`
- Complete event history for troubleshooting
- Chronological view of namespace activity

### 3. **Better Troubleshooting**
- Previous container logs help diagnose crash loops
- Complete resource state at time of collection
- Network policy and configuration details

### 4. **OMC Compatible**
- Works seamlessly with [OpenShift Must-Gather Client (OMC)](https://github.com/gmeghnag/omc)
- Support teams can use OMC for interactive analysis
- Standard must-gather directory structure
- Use familiar `kubectl`/`oc` commands on offline data

### 5. **Complements Existing Collection**
The namespace-inspect feature complements (not replaces) the existing focused collection:
- **Existing**: RHDH-specific, targeted resource collection
- **New**: Comprehensive namespace-level inspection
- **Together**: Complete picture for complex issues

## Implementation Details

### Auto-Detection Logic

The script automatically detects namespaces to inspect:

1. **With `--namespaces` flag**: Uses explicitly specified namespaces
2. **Without flag**: Auto-detects by finding:
   - Namespaces with Helm releases matching "backstage", "rhdh", or "developer-hub"
   - Namespaces with Backstage Custom Resources
   - **Namespaces with RHDH operator deployments** (e.g., `rhdh-operator` namespace)

### Error Handling

- **No `oc` command**: Gracefully skips with informative message
- **Timeout**: Configurable via `CMD_TIMEOUT` environment variable
- **Failed inspection**: Logs error but continues with other namespaces
- **No namespaces found**: Creates informative status file

### Performance Considerations

- Uses `timeout` to prevent hanging on large namespaces
- Default timeout: 30 seconds (configurable via `CMD_TIMEOUT`)
- Processes namespaces sequentially to avoid resource exhaustion
- Large namespaces may need increased timeout

## Compatibility

- **OpenShift**: Fully supported (requires `oc` CLI)
- **Kubernetes**: Skipped with informative message (`oc` not available)
- **Backward compatible**: Opt-in feature, doesn't affect existing functionality
- **Existing filters**: Respects `--namespaces` and time constraint flags

## Testing

### Local Testing

```bash
# Test with local cluster
BASE_COLLECTION_PATH=./test-output LOG_LEVEL=debug \
  ./collection-scripts/must_gather --namespace-inspect

# Test specific script only
BASE_COLLECTION_PATH=./test-output LOG_LEVEL=debug \
  USR_BIN_GATHER=1 ./collection-scripts/gather_namespace-inspect
```

### Container Testing

```bash
# Build and test
make build
make test-container-all

# OpenShift testing
make openshift-test
```

## Future Enhancements

Potential improvements for future versions:

1. **Parallel inspection**: Process multiple namespaces concurrently
2. **Resource filtering**: Allow excluding certain resource types
3. **Size limits**: Add flags to limit log size collection
4. **Kubernetes support**: Implement similar deep inspection for non-OpenShift clusters
5. **Incremental collection**: Support for collecting only changed resources

## Notes

- The feature is **optional** and must be explicitly enabled
- Best used when comprehensive namespace data is needed
- May increase collection time for large namespaces
- Complements rather than replaces existing focused collection
- Data is automatically sanitized by the existing sanitization process

## Related Files

- `collection-scripts/gather_namespace-inspect` - New script
- `collection-scripts/must_gather` - Updated orchestrator
- `collection-scripts/common.sh` - Shared utilities (unchanged)
- `README.md` - Updated documentation

## Migration Guide

### For Users

No migration needed. This is a new opt-in feature:

**Before** (still works):
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
```

**After** (with new feature):
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- /usr/bin/gather --namespace-inspect
```

### For Developers

To extend or modify the namespace inspection:

1. Edit `collection-scripts/gather_namespace-inspect`
2. Follow existing patterns in other gather scripts
3. Use functions from `common.sh` for consistency
4. Update documentation in `README.md`
5. Test locally before committing

## Using with OMC (OpenShift Must-Gather Client)

The namespace inspection output is fully compatible with [OMC](https://github.com/gmeghnag/omc), the OpenShift Must-Gather Client widely used by Red Hat Support teams for interactive must-gather analysis.

### Quick Start with OMC

```bash
# After collecting the must-gather
cd must-gather.local.*/

# Point OMC to the namespace inspection directory (one command for all namespaces)
omc use namespace-inspect

# Query resources interactively across all namespaces
omc get pods --all-namespaces
omc get pods -n rhdh-prod
omc get deployments -n rhdh-staging -o yaml
omc get events --sort-by='.lastTimestamp'
```

### Why Use OMC?

1. **Interactive Analysis**: Query resources using familiar `kubectl`/`oc` syntax without cluster access
2. **Fast Queries**: Instant results from offline data
3. **Advanced Filtering**: Use labels, field selectors, and JSONPath
4. **Support Standard**: Widely used by Red Hat Support for case analysis
5. **Resource Comparison**: Compare resources across namespaces or time periods

### OMC Examples for RHDH

```bash
# Find pods by label
omc get pods -l app.kubernetes.io/name=backstage -o wide

# Get all ConfigMaps
omc get configmaps

# Check specific resource
omc get deployment backstage-bs1 -o yaml

# Filter events
omc get events --field-selector involvedObject.kind=Pod

# Use JSONPath for custom output
omc get pods -o jsonpath="{.items[*].metadata.name}"

# Inspect certificates (if available)
omc certs inspect
```

### Multi-Namespace Workflow

```bash
# Point OMC once to the inspection directory
omc use namespace-inspect

# Query different namespaces
omc get pods -n rhdh-prod -o wide
omc get deployments -n rhdh-staging

# Or view all namespaces at once
omc get pods --all-namespaces
omc get namespaces

# Compare resources between environments
diff <(omc get deploy -n rhdh-prod -o yaml) <(omc get deploy -n rhdh-staging -o yaml)
```

### Directory Structure for OMC

OMC expects a specific structure, which the namespace inspection provides:

```
namespace-inspect/                ← Point OMC here (one context for all namespaces)
├── namespaces/                   ← OMC recognizes this structure
│   ├── rhdh-prod/
│   │   ├── apps/
│   │   ├── core/
│   │   └── pods/
│   ├── rhdh-staging/
│   │   └── [same structure]
│   └── ...
└── event-filter.html
```

**Command**: `omc use namespace-inspect` (single command for all namespaces)

### Installation

```bash
# Linux/Mac
curl -sL https://github.com/gmeghnag/omc/releases/latest/download/omc_$(uname)_$(uname -m).tar.gz | tar xzf - omc
chmod +x ./omc
sudo mv ./omc /usr/local/bin/

# Verify
omc version
```

## Support and Troubleshooting

### Common Issues

**Issue**: "oc command not found"
- **Solution**: Feature requires OpenShift CLI. Install `oc` or skip this feature.

**Issue**: "Inspection timed out"
- **Solution**: Increase timeout: `CMD_TIMEOUT=60 oc adm must-gather ...`

**Issue**: "No namespaces detected"
- **Solution**: Use `--namespaces` flag to explicitly specify namespaces

### Debug Mode

Enable detailed logging:
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  LOG_LEVEL=debug /usr/bin/gather --namespace-inspect
```

## Conclusion

The namespace inspection integration provides a powerful, comprehensive data collection capability for deep troubleshooting of RHDH deployments. It complements the existing focused collection with complete namespace-level resource inspection while maintaining backward compatibility and graceful degradation.

