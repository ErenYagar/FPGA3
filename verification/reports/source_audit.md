# FPGA3 AES-GCM source and build audit

Audit date: 2026-08-22 (Asia/Taipei)

## Repository identity

- Remote: `https://github.com/ErenYagar/FPGA3.git`
- Audit branch: `verify/sva-uvm-board`
- Starting commit: `4a215983f3774c49e833cfe3715a019748200c73`
- Starting status: two pre-existing untracked report-support Tcl files:
  `tcl/report_round55_artifact_data.tcl` and
  `tcl/round55_rebuild_board_synth.tcl`.
- Exact-current build/verification base:
  `ece78ce9677872d0d20da3b785ab83a48b6a8492`.
- Cryptographic datapath content:
  `a6f19472ecc619925b373b1db801911c54062a90`.
- Source/verification promotion commit:
  `4246ebc7a72ce8eb1a49d56969aae6e151578c11`.
- The current candidate also includes SHA-256-identified working-tree board
  implementation evidence tied to immutable checkpoints and hardware
  artifacts. Exact commit and artifact identity is recorded in
  `verification/results/exact_current_manifest.json`.
- Target part: `xc7a100tcsg324-1`.
- Cryptographic datapath behavior changed during this audit: **no**. One
  declaration was moved ahead of its primitive consumers in
  `aes_gcm_stream_core.v` so ModelSim can elaborate the same RTL; no AES/GHASH
  expression, priority, state, or register behavior changed.
- Board-only CDC handling changed: the raw `rst_btn`/MMCM-lock run request now
  feeds a two-stage `ASYNC_REG` synchronizer followed by a separate four-stage
  stable-high release qualifier, and `uart_rx` marks its two-stage synchronizer
  `ASYNC_REG`. The split structure rejects a one-sample run-request pulse;
  continuous-high release now takes six sampled core edges, while retaining
  the old requirement for at least four consecutive raw high samples. Reset
  assertion is delayed by two additional core cycles (about 11.4 ns at
  175 MHz). This changes board reset latency, not AES/GHASH computation or
  protocol priority.

## Installed tools

| Capability | Result | Version / path |
|---|---|---|
| Vivado | installed | Vivado 2021.1, SW build 3247384, IP build 3246043 |
| XSim | installed and used | `C:/Xilinx/Vivado/2021.1/bin/xsim.bat`, Vivado Simulator 2021.1; constrained-random UVM 1.2 regression and functional coverage |
| ModelSim | installed | ModelSim ALTERA STARTER EDITION 10.5b, `C:/intelFPGA_lite/17.0/modelsim_ase/win32aloem/vsim.exe` |
| Yosys | installed in WSL and used | Yosys 0.33, built-in SAT; assumption-free GHASH shift and AES S-box combinational subset |
| Questa | not found | no `questa` command; installed `vsim` identifies itself as ModelSim ASE, not Questa |
| VCS | not found | no `vcs` command |
| Jasper / `jg` | not found | no `jg`, `jasper`, or `jaspergold` command |
| Questa Formal / OneSpin | not found | no `qverify` or `onespin` command |
| Icarus / Verilator | not found | no `iverilog` or `verilator` command |

The absent commercial tools must not be claimed. The installed Yosys subset
proved 19 combinational assertions with zero failures; full sequential formal
closure is not claimed.

## Executive finding

There are two distinct build families:

1. **Legacy `top` / `AESGCM_IO/GHASH.v` family.** The retained
   `engrenring/synth_1g/run_synth.tcl` names legacy source files and elaborates
   `top`. The named legacy production RTL is absent from the current working
   tree, so this flow is stale and cannot verify the production streaming
   design. Obsolete 200 MHz 3/4-lane runners were removed after the audit.
2. **Current streaming family.** The maintained flows elaborate
   `aes_gcm_axi_top` (or a board wrapper above it), compile
   `stream_ghash/ghash16.v`, and include the `stream_aes`, `stream_axi`, and
   `stream_core` sources. This is the production path.

The audit therefore must not invoke `engrenring/synth_1g/run_synth.tcl` as the
current build. The maintained verification build uses the current streaming
source list and the production 175 MHz constraint. Historical analysis remains
available, while obsolete broken 200 MHz lane runners were removed.

## Exact-current 175 MHz evidence

The current full-board candidate is the fresh
`ece78ce_uart_rsp_175_resetqual4_final_v8` routed DCP plus the
hash-verified `ece78ce_uart_rsp_175_resetqual4_audit_v8c` strict audit. Board
programming and vectors used the v8a payload, whose `.bin` is byte-identical
to v8c. The exact execution inputs are:

| Input | SHA-256 |
|---|---|
| `arty_a7_100t_aes_gcm_uart_rsp_top.v` | `FA6E19757BABC3D6FA66879C45A99320ECC4CB2C6861A6C2523E8E5E577389C5` |
| `uart_rx.v` | `3DC746D15DBEB4D68FD475E99E9B772466D20F5FC6A76DF5D160B9271A942EDF` |
| `arty_a7_100t_aes_gcm_uart_rsp.xdc` | `7EF65C0482EF5111355AB1D7190C00DFAA37CA988A1678279762EFD19DFA40AE` |
| Immutable `verification/board/provenance/run_arty_a7_100t_uart_rsp_v8_execution.tcl` used for v8 DCP | `02DD9892D48F8FCFB16A1C4BD88FF43882C5F52CE1890108F522CD965BCECA0A` |
| Current `run_arty_a7_100t_uart_rsp.tcl` after object-list gate repair | `C8CEE93D3D93223926B000A521EF82E413B0855A68FB46B3B9EB23C1F811E18A` |
| `audit_routed_board.tcl` (final v8c) | `62C653E5E49723A51726B92B0D475BA11C55F24A3648D59359A2ABCE99C9286E` |

The first build Tcl hash is captured from the v8 implementation execution.
The current script repairs Tcl object-list canonicalization in post-route
reset/I/O gates and emits a strict-audit-required promotion marker; that later
repair does not retroactively identify the routed DCP. The audit Tcl hash
identifies the final v8c strict audit.

The v8 fresh flow completed synthesis, placement, routing, post-route physical
optimization, and reports. Its final routed setup is WNS `+0.029 ns`, TNS/FEP
`0/0`; final hold is WHS `+0.044 ns`, THS/FEP `0/0`; pulse width is WPWS
`+1.607 ns`, TPWS/FEP `0/0`. All `17,758` routable nets are fully routed,
route errors and unrouted nets are zero, and DRC and methodology
Error/Critical Warning counts are `0/0`. The methodology report has two
ordinary `SYNTH-6 Warning` entries, so the result is not described as
warning-free.

The v8 wrapper stopped after report generation because Tcl compared identical
endpoint lists through different internal string/list representations. It did
not generate a bitstream. v8a verified the immutable routed DCP SHA-256
`A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B`,
and generated the hardware-tested bitstream SHA-256
`22791C17939C1BBC43539C35ABB19C31896425D26AA4721D5E4D4D3ACC5A686E`.
A v8b strict-audit attempt stopped because its Tcl gate misclassified the
hierarchical UART CE tie to VCC; this was an audit-script string-handling
failure, not a DCP fault. v8c corrected the gate and passed strict audit on the
same routed DCP. Its signoff-metrics and bitstream SHA-256 values are
`CBC7D4F16D9D54A67CC6B10E4A9DC612888112933D6263F3F2D69932FB0946CB`
and `DC951AAE0D388DA54836AD5950CA87CB8EEE4A94E5E7EFBB1A685439F0934942`.
The v8a and v8c `.bin` SHA-256 is identically
`8A19D8E5900063B64922DC9B9AD323F953386367CA1D4FA1A61935543B4332F3`;
their `.bit` file hashes differ, so the container files are not claimed
identical. This records wrapper/audit defects without rewriting them as DCP
faults or unqualified successful runs.

The routed CDC schema contains exactly two top-level CDC-3 Info
synchronizers, for the reset request and UART RX, and zero unsafe categories.
MMCM `LOCKED` is not independently covered by `report_cdc`; an exact-fanout
structural gate covers its permitted use. `check_timing` has ten zero critical
categories plus exact false-path allowlists of two inputs and five outputs.
The logical final reset-release stage is physically replicated into four FFs
in `SLICE_X49Y132`; their endpoint sum/union is `13,162/13,161`, with one
recorded reconvergence at `u_aes_gcm/u_core/gh_ctrl_valid_reg/D`.

Exact-current verification status at the time of this audit is:

- XSim UVM 1.2: PASS for seeds `175001`, `175019`, and `175039`; 24
  scoreboard records checked, zero failed, UVM error/fatal `0/0`, and 100% of
  the maintained required functional bins per seed. Code, assertion, and
  exhaustive protocol coverage are not claimed. Latest evidence is
  `verification/results/uvm/xsim_20260823_004035/`; runner, 15-input compile
  manifest, JSON, CSV, and aggregate-log SHA-256 values are respectively
  `835A229F948EFE26C8909D10C2D3DA0A2343E829BB95F7D202FD3D3CE8D03A56`,
  `D36DA381A5326EEBB1DABDA4AD63D45421ACE5E433CE38A3EF80494002233292`,
  `F5B8E59504D967B6841AD73E0B6E3D8361162E251CF7FED2F303682C8B8500AF`,
  `F46216BF196C08ED466200EE34E3F2A7B626EB376E7C0F8A758DCB47B3225641`,
  and `6AC1D83E3C90615448F6391350707963D544F4D42CB7FC6205A7A0C3B7189EC5`.
- ModelSim Starter deterministic UVM 1.2 smoke: PASS with scoreboard `1/0`
  and UVM error/fatal `0/0`. Latest evidence is
  `verification/results/uvm/modelsim_20260823_004145/`; aggregate-log SHA-256
  is `01EF5B244A0C6C8FA8FD812E7C7F7437E3EE017CEF67D43EF5A46E783404D0DE`.
  Constrained randomization is NOT_RUN and functional coverage is
  NOT_COLLECTED under the Starter license.
- Yosys 0.33 formal subset: PARTIAL PASS; 17 GHASH shift assertions and two
  AES S-box algebraic assertions, zero assumptions and failures. Sequential
  and whole-design formal closure are not claimed. The stable run log remains
  SHA-256 `C1FB4DA19869532E1831069A635BF71F7C6714237DD5C08C7EDF6A16CCBC0C96`.
- Directed XSim reset qualification: PASS; 1-, 2-, and 3-sample button and
  MMCM-lock pulses plus alternating chatter are rejected, continuous-valid
  release takes six sampled edges, and invalid-request assertion takes three.
  Latest evidence is
  `verification/results/board/reset_xsim_20260823_004201/`; run/simulation log
  SHA-256 values are
  `D01050A0A6592BB549F1978A123B4C669A326A9AE6F882B57FEE989E7B3C1879`
  and `78106EEE91399C6849721C53949B3DBA7D9D1ED1A3F0831A080C87E90A5F0A68`.
- Integrated stable replay: PARTIAL_PASS with five PASS, one PARTIAL_PASS,
  zero NOT_RUN, zero failed, and six total suites. The sole partial suite is
  the combinational formal subset above. Integrated-log SHA-256 is
  `14F4244DE577CF1B1D80B7B2A9FBE1E6B33A07AF5629341A7F523DFA3DB8D7CA`.
  Its simulated NIST suite passes `47,250/0` in `17,740,527` cycles; log
  SHA-256 is
  `5EDC8CEE2AFF8D05D6538B8CFE911D8B775FFECED758FCBFD36786D9045BBCE3`.
- Hardware Manager programming: PASS on `Digilent/210319BE76DEA` /
  `xc7a100t_0`; AES-128/192/256 encrypt/decrypt smoke is `6/0` on COM4. The
  program log does not establish EOS/DONE/CRC/PLL readback, so the host-side
  bitstream hash is provenance rather than readback attestation.
- Full exact-v8a hardware NIST: PASS, 47,250/47,250, zero failures, first
  failure `null`, elapsed 1,208.505 seconds on COM4. Independent JSONL
  reconciliation found 47,250 rows with unique contiguous indices 0--47,249,
  7,875 rows from each of six sources, 23,625 encrypt and 23,625 decrypt
  cases, including 11,908 expected authentication failures, and zero
  status/data/tag violations. A second independent reconciliation also
  passed. JSONL/summary/run-log SHA-256 values are respectively
  `56DA5E1B7110AE8A5622B5847211A842C4D2A2A22A08EE02AA7D32EFB0C59761`,
  `5DF2EA729BBD0C19C6677AFD13F73DD4F04BB53694B9552A3FF4D9D464604D06`,
  and `B861E8500B214CB85A98A1FDC231C3E097DDA60F237EA3A49021E6BCECEFEEB4`.

Utilization is 12,411 LUTs (11,333 logic plus 1,078 LUTRAM), 9,029 FFs,
10 RAMB18, and zero DSPs. Vectorless power is estimated at 0.461 W total
(0.363 W dynamic, 0.099 W static), Medium confidence. It is not measured board
power; incomplete I/O activity and high inferred reset activity limit the
estimate.

The retained failure chain remains part of the audit record: `strict_v3`
failed CDC gates; `cdc_final_v5` passed timing and 47,250/0 hardware vectors
but had the one-sample delayed-release flaw; `resetqual_final_v6` used only a
two-stage qualifier and did not complete full hardware NIST;
`resetqual4_final_v7` stopped on an `ASYNC_REG` boolean-representation gate;
fresh `resetqual4_final_v8` stopped on the endpoint-list Tcl gate; and
`resetqual4_audit_v8b` stopped on the UART CE VCC string-handling gate before
v8c passed the corrected strict audit on the same routed DCP SHA-256.

## Complete RTL inventory

Thirty-two Verilog/SystemVerilog files were present at the starting commit.

### Current production RTL

- `engrenring/rtl/source/aes_core/sbox.v`
- `engrenring/rtl/source/aes_gcm_axi_top.v`
- `engrenring/rtl/source/stream_aes/aes_block_engine.v`
- `engrenring/rtl/source/stream_aes/aes_first_block_engine.v`
- `engrenring/rtl/source/stream_aes/aes_key_context.v`
- `engrenring/rtl/source/stream_axi/axi_lite_regs.v`
- `engrenring/rtl/source/stream_axi/axis_output_skid_8.v`
- `engrenring/rtl/source/stream_core/aes_gcm_stream_core.v`
- `engrenring/rtl/source/stream_core/stream_fifo.v`
- `engrenring/rtl/source/stream_ghash/ghash16.v`

### Current board RTL

- `engrenring/rtl/source/board/aes_gcm_board_selftest.v`
- `engrenring/rtl/source/board/aes_gcm_uart_rsp_bridge.v`
- `engrenring/rtl/source/board/arty_a7_100t_aes_gcm_selftest_top.v`
- `engrenring/rtl/source/board/arty_a7_100t_aes_gcm_uart_rsp_top.v`
- `engrenring/rtl/source/board/uart_rx.v`
- `engrenring/rtl/source/board/uart_tx.v`

### Current testbench RTL

- `engrenring/rtl/source/stream_ghash/tb_ghash16.sv`
- `engrenring/rtl/functional test/sv/tb_aes_gcm_uart_rsp.sv`
- `engrenring/rtl/functional test/sv/tb_arty_a7_100t_aes_gcm_selftest.sv`
- `engrenring/rtl/functional test/sv/tb_axi_smoke.sv`
- `engrenring/rtl/functional test/sv/tb_nist.sv`
- `engrenring/rtl/functional test/sv/tb_round48_boundary_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round49_residual_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round53_core_zeroize_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round53_key_midzeroize_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round53_non96_ghash_zeroize_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round53_zeroize_public_directed.sv`
- `engrenring/rtl/functional test/sv/tb_round54_fifo_clear_directed.sv`
- `engrenring/rtl/functional test/sv/tb_throughput.sv`
- `engrenring/rtl/functional test/sv/tb_throughput_profile.sv`

### Legacy testbenches with missing production dependencies

- `engrenring/sim/tb_top.sv` elaborates legacy `top`.
- `engrenring/sim/tb_top_1g_parallel.sv` elaborates legacy `top`.

The legacy modules named by their synthesis scripts (`aes_core/AES_e.v`,
`ctr/aes_ctr_wrapper.v`, `AESGCM_IO/IV_IN.v`, `AESGCM_IO/AAD_CT_IN.v`,
`AESGCM_IO/GHASH.v`, `aes_gcm_lane.v`, and `top.v`) are not present.

## GHASH and streaming reference audit

### Files that reference legacy `GHASH.v`

The retained stale `engrenring/synth_1g/run_synth.tcl` uses top `top`.
The starting commit also contained broken 3/4-lane legacy runners; they and
their obsolete 200 MHz constraint were removed from the maintained tree.

No current RTL file defining legacy `GHASH` was found.

### Compile/build files that reference `ghash16.v`

- `tcl/round54_run.tcl`
- `verification/vivado/run_streaming_175mhz.tcl`
- `tcl/round54_regressions.ps1`
- `engrenring/synth_1g/axi_ooc/run_axi_ooc.tcl`
- `engrenring/synth_1g/board/run_arty_a7_100t_selftest.tcl`
- `engrenring/synth_1g/board/run_arty_a7_100t_uart_rsp.tcl`

`run_arty_a7_100t_uart_rsp_from_synth.tcl` does not read RTL; it opens a
hash-verified streaming synth DCP.

### RTL and testbench references to `aes_gcm_stream_core`

- Definition: `engrenring/rtl/source/stream_core/aes_gcm_stream_core.v`.
- Production instantiation: `engrenring/rtl/source/aes_gcm_axi_top.v`.
- Direct integration tests:
  `tb_round53_core_zeroize_directed.sv` and
  `tb_round53_non96_ghash_zeroize_directed.sv`.
- Compile/source-list owners:
  `tcl/round54_run.tcl` and
  `tcl/round54_regressions.ps1`.

### RTL and testbench references to `aes_gcm_axi_top`

- Definition: `engrenring/rtl/source/aes_gcm_axi_top.v`.
- Direct testbench instantiations:
  `tb_axi_smoke.sv`, `tb_nist.sv`, `tb_throughput.sv`,
  `tb_round48_boundary_directed.sv`, `tb_round49_residual_directed.sv`,
  `tb_round53_zeroize_public_directed.sv`,
  `tb_arty_a7_100t_aes_gcm_selftest.sv`, and
  `tb_aes_gcm_uart_rsp.sv`.
- Board wrapper instantiations:
  `arty_a7_100t_aes_gcm_selftest_top.v` and
  `arty_a7_100t_aes_gcm_uart_rsp_top.v`.
- Source/build owners:
  `tcl/round54_run.tcl`,
  `tcl/round54_regressions.ps1`,
  `engrenring/synth_1g/axi_ooc/run_axi_ooc.tcl`, and the board build Tcl
  files listed above.
- DCP-only audit/query consumers:
  `report_synth_targets.tcl`, `partpin_ooc.tcl`,
  `run_axi_ooc_signoff.ps1`, `run_partpin_discovery_candidate.tcl`,
  and `run_partpin_replay.tcl` under `engrenring/synth_1g/axi_ooc`.

No `.f`, `.flist`, `.prj`, or ModelSim `.do` filelist was present.

## Exact top and source path by existing flow

| Existing flow | Top / elaborated snapshot | GHASH selected | Classification |
|---|---|---|---|
| `synth_1g/run_synth.tcl` | `top` | missing `AESGCM_IO/GHASH.v` | legacy, broken |
| `sim/tb_top.sv` | `tb_top` -> `top` | inherited legacy top | legacy, broken |
| `sim/tb_top_1g_parallel.sv` | `tb_top_1g_parallel` -> `top` | inherited legacy top | legacy, broken |
| `axi_ooc/run_axi_ooc.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | current streaming, 175 MHz |
| `verification/vivado/run_streaming_175mhz.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | maintained strict 175 MHz verification flow |
| `tcl/round54_run.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | retained experiment driver, locked to 175 MHz |
| `round54_regressions.ps1` | individual `tb_*` tops | `stream_ghash/ghash16.v` | current streaming simulation |
| `board/run_arty_a7_100t_selftest.tcl` | `arty_a7_100t_aes_gcm_selftest_top` | `stream_ghash/ghash16.v` | current streaming board |
| `board/run_arty_a7_100t_uart_rsp.tcl` | `arty_a7_100t_aes_gcm_uart_rsp_top` | `stream_ghash/ghash16.v` | current streaming board |
| `board/run_arty_a7_100t_uart_rsp_from_synth.tcl` | opens verified synth DCP of UART wrapper | inherited `ghash16` netlist | current streaming board resume |

The production streaming compile order used by the existing regression is:

1. `aes_core/sbox.v`
2. `stream_aes/aes_block_engine.v`
3. `stream_aes/aes_first_block_engine.v`
4. `stream_aes/aes_key_context.v`
5. `stream_ghash/ghash16.v`
6. `stream_axi/axi_lite_regs.v`
7. `stream_axi/axis_output_skid_8.v`
8. `stream_core/stream_fifo.v`
9. `stream_core/aes_gcm_stream_core.v`
10. `aes_gcm_axi_top.v`

## Baseline mapping

| Requested baseline | Simulation top | Required design |
|---|---|---|
| `stream_ghash/tb_ghash16.sv` | `tb_ghash16` | `ghash16.v` |
| `functional test/sv/tb_axi_smoke.sv` | `tb_axi_smoke` | complete production streaming list |
| `functional test/sv/tb_nist.sv` | `tb_nist` | complete production streaming list plus six `.rsp` files |
| `functional test/sv/tb_throughput.sv` | `tb_throughput` | complete production streaming list |

Baseline executions and exact commands are recorded separately under
`verification/results/baseline/`; current aggregate results and exact-current
candidate identity are recorded in `verification/results/verification_summary.md`
and `verification/results/exact_current_manifest.json`.
