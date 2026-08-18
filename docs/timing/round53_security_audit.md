# Round53 ZEROIZE security audit

## Security result and claim boundary

**Result: PASS for the retained R53-C ZEROIZE invariants and directed security
regressions; the same C hunk is independently PASS in the audited R53-D
experiment.**

The audited combined experiment is commit
<code>d131ceea5c34a585d408a231b4fdd6af4199e57c</code>, core SHA-256
<code>EE5F39EF6066D85DED910DA354264B414881F0A6340518170C419A5A229CA713</code>.
The ZEROIZE-only experiment is C at
<code>87649538aa24d62d52c9958edcbc05f724de0394</code>, core SHA-256
<code>EB905D71345AA93E1D64C8B47D0BEEF50BF1CFF8FE77C3E80594D610BF7B0E5E</code>.
D contains the exact C change without modification. Because D's routed
timing regressed all setup metrics relative to C and exposed a larger common
cone, stop-condition commit
<code>96398c1515d08bdb50ae6a9e9d065106c3da3e89</code> restores C as the retained
branch source while preserving the D experiment and this audit in history.

PASS here means that the source transition equations, synthesized primitive
identity/connectivity gates, and listed simulations agree. It is not formal
security certification, and it is not a timing-closure claim.

## Public handshake model

The externally observable result handshake is:

~~~text
result_visible_fire =
    result_valid_r
  & m_axis_result_tready
  & !zeroize
~~~

This follows directly from:

~~~text
m_axis_result_tvalid = result_valid_r & !zeroize
~~~

An internal READY while ZEROIZE is high is therefore not a public transfer.
All retirement, accepted-result accounting, and final-abort sequence
completion must use the visible-fire definition, not merely the internal
<code>result_valid_r && ready</code> pair.

## A/B visible-fire defect and the C/D correction

### Defect

A/B cleared a staged <code>ZEROIZE_ABORT</code> when
<code>result_valid_r && m_axis_result_tready</code> was true, even if a
repeated ZEROIZE simultaneously forced public
<code>m_axis_result_tvalid</code> low. The beat disappeared internally without
ever being observable. Once the result register cleared, the old combinational
sequence-active expression also fell, allowing descriptor admission too
early.

The B negative regression, whose only A delta is unrelated block-writer logic,
reproduced both consequences:

~~~text
ROUND53_CORE_BASELINE_LOSS_REPRODUCED result=13 visible_fires=0
ROUND53_ZSEQ_BASELINE_EARLY_ADMISSION_REPRODUCED active_before_abort=1
~~~

### Fix

C/D define <code>result_visible_fire_w</code> with the explicit
<code>!zeroize</code> term. A ZEROIZE_ABORT-specific derivative,
<code>zeroize_abort_result_fire_w</code>, is used both to retire the internal
result register and to clear the sequence token after the final abort.
General accepted-result accounting is aliased to the same visible event.

The critical collision is now:

| Edge | Conditions | Public observation | Required C/D action |
|---|---|---|---|
| stage | abort count is nonzero and result register is empty | no transfer yet | stage one 0x13 and decrement the pending-to-stage count |
| stalled | 0x13 valid internally, READY=0 | VALID remains asserted if ZEROIZE=0 | hold data, valid, count, and token |
| repeated ZEROIZE collision | internal valid=1, READY=1, ZEROIZE=1 | public VALID=0, so no fire | do not retire; hold token and the 0x13 |
| later visible fire | internal valid=1, READY=1, ZEROIZE=0 | exactly one 0x13 transfer | retire result and, if it is last, clear token |
| next edge | token=0 and count=0 | queued work may resume | admit descriptor without an extra bubble |

C and D ran the direct test in normal mode and each reported:

~~~text
ROUND53_CORE_ZEROIZE_PASS result=13 visible_fires=1
ROUND53_ZSEQ_ADMISSION_PASS held_until_abort=1 admitted_next_edge=1
~~~

This is a correction of an invalid A/B observation, not a new pipeline stage.

## Predictive sequence-token transition proof

The token means:

> A ZEROIZE sequence has started but has not reached its architecturally safe
> completion edge; a repeated ZEROIZE is not a first command and normal
> descriptor admission is forbidden.

Its source equations are:

~~~text
first_zeroize_event =
    zeroize & !zeroize_sequence_active_r

empty_done =
    zeroize_sequence_active_r
  & zeroize_busy_r
  & (zeroize_index == 15)
  & (zeroize_abort_count == 0)

last_abort_done =
    zeroize_sequence_active_r
  & zeroize_abort_result_fire_w
  & (zeroize_abort_count == 0)
~~~

The sequential priority is reset, then first-event set, then the two clear
events, otherwise hold.

| Current condition | Next token | Reason |
|---|---:|---|
| reset asserted | 0 | deterministic inactive state |
| first ZEROIZE while token=0 | 1 | sequence becomes active on the command edge |
| scrub busy, index below 15 | hold 1 | sequence has not finished |
| repeated ZEROIZE while token=1 | hold 1 | <code>first_zeroize_event_w</code> is false, so abort count is not recaptured |
| result output stalled | hold 1 | no visible-fire clear event |
| aborts still waiting to be staged | hold 1 | count is nonzero |
| scrub reaches index 15 with count=0 | 0 | empty sequence is complete |
| last staged abort visibly handshakes with count=0 | 0 | non-empty sequence is complete |
| RESET and any other condition | 0 | reset has highest priority |
| first-event and a stale clear expression | 1 | set has priority over clear |

A last-abort visible fire cannot coincide with ZEROIZE because visible fire
contains <code>!zeroize</code>. For the supported command-pulse interface,
repeated pulses during scrub or result stall therefore cannot prematurely
clear or retrigger the sequence.

## Abort cardinality proof

### First-command snapshot

Only <code>first_zeroize_event_w</code> captures
<code>zeroize_abort_count</code>. The snapshot is:

~~~text
desc_count
+ active_record
+ tagq_count
+ tag_prod_valid
+ detached_result_pending
+ enc_result_pending
~~~

These terms are physical representations of accepted descriptors that have
not yet completed their public result contract:

| Term | Descriptor class represented |
|---|---|
| <code>desc_count</code> | accepted descriptors still in the depth-two descriptor FIFO |
| <code>active_record</code> | the one descriptor owned by the main record state |
| <code>tagq_count</code> | completed encrypt records waiting in the tag packet FIFO |
| <code>tag_prod_valid</code> | a completed encrypt record in the tag producer slot |
| <code>detached_result_pending</code> | an older descriptor occupying the shared result register; results owned by the active record are explicitly excluded |
| <code>enc_result_pending</code> | an encrypt record whose tag completed and whose ENC_OK still must be staged |

The active-result ownership test prevents the same active descriptor from
being counted again as detached. FIFO entries, producer slots, the active
record, and result ownership are distinct storage/lifetime states under the
existing queue invariants.

On that first edge, ZEROIZE also clears the ordinary queues/valids and active
state, so the snapshot becomes the sole number of abort responses still owed.
Repeated ZEROIZE cannot recapture it because the token is already one.

### One count unit produces one result

After scrub, and only when state is IDLE, there is no abort terminator, and the
result register is empty:

1. one 0x13 result is staged;
2. <code>zeroize_abort_count</code> decrements once;
3. while the result is stalled, <code>result_valid_r</code> prevents another
   stage and the count holds;
4. only a visible 0x13 fire clears that result;
5. if more count remains, the next 0x13 is staged subsequently.

The count is therefore the number still to stage, while an asserted result
valid is the one already staged. This representation prevents duplicate
staging under backpressure.

For the last response, staging changes count from one to zero but leaves the
token set. The token clears only on that response's later visible handshake.
Thus count zero alone cannot reopen admission while the final beat is stalled.

For an empty snapshot, no result is staged. The token remains set throughout
the 16-address plaintext scrub and clears only on the final scrub edge.

### Admission proof

Descriptor take requires both:

~~~text
!zeroize_sequence_active_r
&& (zeroize_abort_count == 0)
~~~

The count gate is intentionally retained. The token protects the intervals
where count is zero but scrub is active or the final response is already
staged. The count gate independently protects any state in which aborts
remain to be staged. Removing either condition would weaken the proof.

Because sequential logic observes the old token value on the final visible
handshake edge, a descriptor cannot be taken on that same edge. It can be
taken on the next edge, which the direct test observes. This is the intended
admission boundary, not an added idle cycle.

### Same-edge collisions

- ZEROIZE and descriptor push: command acceptance requires
  <code>!zeroize</code>; pre-existing FIFO occupancy is sampled in the abort
  count and the FIFO is cleared.
- ZEROIZE and an ordinary visible result: visible fire is false because
  ZEROIZE masks public VALID. A detached result is included in the first
  snapshot; an active-owned result is represented by <code>active_record</code>.
- ZEROIZE and active record: the active term contributes exactly one, then
  the main state is forced to IDLE.
- repeated ZEROIZE and staged abort: the token prevents recounting and the
  visible-fire gate prevents invisible retirement.
- final abort handshake and descriptor pending: old token=1 blocks same-edge
  take; next-edge take is allowed.

## Sensitive-state invalidation and scrub

On the first ZEROIZE edge, the core:

- forces main state to IDLE, clears key readiness and registered crypto
  permission, and prevents new AES/GHASH work;
- clears H, tag mask, hash, final tag, input block, counter request state,
  GHASH/AES producer valids, tag/data producer valids, field counts, and
  record framing state;
- clears descriptor, tag, and plaintext-release FIFOs through their ZEROIZE
  clear inputs;
- synchronously resets the AES engine and GHASH engine through
  <code>rst_n && !zeroize</code>;
- sends ZEROIZE to <code>aes_key_context</code>, which clears
  <code>round_keys_r</code>, the key-expansion window and generated-word
  state, ready/busy state, and registered S-box state;
- invalidates both plaintext-bank ownership bits and output-release control.

While <code>zeroize_busy_r</code> is one, the normal crypto branch is not
executed, state is held at IDLE, and both 16-entry plaintext banks are written
with zero at <code>zeroize_index</code> 0 through 15. Ordinary plaintext
writes are excluded by the higher-priority scrub branch. The registered
<code>crypto_event_enable_w</code> also requires neither ZEROIZE nor busy.

Repeated commands may re-clear external/control state, but do not recalculate
the abort count. Result backpressure cannot overwrite a staged abort because
new staging requires <code>!result_valid_r</code>.

## Directed security evidence

The promoted A baseline plus the isolated B, C, and D suites exercise the
public and internal corners relevant to this patch. A and B intentionally
record the historical direct-core defect as an expected negative-test PASS;
C and D must pass the corrected behavior in normal mode:

| Test | Locked result |
|---|---|
| public-interface ZEROIZE | idle results 0; accepted descriptors 2; ZEROIZE_ABORT results 2; no data/tag leakage |
| key mid-expansion | recovery 101 cycles; round keys observed scrubbed |
| non-96-bit IV GHASH collision | 128-bit IV; GHASH busy at pulse; abort results 1; stale outputs 0 |
| direct result stall plus repeated ZEROIZE | A/B expected-loss runs reproduce zero visible fires; C/D produce exactly one visible 0x13 |
| direct admission boundary | A/B expected-loss runs reproduce early admission; C/D hold through abort and admit on the next edge |
| descriptor-push coincident with ZEROIZE | B/C/D attempt 1 with two prior accepted records; exactly two aborts at cycles 19/21; no third credit or extra output |
| registered GHASH-slot stall | B/C/D one stall cycle (162 to 163), 17 input handshakes, two IV block commits, stable held beat |
| AES/data-capacity stall | B/C/D 22 total stall cycles, 21 AES-unavailable cycles (290 to 312), one final-byte handshake, terminal order DATA/TAG/RESULT |
| smoke | 8,364 cycles, unchanged |
| six throughput modes | 18,920/19,139; 19,520/19,739; 20,120/20,339 cycles, unchanged |
| Round48 boundary | 364/722 cycles, unchanged |
| Round49 residual | 546/1,002/1,568 cycles, unchanged |
| NIST525 | 525/525, 145,808 cycles |
| NIST5255 | 5,255/5,255, 1,615,588 cycles |

The table below records the isolated B/C/D security-log SHA-256 identities;
the promoted A outcomes are recorded in <code>round53_results.csv</code>:

| Evidence | B | C | D |
|---|---|---|---|
| public ZEROIZE | <code>23F1C128DBAA5F6DB233D5B5D8B4EA41DAB7FB10E3AD62A7E1F1CEBD204F1CE0</code> | <code>BC70560651C2B11EF3EB47A893792990AEDC4D943ADDBE534C7DA36BEFF04E67</code> | <code>408B973D8E995A80113C50F47BE8B32D2CA68CD811183F3F581C9C63F654D329</code> |
| key mid-expansion | <code>16E324F9CF8660E291DAEFE065A0B728B2DDCFF00673E2AF0E26D00D7568021E</code> | <code>4F397F8A1B9E178FEFAC5141FD860090301AFBB9BBAEF37BE071217F98924DCB</code> | <code>357686CDCE28593D05AD16E4B272EA53072713C72C54F27DDA9776D678C8B98C</code> |
| non-96 GHASH plus capacity stalls | <code>84FC654213FE88D452C01AC66447E9223CD0E9C9FD24BC870AF88811D3CA9A62</code> | <code>A01F860BA509ABC831205B856AB5000610ED4E6896234C4EDA1E051FB3DFB432</code> | <code>182B177696BC4699C702E6A6EA46B66B8FFF077B4CFC83495B393499C1E58988</code> |
| direct core plus descriptor collision | negative baseline: <code>EFA55E52025B780120AE9A0C8B4E4E34BE69BA07227D61F6F5704A433C38C54E</code> | <code>EB292C2C37A8714F6030C138A3C498F42244E0F1B35D5F176FA06AB192B9FDBE</code> | <code>D9B884AD7C6575EB03CF3CA8999413F154B0B54A1EC084F4D0A00ABE7E5243B4</code> |

## Primitive and fail-closed Tcl evidence

In the retained C checkpoints, with the same token mapping independently
confirmed in the diagnostic D checkpoints:

- exactly one <code>zeroize_sequence_active_r_reg</code> exists;
- it maps to <code>FDRE</code> with INIT <code>1'b0</code>, KEEP enabled,
  and equivalent-register removal disabled;
- its D pin is driven by exactly one LUT with the required ZEROIZE, busy,
  index, count, result-valid/data/ready, and token startpoint classes;
- its C pin is on <code>aclk</code>, CE is driven solely by VCC, R is a single
  LUT1 whose sole startpoint is <code>aresetn</code>, and no S pin exists;
- its Q net has 24 synthesized loads and 26 placed/routed loads and reaches
  the main-state/descriptor-admission cone;
- <code>result_data_r</code> has zero direct timing paths to the main-state
  data/control pins;
- <code>zeroize_abort_count</code> still has four paths to main state, as
  required by the retained count admission gate;
- there are no inferred latches, no timing exceptions, and all 12 parsed
  <code>check_timing</code> categories are zero.

The routed zseq-to-state family has worst slack <code>+0.103 ns</code>. The
preserved abort-count-to-state family has two negative paths and worst slack
<code>-0.178 ns</code>; this is honest remaining timing work and must not be
removed without a separate equivalence/security proof.

The Tcl check is fail-closed on empty or non-unique primitive/pin/clock
collections and throws on structural, exception, DRC, routed-hold, or routing
legality failures. It also checks multiple-driven nets, CDC status,
methodology Error/Critical Warning counts, and the block-cut replacement logic
depth. The recorded zseq checks cover primitive identity, INIT/properties, Q
loads/reachability, D startpoint classes, and C/CE/R/S connectivity. They are
not a gate-level formal proof of the entire next-state LUT truth table.

## Limitations

- No formal model checker proved the occupancy partition, unreachable-state
  assumptions, or every possible cross-product of stalls and command pulses.
  The cardinality proof relies on the existing FIFO ownership/state-machine
  invariants and the listed directed simulations.
- The direct cardinality evidence explicitly demonstrates zero, one, and two
  owed-result situations represented by the tests. It does not exhaustively
  force every theoretical encoding of the three-bit counter.
- The ZEROIZE interface is exercised as a command pulse. Indefinitely holding
  the command high across a completed sequence is outside the directed-test
  claim.
- NIST525 and NIST5255 are prefixes of
  <code>gcmEncryptExtIV128.rsp</code> only. The logs report zero vectors from
  the AES-192, AES-256, and decrypt files; the full 47,250 corpus has not been
  run for Round53.
- These tests establish functional behavior in RTL simulation, not resistance
  to power/EM leakage, fault injection, remanence in a configured physical
  device, or synthesis-tool malicious transformation.
- D is not internally timing closed: routed internal WNS is
  <code>-0.553 ns</code>, TNS is <code>-48.576 ns</code>, and FEP is 327.
  No PartPin/I/O signoff claim is made.

## Final security determination

For the retained C RTL and directed scope, same-edge sensitive
control/register invalidation and the existing 16-cycle plaintext-bank scrub
are preserved; repeated ZEROIZE is idempotent with respect to abort counting;
invisible result retirement is prevented; one visible abort is emitted for
each captured owed descriptor; admission remains blocked until the empty-scrub
or final visible-abort completion edge; and crypto restart is blocked while
busy. The same C security hunk passes independently in diagnostic D.

The C security patch retained after commit
<code>96398c1515d08bdb50ae6a9e9d065106c3da3e89</code> is therefore
accepted for continued timing work. D remains an audited combined experiment,
not the promoted source. Timing closure and broader formal/security
certification remain open signoff items.
