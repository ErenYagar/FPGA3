# Fresh 200 MHz streaming implementation

- RTL git SHA: `4a215983f3774c49e833cfe3715a019748200c73`
- Tool: Vivado 2021.1, SW Build 3247384, IP Build 3246043
- Device: `xc7a100tcsg324-1`
- Top: `aes_gcm_axi_top`
- Clock: `aclk`, 5.000 ns (200 MHz)
- Result: **FAIL -- setup timing is not closed**
- Output: `verification/results/vivado_200mhz/run_20260822_151042`

The run was fresh synthesis through routing with these directives:
`ExploreWithRemap`, `ExtraNetDelay_high`, `AggressiveExplore`, and `Explore`.
It used the current streaming GHASH implementation and excluded the legacy
`AESGCM_IO/GHASH.v` source.

| Metric | Routed result | Gate |
|---|---:|---:|
| WNS | -0.615 ns | >= 0 ns |
| TNS | -131.872 ns | 0 ns |
| Setup failing endpoints | 1,462 | 0 |
| WHS | -1.087 ns | board integration required |
| THS | -887.509 ns | board integration required |
| Hold failing endpoints | 974 | board integration required |
| Pulse-width slack | +1.250 ns | >= 0 ns |

The worst hold path starts at the unconstrained physical boundary
`s_axis_tdata[0]` and ends at input-queue LUTRAM. Its zero input delay and
missing approved PartPin/board wrapper make the OOC hold result unsuitable for
board signoff. This does not change the independent internal setup failure.

The worst setup path is
`u_core/u_key_context/generated_word_r_reg[31]` to
`u_core/u_key_context/round_keys_r_reg[159]/D`. Its 5.506 ns data path is
0.890 ns logic and 4.616 ns routing (83.835% route), with three LUT6 levels.
Other leading paths include round-key/state control, AES second-engine round
control, and ZEROIZE/plain-bank clock enables.

| Implementation evidence | Result |
|---|---:|
| Fully routed nets | 16,434 / 16,434 |
| Routing errors | 0 |
| DRC Error/Critical Warning violations | 0 |
| DRC warnings | 2 (`CFGBVS-1`, `RTSTAT-10`) |
| check_timing critical categories | all 0 |
| Methodology Error/Critical Warning violations | 0 |

| Resource/power estimate | Value |
|---|---:|
| Total LUTs | 11,792 |
| Logic LUTs | 10,828 |
| LUTRAMs | 964 |
| FFs | 8,447 |
| RAMB18 | 10 |
| DSP | 0 |
| Vectorless total power | 0.446 W |
| Dynamic / static | 0.361 / 0.085 W |
| Power confidence | Medium |

DCP SHA-256:

- synth: `847CC6B225C3ADE3E259D017CE3E44A98176A8C6690B4EE97A4AA049413FB968`
- placed: `DA22F4AD5062FB7F221EC217AB96F7D04393328FFE15EB2BCBF5A95D4890167B`
- routed: `12BF7815EC6188B928740A661E246391C4881E1CE30BB17B88DDF575C0781CD4`

The full DCPs and raw reports are retained locally and intentionally ignored by
Git. PartPin remains **NO** because there is no approved identity-matched
production map for this new placed DCP.
