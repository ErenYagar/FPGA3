# Formal status

- Full formal closure: **NOT CLAIMED**
- Open-source combinational subset: **PASS**
- Tool: Yosys 0.33 (`git sha1 2584903a060`), built-in SAT
- Proved property groups: 2
- Imported/proved assertions: 19
- Failed: 0
- Inconclusive within proved subset: 0

| Proof | Universal inputs | Assumptions | Assertions | Result |
|---|---:|---:|---:|---|
| GHASH `T^POWER`, `POWER=0..16`, versus repeated NIST one-bit shift | 128 bits | 0 | 17 | PASS |
| AES combinational S-box versus algebraic GF(2^8) inverse/affine reference, plus injectivity | 16 bits across two arbitrary bytes | 0 | 2 | PASS |

The SAT solver reported `no model found: SUCCESS` for both proof groups. Raw
logs are `verification/results/formal/ghash_shift_power.log` and
`verification/results/formal/aes_sbox_algebraic.log`; they are deterministic
output locations and are intentionally ignored by Git. The compact
`run_formal.log` records SHA-256 hashes for every RTL, harness, and Yosys script
used by the two proofs. Its SHA-256 is
`C1FB4DA19869532E1831069A635BF71F7C6714237DD5C08C7EDF6A16CCBC0C96`.

Not proved by this subset: sequential `ghash16` recurrence/control, FIFO
protocol and clear behavior, key-context/ZEROIZE sequencing, top-level GHASH
queue behavior, whole AES/AES-GCM equivalence, liveness, CDC, timing, power,
or side-channel properties. These require a sequential adapter and solver or
a supported commercial formal tool.
