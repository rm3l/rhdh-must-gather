#!/bin/bash

# Shared utilities for RHDH Must-Gather scripts
# This file should be sourced by other scripts: source "$(dirname "$0")/lib/utils.sh"

# Global variables
export MUST_GATHER_DIR="${MUST_GATHER_DIR:-/must-gather}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export COLLECTION_TIMEOUT="${COLLECTION_TIMEOUT:-300}"

# Time constraint variables (used by oc adm must-gather --since/--since-time)
export SINCE="${SINCE:-}"
export SINCE_TIME="${SINCE_TIME:-}"

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[${timestamp}] [${level}] $*" >&2
}

log_info() { 
    log "INFO" "$@"
}

log_warn() { 
    log "WARN" "${YELLOW}$*${NC}"
}

log_error() { 
    log "ERROR" "${RED}$*${NC}"
}

log_success() { 
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_debug() {
    if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
        log "DEBUG" "${BLUE}$*${NC}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Safe command execution with timeout
safe_exec() {
    local cmd="$1"
    local output_file="$2"
    local description="${3:-}"
    
    if [[ -n "$description" ]]; then
        log_info "Collecting: $description"
    fi
    
    log_debug "Executing: $cmd"
    log_debug "Output file: $output_file"
    
    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"
    
    if ! timeout "$COLLECTION_TIMEOUT" bash -c "$cmd" > "$output_file" 2>&1; then
        log_warn "Command timed out or failed: $cmd"
        echo "Command failed or timed out: $cmd" > "$output_file"
        echo "Timestamp: $(date)" >> "$output_file"
        echo "Timeout: ${COLLECTION_TIMEOUT}s" >> "$output_file"
        return 1
    fi
    
    return 0
}

# Check if we have cluster connectivity
check_cluster_connectivity() {
    log_debug "Checking cluster connectivity..."
    
    if ! command_exists kubectl; then
        log_error "kubectl command not found"
        return 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_error "Unable to connect to Kubernetes cluster"
        return 1
    fi
    
    log_debug "Cluster connectivity verified"
    return 0
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Write key-value data to a file
write_detection_result() {
    local key="$1"
    local value="$2"
    local results_file="${3:-$MUST_GATHER_DIR/detection-results.env}"
    
    ensure_directory "$(dirname "$results_file")"
    
    # Remove existing entry for this key
    if [[ -f "$results_file" ]]; then
        grep -v "^${key}=" "$results_file" > "${results_file}.tmp" 2>/dev/null || true
        mv "${results_file}.tmp" "$results_file" 2>/dev/null || true
    fi
    
    # Add new entry
    echo "${key}=${value}" >> "$results_file"
    log_debug "Detection result: ${key}=${value}"
}

# Read detection results
read_detection_result() {
    local key="$1"
    local results_file="${2:-$MUST_GATHER_DIR/detection-results.env}"
    
    if [[ -f "$results_file" ]]; then
        grep "^${key}=" "$results_file" 2>/dev/null | cut -d'=' -f2- || echo ""
    else
        echo ""
    fi
}

# Load all detection results as environment variables
load_detection_results() {
    local results_file="${1:-$MUST_GATHER_DIR/detection-results.env}"
    
    if [[ -f "$results_file" ]]; then
        log_debug "Loading detection results from: $results_file"
        # shellcheck source=/dev/null
        source "$results_file"
    fi
}

# Load RHDH instances information
load_rhdh_instances() {
    local instances_file="${1:-$MUST_GATHER_DIR/rhdh-instances.env}"
    
    if [[ -f "$instances_file" ]]; then
        log_debug "Loading RHDH instances from: $instances_file"
        
        # Read instances into array (skip comment lines)
        mapfile -t RHDH_INSTANCES < <(grep -v '^#' "$instances_file" 2>/dev/null || true)
        
        log_debug "Loaded ${#RHDH_INSTANCES[@]} RHDH instances"
        return 0
    else
        log_debug "No RHDH instances file found"
        return 1
    fi
}

# Get all RHDH namespaces
get_rhdh_namespaces() {
    load_rhdh_instances
    
    local namespaces=()
    for instance in "${RHDH_INSTANCES[@]}"; do
        if [[ -n "$instance" ]]; then
            local namespace=$(echo "$instance" | cut -d':' -f1)
            if [[ -n "$namespace" ]]; then
                namespaces+=("$namespace")
            fi
        fi
    done
    
    # Remove duplicates and return
    printf '%s\n' "${namespaces[@]}" | sort -u
}

# Get RHDH instances by deployment type
get_rhdh_instances_by_type() {
    local deployment_type="$1"
    load_rhdh_instances
    
    local matching_instances=()
    for instance in "${RHDH_INSTANCES[@]}"; do
        if [[ -n "$instance" ]]; then
            local instance_type=$(echo "$instance" | cut -d':' -f2)
            if [[ "$instance_type" == "$deployment_type" ]]; then
                matching_instances+=("$instance")
            fi
        fi
    done
    
    printf '%s\n' "${matching_instances[@]}"
}

# Check if multiple RHDH instances exist
has_multiple_rhdh_instances() {
    load_detection_results
    local instances_count="${RHDH_INSTANCES_COUNT:-0}"
    [[ "$instances_count" -gt 1 ]]
}

# Create a section header in output files
write_section_header() {
    local title="$1"
    local output_file="$2"
    
    cat >> "$output_file" << EOF

================================================================================
$title
================================================================================
Collection Time: $(date)
================================================================================

EOF
}

# Get script directory (useful for finding other scripts)
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
}

# Get lib directory
get_lib_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

# Check if running in container
is_container() {
    [[ -f /.dockerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]
}

# Validate required environment
validate_environment() {
    local errors=0
    
    # Check required commands
    local required_commands=("kubectl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            ((errors++))
        fi
    done
    
    # Check output directory is writable
    if ! touch "$MUST_GATHER_DIR/.test" 2>/dev/null; then
        log_error "Output directory is not writable: $MUST_GATHER_DIR"
        ((errors++))
    else
        rm -f "$MUST_GATHER_DIR/.test"
    fi
    
    # Check cluster connectivity
    if ! check_cluster_connectivity; then
        ((errors++))
    fi
    
    return $errors
}

# Initialize must-gather environment
init_must_gather() {
    log_info "Initializing must-gather environment"
    log_debug "Must-gather directory: $MUST_GATHER_DIR"
    log_debug "Log level: $LOG_LEVEL"
    log_debug "Collection timeout: ${COLLECTION_TIMEOUT}s"
    log_debug "Container environment: $(is_container && echo "yes" || echo "no")"
    
    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        return 1
    fi
    
    # Create base directories
    ensure_directory "$MUST_GATHER_DIR"
    
    log_success "Must-gather environment initialized"
    return 0
}

# Time constraint utilities

# Convert relative time (like "2h") to timestamp
convert_since_to_timestamp() {
    local since="$1"
    
    # Handle different time formats
    if [[ "$since" =~ ^[0-9]+s$ ]]; then
        # Seconds ago
        local seconds="${since%s}"
        date -u -d "$seconds seconds ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -v-"${seconds}S" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    elif [[ "$since" =~ ^[0-9]+m$ ]]; then
        # Minutes ago
        local minutes="${since%m}"
        date -u -d "$minutes minutes ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -v-"${minutes}M" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    elif [[ "$since" =~ ^[0-9]+h$ ]]; then
        # Hours ago
        local hours="${since%h}"
        date -u -d "$hours hours ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -v-"${hours}H" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    elif [[ "$since" =~ ^[0-9]+d$ ]]; then
        # Days ago
        local days="${since%d}"
        date -u -d "$days days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
        date -u -v-"${days}d" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    else
        # Try to parse as relative time directly
        date -u -d "$since" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo ""
    fi
}

# Get the effective since time for log/event collection
get_effective_since_time() {
    local since_timestamp=""
    
    # Check for SINCE_TIME first (absolute timestamp)
    if [[ -n "$SINCE_TIME" ]]; then
        since_timestamp="$SINCE_TIME"
        log_debug "Using SINCE_TIME: $since_timestamp"
    # Then check for SINCE (relative time)
    elif [[ -n "$SINCE" ]]; then
        since_timestamp=$(convert_since_to_timestamp "$SINCE")
        log_debug "Converted SINCE '$SINCE' to timestamp: $since_timestamp"
    fi
    
    echo "$since_timestamp"
}

# Check if time constraints are specified
has_time_constraints() {
    [[ -n "$SINCE" ]] || [[ -n "$SINCE_TIME" ]]
}

# Get kubectl logs time arguments
get_kubectl_logs_since_args() {
    local since_timestamp
    since_timestamp=$(get_effective_since_time)
    
    if [[ -n "$since_timestamp" ]]; then
        echo "--since-time=$since_timestamp"
    elif [[ -n "$SINCE" ]]; then
        # kubectl logs supports relative time directly
        echo "--since=$SINCE"
    else
        echo ""
    fi
}

# Get kubectl events time filter
get_kubectl_events_time_filter() {
    local since_timestamp
    since_timestamp=$(get_effective_since_time)
    
    if [[ -n "$since_timestamp" ]]; then
        echo "lastTimestamp>='$since_timestamp'"
    else
        echo ""
    fi
}

# Log time constraint information
log_time_constraints() {
    if has_time_constraints; then
        log_info "Time constraints detected:"
        [[ -n "$SINCE" ]] && log_info "  SINCE: $SINCE"
        [[ -n "$SINCE_TIME" ]] && log_info "  SINCE_TIME: $SINCE_TIME"
        
        local effective_time
        effective_time=$(get_effective_since_time)
        [[ -n "$effective_time" ]] && log_info "  Effective since time: $effective_time"
    else
        log_debug "No time constraints specified"
    fi
}

# Cleanup function
cleanup_must_gather() {
    log_debug "Performing cleanup..."
    # Remove temporary files, etc.
    find "$MUST_GATHER_DIR" -name "*.tmp" -delete 2>/dev/null || true
    log_debug "Cleanup completed"
}