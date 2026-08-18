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

### R54-A fresh reproducibility baseline

R54-A rebuilt the retained RTL from source with Vivado 2021.1 build 3247384
and the locked directives `ExploreWithRemap`, `ExtraNetDelay_high`,
`AggressiveExplore`, and `Explore`.  The regenerated checkpoints are:

| Stage | SHA-256 |
|---|---|
| synth | `848E00E57697609246F8F4AF243C90137AAACFC8625337B4E16C8C9FA900CF23` |
| placed | `B98A90503BDA7D5B35309A9C97FC7651C7F5FA8FB5F0B7EEAB347BC1C1304E40` |
| routed | `EA4511B5676C9475FB8E6F9A0D8B0B7660C8766CD1922F04E263F8B712B0AE85` |

The DCP container hashes differ from the retained artifacts, but the fresh
implementation reproduces the retained design exactly at the signoff level:
WNS `-0.523 ns`, TNS `-26.673 ns`, FEP 273, WHS `+0.051 ns`, THS 0,
309 control sets, 8,586 LUTs, 7,296 FFs, and 13,269/13,269 routed nets.
The endpoint-family counts and TNS values are also identical.  DRC errors,
critical warnings, route errors, CDC failures, latches, multiple drivers, and
critical `check_timing` categories are all zero.  R54-A therefore passes the
fresh-flow provenance gate and remains the comparison baseline; it does not
pass setup closure.

### R54-B local prep-tag clear (not promoted)

The first inferred-register implementation passed simulation but failed the
structural gate: Vivado folded the descriptor-load logic into the reset cone,
so `zeroize_sequence_active_r` remained in the mapped `prep_tag_bytes` R-pin
fanin.  That failed synth checkpoint is retained with abbreviated SHA-256
`ECA0...1955` as a negative experiment and was not routed.

The corrected implementation used five explicit FDREs.  Raw reset/ZEROIZE
drive R, `take_descriptor` drives CE, and only the decoded descriptor value
drives D.  The routed DCP gate found five mapped bits, five direct raw-ZEROIZE
R-pin paths, and zero zseq nodes in the reset cones.  Checkpoint hashes are:

| Stage | SHA-256 |
|---|---|
| synth | `4F65C79BEDC975E0EBB404EA181169E4567A1471B313ACC6BF3AA0F8AA0E0056` |
| placed | `1AE3619394A01E9E6CD3FAE72D200B73E54271AF0C776E136F64518A6BF71932` |
| routed | `59A1D230057BB8F1BF64F319660537445313B0AD306D1E7698E36A6B5ECC10B6` |

Synthesis improved to WNS `-0.238 ns`, TNS `-0.476 ns`, and 2 failing
endpoints.  Routing, however, finished at WNS `-0.442 ns`, TNS `-33.434 ns`,
358 failing endpoints, WHS `+0.052 ns`, and THS 0.  It used 8,569 LUTs,
7,310 FFs, 407 control sets, and routed all 13,314 nets.  The source ZEROIZE
net fanout fell from 342 to 326, and the ciphertext family fell from
123/-14.028 ns to 13/-0.793 ns, but the round-key control family grew from
62/-5.004 ns to 126/-17.224 ns.  The raw-ZEROIZE negative family was
33/-3.866 ns.

R54-B therefore fails the three-metric promotion rule: only WNS improved;
TNS magnitude and FEP regressed.  Per the isolation plan, no B2 and no
B-derived combination are run.  The new round-key dominance is recorded for
a subsequent round and is not expanded in Round54.
