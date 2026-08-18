# Round53 zero-cycle equivalence audit

## Audit result and scope

**Result: Patch B reachable-state zero-cycle equivalence PASS; Patch C/D
security-transition audit PASS with one intentional A/B collision correction.**

R53-D is an audited experiment, not the retained branch candidate. Its routed
implementation regressed WNS, TNS, and FEP relative to C and exposed a larger
`field_last_r` common cone. Commit
`96398c1515d08bdb50ae6a9e9d065106c3da3e89` therefore reverts only D's
re-applied B hunk while preserving D in history; the final RTL is byte-identical
to the security-correct C core at SHA-256
`EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E`.

This is a review of the two Round53 structural changes in
<code>aes_gcm_stream_core.v</code>. It is not a formal-equivalence run and it
does not claim 200 MHz timing closure. One C/D behavior is intentionally not
equivalent to A/B: C fixes an A/B result-handshake defect in which a
<code>ZEROIZE_ABORT</code> could be retired internally while its public VALID
was masked by ZEROIZE. That correction is isolated and audited in
<code>round53_security_audit.md</code>.

The implementation conclusion at the audited D checkpoint is:

~~~text
Round53 internal timing: FAIL
Eligible for PartPin signoff: NO
~~~

Routed D has internal setup WNS <code>-0.553 ns</code>, TNS
<code>-48.576 ns</code>, and 327 failing endpoints. Internal routed hold is
clean at WHS <code>+0.050 ns</code>, THS <code>0</code>, and zero hold
endpoints.

## Locked experiment identities

All source comparisons use committed Git blobs, not the current working-copy
text.

| Experiment | Commit | Core Git blob | Core SHA-256 | Intended source delta |
|---|---|---|---|---|
| R53-A | <code>dfb010787b93f211f257ebb134d4f836dbdb268e</code> | <code>212820a9457cd1000195d52893cb1d5015d67665</code> | <code>BF73AC638EE1014897E263C5012E258F43A4803859EF4DB6134BB080D9857AD3</code> | Round52 baseline |
| R53-B | <code>0eba8f7acf4b5efa0ead3c72f8b4c26c97005042</code> | <code>4f1c013e2c58ba913f9c449e5f56226d7611ea1c</code> | <code>216C1FECFA189C48FBFB559D9DCC3CF1A344BC7C98AD34391D86EA466F53C077</code> | block-phase local commit only |
| R53-C | <code>87649538aa24d62d52c9958edcbc05f724de0394</code> | <code>72da4dcc0f589c5b0216deeed3349cfb37c3aac8</code> | <code>EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E</code> | predictive ZEROIZE sequence token and visible-fire fix only |
| R53-D | <code>d131ceea5c34a585d408a231b4fdd6af4199e57c</code> | <code>d553ef0bae5a63086ebf9a3e8c9633fbed30df6d</code> | <code>EE5F39EF6066D85DED910DA354264B414881F0A6340518170C419A5A229CA713</code> | exact B plus C union |

The branch is linear and temporarily reverted B before creating C. Experiment
identity is therefore defined by the committed core blob, not by assuming
that B is C's parent.

### Exact D union proof

The two edits touch disjoint base ranges. Four independent comparisons agree:

| Comparison | Added | Deleted | Exact changed-line relation |
|---|---:|---:|---|
| A to B | 13 | 6 | identical to C to D |
| C to D | 13 | 6 | identical to A to B |
| A to C | 32 | 9 | identical to B to D |
| B to D | 32 | 9 | identical to A to C |
| A to D | 45 | 15 | arithmetic and byte-level union |

A memory-only three-way application of A-to-B and A-to-C produced 98,552
bytes, Git blob <code>d553ef0bae5a63086ebf9a3e8c9633fbed30df6d</code>,
and SHA-256
<code>EE5F39EF6066D85DED910DA354264B414881F0A6340518170C419A5A229CA713</code>.
All three values match committed D exactly. There were no overlapping edit
ranges. A, B, C, and D are LF-only, end with a newline, and have no CR, NUL,
or trailing-whitespace lines. Cross-diff and commit
<code>git diff --check</code> checks passed.

D's own commit changes only
<code>engrenring/rtl/source/stream_core/aes_gcm_stream_core.v</code>. Across
A-to-D and C-to-D, that is also the only file changed under
<code>engrenring/rtl/source</code>. Repository-wide C-to-D additionally
contains the preceding Tcl clock-pin hard-gate correction at commit
<code>51f82c04c4463f779cf2274cba93e288d5110221</code>; it is not an extra D
RTL delta.

## Patch B: block-phase local commit

### What changed

Only the writer enable for <code>block_beat_15_r</code> changed. Public
<code>s_axis_tready</code>, <code>input_fire</code>, block payload assembly,
GHASH writes, AES/data writes, field completion, record completion, TLAST
abort generation, and the writer's next-data equation were not changed.

The old enable was:

~~~text
old_commit =
    input_fire
  & input_field_normal
  & block_field_mode
  & !early_tlast
  & !late_tlast
~~~

The new enable is:

~~~text
new_commit =
    s_axis_tvalid
  & !zeroize
  & crypto_context_live
  & block_phase_capacity_local
  & (s_axis_tlast == expected_record_last)
~~~

On every accepted beat, the old pair
<code>!early_tlast && !late_tlast</code> is exactly the equality
<code>s_axis_tlast == expected_record_last</code>. If no input handshake is
possible, old commit is zero; the state-local capacity term makes new commit
zero under the same reachable conditions.

### Reachable-state invariant

The state and field-mode registers change on the same clock edges:

| Main state | Reachable block field mode | Old input capacity | New local capacity |
|---|---|---|---|
| <code>ST_IV</code>, 96-bit IV | <code>IFM_IV96</code> | 1 | 1 because <code>rec_iv_is_96_r</code> is 1 |
| <code>ST_IV</code>, non-96-bit IV | <code>IFM_IVHASH</code> | <code>!completing_block_byte || gh_input_slot_free_r</code> | same |
| <code>ST_AAD</code> | <code>IFM_AAD</code> | <code>!completing_block_byte || gh_input_slot_free_r</code> | same |
| <code>ST_DATA</code> | <code>IFM_DATA</code> | <code>!completing_block_byte || data_block_capacity_r</code> | same |
| descriptor, idle, tag, drain, result, or abort states | no legal block mode | block-mode qualifier is 0 | no IV/AAD/DATA state term, so 0 |

Descriptor capture initializes both sides of this invariant. The
<code>ST_DESC_TOTAL</code> to <code>ST_DESC_START</code> to
<code>ST_IV</code> transitions update <code>input_field_mode_r</code> from
NONE to START to IV96/IVHASH on the matching edges. IV, AAD, DATA, TAG, drain,
abort, ZEROIZE, and non-96-bit J0 transitions likewise update state and mode
without a cycle skew. In a reachable IV/AAD/DATA state,
<code>crypto_context_live_r</code> is one; abort and ZEROIZE invalidate it.

Consequently, for every reachable cycle:

~~~text
old_commit == new_commit
~~~

This is a reachable-state proof. It does not assert equivalence for arbitrary
corrupt encodings of state, field mode, or the registered capacity mirrors.

### Boundary truth table

| Case | Capacity/legality result | Old versus new |
|---|---|---|
| IV = 96 bits | IV never waits for a GHASH input slot | equal |
| IV != 96 bits | a completing IV block waits for <code>gh_input_slot_free_r</code> | equal |
| Empty AAD or empty DATA | state machine skips the absent field; no beat commits | equal |
| Partial, non-final block byte | <code>completing_block_byte=0</code>; capacity term is 1 | equal |
| Full block or partial field-last block | appropriate GHASH or data capacity is required | equal |
| DATA encrypt/decrypt | both use the registered <code>data_block_capacity_r</code>; downstream data ownership is unchanged | equal |
| Correct record TLAST | TLAST equals the registered expected-last bit | both commit |
| Early TLAST | TLAST differs from expected-last | both suppress the writer and take the existing abort path |
| Missing/late TLAST | TLAST differs from expected-last | both suppress the writer and take the existing drain/abort path |
| GHASH slot unavailable on a completing IVHASH/AAD block | capacity is zero | both hold |
| AES/data capacity unavailable on a completing DATA block | capacity is zero | both hold |
| Input VALID low | event is zero | equal |
| Resource backpressure | public READY remains the original READY; local capacity mirrors the same block-boundary condition | equal |
| Output backpressure | only the existing registered data-capacity mirror can affect DATA; no new public handshake is introduced | equal |
| ZEROIZE collision | old READY is masked; new event has an explicit <code>!zeroize</code> | both suppress |
| Abort/queue-clear collision | TLAST error, non-block state, or dead crypto context suppresses the local writer | equal on reachable states |

When the enable is true, both versions execute the same assignment:

~~~text
block_beat_15_r <= !field_last_r && (block_byte_index == 14)
~~~

When it is false, both hold the register. Reset and
<code>take_descriptor</code> priority are unchanged. There is no added
pipeline register and no extra observable cycle.

## Patch C: sequence token and the equivalence boundary

For cycles outside an active ZEROIZE sequence,
<code>zeroize_sequence_active_r=0</code> and
<code>zeroize_abort_count=0</code>; descriptor admission is therefore
unchanged. During a sequence, the new token deliberately prevents admission
until the sequence has actually completed.

For a non-empty sequence, the final abort result is visibly handshaken on one
edge and a queued descriptor may be admitted on the following edge. No
pipeline stage was added to ordinary descriptor, AES, GHASH, tag, data, or
result traffic. The direct-core test proves:

~~~text
held_until_abort=1
admitted_next_edge=1
~~~

A/B could instead lose the final abort and admit early when ZEROIZE coincided
with READY while public result VALID was masked. C/D correct that behavior;
they are intentionally not equivalent to the defective A/B observation at
that collision. The detailed cardinality and edge-priority proof is in the
security audit.

## Cycle-exact functional evidence

All runs used Vivado/XSim 2021.1 with the official <code>glbl</code> model and
<code>-L unisims_ver</code> in isolated work directories.

| Regression | A | B | C | D |
|---|---|---|---|---|
| compile/elaboration | PASS | PASS | PASS | PASS |
| smoke | 8,364 cycles | 8,364 | 8,364 | 8,364 |
| AES-128 enc/dec | 18,920 / 19,139 | exact | exact | exact |
| AES-192 enc/dec | 19,520 / 19,739 | exact | exact | exact |
| AES-256 enc/dec | 20,120 / 20,339 | exact | exact | exact |
| throughput floor | 1.006932 Gbit/s | exact | exact | exact |
| Round48 boundary | 364 / 722 cycles | exact | exact | exact |
| Round49 residual | 546 / 1,002 / 1,568 cycles | exact | exact | exact |
| NIST525 | 525/525, 145,808 cycles | exact | exact | exact |
| NIST5255 | 5,255/5,255, 1,615,588 cycles | exact | exact | exact |
| public ZEROIZE | promoted baseline PASS: idle 0, accepted 2, aborts 2 | same | same | same |
| key-expansion ZEROIZE | promoted baseline PASS: recovery 101, round keys scrubbed | same | same | same |
| non-96-bit IV GHASH ZEROIZE | promoted baseline PASS: abort 1, stale outputs 0 | same | same | same |
| direct visible-fire/admission test | expected-loss negative baseline PASS: visible 0, early admission 1 | same expected A/B loss reproduced with the negative-test plusarg | visible fire 1; admission held then next edge | same |
| descriptor-push + ZEROIZE | not separately rerun | attempt 1; accepted before 2; aborts 2 at cycles 19/21; extra 0 | exact | exact |
| registered GHASH-slot stall | not separately rerun | 1 cycle, 162 to 163; 17 input fires; 2 commits | exact | exact |
| AES/data-capacity stall | not separately rerun | 22 cycles total, 21 AES unavailable, 290 to 312 | exact | exact |

The promoted A baseline and B's negative direct-core run record the historical
defect as an expected negative-test PASS. B's only A delta is the unrelated
block writer, and it reproduced the same A/B behavior:

~~~text
ROUND53_CORE_BASELINE_LOSS_REPRODUCED result=13 visible_fires=0
ROUND53_ZSEQ_BASELINE_EARLY_ADMISSION_REPRODUCED active_before_abort=1
~~~

C and D ran the same test in normal mode, without
<code>EXPECT_BASELINE_LOSS</code>, and both reported one visible abort plus
correct next-edge admission.

The gap-closure testbenches are tracked with SHA-256 identities
<code>518939816B93B26DC28CF152AEA9A768120116E2B025E5C11202B5EE743B8CE9</code>
(direct-core ZEROIZE/collision) and
<code>3FC22A028A92172E6E028F992C1B1D2D7D8F3CC0259A60147E765008C718972D</code>
(GHASH/AES capacity stalls). Hierarchy is used only to classify the intended
registered capacity cause; ready/valid stability, cardinality, TLAST, and
output ordering are checked at module interfaces.

The principal D functional logs have these SHA-256 identities:

| D log | SHA-256 |
|---|---|
| <code>smoke_r53d.log</code> | <code>9377DE163B3B3E7AD40742D771593A28AA74CF95BC034FF6C978F0E5978A0DC8</code> |
| <code>throughput_r53d.log</code> | <code>850A67555DF70D20233DD4A36F6EEE44F49DE56874519B5C86EC02C2E95246BB</code> |
| <code>boundary_r53d.log</code> | <code>F334723B5DE757C7017A90B5B1ADCE42BB11101881B0630E8DF99740E798E92C</code> |
| <code>residual_r53d.log</code> | <code>28A5160B9E3C69E6870701154FFD99ACFBF26BA40D10FB752C33923C7DE16BE5</code> |
| <code>core_zseq_r53d.log</code> | <code>9265FD03CA5BB9661BDB7C424E307D13735C15462E25DBCDED1CC1F8DBEFC60D</code> |
| <code>core_collision_d_final.log</code> | <code>D9B884AD7C6575EB03CF3CA8999413F154B0B54A1EC084F4D0A00ABE7E5243B4</code> |
| <code>block_stalls_d_final.log</code> | <code>182B177696BC4699C702E6A6EA46B66B8FFF077B4CFC83495B393499C1E58988</code> |
| <code>nist525_r53d.log</code> | <code>27E59685B87AC86FDC2F1D9EE5150B7AB619F143A4F02638FFE7E17039BF7EF8</code> |
| <code>nist5255_r53d.log</code> | <code>A72617F32ADF9333EC02AE58601ED9812F2305468A3E7879CEB61C2EF295498E</code> |

## Synthesized/implemented structural gates

The locked D checkpoints are:

| Stage | Bytes | SHA-256 |
|---|---:|---|
| synthesis | 2,793,499 | <code>73F6C2DF464DDCA9599A6E455E19566C2118826386687913271C8C97F64BBB19</code> |
| placed | 4,638,410 | <code>1CCFC3DEF510BF3EC7C3E37EBA1351D0254CFFB34BE98FD5D8C634F2FA2D3DD5</code> |
| routed | 6,127,601 | <code>A9C845C2774D339B899B8A7841C5F73E235B579AF510B89A45DA7B47D1A28252</code> |

The original fail-closed gate at the D synth, placed, and routed stages
verified the following structural identities:

- one 5.000 ns <code>aclk</code> and zero false-path, clock-group,
  multicycle, max-delay, max-delay-DPO, and min-delay exceptions;
- all 12 parsed <code>check_timing</code> categories at zero and zero
  inferred latches;
- zero mode-register paths to <code>block_beat_15_r</code> in D;
- nonempty state, IV-type, GHASH-slot, and data-capacity path identities to
  <code>block_beat_15_r</code>;
- one zseq <code>FDRE</code>, INIT 0, KEEP enabled, equivalent-register
  removal disabled, a nonempty D driver, and clock pin on <code>aclk</code>;
- zseq Q reaches the main-state/admission cone, while
  <code>result_data_r</code> has zero direct paths to that cone;
- the required <code>zeroize_abort_count</code> admission path remains;
- DRC has zero errors/critical warnings and routed nets are
  13,334/13,334 with zero routing errors.

The routed structural family evidence is especially important:

| Family | Routed D result |
|---|---|
| mode to block-beat | zero paths |
| state to block-beat | one path, slack <code>-0.264 ns</code> |
| result data to main state | zero paths |
| zseq Q to main state | four paths, worst slack <code>+0.103 ns</code> |
| abort count to main state | four paths, two negative, worst <code>-0.178 ns</code> |

Thus both requested structural identities survived implementation. A later
hardening pass added explicit multiple-driver, CDC, methodology, primitive-pin,
and replacement-depth checks. A, B, and C pass the enhanced synthesis audit;
D is intentionally rejected because its state and rec-IV replacement paths
remain four LUT levels, equal to the A common cone rather than strictly
shallower. The replacement state path and preserved abort-count gate remain
timing work; their presence does not invalidate the Boolean cycle proof, but
the equal-depth result prevents D from being promoted.

## Limitations and final determination

- No sequential formal-equivalence engine or exhaustive assertion proof was
  run. The algebra is conditioned on the documented reachable state/mode and
  queue invariants and is backed by cycle-exact simulation.
- NIST525 and NIST5255 are limited prefixes of
  <code>gcmEncryptExtIV128.rsp</code>. Their logs show zero vectors from the
  AES-192, AES-256, and decrypt response files. They are not the full 47,250
  vector corpus.
- Directed ZEROIZE tests cover the concrete collisions documented here, but
  do not constitute a cryptographic side-channel, fault-injection, or formal
  information-flow certification.
- D passes the original structural-identity gate but fails the enhanced
  replacement-depth gate. Independently, D reports
  <code>setup_closed=0</code> at synthesis and routing.
- The placed D checkpoint has an internal hold miss (WHS
  <code>-0.095 ns</code>, THS <code>-0.235 ns</code>, 8 endpoints). The flow
  continued only to collect the mandatory routed evidence; this is an
  additional stop/revert signal, not a contract PASS. Routed hold is clean.
- No PartPin or final I/O signoff has been performed.

Within those limits, R53-B is a zero-cycle block-writer transformation, R53-C
provides the intended predictive sequence token plus a necessary visible-fire
security correction, and R53-D is their exact source union with all locked D
functional signatures preserved. The stop-condition revert retains C, not D,
as the final source for subsequent timing work.
