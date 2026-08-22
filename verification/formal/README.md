# Formal targets

Status on 2026-08-22: **NOT RUN**. No `jg`, `qverify`, or OneSpin executable
is installed on this workstation.

The portable property sources target, in order:

1. `ghash16_gf_shift_power`, with all `k=0..16` compared against an
   independent repeated one-bit NIST shift.
2. `ghash16` digit transitions and full 128-bit recurrence.
3. `stream_fifo` count, ready/valid, clear, and retained-head behavior.
4. `aes_key_context` control sequencing and ZEROIZE behavior.
5. `aes_gcm_stream_core` GHASH request queue retention and handshake mapping.

Run `verification/scripts/run_formal.sh`. It queries an installed supported
tool's version/help before any vendor-specific project syntax is generated.
No vendor project file is checked in because no supported formal tool was
available to validate its syntax.
