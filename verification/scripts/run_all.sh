#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/results"
mkdir -p "${RESULT_DIR}"
LOG="${RESULT_DIR}/run_all.log"
FAILED=0

run_one() {
    local script="$1"
    if ! "${SCRIPT_DIR}/${script}" 2>&1 | tee -a "${LOG}"; then
        FAILED=1
    fi
}

: > "${LOG}"
run_one run_smoke.sh
run_one run_nist.sh
run_one run_uvm_regression.sh
run_one run_formal.sh

if [[ ${FAILED} -ne 0 ]]; then
    printf 'VERIFICATION_SUMMARY suite=all status=FAIL log=%s\n' "${LOG}"
    exit 1
fi
printf 'VERIFICATION_SUMMARY suite=all status=PASS_AVAILABLE_TESTS log=%s\n' "${LOG}"
