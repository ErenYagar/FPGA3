# Board status

Current generic verification shell:

- `board_test_shell` RTL compile/elaboration: PASS on XSim 2021.1
- Shell storage mapping: input 256x8 = 1 RAMB18E1; output 512x15 = 1 RAMB18E1
- Generic-shell 175 MHz OOC synthesis: PASS for compile/elaboration and the
  required 1/1 RAMB18 mapping
- OOC DCP SHA-256:
  `1F47062D5DC53F4655FA0B9A1A8BB44DBDB2C194D62C4580C47C2083FDA3F710`
- Evidence: `verification/results/board/ooc_175_20260822_1743/`

This shell OOC result is not timing or board signoff. Its synthesis timing is
negative and a shell-specific board wrapper XDC is still required before
implementation and bitstream generation.

The generic shell includes input/output BRAMs, an AXI-Stream feeder and three
sinks, cycle/input/output/stall counters, programmable LFSR backpressure, and
debug-marked handshake signals. It exposes separate shell-control and DUT
AXI-Lite slaves for connection behind JTAG-to-AXI plus an AXI interconnect.

Existing Arty PACKAGE_PIN constraints in the repository belong to other top
modules. No pin constraint was copied or invented for this shell.

Retained production Arty UART/RSP evidence:

- RTL commit: `63824ad6fe9dd12109a1fff8fff7205ce7d27277`
- Core clock: 175 MHz
- Top: `arty_a7_100t_aes_gcm_uart_rsp_top`
- Bitstream SHA-256:
  `FE57A4276FD63656CAE6618BFAE1B677844A26F75BB5093CA0151A10C21E7586`
- Routed timing: setup WNS +0.010 ns / TNS 0; hold WHS +0.011 ns / THS 0
- DRC Error/Critical Warning: 0/0
- Hardware port: COM4 at 115200 baud
- Full NIST hardware run: **47,250 pass / 0 fail**, elapsed 1,190.304 s
- Evidence:
  `engrenring/synth_1g/board/output/63824ad_uart_rsp_175_default_v5/`

The current RTL commit differs from `63824ad` only by moving one declaration
before its primitive consumers for ModelSim elaboration. That is a
behavior-neutral source change, but the current commit has not been rebuilt,
programmed, and rerun on the board; the retained hardware result is therefore
reported with its exact older commit and bitstream hash.
