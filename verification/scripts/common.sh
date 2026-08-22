#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESULT_ROOT="${REPO_ROOT}/verification/results"

find_vivado_bin() {
    local candidates=()
    if [[ -n "${XILINX_VIVADO:-}" ]]; then
        candidates+=("${XILINX_VIVADO}/bin")
    fi
    candidates+=(
        "/c/Xilinx/Vivado/2021.1/bin"
        "/opt/Xilinx/Vivado/2021.1/bin"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [[ -x "${candidate}/xvlog" || -f "${candidate}/xvlog.bat" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 1
}

tool_path() {
    local bin_dir="$1"
    local name="$2"
    if [[ -x "${bin_dir}/${name}" ]]; then
        printf '%s\n' "${bin_dir}/${name}"
    elif [[ -f "${bin_dir}/${name}.bat" ]]; then
        printf '%s\n' "${bin_dir}/${name}.bat"
    else
        return 1
    fi
}

streaming_rtl_sources() {
    printf '%s\n' \
        "${REPO_ROOT}/engrenring/rtl/source/aes_core/sbox.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_aes/aes_block_engine.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_aes/aes_first_block_engine.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_aes/aes_key_context.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_ghash/ghash16.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_axi/axi_lite_regs.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_axi/axis_output_skid_8.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_core/stream_fifo.v" \
        "${REPO_ROOT}/engrenring/rtl/source/stream_core/aes_gcm_stream_core.v" \
        "${REPO_ROOT}/engrenring/rtl/source/aes_gcm_axi_top.v"
}

sva_sources() {
    printf '%s\n' \
        "${REPO_ROOT}/verification/sva/ghash16_sva.sv" \
        "${REPO_ROOT}/verification/sva/ghash_queue_sva.sv" \
        "${REPO_ROOT}/verification/sva/aes_key_context_sva.sv" \
        "${REPO_ROOT}/verification/sva/axis_output_sva.sv" \
        "${REPO_ROOT}/verification/sva/aesgcm_tag_sva.sv" \
        "${REPO_ROOT}/verification/sva/bind_all.sv"
}

new_work_dir() {
    local suite="$1"
    mkdir -p "${RESULT_ROOT}/${suite}/work"
    mktemp -d "${RESULT_ROOT}/${suite}/work/run.XXXXXX"
}

print_summary() {
    local suite="$1"
    local status="$2"
    shift 2
    printf 'VERIFICATION_SUMMARY suite=%s status=%s' "${suite}" "${status}"
    while (($#)); do
        printf ' %s' "$1"
        shift
    done
    printf '\n'
}
