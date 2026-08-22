# Fresh 175 MHz streaming implementation

- RTL git SHA: `a6f19472ecc619925b373b1db801911c54062a90`
- Tool: Vivado 2021.1, SW Build 3247384, IP Build 3246043
- Device: `xc7a100tcsg324-1`
- Top: `aes_gcm_axi_top`
- GHASH: `stream_ghash/ghash16.v` (legacy GHASH excluded)
- Clock: `aclk`, 5.714 ns (175 MHz contract)
- Output: `verification/results/vivado_175mhz/run_20260822_170742`
- Result: **PASS -- internal setup and hold timing are closed**

This was a fresh synthesis, placement, physical optimization, and route using
`ExploreWithRemap`, `ExtraNetDelay_high`, `AggressiveExplore`, and `Explore`.
It did not reuse a routed checkpoint.

| Internal timing metric | Routed result | Gate |
|---|---:|---:|
| WNS | +0.056 ns | >= 0 ns |
| TNS | 0.000 ns | 0 ns |
| Setup failing endpoints | 0 | 0 |
| Register-to-register WHS | +0.053 ns | >= 0 ns |
| Internal THS | 0.000 ns | 0 ns |
| Internal hold failing endpoints | 0 | 0 |
| Pulse-width slack | +1.607 ns | >= 0 ns |

The worst setup path is from `u_registers/zeroize_pulse_o_reg` through one
LUT2 to `u_core/u_key_context/round_keys_r_reg[1787]/R`. Its data path is
5.057 ns: 0.580 ns logic and 4.477 ns routing. The worst internal hold path is
`u_core/u_aes_second_engine/block_out_r_reg[123]` to
`u_core/aes_second_result_block_r_reg[123]/D`, with +0.053 ns slack.

The unintegrated OOC boundary still reports WHS -1.216 ns, THS -916.429 ns,
and 966 failing hold endpoints. The worst path starts at external input
`s_axi_wdata[22]`; it has 0.000 ns minimum input delay and no approved
`HD.PARTPIN_LOCS`. These boundary numbers are excluded from the internal gate
and remain **OPEN** until the exact parent design and identity-matched PartPin
map are available. Consequently, this report is not board-level timing
signoff and does not claim a production bitstream.

| Implementation evidence | Result |
|---|---:|
| Fully routed nets | 16,327 / 16,327 |
| Routing errors / unrouted nets | 0 / 0 |
| DRC errors/critical warnings | 0 / 0 |
| DRC warnings | 2 (`CFGBVS-1`, `RTSTAT-10`) |
| check_timing critical categories | all 12 are 0 |
| Methodology errors/critical warnings | 0 / 0 |
| Methodology warnings | 201 (2 `SYNTH-6`, 199 boundary `TIMING-15`) |

After this run, the reusable runner was tightened to fail closed on both DRC
and methodology Error/Critical Warning severities. The same routed DCP was
reopened in Vivado 2021.1 and its named methodology result was queried through
`get_methodology_violations`: 201 warnings, 0 errors, and 0 critical warnings,
matching the retained report. DRC Error/Critical Warning is likewise 0/0.

Vivado emits one route critical warning because the complete OOC timing
summary includes the unresolved boundary hold paths. Route verification itself
completed successfully, and the internal register-to-register hold gate is
clean.

| Resource/power estimate | Value |
|---|---:|
| Total LUTs | 11,600 |
| Logic LUTs | 10,636 |
| LUTRAMs | 964 |
| FFs | 8,410 |
| RAMB18 | 10 |
| DSP | 0 |
| Vectorless total power | 0.389 W |
| Dynamic / static | 0.304 / 0.085 W |
| Power confidence | Medium |

DCP SHA-256:

- synth: `70673004EE0F6F46765FD41B06AEE798285A307935938489B2C5C2A9DD41B8E9`
- placed: `82B953F9008789C537681770D55277159F45708215470C82A52111A1BA738E2E`
- routed: `C0266F6CEA03265562A3537058D1BA43B104765D2D7BFC23DF4CADE8C5E2A0D3`

PartPin remains **NO** because no approved identity-matched production map
exists for this placed DCP.
