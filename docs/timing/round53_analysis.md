# Round53 200 MHz timing-closure analysis

## Repository and experiment contract

- Repository: `ErenYagar/FPGA3` (private)
- Branch: `timing/round53-zero-cycle-closure`
- Baseline commit: `dfb010787b93f211f257ebb134d4f836dbdb268e`
- Tool: Vivado 2021.1, part `xc7a100tcsg324-1`
- Top: `aes_gcm_axi_top`, out-of-context clock `aclk`, period `5.000 ns`
- Implementation directives: `synth_design -flatten_hierarchy rebuilt`,
  `opt_design -directive ExploreWithRemap`,
  `place_design -directive ExtraNetDelay_high`,
  `phys_opt_design -directive AggressiveExplore`, and
  `route_design -directive Explore`.
- Vivado default seed was retained. No incremental compile, PartPin placement,
  timing exceptions, or constraint relaxation was used.

The immutable Round52/R53-A source identities are:

| Source | SHA-256 |
|---|---|
| `aes_gcm_stream_core.v` | `BF73AC638EE1014897E263C5012E258F43A4803859EF4DB6134BB080D9857AD3` |
| `aes_gcm_axi_top.v` | `8F1E6F26DAC97D1CC4455AC4C9A22C661E6DED9F9072C5E338F0278B55968C24` |
| `aes_block_engine.v` | `C73046F1841B90A5CB2DA1DAE4A5E32FDE1A677463E8E3712FFABADA69B9BBA6` |
| `aes_key_context.v` | `1FA842B80BD7E9F4BF1DAE5311941C4AE15BD10EE491CB6EE0AFD95F22D03F91` |
| `axi_200mhz_ooc.xdc` | `DAC799A39F1CF985216926A5D363F19B443A27EC7A86A6CD47819A46CBFA0FBE` |

## R53-A fresh baseline reproduction

The functional baseline was rebuilt with the official Vivado `glbl` model and
`unisims_ver` library. It reproduced the locked Round52 cycle signatures:

- smoke: `8364` cycles;
- throughput: `18920/19139`, `19520/19739`, and `20120/20339` cycles for
  AES-128/192/256 encrypt/decrypt respectively;
- throughput floor: `1.006932 Gbit/s` (AES-256 decrypt);
- boundary directed cases: `364/722` cycles;
- residual directed cases: `546/1002/1568` cycles;
- NIST525: `525/525`, `145808` cycles;
- NIST5255: `5255/5255`, `1615588` cycles.

The fresh A implementation artifacts are:

| Stage | Bytes | SHA-256 |
|---|---:|---|
| synthesized DCP | 2,799,667 | `E07B3028A3CE3CC4EE795A93C4C27FF46421667C92AEF276AC5D98685DA9A6AF` |
| placed DCP | 4,639,073 | `C806C0A5C5352ADA1E5207D4FC0027480BB309698A267FBBB5F9D213427D7CB5` |
| routed DCP | 6,140,641 | `0625E4705B8E1E0C4F032030BA827C0E967B44804FE798ECB413515F9001BDE2` |

Internal timing is the register-to-register domain, not the intentionally
budgeted OOC input/output hold paths:

| Stage | WNS (ns) | TNS (ns) | FEP | WHS (ns) | THS (ns) | Hold FEP |
|---|---:|---:|---:|---:|---:|---:|
| synth | -0.168 | -0.623 | 5 | +0.200 | 0 | 0 |
| placed | -0.097 | -0.097 | 1 | -0.001 | -0.001 | 1 |
| routed | -0.398 | -95.962 | 854 | +0.052 | 0 | 0 |

The routed design has `13317/13317` routable nets fully routed and zero route
errors. DRC has zero Error/Critical Warning and only the two established OOC
warnings `CFGBVS-1` and `RTSTAT-10`. All 12 `check_timing` categories are zero.
Utilization is 8,603 LUTs (7,639 logic + 964 LUTRAM), 7,299 FFs, 10 RAMB18,
zero DSPs, and 349 control sets.

R53-A therefore reproduces the functional and physical baseline, but it does
not meet 200 MHz internal setup timing. The B/C/D comparisons below must use
the same flow and must not treat an OOC boundary hold number as internal hold.

<!-- R53-B/C/D results and final critical-family analysis are appended after
     their independent fresh implementation runs. -->
