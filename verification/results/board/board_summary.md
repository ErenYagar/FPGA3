# Board status

## Current exact 175 MHz candidate

The current candidate is the fresh `resetqual4_final_v8` routed design plus
the hash-verified `resetqual4_audit_v8c` strict static signoff. Hardware
Manager programming, all six hardware smoke modes, and the 47,250-vector
hardware NIST run used the v8a bitstream whose `.bin` configuration payload is
byte-identical to v8c. All listed board gates pass. Source and verification
are committed at `4246ebc7a72ce8eb1a49d56969aae6e151578c11`.

- Build-base commit: `ece78ce9677872d0d20da3b785ab83a48b6a8492`
- Source/verification promotion commit:
  `4246ebc7a72ce8eb1a49d56969aae6e151578c11`
- Cryptographic datapath content: `a6f19472ecc619925b373b1db801911c54062a90`
- Top/device: `arty_a7_100t_aes_gcm_uart_rsp_top` /
  `xc7a100tcsg324-1`
- Input/core clocks: 100 MHz / 175 MHz (`5.714 ns` core period)
- UART: COM4 at 115200 baud
- Fresh implementation:
  `engrenring/synth_1g/board/output/ece78ce_uart_rsp_175_resetqual4_final_v8/`
- Final strict routed-DCP audit:
  `engrenring/synth_1g/board/output/ece78ce_uart_rsp_175_resetqual4_audit_v8c/`
- Hardware-tested evidence:
  `engrenring/synth_1g/board/output/ece78ce_uart_rsp_175_resetqual4_audit_v8a/`
- 200 MHz work is out of scope and was not run.

The combined button/MMCM-`LOCKED` run request enters a two-stage
`ASYNC_REG` synchronizer and then a separate four-stage stable-high release
qualifier. UART RX has its own two-stage `ASYNC_REG` synchronizer. This board
CDC/reset change does not alter an AES/GHASH datapath expression or protocol
priority. The directed test rejects 1-, 2-, and 3-sample button and
MMCM-`LOCKED` pulses plus alternating chatter. Continuous valid input releases
after six sampled core edges; an invalid request reaches distributed reset
assertion after three sampled edges.

| Exact build/audit input | SHA-256 |
|---|---|
| Board top RTL | `FA6E19757BABC3D6FA66879C45A99320ECC4CB2C6861A6C2523E8E5E577389C5` |
| UART RX RTL | `3DC746D15DBEB4D68FD475E99E9B772466D20F5FC6A76DF5D160B9271A942EDF` |
| Board XDC | `7EF65C0482EF5111355AB1D7190C00DFAA37CA988A1678279762EFD19DFA40AE` |
| Immutable fresh-build Tcl used for v8 DCP (`verification/board/provenance/run_arty_a7_100t_uart_rsp_v8_execution.tcl`) | `02DD9892D48F8FCFB16A1C4BD88FF43882C5F52CE1890108F522CD965BCECA0A` |
| Current fresh-build Tcl after object-list gate repair | `C8CEE93D3D93223926B000A521EF82E413B0855A68FB46B3B9EB23C1F811E18A` |
| Final strict-audit Tcl | `62C653E5E49723A51726B92B0D475BA11C55F24A3648D59359A2ABCE99C9286E` |

The first fresh-build Tcl hash is the v8 execution-time identity. The current
script fixes Tcl object-list canonicalization in post-route reset/I/O gates
and emits a strict-audit-required promotion marker. That repair does not
retroactively identify the immutable routed DCP. The audit Tcl hash is the
final v8c execution identity.

## Static signoff

The fresh flow used `ExploreWithRemap`, `ExtraNetDelay_high`, pre-route
`AggressiveExplore`, `Explore`, and post-route `AggressiveExplore`. The
fresh v8 wrapper completed implementation and report generation but stopped
before bitstream generation on a Tcl list/string internal-representation
comparison even though the compared endpoint lists were identical. v8a opened
the immutable v8 routed DCP, verified its SHA-256, and generated the
hardware-tested payload. A later v8b strict-audit attempt stopped because its
Tcl gate misclassified the hierarchical UART CE tie to VCC; that was an audit
string-handling failure, not a DCP fault. v8c corrected the gate and passed the
strict audit against the same immutable routed DCP SHA-256. Both failures are
retained as build/audit-gate coding failures, not hidden as design failures.

| Checkpoint | SHA-256 |
|---|---|
| Synth DCP | `C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6` |
| Placed DCP | `82BAA9B402F825B3127202255F5787BA82A8E7F34291A0DDA5F4C86689C4119D` |
| Routed DCP | `A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B` |

| Signoff gate | Result |
|---|---:|
| Placed setup WNS / TNS / FEP | `+0.075 ns / 0 / 0` |
| Placed hold WHS / THS / FEP | `-0.082 ns / -0.364 ns / 9` |
| Final routed setup WNS / TNS / FEP | `+0.029 ns / 0 / 0` |
| Final routed hold WHS / THS / FEP | `+0.044 ns / 0 / 0` |
| Final routed pulse WPWS / TPWS / FEP | `+1.607 ns / 0 / 0` |
| Routed nets | `17,758 / 17,758`; unrouted/errors `0 / 0` |
| DRC Error / Critical Warning | `0 / 0` |
| Methodology Error / Critical Warning | `0 / 0` |
| CDC | expected schema PASS; exactly 2 top-level CDC-3 Info synchronizers; unsafe categories `0` |
| `check_timing` | ten critical categories `0`; exact false-path input/output allowlists `2 / 5` |

The methodology report contains two ordinary `SYNTH-6 Warning` entries; it is
Error/Critical-Warning clean, not warning-free. `report_cdc` covers the reset
request and UART synchronizers. MMCM `LOCKED` is not independently covered by
`report_cdc`; its use is checked by a structural exact-fanout gate. Raw
asynchronous port paths are false-pathed while downstream FF-to-FF stages
remain timed.

The final logical release stage has four physical cells, all in
`SLICE_X49Y132`:

| Physical cell | BEL | Endpoint count |
|---|---|---:|
| `reset_qual_r_reg[3]` | `SLICEL.DFF` | 57 |
| `reset_qual_r_reg[3]_rep` | `SLICEL.BFF` | 1,290 |
| `reset_qual_r_reg[3]_rep__0` | `SLICEL.CFF` | 8,553 |
| `reset_qual_r_reg[3]_rep__1` | `SLICEL.AFF` | 3,262 |

The mapped endpoint sum is 13,162 and the union is 13,161 because
`u_aes_gcm/u_core/gh_ctrl_valid_reg/D` reconverges. The sole approved
stage-2 early endpoint is
`u_aes_gcm/u_core/u_key_context/u_key_sbox1/GEN_REGISTERED_OUTPUT.co_r_reg/ENARDEN`.

## Utilization, power, and artifacts

- Total LUT: 12,411 (11,333 logic, 1,078 LUTRAM)
- FF: 9,029
- RAMB18: 10
- DSP: 0
- Routed vectorless power: 0.461 W total, 0.363 W dynamic, 0.099 W static,
  27.1 degrees C junction estimate, Medium confidence

Power is a vectorless implementation estimate, not measured board power. The
report lacks complete I/O activity and Vivado also warns about high inferred
reset activity, so it must not be presented as a power measurement.

| Final strict-audit v8c artifact/report | SHA-256 |
|---|---|
| Bitstream | `DC951AAE0D388DA54836AD5950CA87CB8EEE4A94E5E7EFBB1A685439F0934942` |
| Binary | `8A19D8E5900063B64922DC9B9AD323F953386367CA1D4FA1A61935543B4332F3` |
| Signoff metrics | `CBC7D4F16D9D54A67CC6B10E4A9DC612888112933D6263F3F2D69932FB0946CB` |
| Timing report | `13885FEB000CAE1D120456C0D01CB5E8DA98742E557DA4567C74C169829BB379` |
| Utilization report | `B43ABD66D016F55E20162B950A47B0EEABBF77234C463BE855AE6CCFA0044DA0` |
| Route report | `5588C95BD9AD4B571B5EB535DEAA0F78F7DB78F84E56B6C4608EA1D2611F2569` |
| DRC report | `43D5E554BCB47C680CCD5E94BE501BA23EBCE26B1E04512AB31E9515B117C867` |
| Methodology report | `A80B78B0C6E7ED4D1AE4F9EF37C60F885670AA134771145B437E23E8D17014F9` |
| CDC report | `DA5C4FCE87D7690F9164670F00D073CF12003D689D03BA304EB448A3355DCB22` |
| `check_timing` report | `043FD5C662EF6FD8403A0848AE168BBAEDBFA200A4FDEB4EE85BCA030761F951` |
| Clock-utilization report | `67640CD2CC4716F14A05703C052E71A991A2193D90EB9AEDB41F97725C4EFEDC` |
| Power report | `687014688995046BACE3FFA09CB4E3E3B76A551B0F9A1D3C92C7C6874A9EF351` |

The hardware-tested v8a bitstream SHA-256 is
`22791C17939C1BBC43539C35ABB19C31896425D26AA4721D5E4D4D3ACC5A686E`.
Its `.bin` SHA-256 is
`8A19D8E5900063B64922DC9B9AD323F953386367CA1D4FA1A61935543B4332F3`,
exactly matching the final v8c `.bin`. The v8a and v8c `.bit` hashes differ,
so the `.bit` container files are not claimed identical.

## Hardware verification

- Hardware Manager program command: PASS
- Target/device: `Digilent/210319BE76DEA` / `xc7a100t_0`
- Exact programmed host bitstream SHA-256:
  `22791C17939C1BBC43539C35ABB19C31896425D26AA4721D5E4D4D3ACC5A686E`
- Program log SHA-256:
  `4301F53AFF229FD358B699E63BA199A7718DEDE96E7756BE01F2E13FAB4135D4`
- AES-128/192/256 encrypt/decrypt hardware smoke: **6 pass / 0 fail**
- Aggregate smoke log SHA-256:
  `519C9820BED299203A8C04380E159A4F7A256098A028D112E215822324194CD1`
- Exact-v8a full hardware NIST: **47,250 pass / 0 fail**, first failure
  `null`, elapsed 1,208.505 s on COM4
- NIST JSONL SHA-256:
  `56DA5E1B7110AE8A5622B5847211A842C4D2A2A22A08EE02AA7D32EFB0C59761`
- NIST summary SHA-256:
  `5DF2EA729BBD0C19C6677AFD13F73DD4F04BB53694B9552A3FF4D9D464604D06`
- NIST run-log SHA-256:
  `B861E8500B214CB85A98A1FDC231C3E097DDA60F237EA3A49021E6BCECEFEEB4`

Independent JSONL reconciliation found exactly 47,250 rows with unique,
contiguous indices 0--47,249; each of the six RSP sources contributed 7,875
rows. The outcome classes are 23,625 encrypt and 23,625 decrypt: 11,717
successful decrypt plus 11,908 expected authentication failures. Status,
data, and tag violations are `0 / 0 / 0`; a second independent reconciliation
also passed.

The host hash establishes artifact provenance, not FPGA readback attestation.
The program log does not contain independent EOS/DONE/CRC/PLL readback, so
none is claimed. Programming success, all six smoke modes, and the reconciled
full NIST run are the operational board evidence.

## Post-commit integrated verification

At promotion commit `4246ebc7a72ce8eb1a49d56969aae6e151578c11`, the stable
`verification/scripts/run_all.sh` replay is **PARTIAL_PASS**: five suites PASS,
one suite is PARTIAL_PASS, zero are NOT_RUN, and zero fail, for six total. The
only partial suite is the 19-assertion assumption-free combinational formal
subset; full sequential formal closure remains unclaimed. The integrated log
SHA-256 is
`14F4244DE577CF1B1D80B7B2A9FBE1E6B33A07AF5629341A7F523DFA3DB8D7CA`.

Within that replay, simulated NIST is 47,250 pass / 0 fail in 17,740,527
cycles; its log SHA-256 is
`5EDC8CEE2AFF8D05D6538B8CFE911D8B775FFECED758FCBFD36786D9045BBCE3`.
This integrated PARTIAL_PASS label reflects formal scope only and does not
replace or weaken the independently closed implementation and hardware gates
above.

## Rejected or non-promoted history

- `strict_v3`: timing and hardware-vector checks passed, but CDC had 5
  Critical and 3 Warning paths.
- `cdc_final_v5`: timing passed and the board completed 47,250/0 hardware
  vectors, but a pure four-FF shift could convert a one-sample run request into
  a delayed one-cycle release.
- `resetqual_final_v6`: separated synchronization and qualification but used
  only a two-stage qualifier, weakening the required four-sample threshold;
  its full hardware NIST run did not complete.
- `resetqual4_final_v7`: correct 2+4 topology and routed timing passed, but an
  `ASYNC_REG` boolean-representation Tcl gate stopped the build before the
  bitstream.
- `resetqual4_final_v8`: correct fresh implementation and promoted routed
  DCP, but the wrapper stopped on the exact-list Tcl comparison; v8a
  hash-verified the DCP and produced the hardware-tested payload.
- `resetqual4_audit_v8b`: stopped because the audit Tcl misclassified the
  hierarchical UART CE VCC tie; this was not a DCP fault. v8c corrected the
  gate and passed strict audit on the same routed DCP SHA-256.

Passing AES vectors do not override a reset/CDC or build-provenance gate.

## Generic shell and PartPin status

The generic `board_test_shell` still compiles/elaborates in XSim and maps
input/output storage to one RAMB18 each. Its 175 MHz OOC DCP SHA-256 is
`1F47062D5DC53F4655FA0B9A1A8BB44DBDB2C194D62C4580C47C2083FDA3F710`.
That shell-only result is not board timing signoff.

Standalone OOC PartPin replay remains **NO / NOT RUN** because no approved,
identity-matched production `HD.PARTPIN_LOCS` map and parent timing model are
available. This does not invalidate the completed full-board implementation.
