# 175 MHz limited NIST signatures

- Production RTL content: `a6f19472ecc619925b373b1db801911c54062a90`
- Tool: XSim/Vivado 2021.1
- Testbench clock: 175 MHz (`5.714 ns`)
- Local evidence: `verification/results/nist_limited_175/run_20260822_1831/`
- Assertion failures: 0

| Signature | Pass/fail | Simulated cycles |
|---|---:|---:|
| NIST525 | 525 / 0 | 145,808 |
| NIST5255 | 5,255 / 0 | 1,594,798 |

Both totals, zero-failure checks, and exact cycle signatures passed.
