#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" == Linux* && -n "${WSL_DISTRO_NAME:-}" ]]; then
    printf 'VERIFICATION_SUMMARY suite=all status=NOT_RUN reason=launch_from_git_bash_for_windows_simulators\n' >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/results"
mkdir -p "${RESULT_DIR}"
LOG="${RESULT_DIR}/run_all.log"
FAILED=0
PARTIAL=0
NOT_RUN=0
PASSED=0
TOTAL=0

run_one() {
    local script="$1"
    local suite_log
    local rc
    local summary
    local status

    suite_log="$(mktemp "${RESULT_DIR}/.run_all.${script}.XXXXXX")"
    set +e
    bash "${SCRIPT_DIR}/${script}" 2>&1 | tee -a "${LOG}" | tee "${suite_log}"
    rc=${PIPESTATUS[0]}
    set -e
    summary="$(grep '^VERIFICATION_SUMMARY ' "${suite_log}" | tail -n 1 || true)"
    rm -f "${suite_log}"
    status="$(sed -n 's/.* status=\([^ ]*\).*/\1/p' <<< "${summary}")"
    TOTAL=$((TOTAL+1))

    if [[ ${rc} -ne 0 ]]; then
        FAILED=$((FAILED+1))
        return
    fi
    case "${status}" in
        PASS) PASSED=$((PASSED+1)) ;;
        PARTIAL_PASS) PARTIAL=$((PARTIAL+1)) ;;
        NOT_RUN) NOT_RUN=$((NOT_RUN+1)) ;;
        *) FAILED=$((FAILED+1)) ;;
    esac
}

: > "${LOG}"
run_one run_smoke.sh
run_one run_nist.sh
run_one run_uvm_xsim.sh
run_one run_uvm_regression.sh
run_one run_board_reset_xsim.sh
run_one run_formal.sh

if [[ ${FAILED} -ne 0 ]]; then
    printf 'VERIFICATION_SUMMARY suite=all status=FAIL passed=%s partial=%s not_run=%s failed=%s total=%s log=%s\n' \
        "${PASSED}" "${PARTIAL}" "${NOT_RUN}" "${FAILED}" "${TOTAL}" "${LOG}"
    exit 1
fi
if [[ ${PASSED} -eq 0 && ${PARTIAL} -eq 0 ]]; then
    printf 'VERIFICATION_SUMMARY suite=all status=NOT_RUN passed=0 partial=0 not_run=%s failed=0 total=%s log=%s\n' \
        "${NOT_RUN}" "${TOTAL}" "${LOG}"
    exit 2
fi
if [[ ${PARTIAL} -ne 0 || ${NOT_RUN} -ne 0 ]]; then
    printf 'VERIFICATION_SUMMARY suite=all status=PARTIAL_PASS passed=%s partial=%s not_run=%s failed=0 total=%s log=%s\n' \
        "${PASSED}" "${PARTIAL}" "${NOT_RUN}" "${TOTAL}" "${LOG}"
    exit 2
fi
printf 'VERIFICATION_SUMMARY suite=all status=PASS passed=%s partial=0 not_run=0 failed=0 total=%s log=%s\n' \
    "${PASSED}" "${TOTAL}" "${LOG}"
