#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"

SUITE="uvm_xsim"
SEEDS=(175001 175019 175039)
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${RESULT_ROOT}/uvm/xsim_${STAMP}"
LOG="${RESULT_ROOT}/uvm/run_uvm_xsim_${STAMP}.log"
STATUS="FAIL"
SEEDS_PASSED=0
mkdir -p "${OUT}"
: > "${LOG}"

finish() {
    local rc=$?
    trap - EXIT
    if [[ ${rc} -eq 0 ]]; then STATUS="PASS"; fi
    print_summary "${SUITE}" "${STATUS}" \
        "uvm_version=1.2" "frequency_mhz=175" \
        "seeds_passed=${SEEDS_PASSED}" "seeds_total=${#SEEDS[@]}" \
        "output=${OUT}" "log=${LOG}" | tee -a "${LOG}"
    exit "${rc}"
}
trap finish EXIT

VIVADO_BIN="$(find_vivado_bin)"
XVLOG="$(tool_path "${VIVADO_BIN}" xvlog)"
XELAB="$(tool_path "${VIVADO_BIN}" xelab)"
XSIM="$(tool_path "${VIVADO_BIN}" xsim)"
GLBL="$(cd "${VIVADO_BIN}/.." && pwd)/data/verilog/src/glbl.v"

for required in "${XVLOG}" "${XELAB}" "${XSIM}" "${GLBL}"; do
    if [[ ! -f "${required}" ]]; then
        trap - EXIT
        print_summary "${SUITE}" "NOT_RUN" \
            "reason=missing_dependency" "path=${required}" | tee -a "${LOG}"
        exit 0
    fi
done

mapfile -t RTL_FILES < <(streaming_rtl_sources)
MODEL_FILES=(
    "${RTL_FILES[@]}"
    "${REPO_ROOT}/verification/uvm/aesgcm_reference_model_pkg.sv"
    "${REPO_ROOT}/verification/uvm/aesgcm_uvm_interfaces.sv"
    "${REPO_ROOT}/verification/uvm/aesgcm_uvm_pkg.sv"
    "${REPO_ROOT}/verification/uvm/tb_uvm_top.sv"
    "${GLBL}"
)
for source in "${MODEL_FILES[@]}"; do
    if [[ ! -f "${source}" ]]; then
        printf 'UVM_XSIM_MISSING_SOURCE path=%s\n' "${source}" | tee -a "${LOG}"
        exit 1
    fi
done

INPUT_MANIFEST="${OUT}/compile_inputs.sha256"
INPUT_HASHES=()
: > "${INPUT_MANIFEST}"
for source in "${MODEL_FILES[@]}"; do
    source_hash="$(sha256sum "${source}" | cut -d ' ' -f 1)"
    INPUT_HASHES+=("${source_hash}")
    printf '%s  %s\n' "${source_hash}" "${source}" >> "${INPUT_MANIFEST}"
    printf 'UVM_XSIM_INPUT sha256=%s path=%s\n' \
        "${source_hash}" "${source}" >> "${LOG}"
done

cd "${OUT}"
{
    "${XVLOG}" -sv --relax -L uvm "${MODEL_FILES[@]}"
    "${XELAB}" tb_uvm_top glbl -L uvm -L unisims_ver \
        --uvm_version 1.2 --relax --debug off -s aesgcm_uvm_xsim
} 2>&1 | tee -a "${LOG}"

SUMMARY_CSV="${OUT}/summary.csv"
SUMMARY_JSON="${OUT}/summary.json"
printf 'seed,status,records,scoreboard_failed,coverage_pct,scenarios\n' > "${SUMMARY_CSV}"

RESULT_STATUS=()
RESULT_RECORDS=()
RESULT_FAILED=()
RESULT_COVERAGE=()
RESULT_SCENARIOS=()

for seed in "${SEEDS[@]}"; do
    RUN_LOG="${OUT}/seed_${seed}.log"
    CONSOLE_LOG="${OUT}/seed_${seed}_console.log"
    "${XSIM}" aesgcm_uvm_xsim --runall --sv_seed "${seed}" \
        --testplusarg UVM_TESTNAME_aesgcm_xsim_random_test \
        --testplusarg "UVM_SEED_${seed}" \
        --cov_db_dir "${OUT}/coverage" --cov_db_name "seed_${seed}" \
        --log "${RUN_LOG}" 2>&1 | tee "${CONSOLE_LOG}" | tee -a "${LOG}"

    RESULT_LINE="$(grep 'UVM_REGRESSION_RESULT' "${RUN_LOG}" | tail -n 1)"
    grep -Eq 'UVM_REGRESSION_RESULT status=PASS' <<< "${RESULT_LINE}"
    grep -Eq 'UVM_ERROR[[:space:]]*:[[:space:]]*0' "${RUN_LOG}"
    grep -Eq 'UVM_FATAL[[:space:]]*:[[:space:]]*0' "${RUN_LOG}"
    grep -Eq '\[COVERAGE\].*coverage_pct=100\.00 required_bins=COVERED' "${RUN_LOG}"

    records="$(sed -E 's/.* records=([0-9]+).*/\1/' <<< "${RESULT_LINE}")"
    failed="$(sed -E 's/.* scoreboard_failed=([0-9]+).*/\1/' <<< "${RESULT_LINE}")"
    coverage="$(sed -E 's/.* coverage_pct=([0-9.]+).*/\1/' <<< "${RESULT_LINE}")"
    scenarios="$(grep -c '\[SCENARIO\] index=' "${RUN_LOG}")"
    [[ "${records}" == "8" && "${failed}" == "0" && "${coverage}" == "100.00" ]]
    [[ "${scenarios}" == "8" ]]

    printf '%s,PASS,%s,%s,%s,%s\n' \
        "${seed}" "${records}" "${failed}" "${coverage}" "${scenarios}" \
        >> "${SUMMARY_CSV}"
    RESULT_STATUS+=("PASS")
    RESULT_RECORDS+=("${records}")
    RESULT_FAILED+=("${failed}")
    RESULT_COVERAGE+=("${coverage}")
    RESULT_SCENARIOS+=("${scenarios}")
    SEEDS_PASSED=$((SEEDS_PASSED+1))
done

{
    printf '{\n'
    printf '  "suite": "uvm_xsim",\n'
    printf '  "simulator": "Vivado Simulator 2021.1",\n'
    printf '  "uvm_version": "1.2",\n'
    printf '  "frequency_mhz": 175,\n'
    printf '  "compile_inputs": [\n'
    for index in "${!MODEL_FILES[@]}"; do
        if [[ ${index} -ne 0 ]]; then printf ',\n'; fi
        input_path="${MODEL_FILES[${index}]}"
        input_path="${input_path//\\/\\\\}"
        input_path="${input_path//\"/\\\"}"
        printf '    {"path": "%s", "sha256": "%s"}' \
            "${input_path}" "${INPUT_HASHES[${index}]}"
    done
    printf '\n  ],\n'
    printf '  "results": [\n'
    for index in "${!SEEDS[@]}"; do
        if [[ ${index} -ne 0 ]]; then printf ',\n'; fi
        printf '    {"seed": %s, "status": "%s", "records": %s, "scoreboard_failed": %s, "coverage_pct": %s, "scenarios": %s}' \
            "${SEEDS[${index}]}" "${RESULT_STATUS[${index}]}" \
            "${RESULT_RECORDS[${index}]}" "${RESULT_FAILED[${index}]}" \
            "${RESULT_COVERAGE[${index}]}" "${RESULT_SCENARIOS[${index}]}"
    done
    printf '\n  ]\n}\n'
} > "${SUMMARY_JSON}"

printf 'UVM_XSIM_REGRESSION_PASS seeds=%s records_per_seed=8 total_records=%s coverage_pct=100.00 summary_csv=%s summary_json=%s\n' \
    "${#SEEDS[@]}" "$((SEEDS_PASSED*8))" "${SUMMARY_CSV}" "${SUMMARY_JSON}" | tee -a "${LOG}"
