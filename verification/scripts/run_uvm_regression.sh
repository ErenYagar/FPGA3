#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="uvm"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_uvm_regression.log"

find_uvm_pkg() {
    local candidate
    for candidate in \
        "${UVM_HOME:-}/src/uvm_pkg.sv" \
        "/c/Xilinx/Vivado/2021.1/data/xsim/systemC/uvm/uvm_pkg.sv" \
        "/c/intelFPGA_lite/17.0/modelsim_ase/uvm-1.2/src/uvm_pkg.sv"; do
        if [[ -n "${candidate}" && -f "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

if ! UVM_PKG="$(find_uvm_pkg)"; then
    printf 'UVM_NOT_RUN reason=uvm_1_2_library_unavailable\n' | tee "${LOG}"
    print_summary "${SUITE}" "NOT_RUN" "reason=uvm_1_2_library_unavailable" "log=${LOG}"
    exit 0
fi

printf 'UVM_NOT_RUN reason=simulator_adapter_not_configured uvm_pkg=%s\n' "${UVM_PKG}" | tee "${LOG}"
print_summary "${SUITE}" "NOT_RUN" "reason=simulator_adapter_not_configured" "log=${LOG}"
