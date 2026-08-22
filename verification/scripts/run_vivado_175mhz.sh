#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="vivado_175mhz"
VIVADO_BIN="$(find_vivado_bin)"
VIVADO="$(tool_path "${VIVADO_BIN}" vivado)"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${RESULT_ROOT}/${SUITE}/run_${STAMP}"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_${STAMP}.log"
STATUS="FAIL"
finish(){ local rc=$?;if [[ $rc -eq 0 ]];then STATUS=PASS;fi;print_summary "${SUITE}" "${STATUS}" "output=${OUT}" "log=${LOG}";exit $rc; }
trap finish EXIT
"${VIVADO}" -mode batch -source \
    "${REPO_ROOT}/verification/vivado/run_streaming_175mhz.tcl" \
    -tclargs "${OUT}" 2>&1 | tee "${LOG}"
grep -q 'STREAMING_175MHZ_SUMMARY status=PASS' "${LOG}"
