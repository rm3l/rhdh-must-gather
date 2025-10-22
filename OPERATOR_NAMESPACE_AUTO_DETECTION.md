# Operator Namespace Auto-Detection

## Summary

The namespace inspection now **automatically detects and includes the RHDH operator namespace** when collecting data. This ensures complete operator-related diagnostics are captured without requiring manual namespace specification.

## Why This Matters

### The Problem Before

Previously, namespace inspection would auto-detect:
- ✅ Namespaces where RHDH instances are deployed (via Helm or Operator)
- ❌ **Missed** the operator namespace itself (e.g., `rhdh-operator`)

This meant critical operator information was only collected by the `gather_operator` script but not included in the comprehensive namespace inspection that Support teams use with OMC.

### The Solution Now

The script now auto-detects **three types** of RHDH-related namespaces:
1. **Helm deployment namespaces** - Where Helm-based RHDH is running
2. **CR namespaces** - Where Backstage Custom Resources are deployed
3. **Operator namespace(s)** - Where the RHDH operator itself is running ✨ **NEW**

## How It Works

### Detection Logic

```bash
# Find operator namespace(s) by looking for operator deployments
operator_namespaces=$(kubectl get deployments --all-namespaces \
    -l app=rhdh-operator \
    -o jsonpath='{.items[*].metadata.namespace}' 2>/dev/null)
```

### Integration

The operator namespaces are combined with other detected namespaces:

```bash
# Combine all detected namespaces
all_namespaces=$(echo -e "${helm_namespaces}\n${cr_namespaces}\n${operator_namespaces}" \
    | grep -v '^$' | sort | uniq)
```

### Logging

When operator namespaces are found, they're logged:

```bash
if [[ -n "$operator_namespaces" ]]; then
    log_info "Auto-detected RHDH operator namespace(s): $operator_namespaces"
fi
```

## What Gets Collected

With operator namespace included, the inspection now captures:

### From Operator Namespace (e.g., `rhdh-operator`)
- **Operator deployment** configuration and status
- **Operator pods** with current and previous logs
- **Operator ConfigMaps** (default configs, plugin dependencies)
- **Operator Secrets** (sanitized)
- **RBAC resources** (ServiceAccounts, Roles, RoleBindings)
- **Events** related to operator activity
- **OLM resources** (if operator installed via OLM)

### Complete Picture for Support Teams

Now OMC users can query everything in one context:

```bash
omc use namespace-inspect

# Application namespace
omc get pods -n rhdh-prod

# Operator namespace  ← NEW: Now included automatically!
omc get pods -n rhdh-operator
omc get deployment -n rhdh-operator -o yaml

# Compare operator logs with app logs
omc logs -n rhdh-operator deployment/rhdh-operator-controller-manager
```

## Example Scenarios

### Scenario 1: Operator-Based Deployment

**Setup**:
- Operator in `rhdh-operator` namespace
- Backstage CR in `rhdh-prod` namespace

**Before**:
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Result: Only rhdh-prod in namespace-inspect
# Operator info only in operator/ directory (separate collection)
```

**After**:
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Result: Both namespaces in namespace-inspect/namespaces/
# - rhdh-prod/      (application)
# - rhdh-operator/  (operator) ← Automatically included!
```

### Scenario 2: Multi-Environment with Shared Operator

**Setup**:
- One operator in `rhdh-operator` namespace
- Multiple CRs in `rhdh-prod`, `rhdh-staging`, `rhdh-dev`

**Collection**:
```bash
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Result: All namespaces inspected
namespace-inspect/namespaces/
├── rhdh-operator/   ← Operator namespace (auto-detected)
├── rhdh-prod/       ← Production app
├── rhdh-staging/    ← Staging app
└── rhdh-dev/        ← Development app
```

### Scenario 3: Operator Issue Troubleshooting

**Problem**: Operator not reconciling Backstage CR

**With Auto-Detection**:
```bash
omc use namespace-inspect

# Check operator status
omc get deployment -n rhdh-operator
omc get pods -n rhdh-operator

# Check operator logs
omc logs -n rhdh-operator -l app=rhdh-operator

# Check CR status
omc get backstages.rhdh.redhat.com -n rhdh-prod

# Compare events
omc get events -n rhdh-operator --sort-by='.lastTimestamp'
omc get events -n rhdh-prod --sort-by='.lastTimestamp'
```

All in one OMC context! 🎉

## Benefits

### 1. **Complete Diagnostics**
- No missing operator information
- Single collection captures everything
- Operator and application data together

### 2. **Easier Troubleshooting**
- One OMC context for all namespaces
- Easy correlation between operator and app issues
- Natural workflow for Support teams

### 3. **No Manual Specification**
- Works automatically without `--namespaces` flag
- Detects operator namespace wherever it is
- Reduces user errors

### 4. **Consistent with Expectations**
- Operator namespace logically belongs in namespace inspection
- Matches user mental model
- Reduces surprise/confusion

## Edge Cases Handled

### Multiple Operator Namespaces

If multiple operator instances exist (unusual but possible):

```bash
# Detects and includes all operator namespaces
operator_namespaces="rhdh-operator rhdh-operator-dev"

# Result: All included in inspection
namespace-inspect/namespaces/
├── rhdh-operator/
├── rhdh-operator-dev/
└── ...
```

### No Operator Found

If RHDH is deployed only via Helm (no operator):

```bash
# operator_namespaces is empty
# Only Helm namespaces are collected
# No error, works as expected
```

### Operator But No CRs

If operator is installed but no Backstage CRs exist yet:

```bash
# operator_namespaces: rhdh-operator
# cr_namespaces: (empty)
# Result: Only operator namespace inspected
```

This is useful for "operator installed but not configured yet" scenarios.

## Manual Override

Users can still manually specify namespaces:

```bash
# Inspect only specific namespaces (operator NOT auto-included)
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --namespaces rhdh-prod,rhdh-staging

# To include operator with manual specification:
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main -- \
  /usr/bin/gather --namespaces rhdh-prod,rhdh-operator
```

## Implementation Details

### Detection Query

The operator namespace is detected using the same label selector as `gather_operator`:

```bash
kubectl get deployments --all-namespaces \
    -l app=rhdh-operator \
    -o jsonpath='{.items[*].metadata.namespace}'
```

This matches the standard label used by the RHDH operator deployment.

### Deduplication

If a namespace appears in multiple detection methods, it's automatically deduplicated:

```bash
# If operator is in same namespace as CR (unusual):
# helm_namespaces: my-namespace
# cr_namespaces: my-namespace
# operator_namespaces: my-namespace
# Result: my-namespace appears only once ✓
```

### Logging

Clear logging helps users understand what was detected:

```
[INFO] Auto-detecting namespaces with RHDH deployments...
[INFO] Auto-detected RHDH operator namespace(s): rhdh-operator
[INFO] Found 3 namespace(s) to inspect: rhdh-operator rhdh-prod rhdh-staging
```

## Testing

### Test Cases

1. **Operator-based deployment**:
   - Operator in `rhdh-operator`
   - CR in `rhdh-prod`
   - ✅ Both namespaces should be inspected

2. **Helm-based deployment**:
   - No operator
   - Helm release in `rhdh-prod`
   - ✅ Only `rhdh-prod` should be inspected

3. **Mixed deployment**:
   - Operator in `rhdh-operator`
   - Some CRs, some Helm releases
   - ✅ All related namespaces should be inspected

4. **Manual namespace specification**:
   - `--namespaces rhdh-prod`
   - ✅ Only `rhdh-prod` inspected (no auto-detection)

### Validation

```bash
# Run collection
oc adm must-gather --image=ghcr.io/rm3l/rhdh-must-gather:main

# Check collected namespaces
cd must-gather.local.*/
ls namespace-inspect/namespaces/

# Expected: rhdh-operator (if operator exists) + app namespaces
```

## Documentation Updates

All documentation updated to reflect operator namespace auto-detection:

- ✅ **README.md** - Added to "Auto-detects RHDH namespaces" section
- ✅ **NAMESPACE_INSPECT_INTEGRATION.md** - Updated auto-detection logic
- ✅ **NAMESPACE_INSPECT_QUICK_REF.md** - Added to "What Gets Collected"
- ✅ **CHANGES_SUMMARY.md** - Updated auto-detection features
- ✅ **OPERATOR_NAMESPACE_AUTO_DETECTION.md** (this file) - Complete guide

## Backward Compatibility

✅ **100% Backward Compatible**

- Existing collections still work
- No breaking changes to flags or options
- Additional data (operator namespace) enhances, doesn't break

## Conclusion

The operator namespace auto-detection completes the namespace inspection feature by ensuring that **all RHDH-related namespaces** are automatically detected and included. This provides:

- ✅ **Complete diagnostics** for operator-based deployments
- ✅ **Single OMC context** for all RHDH components
- ✅ **Automatic detection** without manual configuration
- ✅ **Better troubleshooting** with operator and app data together

Support teams can now use OMC to analyze operator and application issues in one unified context, making troubleshooting faster and more effective.

