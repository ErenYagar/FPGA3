# AES-GCM verification status

## Current conclusion

The 175 MHz exact-source candidate passes final v8c strict static signoff,
exact-current XSim UVM, the available assumption-free combinational formal
subset, directed reset qualification, Hardware Manager programming, and six
board smoke modes. The exact-v8a full hardware NIST run also passes all 47,250
vectors with zero failures and passed a second independent evidence
reconciliation. The v8c `.bin` configuration payload is byte-identical to the
hardware-tested v8a `.bin`. Source and verification are committed at
`4246ebc7a72ce8eb1a49d56969aae6e151578c11`.

- Verification/build base:
  `ece78ce9677872d0d20da3b785ab83a48b6a8492`
- Source/verification promotion commit:
  `4246ebc7a72ce8eb1a49d56969aae6e151578c11`
- Cryptographic datapath content:
  `a6f19472ecc619925b373b1db801911c54062a90`
- Production simulation/standalone top: `aes_gcm_axi_top`
- Full-board top: `arty_a7_100t_aes_gcm_uart_rsp_top`
- Production GHASH: `engrenring/rtl/source/stream_ghash/ghash16.v`
- Legacy `engrenring/rtl/source/AESGCM_IO/GHASH.v`: excluded
- Target: 175 MHz (`5.714 ns`) on `xc7a100tcsg324-1`
- 200 MHz: out of scope and not run
- Machine-readable evidence index:
  `verification/results/exact_current_manifest.json`

The immutable implementation candidate was built from the listed base plus
the exact execution-input hashes in the manifest. Current source and
verification identity is the promotion commit above.

## Verification matrix

| Verification item | Status | Evidence |
|---|---:|---|
| GHASH baseline | PASS | 66 tests; digit latency 8; external II 9 |
| AXI smoke baseline | PASS | 7,676 cycles |
| Six-mode simulated throughput at 175 MHz | PASS | 1.051705--1.065398 Gbit/s |
| Promoted non-D directed regression | PASS | 8/8 applicable Round48/49/53 and FIFO clear/refill tests |
| Limited simulated NIST signatures | PASS | 525/0 at 145,808 cycles; 5,255/0 at 1,594,798 cycles |
| Full simulated NIST RSP | PASS | 47,250/0; 17,740,527 cycles; log `5EDC8CEE...BBCE3` |
| SVA smoke | PASS | 37 properties; 0 assertion failures |
| Independent reference model | PASS | FIPS-197 AES and SP 800-38D GCM |
| ModelSim UVM 1.2 deterministic smoke | PASS | latest `modelsim_20260823_004145`; one fixed AES-128 record; scoreboard 1/0; UVM error/fatal 0/0 |
| Exact-current XSim UVM 1.2 | PASS | latest `xsim_20260823_004035`; 15 hashed compile inputs; 3/3 seeds; scoreboard records 24/0; maintained functional coverage 100% per seed |
| Exact-current Yosys formal subset | PARTIAL PASS | 19 assumption-free combinational assertions; 0 failures; no sequential/whole-design closure claim |
| Exact-current board reset XSim | PASS | 1/2/3-sample button and LOCKED pulses plus chatter rejected; release/assertion edges 6/3 |
| Standalone 175 MHz internal implementation | PASS | setup WNS +0.056 ns; internal WHS +0.053 ns; TNS/THS/FEP 0 |
| Exact-current full-board v8/v8c implementation | PASS | setup WNS +0.029 ns; hold WHS +0.044 ns; pulse WPWS +1.607 ns; TNS/THS/TPWS/FEP 0; 17,758/17,758 routed |
| Full-board legality/security gates | PASS | route errors 0; DRC and methodology E/CW 0/0; expected CDC schema; unsafe CDC categories 0 |
| Exact-v8a board program and six-mode smoke | PASS | COM4; bit `22791C17...A686E`; AES-128/192/256 encrypt/decrypt 6/0 |
| Exact-v8a full hardware NIST | PASS | 47,250/47,250; 0 fail; first failure `null`; 1,208.505 s on COM4; second independent reconciliation PASS |
| Integrated stable `run_all` | PARTIAL PASS | 5 PASS, 1 PARTIAL_PASS, 0 NOT_RUN, 0 failed, 6 total; the sole partial suite is the combinational formal subset |
| Standalone OOC PartPin replay | NO / NOT RUN | no approved identity-matched map and exact parent timing model |

The 175 MHz simulated throughput measurements are 16,820 cycles /
1.065398 Gbit/s for each encrypt record and 17,039 cycles /
1.051705 Gbit/s for each decrypt record. They are simulation test-level
measurements, not board throughput measurements.

## Exact-current UVM evidence

The maintained XSim UVM 1.2 regression passed seeds `175001`, `175019`, and
`175039`. Each seed checked eight records, for 24 checked and zero failed;
each ended with zero UVM errors and fatals and 100% of the maintained required
functional bins.

- Evidence directory:
  `verification/results/uvm/xsim_20260823_004035/`
- Compile-input manifest: 15 inputs; SHA-256
  `D36DA381A5326EEBB1DABDA4AD63D45421ACE5E433CE38A3EF80494002233292`
- Summary JSON SHA-256:
  `F5B8E59504D967B6841AD73E0B6E3D8361162E251CF7FED2F303682C8B8500AF`
- Summary CSV SHA-256:
  `F46216BF196C08ED466200EE34E3F2A7B626EB376E7C0F8A758DCB47B3225641`
- Aggregate run-log SHA-256:
  `6AC1D83E3C90615448F6391350707963D544F4D42CB7FC6205A7A0C3B7189EC5`
- Runner SHA-256:
  `835A229F948EFE26C8909D10C2D3DA0A2343E829BB95F7D202FD3D3CE8D03A56`

This 100% is functional coverage of the maintained scenario bins. It is not
code coverage, assertion coverage, or exhaustive protocol coverage. Random
output backpressure, ZEROIZE phase injection, queue saturation, and TLAST
fault injection are not included in this regression.

The latest ModelSim Starter deterministic UVM 1.2 smoke is under
`verification/results/uvm/modelsim_20260823_004145/`. It passes one fixed
AES-128 record with scoreboard 1/0 and UVM error/fatal 0/0. Its aggregate log
SHA-256 is
`01EF5B244A0C6C8FA8FD812E7C7F7437E3EE017CEF67D43EF5A46E783404D0DE`.
ModelSim Starter constrained randomization is NOT_RUN and functional coverage
is NOT_COLLECTED because of the Starter license; those capabilities are not
inferred from the deterministic smoke.

## Exact-current formal evidence

Yosys 0.33 (git SHA1 `2584903a060`) proved 17 GHASH shift-power assertions
and two AES S-box algebraic assertions with zero assumptions and zero failures.

- Runner SHA-256:
  `DFE86E69B3213764B6FFFB903C5653F6B6DF282FEC96295ED36FEE2B8371B0F8`
- Run-log SHA-256:
  `C1FB4DA19869532E1831069A635BF71F7C6714237DD5C08C7EDF6A16CCBC0C96`

This is a partial combinational proof only. It does not prove sequential
GHASH/control behavior, FIFO/ZEROIZE behavior, whole AES-GCM equivalence,
liveness, CDC, timing, power, or side-channel properties.

## Exact-current reset and CDC evidence

The board run request now uses two `ASYNC_REG` synchronizer stages followed
by four stable-high qualifier stages. The directed XSim test passed rejection
of 1-, 2-, and 3-sample button and MMCM-`LOCKED` pulses, alternating chatter,
six-edge continuous-valid release, and three-edge invalid-request assertion.

- Evidence directory:
  `verification/results/board/reset_xsim_20260823_004201/`
- Testbench SHA-256:
  `77EE92995E9CB3E1A8F6C23FBC41C5C9FAE6B1B7860200095CEE8CCF02D47841`
- Runner SHA-256:
  `A6D51C91669C94066F0BC600AE616136BA86EBE41691DE9EDB4F467CE7ABFD35`
- Run-log SHA-256:
  `D01050A0A6592BB549F1978A123B4C669A326A9AE6F882B57FEE989E7B3C1879`
- Simulation-log SHA-256:
  `78106EEE91399C6849721C53949B3DBA7D9D1ED1A3F0831A080C87E90A5F0A68`

The routed CDC report has exactly two top-level CDC-3 Info synchronizers: reset
request and UART RX. Unsafe categories are zero. MMCM `LOCKED` is outside
`report_cdc` coverage and is instead protected by a structural exact-fanout
gate. Raw asynchronous port paths are false-pathed; downstream FF-to-FF stages
remain timed.

## Exact-current implementation and hardware evidence

Fresh v8 generated the synth, placed, and final routed DCPs. Its wrapper then
stopped after reports on a Tcl list/string internal-representation comparison,
so v8 generated no bitstream. v8a verified the exact routed-DCP SHA-256
`A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`
and generated the hardware-tested payload. A v8b strict-audit attempt then
stopped because its Tcl gate misclassified the hierarchical UART CE tie to
VCC; this was an audit-script string-handling failure, not a DCP fault. v8c
corrected that gate and passed strict audit on the same routed DCP. Its audit
script SHA-256 is
`62C653E5E49723A51726B92B0D475BA11C55F24A3648D59359A2ABCE99C9286E`.
The current fresh-build driver SHA-256 is
`C8CEE93D3D93223926B000A521EF82E413B0855A68FB46B3B9EB23C1F811E18A`;
it fixes Tcl object canonicalization and emits a strict-audit-required marker.
It was not used to generate the immutable v8 DCP.

The final routed result has setup WNS +0.029 ns, hold WHS +0.044 ns, and pulse
WPWS +1.607 ns with zero TNS, THS, TPWS, and failing endpoints. All 17,758
routable nets are fully routed. Route errors and unrouted nets are zero. DRC
and methodology
Error/Critical Warning are 0/0. Two ordinary `SYNTH-6 Warning` messages remain
and are not hidden. `check_timing` has ten zero critical categories plus
exact false-path input/output allowlists of 2/5.

The final v8c signoff-metrics SHA-256 is
`CBC7D4F16D9D54A67CC6B10E4A9DC612888112933D6263F3F2D69932FB0946CB`.
Its `.bit` SHA-256 is
`DC951AAE0D388DA54836AD5950CA87CB8EEE4A94E5E7EFBB1A685439F0934942`
and its `.bin` SHA-256 is
`8A19D8E5900063B64922DC9B9AD323F953386367CA1D4FA1A61935543B4332F3`.
The hardware-tested v8a `.bin` has the exact same SHA-256. The v8a and v8c
`.bit` hashes differ, so the `.bit` container files are not claimed identical.

The full board uses 12,411 LUTs (11,333 logic and 1,078 LUTRAM), 9,029 FFs,
10 RAMB18, and no DSPs. Vectorless power is estimated at 0.461 W total
(0.363 W dynamic, 0.099 W static), Medium confidence. This is not a board
measurement and the estimate has incomplete I/O activity plus a high-reset-
activity warning.

Hardware Manager reported programming PASS for
`Digilent/210319BE76DEA` / `xc7a100t_0`. The host-side bitstream SHA-256 is
`22791C17939C1BBC43539C35ABB19C31896425D26AA4721D5E4D4D3ACC5A686E`.
AES-128/192/256 encrypt and decrypt smoke completed 6/0. The aggregate smoke
log SHA-256 is
`519C9820BED299203A8C04380E159A4F7A256098A028D112E215822324194CD1`.

The program log does not provide independent EOS/DONE/CRC/PLL readback, so the
host bit hash is artifact provenance rather than FPGA readback attestation.

The exact-v8a full hardware NIST run completed 47,250/47,250 with zero
failures, first failure `null`, in 1,208.505 seconds on COM4. Independent JSONL
reconciliation found exactly 47,250 rows, unique contiguous global indices
0--47,249, and 7,875 rows from each of the six RSP sources. The classes are
23,625 encrypt and 23,625 decrypt; decrypt contains 11,717 successful cases
and 11,908 expected authentication failures. Status, data, and tag violations
are `0 / 0 / 0`, and a second independent reconciliation also passed.

- JSONL SHA-256:
  `56DA5E1B7110AE8A5622B5847211A842C4D2A2A22A08EE02AA7D32EFB0C59761`
- Summary SHA-256:
  `5DF2EA729BBD0C19C6677AFD13F73DD4F04BB53694B9552A3FF4D9D464604D06`
- Run-log SHA-256:
  `B861E8500B214CB85A98A1FDC231C3E097DDA60F237EA3A49021E6BCECEFEEB4`

## Integrated post-commit replay

At promotion commit `4246ebc7a72ce8eb1a49d56969aae6e151578c11`, the stable
`verification/scripts/run_all.sh` result is **PARTIAL_PASS**: five suites PASS,
one is PARTIAL_PASS, zero are NOT_RUN, and zero fail, for six total. The only
partial suite is formal: Yosys proves the 19-assertion assumption-free
combinational subset, while sequential and whole-design formal closure remain
unclaimed. The integrated run log SHA-256 is
`14F4244DE577CF1B1D80B7B2A9FBE1E6B33A07AF5629341A7F523DFA3DB8D7CA`.

The replayed simulated NIST suite passes 47,250/47,250 with zero failures in
17,740,527 cycles. Its log SHA-256 is
`5EDC8CEE2AFF8D05D6538B8CFE911D8B775FFECED758FCBFD36786D9045BBCE3`.
The integrated PARTIAL_PASS status therefore records formal scope, not a test
failure or a NOT_RUN suite.

## Retained failure history and open limits

- `strict_v3`: rejected for 5 CDC Critical and 3 CDC Warning paths.
- `cdc_final_v5`: timing and 47,250/0 board vectors passed, but a pure
  four-FF shift had a one-sample delayed-release flaw.
- `resetqual_final_v6`: only a two-stage qualifier, weakening the intended
  four-sample threshold; full hardware NIST did not complete.
- `resetqual4_final_v7`: correct 2+4 structure and routed timing passed, but
  an `ASYNC_REG` boolean-representation gate stopped before bit generation.
- `resetqual4_final_v8`: fresh routed design passed, but a Tcl exact-list
  comparison stopped the wrapper after reports; hash-verified v8a produced the
  hardware-tested payload.
- `resetqual4_audit_v8b`: its Tcl gate misclassified the hierarchical UART CE
  VCC tie; this was not a routed-DCP fault. v8c corrected the gate and passed
  strict audit on the same routed DCP SHA-256.

Open limits are an approved identity-matched PartPin map for standalone OOC
reuse, sequential/whole-design formal closure, code and UVM assertion
coverage, and the unimplemented randomized UVM scenarios listed above.

Reusable sources are under `verification/sva/`, `verification/uvm/`,
`verification/formal/`, `verification/board/`, `verification/vivado/`,
and `verification/scripts/`. The tracked machine-readable manifest and
compact summaries live under `verification/results/`; large raw work
products remain local.
