# Board shell status

- `board_test_shell` RTL compile/elaboration: PASS on XSim 2021.1
- OOC synthesis: PASS (`BOARD_BUILD_SUMMARY status=OOC_PASS`)
- Shell storage mapping: input 256x8 = 1 RAMB18E1; output 512x15 = 1 RAMB18E1
- Bitstream generated: NO
- Board programmed: NO
- Board vectors executed: 0

The generic shell includes input/output BRAMs, an AXI-Stream feeder and three
sinks, cycle/input/output/stall counters, programmable LFSR backpressure, and
debug-marked handshake signals. It exposes separate shell-control and DUT
AXI-Lite slaves for connection behind JTAG-to-AXI plus an AXI interconnect.

Existing Arty PACKAGE_PIN constraints in the repository belong to other top
modules. No pin constraint was copied or invented for this shell.
