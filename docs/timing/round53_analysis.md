# Round53 200 MHz timing-closure analysis

> Historical investigation only. The production implementation contract is
> now fixed at 175 MHz; the metrics below are retained as provenance.

## Repository and experiment contract

- Repository: `ErenYagar/FPGA3` (private)
- Branch: `timing/round53-zero-cycle-closure`
- Baseline RTL source commit: `dfb010787b93f211f257ebb134d4f836dbdb268e`
- Baseline reproduction/audit commit:
  `736a30f02be584aff97bd3b553e24cf38ac2afcf`
- Tool: Vivado 2021.1, part `xc7a100tcsg324-1`
- Top: `aes_gcm_axi_top`, out-of-context clock `aclk`, period `5.000 ns`
- Implementation directives: `synth_design -flatten_hierarchy rebuilt`,
  `opt_design -directive ExploreWithRemap`,
  `place_design -directive ExtraNetDelay_high`,
  `phys_opt_design -directive AggressiveExplore`, and
  `route_design -directive Explore`.
- Every experiment used the same Vivado 2021.1 default-flow seed behavior. The
  original flow does not set or log an effective numeric placement/route seed,
  so this is a controlled same-default-flow comparison, not an auditable
  numeric fixed-seed lock. No incremental compile, PartPin placement, timing
  exceptions, or constraint relaxation was used.

The immutable Round52/R53-A source identities are:

| Source | SHA-256 |
|---|---|
| `aes_gcm_stream_core.v` | `BF73AC638EE1014897E263C5012E258F43A4803859EF4DB6134BB080D9857AD3` |
| `aes_gcm_axi_top.v` | `8F1E6F26DAC97D1CC4455AC4C9A22C661E6DED9F9072C5E338F0278B55968C24` |
| `aes_block_engine.v` | `C73046F1841B90A5CB2DA1DAE4A5E32FDE1A677463E8E3712FFABADA69B9BBA6` |
| `aes_key_context.v` | `1FA842B80BD7E9F4BF1DAE5311941C4AE15BD10EE491CB6EE0AFD95F22D03F91` |
| `axi_200mhz_ooc.xdc` | `DAC799A39F1CF985216926A5D363F19B443A27EC7A86A6CD47819A46CBFA0FBE` |

The finalized reusable Tcl identities are:

| Script | SHA-256 |
|---|---|
| `round53_hard_gate.tcl` | `8E4477D45DD43D825D954E4F80D839599494FB54BAA8A22E898B5282458AC2C4` |
| `round53_reports.tcl` | `8E07A14984448AE7C7CBFBA0FB4EFB915E273310D4B95D73C516FFB6E29264B1` |
| `round53_run.tcl` | `8BAD6305EB5CBFB491B1F8F595575C238847A68A8D77AED5675F3CCC543FFFE3` |

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
not meet 200 MHz internal setup timing. The B/C/D comparisons below use the
same flow and do not treat an OOC boundary hold number as internal hold.

## Top routed path families

The family tables were built from fresh routed DCPs, not from RTL names alone.
For each experiment the first 1,000 register-to-register setup paths were
exported with rank, startpoint, endpoint, slack, logic levels, logic delay, and
net delay. Rank 1,000 in A already has positive slack (`+0.026 ns`), so the A
table includes every one of its 854 failing internal endpoints. The B, C, and
D exports similarly contain all 359, 273, and 327 failing endpoints.

The representative critical-family table below uses the worst path in each
listed family for logic/net detail. TNS and endpoint count cover the whole
named family, not just that representative path. The raw top-1000 exports are
retained in the local implementation evidence directories; the Markdown table
is the review summary rather than a separate machine-readable grouped-family
artifact.

| Experiment / path family | Worst slack | TNS contribution | Endpoints | Logic levels | Logic delay | Net delay | Source fanout | Root cause | Candidate optimization |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| A: mode to block-beat D | -0.398 ns | -0.398 ns | 1 | 4 | 0.952 ns | 4.328 ns | 33 | generic mode/capacity/framing cone reaches the writer | B's state-local commit event |
| B: tag-output FIFO WE | -0.295 ns | -4.584 ns | 16 | 2 | 0.934 ns | 3.858 ns | 184 | high-fanout ZEROIZE plus FIFO pointer/write decode | isolate only after a same-edge scrub proof |
| C: ZEROIZE to prep-tag reset | -0.523 ns | -2.615 ns | 5 | 4 | 0.952 ns | 4.087 ns | 342 | ZEROIZE reconverges through queue/sequence/tag-length control | local same-edge reset/physical-replication experiment |
| D: field-last to input-mode D | -0.553 ns | -1.177 ns | 3 | 6 | 1.200 ns | 4.324 ns | 112 | combined control placement expands the field-last cone | keep D reverted; isolate accepted-DATA/field event before retrying B+C |

A's synthesis estimate has only 5 failing endpoints and `-0.623 ns` TNS,
whereas its routed netlist has 854 and `-95.962 ns`. This is not 849 new
functional paths. Before placement, estimated interconnect does not model the
final distance and locality of high-fanout mode/count/valid controls. Physical
synthesis then replicates control logic into 349 control sets, while the same
shallow signals drive hundreds of register CE and RAM WE endpoints. The A WNS
path is only four LUTs but is 82.0% routed-net delay. The exact A slack bins
are 79 endpoints below `-0.20 ns`, 588 in `[-0.20,-0.05)`, and 187 in
`[-0.05,0)`. Thus 775 of 854 are individually small violations above
`-0.20 ns`, but they accumulate into the large routed TNS/FEP. This is why
synthesis WNS alone was not used as a closure decision.

R53-A is control-plane dominated. Its worst path is
`input_field_mode_r[1] -> block_beat_15_r_reg_replica/D` at `-0.398 ns`.
Large endpoint groups include key-context FSM to round-key CE (260 paths,
`-30.864 ns`), AES-result FIFO/count control (200 paths, `-26.038 ns`),
keystream FIFO/RAM write control (172 paths, `-22.768 ns`), and plaintext-write
control (72 paths, `-5.365 ns`). None of these is an S-box or MixColumns data
round path.

R53-B removes the old mode-to-block-beat family structurally. Its routed
negative-path distribution is led by ciphertext FIFO control (156 paths,
`-16.031 ns`), tag-output FIFO control (16 paths, `-4.584 ns`), GHASH request
control (56 paths, `-3.328 ns`), plaintext-write control (34 paths,
`-2.262 ns`), and round-key CE control (67 paths, `-1.733 ns`). Its new WNS is
a two-LUT, route-dominated `zeroize -> tag-output LUTRAM WE` path at
`-0.295 ns`; 80.5% of that path delay is routing.

R53-C leaves the mode-to-block-beat topology present but moves it safely out
of the negative endpoint set (`+1.229 ns` routed). Its negative families are
ciphertext FIFO control (123 paths, `-14.028 ns`), round-key CE control
(62 paths, `-5.004 ns`), `prep_tag_bytes` reset (5 paths, `-2.615 ns`), result
control (5 paths, `-1.709 ns`), and keystream control (56 paths,
`-1.520 ns`). Its five tied WNS paths are
`zeroize_pulse -> prep_tag_bytes[0:4]/R` at `-0.523 ns`; the path is 81.1%
routing delay and the source fanout is 342.

R53-D proves that the two individually valid cuts are not physically
additive in this same-default-flow implementation comparison. Its WNS is
`field_last_r -> input_field_mode_r[0]/D` at `-0.553 ns`, six logic levels and
5.524 ns total delay (1.200 ns logic plus 4.324 ns route, 78.3% routing), with
source fanout 112. `field_last_r` accounts for 195 failing endpoints and
`-32.188 ns` (66.26%) of D's TNS. The 128-path
`field_last_r -> plain_write_data[*]/CE` subset alone contributes
`-24.972 ns` (51.41%). `result_valid_r -> ciphertext FIFO` contributes another
93 endpoints and `-10.888 ns` (22.41%). Those two subfamilies therefore
account for 73.82% of D's total TNS.

## Root-cause analysis

The measured limitation is the control plane, not AES arithmetic. In A the
generic ingress availability expression combines field mode, block/field
completion, GHASH-slot availability, and data-block capacity before reaching
the `block_beat_15_r` writer. That shared decode creates both depth and poor
placement locality. The visible ZEROIZE-sequence state was also reconstructed
combinationally from `zeroize_busy_r`, `zeroize_abort_count`, and a result-code
comparison, spreading count/result control into descriptor admission and
state logic.

B verifies the first diagnosis: removing only the generic mode cone from the
block-beat writer improves A routed WNS by `0.103 ns`, reduces TNS magnitude
by 69.3%, and removes 495 failing endpoints (58.0%). C verifies the second:
the predictive sequence token removes result-data-to-main-state paths and
reduces A TNS magnitude by 72.2% and FEP by 68.0%, although a high-fanout
ZEROIZE reset becomes its WNS. D exposes the next interaction: combining the
cuts reorganizes local control sets and placement enough that `field_last_r`
and `result_valid_r` become the dominant shared sources. The router reports no
global congestion failure, so this is local control/control-set placement and
routing, not a global utilization or routability problem.

## Patch 1 design: state-local block commit

R53-B is commit `0eba8f7acf4b5efa0ead3c72f8b4c26c97005042` and changes only
`aes_gcm_stream_core.v`. It replaces the writer enable for `block_beat_15_r`
with two local predecoded signals:

- `block_phase_capacity_local_w` selects the exact capacity authority for
  `ST_IV`, `ST_AAD`, and `ST_DATA`;
- `block_phase_commit_local_w` requires input valid, no ZEROIZE, a live crypto
  context, local capacity, and `s_axis_tlast == expected_record_last`.

The public `s_axis_tready`, `input_fire`, mode/state machines, byte storage,
GHASH producer, record framing, and all other writers are unchanged. The old
`input_field_block_w` and `block_phase_commit_w` become unused because this
patch created their only orphaned use, so they are removed. The resulting core
SHA-256 is
`216C1FECFA189C48FBFB559D9DCC3CF1A344BC7C98AD34391D86EA466F53C077`.

The capacity truth table is exact: IV96 is always ready; non-96 IV and AAD
need `gh_input_slot_free_r` only on a completing block; DATA needs
`data_block_capacity_r` only on a completing block. All other states are
excluded. `crypto_context_live_r` prevents a defensive abort/state-mode
collision from creating a later spurious writer event.

## Patch 2 design: predictive ZEROIZE sequence token

R53-C's RTL is commit `87649538aa24d62d52c9958edcbc05f724de0394`;
commit `51f82c04c4463f779cf2274cba93e288d5110221` completes its DCP hard-gate.
It adds one preserved `zeroize_sequence_active_r` FF and the following shared
events in `aes_gcm_stream_core.v`:

- `result_visible_fire_w = result_valid_r && m_axis_result_tready && !zeroize`;
- `zeroize_abort_result_fire_w`, the visible fire additionally qualified by
  result code `RESULT_ZEROIZE_ABORT`;
- `first_zeroize_event_w`, true only for the first ZEROIZE of a sequence;
- `zeroize_sequence_empty_done_w`, true only at an empty scrub completion;
- `zeroize_sequence_last_abort_done_w`, true only at the final visible
  ZEROIZE_ABORT handshake.

The token has reset > start > terminal-clear > hold priority. Descriptor
admission retains the existing `zeroize_abort_count == 0` gate and adds
`!zeroize_sequence_active_r`; the count remains the unmaterialized-abort
barrier, while the token also covers the final staged/stalled abort beat. The
same `zeroize_abort_result_fire_w` retires that beat and clears the terminal
token, preventing predicate drift. The resulting C core SHA-256 is
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`.

R53-D, commit `d131ceea5c34a585d408a231b4fdd6af4199e57c`, is the exact
non-overlapping union of B and C. Its core SHA-256 is
`EE5F39EF6066D85DED910DA354264B414881F0A6340518170C419A5A229CA713`.
After the D route exposed a larger `field_last_r` common cone and regressed
all three setup metrics relative to C, commit
`96398c1515d08bdb50ae6a9e9d065106c3da3e89` reverted only D's re-applied B
hunk. This preserves the complete D
experiment in history while restoring the final branch RTL to the
security-correct C core hash
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`,
as required by the Round53 stop rule.

## Cycle-equivalence reasoning

For B, once a descriptor enters a live block phase, the reachable
state/mode pairs are exactly IV96 or IVHASH with `ST_IV`, AAD with `ST_AAD`,
and DATA with `ST_DATA`. Those pairs enter and leave together. Given an
accepted input byte, the old `!early && !late` framing tests reduce exactly to
`s_axis_tlast == expected_record_last`. Substituting the state-specific
capacity table therefore changes only the Boolean implementation of the
`block_beat_15_r` enable, not an accepted input edge or its value. Reset and
`take_descriptor` remain higher-priority clears. ZEROIZE, framing abort,
unexpected AES-kind abort, and repeated ZEROIZE collisions have the same
next-state result.

For C, at each sampled cycle boundary:

```text
zeroize_sequence_active_r
  == zeroize_busy_r
  || (zeroize_abort_count != 0)
  || (result_valid_r && result_data_r == RESULT_ZEROIZE_ABORT)
```

The first ZEROIZE snapshots exactly the existing owed-result cardinality and
sets the token. Repeated ZEROIZE does not resnapshot it. A sequence with no
owed results clears on scrub index 15; a nonempty sequence clears on the final
visible abort-result fire, after the counter has already reached zero. A
stalled final abort keeps both result and token stable. Descriptor admission
can resume on the edge after that public handshake, exactly when the sequence
is no longer externally observable. The three-bit abort count cannot overflow:
the disjoint architectural buckets are bounded by descriptor FIFO 2, active
record 1, tag queue 2, tag producer 1, and one detached/pending encryption
completion, for a maximum of 7.

D is the byte-exact union of the two independent source hunks. Their writers,
priority chains, and observer sets do not overlap. All ordinary/public cycle
signatures, six throughput counts, and non-collision directed regressions
remain identical to A. The direct-core repeated-ZEROIZE collision is
intentionally corrected: A/B reproduce invisible retirement and early
admission, while C/D retain one visible abort and hold admission through it.

## ZEROIZE security reasoning

The A/B core used an internal `valid && ready && code==0x13` retirement test
while public result valid was masked by `!zeroize`. At the AXI top,
`core_result_tready` is also masked during the same pulse, so the existing top
does not expose a loss. A direct-core environment can nevertheless assert
READY and repeated ZEROIZE together and retire an externally invisible abort
beat. The new direct-core test reproduces that A/B behavior and C/D fixes it:
retirement now requires the single shared visible-fire predicate containing
`!zeroize`.

The token also closes a direct-core admission window. With only the old count
gate, the last abort credit has already been decremented when its public beat
is staged, so a re-keyed core could take a descriptor while that beat was
stalled. Keeping both `zeroize_abort_count == 0` and
`!zeroize_sequence_active_r` blocks admission through the final visible
handshake. Public tests verify exact abort cardinality, repeated ZEROIZE during
scrub and result stall, no stale data/tag output, and post-sequence recovery.
Key-mid-expansion and non-96-IV GHASH ZEROIZE tests verify that key/GHASH state
does not escape the existing synchronous scrub priorities.

## Synthesis DCP hard-gate

The hard gate is fail-closed: object sets must be nonempty before a zero-path
claim is accepted. It checks source identity, primitive type and pins, expected
family removal and replacement paths, replacement logic-depth ceilings,
multiple-driven nets, CDC, latches, timing exceptions, DRC/methodology
Error/Critical Warning, route legality, all check-timing categories, and
internal setup/hold metrics.

| Structural assertion | A | B | C | D |
|---|---|---|---|---|
| mode registers to `block_beat_15_r/D` | present, critical | 0 paths | present, routed `+1.229 ns` | 0 paths |
| state/rec-IV/GH-slot/data-capacity replacement paths | n/a | nonempty | n/a | nonempty |
| `result_data_r` to main-state D | present | present | 0 paths | 0 paths |
| `zeroize_sequence_active_r` | absent | absent | one preserved FDRE | one preserved FDRE |
| abort-count to main state | present | present | four paths retained | four paths retained |
| zseq to main state | absent | absent | four paths | four paths |
| descriptor idle token | exact FDRE | exact FDRE | exact FDRE | exact FDRE |

In D the descriptor token is exactly one `FDRE`, `INIT=0`, `KEEP` and
`DONT_TOUCH`; D is VCC, R is the full reset/ZEROIZE/key-commit/take clear cone,
and CE is the H/ENC/DEC/ABORT retire set cone. Zseq is exactly one preserved
`FDRE`, `INIT=0`, clocked by `aclk`. D routed structural slacks are
state/rec-IV/GH-slot/data-capacity to block-beat `-0.264/+0.216/+0.654/+0.533
ns`, abort-count to main state `-0.178 ns`, and zseq to main state `+0.103 ns`.
The original topology checks pass, but the enhanced depth gate rejects D:
its state and rec-IV replacement paths are four LUT levels, equal to the A
mode path rather than strictly shallower. B remains within three levels for
state/rec-IV and two for GH-slot/data-capacity. This enhanced D failure is an
additional reason the combined experiment is reverted; setup closure also
does not pass.

The enhanced gate was re-executed read-only on all A/B/C/D synthesized DCPs
and on the retained C and diagnostic D routed DCPs. A/B/C synthesis and C
routing complete the enhanced audit; D synthesis/routing deliberately stop at
the replacement-depth failure after their earlier multiple-driver and CDC
checks pass. The original stage gates and reports supply D's methodology/DRC/
route-integrity evidence; no claim is made that every stage passed the same
enhanced script revision. The completed enhanced runs report zero
multiple-driven nets, `report_cdc` “All paths are Safely Timed,” zero
methodology Error/Critical Warning where reached, and the expected zero timing
exceptions.
For C/D zseq CE is VCC, R is a single LUT1 whose sole startpoint is `aresetn`,
S is absent, C is `aclk`, and D is one LUT with all required sequence/result/
count startpoint classes. A, B, and C pass the enhanced synthesis audit; D is
expectedly rejected at its block replacement-depth check. C routed passes all
structural/netlist checks with `setup_closed=0`; D routed is similarly rejected
before any promotion claim.

## Routed timing comparison

All values below are internal register-to-register timing in nanoseconds.

| Experiment | Synth WNS | Synth TNS | Synth FEP | Route WNS | Route TNS | Route FEP | Route WHS | Route THS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R53-A baseline | -0.168 | -0.623 | 5 | -0.398 | -95.962 | 854 | +0.052 | 0 |
| R53-B block-local | -0.347 | -52.441 | 156 | -0.295 | -29.469 | 359 | +0.053 | 0 |
| R53-C zseq | -0.497 | -2.225 | 10 | -0.523 | -26.673 | 273 | +0.051 | 0 |
| R53-D combined | -0.263 | -2.650 | 13 | -0.553 | -48.576 | 327 | +0.050 | 0 |

B has the best routed WNS. C has the best routed TNS and FEP. Relative to A,
D still reduces TNS magnitude by 49.4% and FEP by 61.7%, but its WNS is
`0.155 ns` worse. Relative to C, D is worse in all three setup metrics: WNS by
`0.030 ns`, TNS magnitude by `21.903 ns` (82.1%), and FEP by 54. This is the
measured negative physical interaction that prevents treating B+C as an
additive timing solution.

Fresh DCP SHA-256 values are recorded in `round53_results.csv`. All four routes
are legal, with zero unrouted/routing-error nets and zero DRC Error/Critical
Warning. The negative overall hold values belong to unplaced OOC boundary
ports; every routed internal hold report has zero failing endpoints.

## Resource comparison

Routed resources use the same part and implementation flow.

| Experiment | LUT | Logic LUT | LUTRAM | FF | RAMB18 | DSP | Control sets | Routable nets |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| R53-A | 8603 | 7639 | 964 | 7299 | 10 | 0 | 349 | 13317 |
| R53-B | 8640 | 7676 | 964 | 7309 | 10 | 0 | 332 | 13385 |
| R53-C | 8586 | 7622 | 964 | 7296 | 10 | 0 | 309 | 13269 |
| R53-D | 8641 | 7677 | 964 | 7298 | 10 | 0 | 359 | 13334 |

BRAM and DSP use are unchanged. D has 359 control sets, versus 309 in C and a
naive B+C-A estimate of 292. Physical synthesis added 251 replicated control
structures and left 1,014 unused register sites in D. This supports the local
placement/control-set reorganization diagnosis; it does not indicate global
congestion, because routing completed cleanly and overall utilization remains
modest.

## Regression results

Every experiment was compiled and elaborated fresh with Vivado 2021.1's
official `glbl` model and `unisims_ver`. No hierarchy force, random test, or
cycle tolerance was used for the production regressions.

| Regression | A | B | C | D |
|---|---:|---:|---:|---:|
| AXI smoke | 8364 | 8364 | 8364 | 8364 |
| AES-128 enc/dec | 18920 / 19139 | exact | exact | exact |
| AES-192 enc/dec | 19520 / 19739 | exact | exact | exact |
| AES-256 enc/dec | 20120 / 20339 | exact | exact | exact |
| Round48 boundary | 364 / 722 | exact | exact | exact |
| Round49 residual | 546 / 1002 / 1568 | exact | exact | exact |
| public ZEROIZE | idle 0, accepted 2, abort 2 | exact | exact | exact |
| key mid-expansion ZEROIZE | recovery 101 | exact | exact | exact |
| non-96-IV GHASH ZEROIZE | abort 1, stale 0 | exact | exact | exact |
| descriptor-push + ZEROIZE collision | not separately rerun | attempt 1; prior accepted 2; aborts 2 at cycles 19/21; extras 0 | exact | exact |
| registered GHASH-slot stall | not separately rerun | 1 cycle, 162 to 163; 17 input fires; 2 commits | exact | exact |
| AES/data-capacity stall | not separately rerun | 22 cycles total, 21 AES-unavailable, 290 to 312 | exact | exact |
| NIST525 | 525/525, 145808 | exact | exact | exact |
| NIST5255 | 5255/5255, 1615588 | exact | exact | exact |

The minimum measured throughput remains `1.006932 Gbit/s` (AES-256 decrypt).
A/B direct-core tests intentionally reproduce the pre-patch invisible-fire
and early-admission signatures. C/D pass with one visible abort fire, admission
held through the final abort, and admission enabled on the following edge. The
new collision case proves that a third otherwise-admissible descriptor is not
accepted on the ZEROIZE edge while the two pre-existing records still produce
exactly two aborts. The capacity cases hold public VALID/DATA/TLAST stable and
show identical B/C/D stall cycles, one eventual handshake, and terminal order
`DATA TLAST -> TAG TLAST -> RESULT`.

## Remaining critical families

D's top routed setup paths are now:

1. `field_last_r -> input_field_mode_r[0]/D`, `-0.553 ns`, six levels;
2. `field_last_r -> tag_input_active`, `-0.476 ns`;
3. `field_last_r -> state[3]/D`, `-0.462 ns`;
4. a ZEROIZE replica to `ctr_issue_pending`, `-0.455 ns`;
5. `field_last_r -> state[0]/D`, `-0.410 ns`;
6. abort-count control to `prep_tag_bytes/R`, approximately `-0.408 ns`;
7. the 128-path `field_last_r -> plain_write_data[*]/CE` family;
8. the 93-path `result_valid_r -> ciphertext FIFO` family.

The old S-box/MixColumns and previous raw GH-valid/public-boundary families are
not the active closure limit. The new limiting paths are again wide shared
control and RAM/register enable/reset cones. D passes routing, DRC, methodology
integrity, and internal hold, but has 327 internal setup violations.

## Round54 recommendation

Round54 should start from the retained, security-correct C source and treat the
B structural cut as an independent experiment rather than assuming D's
placement is additive. The next controlled experiments must follow the routed
source actually being retained:

1. decode and arc-mask C's complete
   `zeroize_pulse -> prep_tag_bytes[0:4]/R` cone and the other ZEROIZE-sourced
   endpoints; this source accounts for 134 C failures and `-17.180 ns`, 64.41%
   of C TNS;
2. test only a same-edge, security-equivalent local reset/physical-replication
   structure for that cone, with an explicit DCP gate proving that all direct
   key, GHASH, plaintext-bank, tag, and result scrub endpoints retain the
   original ZEROIZE edge and that no registered delay was introduced;
3. rerun C with the same recorded default flow and require WNS, TNS, and FEP
   to improve together; before a robustness sweep or production claim, add
   and record an explicit numeric seed so later runs are auditable;
4. keep B separate. If it is reintroduced later, first use the D evidence to
   decode and isolate `field_last_r -> plain_write_data[*]/CE` (128 endpoints,
   `-24.972 ns`) and its mode/state observers; D proves that stacking B without
   this physical check creates a larger control cone;
5. only after that family is controlled should the second-place
   `result_valid_r -> ciphertext FIFO` family be considered. Do not introduce
   Pblocks, PartPins, timing exceptions, or speculative AES datapath changes.

This recommendation is deliberately not an implementation. Round53 evidence
shows that merely stacking two good Boolean cuts can worsen local placement;
the next patch needs its own isolated A/B comparison and post-synth hard-gate.

## Closure decision

**Round53 internal timing: FAIL.** The best routed WNS is B at `-0.295 ns`;
the security-correct C and combined D experiments remain at `-0.523 ns` and
`-0.553 ns`. All routes are legal and internal hold is clean, but none has
nonnegative routed internal setup WNS/TNS/FEP.

**PartPin signoff: NO.** Per the experiment contract, formal PartPin/I/O
signoff begins only after internal setup closure. The current OOC boundary hold
violations are recorded but are not being hidden with constraints or pin
placement. No Round53 result may be promoted as a 200 MHz timing signoff.
The retained source is C-only at revert commit
`96398c1515d08bdb50ae6a9e9d065106c3da3e89`; D remains an audited
diagnostic checkpoint and is not the promoted RTL candidate.
