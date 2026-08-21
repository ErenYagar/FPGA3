# Round54 security audit

## Retained security contract

Round54 retains R53-C's `zeroize_sequence_active_r`,
`result_visible_fire_w`, `zeroize_abort_result_fire_w`, and
`first_zeroize_event_w` sequence/cardinality semantics.  Timing experiments
must not delay the raw ZEROIZE edge, restart the scrub index, recompute abort
cardinality, invisibly retire the final abort, or admit a descriptor before
the final visible abort.

The Round53 hard gate remains mandatory and is wrapped by the Round54 gate.
The wrapper additionally records the physical ZEROIZE driver, verifies direct
raw-ZEROIZE reachability to every mapped `prep_tag_bytes` bit, rejects a zseq
decode in the R54-B prep-tag clear cone, and records ciphertext head control
reachability.

## Prep-tag source audit

`prep_tag_bytes` has exactly three writer cases in the retained source:

1. global reset writes zero;
2. the first ZEROIZE event writes zero;
3. an accepted descriptor writes its decoded tag byte count.

Its readers choose input-field mode and remaining-byte/last-byte state.  While
the ZEROIZE lifecycle is active, the main state machine remains in the
`zeroize_busy_r` branch and `take_descriptor` is independently gated by raw
ZEROIZE, queue clear, `zeroize_sequence_active_r`, and abort count.  Therefore
the register cannot be loaded during repeated ZEROIZE.  The next admissible
descriptor overwrites it before any record uses it.

This makes repeated raw-ZEROIZE writes of zero idempotent for this metadata,
but does not justify moving abort-count, sequence, key, round-key, GHASH,
plaintext ownership, or scrub state off `first_zeroize_event_w`.

## Signoff rule

Simulation is necessary but not sufficient.  A promoted experiment must also
pass the DCP structural checks for key context, AES/GHASH state, plaintext
banks, output-valid invalidation, result sequencing, abort cardinality, and
same-edge ZEROIZE reachability.  PartPin signoff remains NO unless an approved
production map matches the retained placed-DCP SHA-256 and passes strict
replay; the existing Round46 maps are discovery candidates for another parent
checkpoint.

## R54-A baseline audit

The fresh R54-A build preserved the exact raw ZEROIZE implementation driver
(`u_registers/zeroize_pulse_o_reg`, FDRE), its 342-load net, direct
reachability to all five `prep_tag_bytes` bits, all 134 ciphertext head bits,
and the retained ZEROIZE sequence structure.  It also reproduced every
negative-path family count and TNS exactly.  No security behavior was changed;
the existing Round53-C functional/security signatures are inherited only for
this byte-identical RTL baseline.  Any RTL-changing experiment must rerun the
directed and regression simulations rather than inherit these results.

## R54-B audit (failed timing promotion)

The final explicit-FDRE implementation has one writer per mapped bit.  Raw
ZEROIZE reaches all five R pins on the same edge, and the routed fanin audit
finds no `zeroize_sequence_active_r` decode in those reset cones.  The
ciphertext FIFO still has 134 head registers with raw-ZEROIZE reachability to
their CE cones.  Latch, multiple-driver, CDC, route, DRC, methodology, and
Round53 sequence/cardinality gates all pass.

The RTL-changing candidate passed the exact 8,364-cycle smoke signature, all
six throughput signatures (including AES II 10/12/14 and every mode above
1 Gbit/s), Round48/49, all Round53 ZEROIZE/stall/capacity regressions, the
repeated-ZEROIZE same-edge prep-tag test, NIST525 at 145,808 cycles, and
NIST5255 at 1,615,588 cycles.  Functional/security behavior is clean, but the
candidate is rejected because routed TNS and FEP regress; none of its RTL is
eligible for promotion.

## R54-C audit (remap did not occur)

R54-C changed no RTL, so retained functional signatures remain applicable.
Its physical experiment nevertheless failed the mandatory structural gate:
the five prep-tag R pins remained present, and ZEROIZE also entered their new
five-level D cones.  Routing was intentionally not run.  This experiment is
rejected and contributes no netlist or property to a combination.

## R54-D audit (functional pass, timing promotion fail)

The ciphertext FIFO always clears count and pointer state, so `out_valid`
drops on the clear edge.  With `CLEAR_HEAD_ON_CLEAR=0`, logical clear alone
does not scrub the head bits; global reset still does.  The directed test
proves abort clear, raw-ZEROIZE clear, clear-over-push/pop priority, immediate
empty refill, no stale-head fire, and global scrub.  Existing public-valid and
abort sequencing gates also pass, so a retained head value cannot be observed
or retired.

The routed DCP contains 134 always-enabled ciphertext head FDREs and no
logical ZEROIZE path to their CE pins.  All 180 LUTRAM WE pins retain logical
ZEROIZE reachability.  Two physical ZEROIZE replicas created by baseline
phys-opt are accepted only after strict equivalence checks against the primary
FF and its D cone; the audit records their LOC/BEL, fanout, and every load.
The routed design has no hold, CDC, route, DRC, latch, multiple-driver, or
sequence/cardinality regression.

The RTL-changing candidate passed smoke at 8,364 cycles, all six throughput
signatures and AES II 10/12/14, Round48/49, all Round53 regressions, NIST525 at
145,808 cycles, and NIST5255 at 1,615,588 cycles.  It is still rejected because
routed TNS and FEP are worse than retained C.  No D RTL is eligible for the
integration branch or a structural combination.

## R54-E audit (equivalent physical replicas, timing promotion fail)

R54-E changes no RTL, clock, exception, or protocol behavior.  Its nine
physical ZEROIZE replicas are accepted by the audit only because each matches
the primary FDRE's INIT, clock, CE, reset/set, D-driver LUT primitive and INIT,
and complete D-cone startpoint set.  The recorded primary-plus-replica fanouts
sum to all 342 original loads, and the routed audit retains direct logical
ZEROIZE reachability to all five prep-tag bits, 134 ciphertext head CE cones,
and 180 transformed LUTRAM WE pins.  Sequence/cardinality, CDC, latch,
multiple-driver, route, DRC, and hold gates all pass.

Because the source is byte-identical to retained R53-C, the existing smoke,
throughput, Round48/49/53, ZEROIZE, NIST525, and NIST5255 signatures are
inherited.  The routed setup result is nevertheless worse on WNS, TNS, and
FEP, so no physical checkpoint or replica mapping is promoted.  No
combination or final routing sweep can inherit E.

Round54 ends without an internal-closure candidate.  The full 47,250-vector
NIST run is reserved for a closed final candidate and is therefore not run.
PartPin remains NO because there is no approved, identity-matched production
map for the retained placed checkpoint.

## Continued R54-F/G audit

R54-F changes only the round-key context's internal word-write locality.  The
new one-hot enables are cleared by reset and raw ZEROIZE and preserve the
existing generation/capture edge ordering.  It passed smoke at 8,364 cycles,
all six exact throughput signatures (18,920/19,139, 19,520/19,739, and
20,120/20,339), AES II 10/12/14, Round48/49, all applicable Round53
ZEROIZE/stall/capacity regressions, the key-mid-expansion ZEROIZE recovery,
NIST525 at 145,808 cycles, and NIST5255 at 1,615,588 cycles.

R54-G changes no RTL or architectural state.  It physically replicates only
the exact `input_field_mode_r[2]` register net from the hash-matched R54-F
placed checkpoint, so it inherits F's functional evidence.  Routed hard
gates confirm the original clock and exceptions, direct prep-tag and FIFO
ZEROIZE reachability, sequence/cardinality structure, zero latches and
multiple drivers, safe CDC, zero route errors, zero DRC errors/critical
warnings, and positive hold slack.  G is security/legal for promotion as the
best available implementation, but it is not a final candidate because 86
setup endpoints remain.  The 47,250-vector NIST run remains reserved for an
internally closed candidate; PartPin remains NO.

## Continued R54-H/I/GI/J/EGI/K audit

R54-H changes only the combinational expression for FIFO full.  The count
register remains the state authority and the existing clear/push/pop priority
is unchanged.  H is subsequently covered by the complete I functional run.

R54-I adds five explicit prep-tag FDRE instances.  The RTL and mapped-netlist
audits both prove one logical writer per bit, reset/raw-ZEROIZE priority over
descriptor load, direct same-edge raw-ZEROIZE reachability to every R pin,
and no zseq decode in the reset cone.  Physical synthesis may replicate a
prep-tag source, but the gate counts logical bits separately from physical
sources and accepts a replica only when its FDRE INIT, clock, D/CE/R/S
mapping, D-driver signature and disjoint Q-load partition match its canonical
bit.  The same equivalence rule now covers the public-idle FDSE replica,
including INIT=1 and matching D/CE/S signatures.

The I RTL passes compile/elaboration, the 8,364-cycle smoke signature, all six
throughput signatures (`18920/19139`, `19520/19739`, `20120/20339`), AES II
10/12/14, every mode above 1 Gbit/s, Round48, Round49, the applicable Round53
ZEROIZE/stall/capacity tests, repeated-ZEROIZE prep-tag same-edge clear,
NIST525 at 145,808 cycles, and NIST5255 at 1,615,588 cycles.  Scrub and abort
sequence/cardinality behavior is unchanged.

R54-GI changes no RTL.  It replicates only the exact
`input_field_mode_r[2]` physical net from the SHA-256-matched I placed DCP.
The gate proves one canonical FDRE plus one equivalent replica, maps all 36
loads exactly once (1 primary and 35 replica loads), and rechecks clock,
exceptions, ZEROIZE, prep-tag, ciphertext clear, public-idle, route, DRC,
methodology, CDC, latch, multiple-driver and hold gates on the routed DCP.
GI therefore inherits I's functional evidence and is security/legal for
promotion as the best available implementation.  It is not final signoff
because 19 setup endpoints remain.

R54-J changes no netlist structure and routes independent copies of the same
immutable GI placed DCP with three other directives.  All legality/security
gates pass, but all timing results are worse than GI, so none is promoted.
R54-EGI additionally force-replicates the exact ZEROIZE net.  Its 11 physical
replicas pass strict equivalence and complete-load mapping, but routed setup
regresses to `-0.422/-38.597/287`; no EGI DCP or replica mapping is promoted.

R54-K is the final manual-pulse experiment permitted by the plan.  The
boundary and core pulse FDREs are both written directly by the same accepted
AXI control-write edge and the same requested control bit.  It does not delay
ZEROIZE and does not implement `copy <= zeroize_pulse_o`.  Boundary/public
and FIFO consumers remain on the original pulse; only `u_core.zeroize` uses
the second pulse.  Source and DCP audits verify the common LUT2 writer
function, same clock/reset behavior, physical replicas, prep-tag reachability,
public-idle mapping and all Round53 sequence/cardinality invariants.

K passes the same full functional signatures as I, including repeated
ZEROIZE and both NIST suites.  Nevertheless all four routed implementations
fail setup promotion.  The GK probe produces seven input-mode replicas and a
placed setup regression to `-0.621/-2.564/8`; the fail-closed topology gate
stops it before routing.  K and GK are rejected, and their RTL is not eligible
for the integration branch.

The promoted Round54 source is therefore I, paired with the GI physical DCP
and its exact input-mode replica map.  This is a best-available promotion, not
internal closure.  The 47,250-vector NIST run remains gated on WNS >= 0 and
TNS/FEP/THS = 0.  PartPin remains NO because no approved production map
matches the GI placed-DCP identity and passes strict replay.

The promoted integration source was independently rerun at commit
`839ebdede1473afd51a41c72261a34264d51f007` with the non-D regression
profile.  It passed compile/elaboration, smoke `8364`, all six throughput
signatures, Round48/49, every applicable Round53 security/stall/capacity
test, repeated-ZEROIZE prep-tag same-edge clear, NIST525 `525/0` at 145,808
cycles, and NIST5255 `5255/0` at 1,615,588 cycles.  The D-only FIFO testbench
is not applicable because GI deliberately does not contain D's rejected
`CLEAR_HEAD_ON_CLEAR` parameter; this exclusion is explicit in the runner
and does not remove the retained FIFO clear/abort/ZEROIZE gates.

The subsequent 175 MHz audit changes constraints only.  It uses the same
promoted RTL and exact GI physical netlist, so all previously passed cycle and
security regressions remain applicable.  Vivado rechecked the routed DCP at
the strict `5.714 ns` period and passed ZEROIZE direct-cone, prep-tag mapping,
descriptor admission, ciphertext clear, public-idle, input-mode replica,
CDC, latch, multiple-driver, DRC, methodology, route, setup, and hold gates.
No timing exception was added.  The archived reclocked DCP is
`EC5C296177A30C3268A20B30A419A8ADC7B284EE49EC443CC0969ADA3165AA9B`.
This establishes security/legal internal timing closure at 175 MHz only;
PartPin remains NO and the original >1 Gbit/s throughput gate is not met at
the lower frequency.

## Round55 throughput candidate audit

Round55-T adds two fast CTR contexts and a two-entry data-block queue.  Each
fast AES context and its pending result register reset synchronously on raw
ZEROIZE.  Both queue payload entries, indices, byte counts, last markers, and
valid count clear on the existing `queue_clear`, covering protocol abort and
ZEROIZE.  The ordered data and keystream indices are required to match before
consumption, preventing duplicate, lost, or cross-record ciphertext.

The repeated-ZEROIZE directed test injects nonzero sensitive values into both
data queue entries, both fast AES states, and both fast result buffers, then
proves they are zero and invalid on the raw ZEROIZE edge.  Existing abort
cardinality, descriptor admission, non-96-bit IV, GHASH-slot stall, public
visibility, key-mid-expansion, Round48, and Round49 gates all pass.  The
routed hard gate independently reports direct raw-ZEROIZE reachability,
complete ciphertext clear mapping, no unsafe CDC, no latch or multiple
driver, no route/DRC error, and positive internal setup and hold slack.

The exact commit passes NIST525 `525/0`, NIST5255 `5255/0`, and the final
NIST run `47250/0` at 17,740,527 cycles.  The R54-D-only
`CLEAR_HEAD_ON_CLEAR` test is N/A because that rejected parameter is absent
from this baseline; the retained FIFO count/out-valid, abort-clear, ZEROIZE,
and stale-output visibility gates remain active and pass.  Security and
internal timing promotion are **PASS** at 175 MHz.  PartPin remains **NO**
pending an approved identity-matched production map.
