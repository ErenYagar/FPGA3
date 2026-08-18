# Round54 200 MHz internal timing closure

## Locked starting point

Round54 starts from clean commit
`fc77b1224f36925e4ec661a40edd3ece112d1992` on the retained R53-C source.
The core SHA-256 is
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`.

The local checkpoints passed the required identity gate:

| Stage | SHA-256 |
|---|---|
| synth | `5875BEAFB0A217C9D8CE7062FA27849BF5D41DC5FD8FF8C2031B20E35AEA0789` |
| placed | `09F1A704115CD6C7474438A21A62092798FA2748FDCA6480EAFE8B8991A86D21` |
| routed | `2C2DEAAA2DAAF6CC538BCB336B293030C2AD7791CB8BDCBBC902849BCD611C78` |

Retained routed internal timing is WNS `-0.523 ns`, TNS `-26.673 ns`, 273
failing endpoints, WHS `+0.051 ns`, and THS 0.  Routing is complete and the
DRC/check-timing critical categories are clean.

## Routed family decode

The hash-matched routed DCP was opened in Vivado 2021.1 and all 273 negative
internal register-to-register paths were queried directly.  The ciphertext
family is not inferred from FIFO width:

| Family | Primitive/pin | Paths | TNS (ns) | Worst (ns) |
|---|---:|---:|---:|---:|
| ciphertext head | `FDRE/CE` | 87 | -13.404 | -0.362 |
| ciphertext LUTRAM | `RAMD32/WE` | 28 | -0.492 | -0.034 |
| ciphertext LUTRAM | `RAMS32/WE` | 8 | -0.132 | -0.016 |
| prep tag | `FDRE/R` | 5 | -2.615 | -0.523 |
| round-key main control | `FDRE/CE` | 62 | -5.004 | -0.187 |
| round-key residual | `FDRE/D` | 1 | -0.076 | -0.076 |

All 123 ciphertext failures launch from the physical
`u_registers/zeroize_pulse_o_reg` FDRE.  Its Q net is
`u_registers/zeroize_pulse`, has 342 leaf loads, and is placed at
`SLICE_X32Y122`.  Representative CE and WE fanin cones include both raw
ZEROIZE and `abort_queue_clear`; the WE cone also includes FIFO count and
producer-valid state.

The complete ZEROIZE-source distribution is:

| Endpoint class | Paths | TNS (ns) | Worst (ns) | Average levels | Net/logic |
|---|---:|---:|---:|---:|---:|
| ciphertext head CE | 87 | -13.404 | -0.362 | 4.0 | 4.10 |
| ciphertext LUTRAM WE | 36 | -0.624 | -0.034 | 2.0 | 5.18 |
| prep-tag R | 5 | -2.615 | -0.523 | 4.0 | 4.29 |
| tag-mismatch D | 5 | -0.467 | -0.163 | 4.0 | 4.25 |
| state/control R | 1 | -0.070 | -0.070 | 3.0 | 4.42 |

## Experiment ledger

Results are recorded in `round54_results.csv`.  No experiment is promoted
unless WNS, TNS magnitude, and failing endpoint count all improve relative to
the retained routed C checkpoint and all functional/security gates pass.
