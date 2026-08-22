# 175 MHz promoted non-D directed regression

- Production RTL content: `a6f19472ecc619925b373b1db801911c54062a90`
- Tool: XSim/Vivado 2021.1
- Clock contract: 175 MHz (`5.714 ns`)
- Local evidence: `verification/results/directed_175/run_20260822_1824/`
- Result: **PASS -- 8/8 applicable tests, zero assertion failures**

| Test | Result | Required evidence |
|---|---:|---|
| Six-mode throughput | PASS | AES-128/192/256 encrypt `16820` cycles; decrypt `17039` cycles; all above 1 Gbit/s |
| Round48 boundary | PASS | `ROUND48_BOUNDARY_DIRECTED_PASS cycles=712` |
| Round49 residual | PASS | abort token, ciphertext index, and tag replacement signatures |
| Round53 core ZEROIZE | PASS | repeated prep-tag clear, fast context/result scrub, abort cardinality, admission, descriptor collision |
| Round53 key ZEROIZE | PASS | key-mid-expansion scrub and recovery |
| Round53 non-96-bit/GHASH | PASS | mid-GHASH ZEROIZE, slot stall, AES data buffer ordering |
| Round53 public ZEROIZE | PASS | idle invisibility and two accepted/two abort-result cardinality |
| Current FIFO clear | PASS | abort/ZEROIZE clear, clear priority, immediate refill, stale-fire prevention, global head scrub |

The current FIFO bench tests the promoted default `stream_fifo` directly and
does not instantiate Round54-D's rejected `CLEAR_HEAD_ON_CLEAR` parameter.
That rejected specialization comparison remains N/A, while the current FIFO's
count/out-valid, abort/ZEROIZE, stale-output visibility, immediate-refill, and
global-scrub behavior is actively tested and passing.
