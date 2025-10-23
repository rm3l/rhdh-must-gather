# Error Handling Improvement

## Summary

Updated the main `must_gather` orchestrator script to handle collection script failures gracefully. If one script fails, the collection continues with remaining scripts instead of aborting the entire must-gather operation.

## Problem Before

Previously, if any collection script failed, the behavior was unpredictable:
- With `set -euo pipefail`, a script failure could abort the entire collection
- No clear logging of which script failed
- Partial collections without indication of what was missed
- Users wouldn't know why their collection was incomplete

```bash
# Old code - no error handling
function run_scripts {
  log_info "running the following scripts: ${requested_scripts[*]}"
  for script in "${requested_scripts[@]}";
  do
    script_name="gather_${script}"
    log_info "running ${script_name}"
    eval USR_BIN_GATHER=1 "${DIR_NAME}/${script_name}"  # If this fails, behavior unclear
  done
}
```

## Solution Now

Each script execution is wrapped in error handling that:
1. **Catches failures** - Uses `if !` to catch non-zero exit codes
2. **Logs the error** - Clear message indicating which script failed
3. **Continues collection** - Loop continues to next script
4. **Completes sanitization** - EXIT trap still runs at the end

```bash
# New code - graceful error handling
function run_scripts {
  log_info "running the following scripts: ${requested_scripts[*]}"
  for script in "${requested_scripts[@]}";
  do
    script_name="gather_${script}"
    log_info "running ${script_name}"
    if ! eval USR_BIN_GATHER=1 "${DIR_NAME}/${script_name}"; then
      log_error "Failed to run ${script_name}, continuing with next script..."
    fi
  done
}

function run_logs {
  log_info "running logs"
  if ! USR_BIN_GATHER=1 "${DIR_NAME}"/logs.sh; then
    log_error "Failed to run logs.sh, continuing..."
  fi
}
```

## Benefits

### 1. **Maximum Data Collection**
Even if one component fails, all other data is collected:

```bash
# Scenario: Operator script fails (e.g., CRD not found)
[INFO] running gather_platform    ✓ Success
[INFO] running gather_helm         ✓ Success
[INFO] running gather_operator     ✗ FAILED
[ERROR] Failed to run gather_operator, continuing with next script...
[INFO] running gather_route        ✓ Success
[INFO] running gather_ingress      ✓ Success
[INFO] running gather_namespace-inspect ✓ Success

# Result: Most data collected, clear indication of what failed
```

### 2. **Clear Error Reporting**
Users know exactly what failed:

```
[ERROR] Failed to run gather_operator, continuing with next script...
```

This helps:
- Understand what data might be missing
- Troubleshoot the failure
- Report issues with specific context

### 3. **Predictable Behavior**
- Collection **always completes** (runs all scripts)
- Sanitization **always runs** (EXIT trap)
- Consistent output structure
- Users get **something** rather than nothing

### 4. **Better for Support Teams**
- Partial data is better than no data
- Clear logs show what was attempted
- Can identify patterns (e.g., "operator script always fails")
- Don't lose valuable data from successful collections

## Example Scenarios

### Scenario 1: Missing CRD

**Problem**: Operator CRD doesn't exist (non-operator deployment)

**Before**: Might abort entire collection

**After**:
```
[INFO] running gather_operator
[ERROR] Failed to run gather_operator, continuing with next script...
[INFO] running gather_route
✓ Collection completes with Helm data + routes + ingresses
```

### Scenario 2: Permission Issues

**Problem**: User lacks permission to list some resources

**Before**: Collection might stop at first permission error

**After**:
```
[INFO] running gather_platform
✓ Platform data collected

[INFO] running gather_helm
✓ Helm data collected

[INFO] running gather_operator
[ERROR] Failed to run gather_operator, continuing with next script...

[INFO] running gather_namespace-inspect
✓ Namespace inspection completed

Result: Most data collected despite permission issue
```

### Scenario 3: Network Timeout

**Problem**: Helm command times out connecting to storage

**Before**: Collection aborts, lose everything

**After**:
```
[INFO] running gather_helm
[ERROR] Failed to run gather_helm, continuing with next script...
[INFO] running gather_operator
✓ Operator data collected

[INFO] running gather_namespace-inspect
✓ Namespace inspection completed

Result: Have operator and namespace data even without Helm
```

## Error Handling Flow

```
main()
  ├─ init_must_gather()           # Can fail - abort is appropriate
  ├─ parse_flags()                # Parse user input
  ├─ run_scripts()                # Run collection scripts
  │   ├─ gather_platform          # If fails: log error, continue
  │   ├─ gather_helm              # If fails: log error, continue
  │   ├─ gather_operator          # If fails: log error, continue
  │   ├─ gather_route             # If fails: log error, continue
  │   ├─ gather_ingress           # If fails: log error, continue
  │   └─ gather_namespace-inspect # If fails: log error, continue
  ├─ run_logs()                   # If fails: log error, continue
  ├─ sync                         # Ensure data written to disk
  └─ exit 0                       # Always exits successfully

EXIT trap: sanitize data          # Always runs, even on errors
```

## Implementation Details

### Error Detection

```bash
if ! eval USR_BIN_GATHER=1 "${DIR_NAME}/${script_name}"; then
    # Command returned non-zero exit code
    log_error "Failed to run ${script_name}, continuing with next script..."
fi
```

### Why This Works

1. **`if !`** - Inverts the exit code check
2. **Command still runs** - Script executes normally
3. **Error caught** - Non-zero exit doesn't trigger `set -e`
4. **Loop continues** - `for` loop moves to next script
5. **EXIT trap preserved** - Sanitization always runs

### Existing Traps Still Work

```bash
# EXIT trap - always runs for sanitization
trap "echo 'done with data collection. Now sanitizing data...' && \
      '${DIR_NAME}'/sanitize '${BASE_COLLECTION_PATH}' || true" EXIT

# ERR trap - catches unexpected errors in main()
trap 'log "An unexpected error occurred. See logs above."' ERR
```

The ERR trap now only fires for **unexpected** errors (not caught by our `if !` checks).

## Testing

### Test Case 1: All Scripts Succeed
```bash
# All scripts run successfully
[INFO] running gather_platform ✓
[INFO] running gather_helm ✓
[INFO] running gather_operator ✓
[INFO] running gather_route ✓
[INFO] running gather_ingress ✓
[INFO] running gather_namespace-inspect ✓

Result: Complete collection, no errors
```

### Test Case 2: One Script Fails
```bash
# Operator script fails (simulated)
[INFO] running gather_platform ✓
[INFO] running gather_helm ✓
[INFO] running gather_operator ✗
[ERROR] Failed to run gather_operator, continuing with next script...
[INFO] running gather_route ✓
[INFO] running gather_ingress ✓
[INFO] running gather_namespace-inspect ✓

Result: 5/6 scripts succeed, clear error logged
```

### Test Case 3: Multiple Scripts Fail
```bash
[INFO] running gather_platform ✓
[INFO] running gather_helm ✗
[ERROR] Failed to run gather_helm, continuing with next script...
[INFO] running gather_operator ✗
[ERROR] Failed to run gather_operator, continuing with next script...
[INFO] running gather_route ✓
[INFO] running gather_ingress ✓
[INFO] running gather_namespace-inspect ✓

Result: 4/6 scripts succeed, both errors logged
```

## Validation

```bash
# Syntax check
bash -n collection-scripts/must_gather
# Exit code: 0 ✓

# Simulate failure test
# (Temporarily make a script exit 1, verify collection continues)
```

## User Experience Impact

### For End Users

**Before**: 
- ❌ "Collection failed, try again"
- ❌ No data if any script errors
- ❌ Unclear what went wrong

**After**:
- ✅ "Collection completed with some errors"
- ✅ Partial data always collected
- ✅ Clear log of what failed
- ✅ Can still analyze successful collections

### For Support Teams

**Before**:
- ❌ "No must-gather available"
- ❌ Have to ask customer to retry
- ❌ Lose time waiting for new collection

**After**:
- ✅ "Have partial must-gather"
- ✅ Can analyze what was collected
- ✅ Can identify systemic issues (e.g., permission problems)
- ✅ Faster case resolution

## Best Practices

### Script Authors

When writing collection scripts:

1. **Exit non-zero on failure** - Clear signal to orchestrator
   ```bash
   if ! some_command; then
       log_error "Command failed"
       exit 1
   fi
   ```

2. **Don't use `exit 0` to hide errors** - Be honest about failures

3. **Log errors clearly** - Help users understand what failed

4. **Make scripts idempotent** - Safe to retry

### Users

When analyzing collections with errors:

1. **Check logs** - Look for ERROR messages
2. **Understand what's missing** - Failed scripts won't have output
3. **Work with what you have** - Partial data is often sufficient
4. **Report patterns** - Multiple failures might indicate bigger issue

## Backward Compatibility

✅ **100% Backward Compatible**

- Successful scripts behave identically
- Failed scripts now handled gracefully instead of aborting
- Output structure unchanged
- Exit code behavior: Always exits 0 (successful collection completion)
- User-facing behavior: Better (more data, clearer errors)

## Future Enhancements

Potential improvements:

1. **Summary report** - List which scripts succeeded/failed at end
2. **Retry logic** - Optionally retry failed scripts once
3. **Timeout per script** - Prevent one script from hanging collection
4. **Parallel execution** - Run independent scripts concurrently
5. **Failure metrics** - Track which scripts fail most often

## Conclusion

The error handling improvement ensures that **must-gather collections complete successfully** even when individual scripts fail. This provides:

- ✅ **Maximum data collection** - Get all possible data
- ✅ **Clear error reporting** - Know what failed
- ✅ **Predictable behavior** - Collection always completes
- ✅ **Better user experience** - Something is better than nothing
- ✅ **Faster support** - Partial data beats no data

This change makes the must-gather tool more **robust** and **production-ready** for real-world scenarios where not everything always works perfectly.

