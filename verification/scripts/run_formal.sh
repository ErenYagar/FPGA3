#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/common.sh"
SUITE="formal"
mkdir -p "${RESULT_ROOT}/${SUITE}"
LOG="${RESULT_ROOT}/${SUITE}/run_formal.log"

if ! command -v yosys >/dev/null 2>&1 &&
   command -v cygpath >/dev/null 2>&1 &&
   command -v wsl.exe >/dev/null 2>&1 &&
   env MSYS_NO_PATHCONV=1 wsl.exe --exec bash -c \
       'command -v yosys >/dev/null 2>&1' >/dev/null 2>&1
then
    FORMAL_REPO_WINDOWS="$(cygpath -w "${REPO_ROOT}")"
    printf 'FORMAL_DISPATCH host=git-bash target=wsl repo=%s\n' "${REPO_ROOT}"
    exec env MSYS_NO_PATHCONV=1 wsl.exe --exec bash -c \
        'set -euo pipefail; repo="$(wslpath -a "$1")"; cd "$repo"; exec bash verification/scripts/run_formal.sh' \
        bash "${FORMAL_REPO_WINDOWS}"
fi

if ! command -v yosys >/dev/null 2>&1; then
    printf 'FORMAL_NOT_RUN reason=no_yosys tools_checked=yosys\n' | tee "${LOG}"
    print_summary "${SUITE}" "NOT_RUN" "reason=no_yosys" "log=${LOG}"
    exit 0
fi

YOSYS_TOOL="$(command -v yosys)"
YOSYS_VERSION="$("${YOSYS_TOOL}" -V | head -n 1)"
cd "${REPO_ROOT}"

printf 'FORMAL_TOOL tool=yosys version=%q\n' "${YOSYS_VERSION}" > "${LOG}"

for source in \
    engrenring/rtl/source/stream_ghash/ghash16.v \
    verification/formal/ghash_shift_formal.sv \
    verification/formal/ghash_shift_yosys.ys \
    engrenring/rtl/source/aes_core/sbox.v \
    verification/formal/aes_sbox_formal.sv \
    verification/formal/aes_sbox_yosys.ys
do
    printf 'FORMAL_INPUT sha256=%s path=%s\n' \
        "$(sha256sum "${source}" | cut -d ' ' -f 1)" "${source}" >> "${LOG}"
done

run_proof() {
    local name="$1"
    local expected_assertions="$2"
    local script="$3"
    local proof_log="${RESULT_ROOT}/${SUITE}/${name}.log"
    local imported_assertions
    local successes

    if ! "${YOSYS_TOOL}" -Q -s "${script}" > "${proof_log}" 2>&1; then
        printf 'FORMAL_PROOF name=%s status=FAIL reason=yosys_exit_nonzero log=%s\n' \
            "${name}" "${proof_log}" | tee -a "${LOG}"
        tail -n 40 "${proof_log}"
        return 1
    fi

    imported_assertions="$(grep -c 'Import proof for assert:' "${proof_log}" || true)"
    successes="$(grep -c 'SAT proof finished - no model found: SUCCESS!' "${proof_log}" || true)"
    if [[ "${imported_assertions}" != "${expected_assertions}" || "${successes}" != "1" ]]; then
        printf 'FORMAL_PROOF name=%s status=FAIL reason=evidence_mismatch expected_assertions=%s imported_assertions=%s success_markers=%s log=%s\n' \
            "${name}" "${expected_assertions}" "${imported_assertions}" \
            "${successes}" "${proof_log}" | tee -a "${LOG}"
        return 1
    fi

    printf 'FORMAL_PROOF name=%s status=PASS assertions=%s engine=yosys_sat assumptions=0 log=%s\n' \
        "${name}" "${imported_assertions}" "${proof_log}" | tee -a "${LOG}"
}

run_proof ghash_shift_power 17 verification/formal/ghash_shift_yosys.ys
run_proof aes_sbox_algebraic 2 verification/formal/aes_sbox_yosys.ys

printf 'FORMAL_SUBSET status=PASS proofs=2 assertions=19 scope=combinational closure_claimed=NO\n' | tee -a "${LOG}"
print_summary "${SUITE}" "PARTIAL_PASS" \
    "proofs=2" "assertions=19" "scope=combinational" \
    "closure_claimed=NO" "log=${LOG}"
