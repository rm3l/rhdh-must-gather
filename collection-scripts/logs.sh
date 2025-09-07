#!/usr/bin/env bash

set -euo pipefail

DIR_NAME=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${DIR_NAME}/common.sh"
check_command

NAMESPACE_FILE=/var/run/secrets/kubernetes.io/serviceaccount/namespace

# if running in a pod
if [[ -f ${NAMESPACE_FILE} ]]; then
  safe_exec "oc logs --timestamps=true -n '$(cat ${NAMESPACE_FILE})' '${POD_NAME:-}' -c gather" "${BASE_COLLECTION_PATH}/must-gather.log" "must-gather pod logs"
fi
