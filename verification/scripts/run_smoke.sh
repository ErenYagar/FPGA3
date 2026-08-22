#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="smoke"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_smoke.log"
WORK="$(new_work_dir "${SUITE}")"
STATUS="FAIL"

finish() {
    local rc=$?
    if [[ ${rc} -eq 0 ]]; then STATUS="PASS"; fi
    print_summary "${SUITE}" "${STATUS}" "assertion_failures=$(grep -c 'Assertion failed' "${LOG}" 2>/dev/null || true)" "log=${LOG}"
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

cd "${WORK}"
{
    "${XVLOG}" -sv "${RTL[@]}" "${SVA[@]}" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_ghash/tb_ghash16.sv" \
        "${REPO_ROOT}/engrenring/rtl/functional test/sv/tb_axi_smoke.sv" \
        "${GLBL}"
    "${XELAB}" tb_ghash16 glbl -L unisims_ver -s verify_ghash_smoke
    "${XSIM}" verify_ghash_smoke -runall
    "${XELAB}" tb_axi_smoke glbl -L unisims_ver -s verify_axi_smoke
    "${XSIM}" verify_axi_smoke -runall
} 2>&1 | tee "${LOG}"

grep -q 'GHASH16_PASS tests=66' "${LOG}"
grep -q 'AXI_SMOKE_PASS cycles=7676' "${LOG}"
if grep -q 'Assertion failed' "${LOG}"; then
    exit 1
fi
