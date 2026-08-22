#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="nist"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_nist.log"
WORK="$(new_work_dir "${SUITE}")"
STATUS="FAIL"

finish() {
    local rc=$?
    if [[ ${rc} -eq 0 ]]; then STATUS="PASS"; fi
    print_summary "${SUITE}" "${STATUS}" "expected=47250" "log=${LOG}"
    exit "${rc}"
}
trap finish EXIT

VIVADO_BIN="$(find_vivado_bin)"
XVLOG="$(tool_path "${VIVADO_BIN}" xvlog)"
XELAB="$(tool_path "${VIVADO_BIN}" xelab)"
XSIM="$(tool_path "${VIVADO_BIN}" xsim)"
mapfile -t RTL < <(streaming_rtl_sources)
mapfile -t SVA < <(sva_sources)
GLBL="$(cd "${VIVADO_BIN}/.." && pwd)/data/verilog/src/glbl.v"
RSP_SOURCE="${REPO_ROOT}/engrenring/rtl/functional test/rsp"

mkdir -p "${WORK}/rsp"
cp "${RSP_SOURCE}"/*.rsp "${WORK}/rsp/"
cd "${WORK}"
{
    "${XVLOG}" -sv "${RTL[@]}" "${SVA[@]}" \
        "${REPO_ROOT}/engrenring/rtl/functional test/sv/tb_nist.sv" \
        "${GLBL}"
    "${XELAB}" tb_nist glbl -L unisims_ver -s verify_nist_47250
    "${XSIM}" verify_nist_47250 -runall -testplusarg RSP_DIR_rsp
} 2>&1 | tee "${LOG}"

grep -q 'NIST_TOTAL_SUMMARY pass=47250 fail=0 total=47250' "${LOG}"
grep -q 'NIST_ALL_PASS 47250/47250' "${LOG}"
if grep -q 'Assertion failed' "${LOG}"; then
    exit 1
fi
