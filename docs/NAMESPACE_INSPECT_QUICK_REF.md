# Namespace Inspection - Quick Reference

## What It Does

Deep namespace inspection for RHDH must-gather using `oc adm inspect namespace`.

**Status**: ✅ **Collected by default** - all must-gather outputs are now OMC-compatible for Support analysis.

## Quick Start

```bash
# Namespace inspection included by default
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
```

## Common Use Cases

### 1. Standard Collection (includes namespace inspection)
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main
```

### 2. Inspect Specific Namespaces Only
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --namespaces rhdh-prod
```

### 3. With Time Filtering (Last 2 Hours)
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main --since=2h
```

### 4. Full Diagnostic Collection (with cluster-info)
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --cluster-info
```

### 5. Without Namespace Inspection (not recommended)
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --without-namespace-inspect
```
**Note**: Removes OMC compatibility

## What Gets Collected

- ✅ All Kubernetes resources (YAML)
- ✅ Pod logs (current + previous)
- ✅ Events timeline with HTML visualization
- ✅ Resource descriptions
- ✅ Network configurations
- ✅ Organized by resource type
- ✅ **Automatically includes operator namespace** (e.g., `rhdh-operator`)

## Output Location

```
/must-gather/namespace-inspect/
├── inspect.log
├── inspection-summary.txt
└── namespaces/                     # All inspected namespaces
    ├── rhdh-prod/                  # First namespace
    ├── rhdh-staging/               # Second namespace
    └── ...                         # Additional namespaces
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RHDH_TARGET_NAMESPACES` | (auto-detect) | Comma-separated namespaces to inspect |
| `CMD_TIMEOUT` | `30` | Timeout in seconds per namespace |
| `LOG_LEVEL` | `info` | Logging level (info, debug, trace) |
| `MUST_GATHER_SINCE` | - | Relative time (e.g., "2h", "30m") |
| `MUST_GATHER_SINCE_TIME` | - | Absolute time (RFC3339) |

## Troubleshooting

### "oc command not found"
- **Cause**: Running on Kubernetes without OpenShift CLI
- **Solution**: Install `oc` or skip this feature (it's optional)

### "Inspection timed out"
- **Cause**: Large namespace takes > 30 seconds
- **Solution**: Increase timeout:
  ```bash
  oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
    CMD_TIMEOUT=60 /usr/bin/gather
  ```

### "No namespaces detected"
- **Cause**: No RHDH deployments found
- **Solution**: Use `--namespaces` to explicitly specify:
  ```bash
  oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
    /usr/bin/gather --namespaces my-rhdh-ns
  ```

## Debug Mode

```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  LOG_LEVEL=debug /usr/bin/gather
```

## OMC Integration

The namespace inspection output is **fully compatible** with [OMC (OpenShift Must-Gather Client)](https://github.com/gmeghnag/omc), used by Support teams.

### Using OMC with Inspection Data

```bash
# Navigate to must-gather output
cd must-gather.local.*/

# Point OMC to namespace inspection (one command for all namespaces)
omc use namespace-inspect

# Query interactively across all namespaces
omc get pods --all-namespaces
omc get pods -n rhdh-prod -o wide
omc get deployments -n rhdh-staging
omc get events --all-namespaces --sort-by='.lastTimestamp'
```

### OMC Benefits
- 🔍 Interactive queries with `kubectl`/`oc` syntax
- 🚀 Fast offline analysis
- 📊 Labels, field selectors, JSONPath support
- ✅ Support standard tool

## When to Use

✅ **Use when you need**:
- Complete resource state
- Previous container logs (crash analysis)
- Event timeline
- Full network configuration
- Comprehensive troubleshooting data
- **OMC-compatible output for Support analysis**

❌ **Not needed when**:
- Quick log check (use existing collection)
- Known issue with specific resource
- Limited time/storage
- Non-OpenShift cluster without `oc`

## Key Points

- **Collected by default**: Runs automatically in all must-gather collections
- **Auto-detects**: Finds RHDH namespaces automatically (Helm, Operator, and operator namespace)
- **Complements**: Works with existing collection
- **Compatible**: Respects namespace and time filters
- **Safe**: Read-only inspection, no cluster changes
- **OMC-ready**: All output is compatible with OMC for Support analysis

## Files

| File | Purpose |
|------|---------|
| `collection-scripts/gather_namespace-inspect` | Main script |
| `collection-scripts/must_gather` | Orchestrator |
| `README.md` | Complete user documentation |
| `OMC_COMPATIBILITY.md` | OMC usage guide |
| `NAMESPACE_INSPECT_QUICK_REF.md` | This quick reference |

## Testing Locally

```bash
# Quick test (namespace inspection included by default)
make test-local-all

# Test with specific namespaces
BASE_COLLECTION_PATH=./test-output \
  ./collection-scripts/must_gather --namespaces my-ns

# Debug mode
BASE_COLLECTION_PATH=./test-output LOG_LEVEL=debug \
  ./collection-scripts/must_gather
```

## Getting Help

```bash
# Show all options
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --help
```

---

**Quick Tip**: Start with basic inspection, add filters as needed!

