# Full 175 MHz NIST RSP regression

- Production RTL content: `a6f19472ecc619925b373b1db801911c54062a90`
- Tool: XSim/Vivado 2021.1
- Testbench clock: 175 MHz (`5.714 ns`)
- Local log: `verification/results/nist/run_nist.log`
- Result: **PASS -- 47,250/47,250, zero failures**
- Total simulated cycles: 17,740,527
- XSim elapsed time: 56 min 10 s
- Assertion failures: 0

| RSP file | Passed | Failed |
|---|---:|---:|
| `gcmEncryptExtIV128.rsp` | 7,875 | 0 |
| `gcmEncryptExtIV192.rsp` | 7,875 | 0 |
| `gcmEncryptExtIV256.rsp` | 7,875 | 0 |
| `gcmDecrypt128.rsp` | 7,875 | 0 |
| `gcmDecrypt192.rsp` | 7,875 | 0 |
| `gcmDecrypt256.rsp` | 7,875 | 0 |

Required terminal signatures:

```text
NIST_TOTAL_SUMMARY pass=47250 fail=0 total=47250 cycles=17740527
NIST_ALL_PASS 47250/47250
```
