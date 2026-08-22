#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

SUITE="board_reset_xsim"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${RESULT_ROOT}/board/reset_xsim_${STAMP}"
LOG="${OUT}/run.log"
STATUS="FAIL"
mkdir -p "${OUT}"

finish() {
    local rc=$?
    trap - EXIT
    if [[ ${rc} -eq 0 ]]; then STATUS="PASS"; fi
    print_summary "${SUITE}" "${STATUS}" \
        "frequency_mhz=175" "output=${OUT}" "log=${LOG}" | tee -a "${LOG}"
    exit "${rc}"
}
trap finish EXIT

VIVADO_BIN="$(find_vivado_bin)"
XVLOG="$(tool_path "${VIVADO_BIN}" xvlog)"
XELAB="$(tool_path "${VIVADO_BIN}" xelab)"
XSIM="$(tool_path "${VIVADO_BIN}" xsim)"
GLBL="$(cd "${VIVADO_BIN}/.." && pwd)/data/verilog/src/glbl.v"

mapfile -t RTL_FILES < <(streaming_rtl_sources)
MODEL_FILES=(
    "${RTL_FILES[@]}"
    "${REPO_ROOT}/engrenring/rtl/source/board/uart_rx.v"
    "${REPO_ROOT}/engrenring/rtl/source/board/uart_tx.v"
    "${REPO_ROOT}/engrenring/rtl/source/board/aes_gcm_uart_rsp_bridge.v"
    "${REPO_ROOT}/engrenring/rtl/source/board/arty_a7_100t_aes_gcm_uart_rsp_top.v"
    "${REPO_ROOT}/verification/board/tb_board_reset_qualifier.sv"
    "${GLBL}"
)

for required in "${XVLOG}" "${XELAB}" "${XSIM}" "${MODEL_FILES[@]}"; do
    if [[ ! -f "${required}" ]]; then
        printf 'BOARD_RESET_XSIM_MISSING path=%s\n' "${required}" | tee -a "${LOG}"
        exit 1
    fi
done

cd "${OUT}"
{
    "${XVLOG}" -sv --relax "${MODEL_FILES[@]}"
    "${XELAB}" tb_board_reset_qualifier glbl -L unisims_ver \
        --relax --debug off -s board_reset_xsim
    "${XSIM}" board_reset_xsim --runall --log simulation.log
} 2>&1 | tee "${LOG}"

grep -q 'BOARD_RESET_QUALIFIER_PASS' "${LOG}"
