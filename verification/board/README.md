# Generic board validation shell

`board_test_shell.sv` wraps the production `aes_gcm_axi_top` with an input
BRAM feeder, output BRAM sink, cycle/input/output/stall counters, programmable
LFSR output backpressure, status IRQ, and marked ILA candidates.

It exposes two AXI-Lite slaves. Connect a JTAG-to-AXI master through an AXI
interconnect: one region to the shell control port and one region to the DUT
configuration port. JTAG-to-AXI is **not** treated as an AXI-Stream source.

Shell control map:

| Offset | Access | Purpose |
|---:|:---:|---|
| `0x000` | W | bit0 start, bit1 clear |
| `0x004` | R | running/done/feed-valid/overflow |
| `0x008` | R/W | input byte length |
| `0x00c` | R/W | LFSR enable, channel mask, threshold/seed |
| `0x010..0x01c` | R | cycle/input/output/stall counters |
| `0x100..0x4fc` | W | input BRAM, one byte per 32-bit word |
| `0x800..0xffc` | R | output BRAM `{channel,last,user,data}` |

The repository contains real PACKAGE_PIN constraints for the existing Arty
A7 UART/self-test tops under `engrenring/synth_1g/board/`. Those constraints
do not name this generic shell's ports and therefore are not reused. A board
project must supply an approved clock/reset wrapper and matching XDC before
bitstream generation.

## Production Arty UART/RSP reset qualification

The production `arty_a7_100t_aes_gcm_uart_rsp_top` has its own matching XDC
under `engrenring/synth_1g/board/`; it is separate from the generic shell.
Its raw button/MMCM-lock run request passes through a two-stage `ASYNC_REG`
synchronizer and a separate four-stage stable-high reset-release qualifier.

Run the directed XSim corner-case test from the repository root with Git Bash:

```text
& 'C:\Program Files\Git\bin\bash.exe' verification/scripts/run_board_reset_xsim.sh
```

The test rejects one-, two-, and three-sample button and MMCM-lock pulses plus
alternating chatter, checks release on the sixth continuous-valid sample, and
checks reset assertion on the third invalid sample. The full implementation
Tcl separately gates the exact CDC topology, timing, routing, DRC, methodology,
and `check_timing` schema.

## Reproduce the 175 MHz production implementation

Run the fresh implementation with a new output label; the driver refuses to
overwrite an existing directory:

```powershell
& 'C:\Xilinx\Vivado\2021.1\bin\vivado.bat' -mode batch `
  -source engrenring/synth_1g/board/run_arty_a7_100t_uart_rsp.tcl `
  -tclargs <unique-label>
```

Promotion uses a second, SHA-bound audit of the routed checkpoint. Supply the
SHA-256 printed for the checkpoint and another unused label:

```powershell
& 'C:\Xilinx\Vivado\2021.1\bin\vivado.bat' -mode batch `
  -source verification/board/audit_routed_board.tcl `
  -tclargs <routed.dcp> <expected-sha256> <unique-audit-label>
```

The audit is fixed to Vivado 2021.1 build 3247384, top
`arty_a7_100t_aes_gcm_uart_rsp_top`, part `xc7a100tcsg324-1`, and a 175 MHz
core clock. It fails before bitstream generation unless setup, hold, pulse
width, routing, DRC, methodology, CDC, timing-exception coverage, reset/UART
synchronizer topology, and `check_timing` all match the approved schema.

Program the audited bitstream only after that PASS signature:

```powershell
& 'C:\Xilinx\Vivado\2021.1\bin\vivado.bat' -mode batch `
  -source verification/board/program_board.tcl `
  -tclargs <audited.bit> xc7a100t_0
```

With the board UART on COM4, run all six NIST response files and bind the
evidence to the exact programmed bitstream:

```powershell
python engrenring/synth_1g/board/run_nist_rsp_uart.py `
  --port COM4 --baud 115200 --progress 1000 --stop-on-fail `
  --bitstream <audited.bit> --output <evidence.jsonl>
```

The UART link is a validation transport, not the datapath throughput path.
At 115200 baud with 8N1 framing its line-code payload ceiling is 92.16 kbit/s;
use the core throughput regression or an on-chip counter for Gbit/s claims.

Recommended marked probes include key commit/ready/busy, input/output
handshakes, GHASH start/busy/done/digit index, GHASH queue valid/ready, and tag
output index. The shell already marks the internal GHASH/key signals; a board
integrator may add an ILA core to the marked nets.
