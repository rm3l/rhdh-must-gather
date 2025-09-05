#!/bin/bash -x

set -euo pipefail

DIR_NAME=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
export BASE_COLLECTION_PATH="${BASE_COLLECTION_PATH:-/must-gather}"
export PROS=${PROS:-5}
export INSTALLATION_NAMESPACE=${INSTALLATION_NAMESPACE:-rhdh-operator}

# Command timeout (seconds) for kubectl/helm calls
CMD_TIMEOUT="${CMD_TIMEOUT:-30}"

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

export LOG_LEVEL="${LOG_LEVEL:-info}"
if [[ "$LOG_LEVEL" == "trace" ]]; then
  set -x
fi

# Logging functions
log() {
    local level="$1"
    shift
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] $*" >&2
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
    if [[ "$LOG_LEVEL" == "debug" || "$LOG_LEVEL" == "trace" ]]; then
        log "DEBUG" "${BLUE}$*${NC}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

function run() {
  timeout "${CMD_TIMEOUT}" "$@" 2>&1 || true
}

function kubectl_or_oc() {
  timeout "${CMD_TIMEOUT}" kubectl "$@" 2>&1 || timeout "${CMD_TIMEOUT}" oc "$@" 2>&1
}

function check_command {
    if [[ -z "$USR_BIN_GATHER" ]]; then
        log_error "This script should not be directly executed." 1>&2
        log_error "Please check \"${DIR_NAME}/gather --help\" for execution options." 1>&2
        exit 1
    fi
}


# Check if we have cluster connectivity
check_cluster_connectivity() {
    log_debug "Checking cluster connectivity..."

    if ! oc cluster-info >/dev/null 2>&1; then
        log_error "Unable to connect to Kubernetes cluster"
        return 1
    fi

    log_debug "Cluster connectivity verified"
    return 0
}

# Validate required environment
validate_environment() {
    local errors=0

    # Check required commands
    if ! (command_exists "kubectl" || command_exists "oc"); then
        log_error "Required 'kubectl' or 'oc' command not found"
        ((errors++))
    fi
    if ! command_exists "helm"; then
        log_error "Required command not found: helm"
        ((errors++))
    fi
    if ! command_exists "jq"; then
        log_error "Required command not found: jq"
        ((errors++))
    fi

    # Check output directory is writable
    if ! touch "$BASE_COLLECTION_PATH/.test" 2>/dev/null; then
        log_error "Output directory is not writable: $BASE_COLLECTION_PATH"
        ((errors++))
    else
        rm -f "$BASE_COLLECTION_PATH/.test"
    fi

    # Check cluster connectivity
    if ! check_cluster_connectivity; then
        ((errors++))
    fi

    return $errors
}

# Create directory if it doesn't exist
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        mkdir -p "$dir"
    fi
}

# Check if running in container
is_container() {
    [[ -f /.dockerenv ]] || [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]
}

# Initialize must-gather environment
init_must_gather() {
    log_info "Initializing must-gather environment"
    log_debug "Must-gather directory: $BASE_COLLECTION_PATH"
    log_debug "Log level: $LOG_LEVEL"
    log_debug "Collection timeout: ${CMD_TIMEOUT}s"
    log_debug "Container environment: $(is_container && echo "yes" || echo "no")"

    # Validate environment
    if ! validate_environment; then
        log_error "Environment validation failed"
        return 1
    fi

    # Create base directories
    ensure_directory "$BASE_COLLECTION_PATH"

    log_success "Must-gather environment initialized"
    return 0
}

# Safe command execution with timeout
safe_exec() {
    local cmd="$1 || true"
    local output_file="$2"
    local description="${3:-}"

    if [[ -n "$description" ]]; then
        log_info "Collecting: $description"
    fi

    log_debug "Executing: $cmd"
    log_debug "Output file: $output_file"

    # Ensure output directory exists
    mkdir -p "$(dirname "$output_file")"

    if ! timeout "$CMD_TIMEOUT" bash -c "$cmd" > "$output_file" 2>&1; then
        log_warn "Command timed out or failed: $cmd"
        echo "Command failed or timed out: $cmd" > "$output_file"
        echo "Timestamp: $(date)" >> "$output_file"
        echo "Timeout: ${CMD_TIMEOUT}s" >> "$output_file"
        return 1
    fi

    return 0
}

export_log_collection_args() {
	# validation of MUST_GATHER_SINCE and MUST_GATHER_SINCE_TIME is done by the
	# caller (oc adm must-gather) so it's safe to use the values as they are.
	log_collection_args=""
	log_debug "MUST_GATHER_SINCE=${MUST_GATHER_SINCE:-}"
	log_debug "MUST_GATHER_SINCE_TIME=${MUST_GATHER_SINCE_TIME:-}"

	if [ -n "${MUST_GATHER_SINCE:-}" ]; then
		log_collection_args=--since="${MUST_GATHER_SINCE}"
	fi
	if [ -n "${MUST_GATHER_SINCE_TIME:-}" ]; then
		log_collection_args=--since-time="${MUST_GATHER_SINCE_TIME}"
	fi

	# oc adm node-logs `--since` parameter is not the same as oc adm inspect `--since`.
	# it takes a simplified duration in the form of '(+|-)[0-9]+(s|m|h|d)' or
	# an ISO formatted time. since MUST_GATHER_SINCE and MUST_GATHER_SINCE_TIME
	# are formatted differently, we re-format them so they can be used
	# transparently by node-logs invocations.
	node_log_collection_args=""

	if [ -n "${MUST_GATHER_SINCE:-}" ]; then
		# shellcheck disable=SC2001
		since=$(echo "${MUST_GATHER_SINCE:-}" | sed 's/\([0-9]*[dhms]\).*/\1/')
		node_log_collection_args=--since="-${since}"
	fi
	if [ -n "${MUST_GATHER_SINCE_TIME:-}" ]; then
	  # shellcheck disable=SC2001
		iso_time=$(echo "${MUST_GATHER_SINCE_TIME}" | sed 's/T/ /; s/Z//')
		node_log_collection_args=--since="${iso_time}"
	fi
	export log_collection_args
	export node_log_collection_args
}
