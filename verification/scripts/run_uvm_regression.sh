#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

SUITE="uvm_modelsim"
MODELSIM_ROOT="${MODELSIM_ROOT:-/c/intelFPGA_lite/17.0/modelsim_ase}"
MODELSIM_BIN="${MODELSIM_ROOT}/win32aloem"
UVM_ROOT="${UVM_HOME:-${MODELSIM_ROOT}/verilog_src/uvm-1.2}"
UVM_SRC="${UVM_ROOT}/src"
VIVADO_ROOT="${XILINX_VIVADO:-/c/Xilinx/Vivado/2021.1}"

VLIB="${MODELSIM_BIN}/vlib.exe"
VMAP="${MODELSIM_BIN}/vmap.exe"
VLOG="${MODELSIM_BIN}/vlog.exe"
VSIM="${MODELSIM_BIN}/vsim.exe"
UVM_PKG="${UVM_SRC}/uvm_pkg.sv"
GLBL="${VIVADO_ROOT}/data/verilog/src/glbl.v"
FDRE="${VIVADO_ROOT}/data/verilog/src/unisims/FDRE.v"

for required in "${VLIB}" "${VMAP}" "${VLOG}" "${VSIM}" \
                "${UVM_PKG}" "${GLBL}" "${FDRE}"; do
    if [[ ! -f "${required}" ]]; then
        print_summary "${SUITE}" "NOT_RUN" \
            "reason=missing_dependency" "path=${required}"
        exit 0
    fi
done

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${RESULT_ROOT}/uvm/modelsim_${STAMP}"
LOG="${RESULT_ROOT}/uvm/run_uvm_regression_${STAMP}.log"
mkdir -p "${OUT}"
: > "${LOG}"
STATUS="FAIL"
SCOREBOARD_CHECKED="NOT_RUN"
SCOREBOARD_FAILED="NOT_RUN"

finish() {
    local rc=$?
    trap - EXIT
    if [[ ${rc} -eq 0 ]]; then STATUS="PASS"; fi
    print_summary "${SUITE}" "${STATUS}" \
        "mode=deterministic_uvm_1_2" \
        "scoreboard_checked=${SCOREBOARD_CHECKED}" \
        "scoreboard_failed=${SCOREBOARD_FAILED}" \
        "full_random=NOT_RUN" "coverage=NOT_COLLECTED" \
        "output=${OUT}" "log=${LOG}" | tee -a "${LOG}"
    exit "${rc}"
}
trap finish EXIT

to_windows_path() {
    cygpath -m "$1"
}

mapfile -t RTL_FILES < <(streaming_rtl_sources)
MODEL_FILES=("${GLBL}" "${FDRE}" "${RTL_FILES[@]}"
    "${REPO_ROOT}/verification/uvm/aesgcm_reference_model_pkg.sv"
    "${REPO_ROOT}/verification/uvm/aesgcm_uvm_interfaces.sv"
    "${REPO_ROOT}/verification/uvm/aesgcm_uvm_pkg.sv"
    "${REPO_ROOT}/verification/uvm/tb_uvm_top.sv")
MODEL_FILES_WINDOWS=()
for source in "${MODEL_FILES[@]}"; do
    [[ -f "${source}" ]] || {
        print_summary "${SUITE}" "FAIL" "reason=missing_source" "path=${source}"
        exit 1
    }
    MODEL_FILES_WINDOWS+=("$(to_windows_path "${source}")")
done

{
    cd "${OUT}"
    "${VMAP}" -c
    "${VLIB}" uvm
    "${VMAP}" -modelsimini modelsim.ini uvm uvm
    "${VLOG}" -modelsimini modelsim.ini -work uvm -sv \
        +define+UVM_NO_DPI "+incdir+$(to_windows_path "${UVM_SRC}")" \
        "$(to_windows_path "${UVM_PKG}")" -l uvm_compile.log
    "${VLIB}" work
    "${VMAP}" -modelsimini modelsim.ini work work
    "${VLOG}" -modelsimini modelsim.ini -work work -L uvm -sv -permissive \
        +define+UVM_NO_DPI +define+MODELSIM_STARTER \
        "+incdir+$(to_windows_path "${UVM_SRC}")" \
        "${MODEL_FILES_WINDOWS[@]}" -l dut_uvm_compile.log
    "${VSIM}" -c -modelsimini modelsim.ini -suppress 19 -L uvm \
        work.tb_uvm_top work.glbl -do "run -all; quit -f" -l uvm_run.log
} 2>&1 | tee -a "${LOG}"

RUN_LOG="${OUT}/uvm_run.log"
grep -Eq '\[SCOREBOARD\].*checked=1 failed=0' "${RUN_LOG}"
grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "${RUN_LOG}"
grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "${RUN_LOG}"
grep -Eq '\[COVERAGE\].*NOT_COLLECTED modelsim_starter samples=1' "${RUN_LOG}"
grep -Eq '^# Errors: 0, Warnings:' "${RUN_LOG}"
if grep -Eq '^# \*\* (Error|Fatal):' "${RUN_LOG}"; then
    printf 'MODELSIM_RUNTIME_ERROR detected_in=%s\n' "${RUN_LOG}" >&2
    exit 1
fi
SCOREBOARD_CHECKED="1"
SCOREBOARD_FAILED="0"

printf 'UVM_CAPABILITY constrained_random=NOT_RUN functional_coverage=NOT_COLLECTED reason=modelsim_starter_license\n' | tee -a "${LOG}"
