# SVA execution summary

- RTL git SHA: `4a215983f3774c49e833cfe3715a019748200c73`
- Simulator: XSim 2021.1, SW Build 3247384, IP Build 3246043
- Property statements: 37
- Bound production top: `aes_gcm_axi_top`
- Bound GHASH: `stream_ghash/ghash16.v`

| Run | Result | Assertion failures | DUT signature |
|---|---:|---:|---|
| GHASH checker smoke | PASS | 0 | `GHASH16_PASS tests=66 digit_cycles=8 external_ii=9` |
| AXI integration checker smoke | PASS | 0 | `AXI_SMOKE_PASS cycles=7676` |

The GHASH checker uses repeated one-bit NIST shift/reduce operations for its
T^16, digit-product, and full-multiplication references. It does not call the
DUT's direct `T^POWER` implementation.

Raw compile, elaboration, and simulation logs are retained locally under
`verification/results/sva/` and intentionally ignored by Git.
