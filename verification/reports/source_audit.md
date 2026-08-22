# FPGA3 AES-GCM source and build audit

Audit date: 2026-08-22 (Asia/Taipei)

## Repository identity

- Remote: `https://github.com/ErenYagar/FPGA3.git`
- Audit branch: `verify/sva-uvm-board`
- Starting commit: `4a215983f3774c49e833cfe3715a019748200c73`
- Starting status: two pre-existing untracked report-support Tcl files:
  `tcl/report_round55_artifact_data.tcl` and
  `tcl/round55_rebuild_board_synth.tcl`.
- Target part: `xc7a100tcsg324-1`.
- Cryptographic behavior changed during this audit: **no**. One declaration
  was moved ahead of its primitive consumers in `aes_gcm_stream_core.v` so
  ModelSim can elaborate the same RTL; no expression, priority, state, or
  register behavior changed.

## Installed tools

| Capability | Result | Version / path |
|---|---|---|
| Vivado | installed | Vivado 2021.1, SW build 3247384, IP build 3246043 |
| XSim | installed, not on `PATH` | `C:/Xilinx/Vivado/2021.1/bin/xsim.bat`, Vivado Simulator 2021.1 |
| ModelSim | installed | ModelSim ALTERA STARTER EDITION 10.5b, `C:/intelFPGA_lite/17.0/modelsim_ase/win32aloem/vsim.exe` |
| Questa | not found | no `questa` command; installed `vsim` identifies itself as ModelSim ASE, not Questa |
| VCS | not found | no `vcs` command |
| Jasper / `jg` | not found | no `jg`, `jasper`, or `jaspergold` command |
| Questa Formal / OneSpin | not found | no `qverify` or `onespin` command |
| Icarus / Verilator | not found | no `iverilog` or `verilator` command |

Formal tool syntax must not be generated as if one of the absent tools had
been detected. Formal execution is `NOT RUN` unless the environment changes.

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

- `tcl/round53_run.tcl`
- `tcl/round54_run.tcl`
- `verification/vivado/run_streaming_175mhz.tcl`
- `tcl/round54_regressions.ps1`
- `tcl/round55_rebuild_board_synth.tcl`
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
  `tcl/round53_run.tcl`, `tcl/round54_run.tcl`, and
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
  `tcl/round53_run.tcl`, `tcl/round54_run.tcl`,
  `tcl/round54_regressions.ps1`,
  `engrenring/synth_1g/axi_ooc/run_axi_ooc.tcl`, and the board build Tcl
  files listed above.
- DCP-only audit/query consumers:
  `report_synth_targets.tcl`, `partpin_ooc.tcl`,
  `run_axi_ooc_signoff.ps1`, `run_partpin_discovery_candidate.tcl`,
  `run_partpin_replay.tcl`, `run_round51b_frozen_route.tcl`,
  `run_round52_frozen_route.tcl`, and all
  `query_round51*.tcl`/`query_round52*.tcl` files under
  `engrenring/synth_1g/axi_ooc`.

No `.f`, `.flist`, `.prj`, or ModelSim `.do` filelist was present.

## Exact top and source path by existing flow

| Existing flow | Top / elaborated snapshot | GHASH selected | Classification |
|---|---|---|---|
| `synth_1g/run_synth.tcl` | `top` | missing `AESGCM_IO/GHASH.v` | legacy, broken |
| `sim/tb_top.sv` | `tb_top` -> `top` | inherited legacy top | legacy, broken |
| `sim/tb_top_1g_parallel.sv` | `tb_top_1g_parallel` -> `top` | inherited legacy top | legacy, broken |
| `axi_ooc/run_axi_ooc.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | current streaming, 175 MHz |
| `verification/vivado/run_streaming_175mhz.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | maintained strict 175 MHz verification flow |
| `tcl/round53_run.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | historical timing evidence |
| `tcl/round54_run.tcl` | `aes_gcm_axi_top` | `stream_ghash/ghash16.v` | retained experiment driver, locked to 175 MHz |
| `round54_regressions.ps1` | individual `tb_*` tops | `stream_ghash/ghash16.v` | current streaming simulation |
| `board/run_arty_a7_100t_selftest.tcl` | `arty_a7_100t_aes_gcm_selftest_top` | `stream_ghash/ghash16.v` | current streaming board |
| `board/run_arty_a7_100t_uart_rsp.tcl` | `arty_a7_100t_aes_gcm_uart_rsp_top` | `stream_ghash/ghash16.v` | current streaming board |
| `board/run_arty_a7_100t_uart_rsp_from_synth.tcl` | opens verified synth DCP of UART wrapper | inherited `ghash16` netlist | current streaming board resume |
| `tcl/round55_rebuild_board_synth.tcl` | `arty_a7_100t_aes_gcm_uart_rsp_top` | `stream_ghash/ghash16.v` | current streaming board rebuild |

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

The baseline executions and exact commands are recorded separately under
`verification/results/baseline/`; this document does not claim their result
before they are run.
