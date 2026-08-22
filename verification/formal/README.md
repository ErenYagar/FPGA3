# Formal targets

The maintained open-source subset runs with Yosys 0.33 and its built-in SAT
engine. From Windows Git Bash, the runner automatically dispatches to the
installed WSL copy of Yosys when no native executable is available:

```text
bash verification/scripts/run_formal.sh
```

The dispatch preserves the repository path and the inner process exit code.
Calling the same runner directly inside WSL remains supported.

The runner executes two assumption-free combinational proofs:

1. `ghash16_gf_shift_power`: all 17 production instances `POWER=0..16` are
   equivalent, for every 128-bit input, to an independent repeated one-bit
   NIST SP 800-38D right-shift/reduction reference.
2. `sbox` with `REGISTERED=0`: every input byte equals an independent
   GF(2^8) inverse plus AES affine-transform reference, and two distinct input
   bytes cannot produce the same output.

The raw Yosys logs are written to `verification/results/formal/` and the
runner rejects missing assertions or missing SAT success markers. Logs are
runtime evidence and remain ignored by Git; the compact result summary is
tracked.

This is deliberately **not full formal closure**. The existing sequential
targets below remain portable property sources but have not been proved by
this Yosys subset:

- `ghash16` eight-digit state transitions and full recurrence.
- `stream_fifo` count, ready/valid, clear, and retained-head behavior.
- `aes_key_context` sequencing and ZEROIZE behavior.
- `aes_gcm_stream_core` GHASH queue retention and handshake mapping.

Those SVA targets use constructs outside this small Yosys adapter and still
need a validated sequential adapter/solver or a commercial formal tool.
