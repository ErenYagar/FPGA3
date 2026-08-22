# Unmodified baseline results

- Git SHA: `4a215983f3774c49e833cfe3715a019748200c73`
- Simulator: XSim 2021.1, SW Build 3247384, IP Build 3246043
- RTL top for AXI tests: `aes_gcm_axi_top`
- GHASH source: `engrenring/rtl/source/stream_ghash/ghash16.v`
- Legacy `AESGCM_IO/GHASH.v`: not compiled

| Baseline | Result | Exact signature |
|---|---:|---|
| `tb_ghash16` | PASS | `GHASH16_PASS tests=66 digit_cycles=8 external_ii=9` |
| `tb_axi_smoke` | PASS | `AXI_SMOKE_PASS cycles=7676` |
| `tb_throughput` | PASS | all six AES-128/192/256 encrypt/decrypt modes >1 Gbit/s at 175 MHz |
| `tb_nist` | PASS | `pass=47250 fail=0 total=47250 cycles=17740527` |

Throughput results:

| Mode | Encrypt cycles / Gbit/s | Decrypt cycles / Gbit/s |
|---|---:|---:|
| AES-128 | 16820 / 1.065398 | 17039 / 1.051705 |
| AES-192 | 16820 / 1.065398 | 17039 / 1.051705 |
| AES-256 | 16820 / 1.065398 | 17039 / 1.051705 |

NIST used six RSP files, each with 7,875 passing vectors. Raw logs remain
under `verification/results/baseline/` and are intentionally ignored by Git.
