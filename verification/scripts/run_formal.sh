#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="formal"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_formal.log"

FORMAL_TOOL=""
for tool in jg qverify onespin; do
    if command -v "${tool}" >/dev/null 2>&1; then
        FORMAL_TOOL="$(command -v "${tool}")"
        break
    fi
done

if [[ -z "${FORMAL_TOOL}" ]]; then
    printf 'FORMAL_NOT_RUN reason=no_supported_formal_tool tools_checked=jg,qverify,onespin\n' | tee "${LOG}"
    print_summary "${SUITE}" "NOT_RUN" "reason=no_supported_formal_tool" "log=${LOG}"
    exit 0
fi

{
    "${FORMAL_TOOL}" -version || "${FORMAL_TOOL}" -help
} 2>&1 | tee "${LOG}"

printf 'FORMAL_NOT_RUN reason=tool_detected_but_version_specific_adapter_missing tool=%s\n' "${FORMAL_TOOL}" | tee -a "${LOG}"
print_summary "${SUITE}" "NOT_RUN" "reason=version_specific_adapter_missing" "tool=${FORMAL_TOOL}" "log=${LOG}"
