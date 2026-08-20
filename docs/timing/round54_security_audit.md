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
