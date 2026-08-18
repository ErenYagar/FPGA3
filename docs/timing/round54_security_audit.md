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
