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

Recommended marked probes include key commit/ready/busy, input/output
handshakes, GHASH start/busy/done/digit index, GHASH queue valid/ready, and tag
output index. The shell already marks the internal GHASH/key signals; a board
integrator may add an ILA core to the marked nets.
