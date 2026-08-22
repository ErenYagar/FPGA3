# UVM status

- Source/verification promotion commit:
  `4246ebc7a72ce8eb1a49d56969aae6e151578c11`
- XSim constrained-random UVM 1.2 regression: **PASS**
- Simulator: Vivado Simulator 2021.1
- Seeds: `175001`, `175019`, `175039`
- Records: 8 per seed, 24 total
- Scoreboard: `checked=24 failed=0`
- UVM errors/fatals: 0/0 for every seed
- Required functional coverage: 100.00% for every seed
- Latest local evidence: `verification/results/uvm/xsim_20260823_004035/`
- Runner SHA-256:
  `835A229F948EFE26C8909D10C2D3DA0A2343E829BB95F7D202FD3D3CE8D03A56`
- Compile-input manifest: 15 inputs; SHA-256
  `D36DA381A5326EEBB1DABDA4AD63D45421ACE5E433CE38A3EF80494002233292`
- Machine-readable results: `xsim_20260823_004035/summary.csv` and
  `xsim_20260823_004035/summary.json`
- Summary SHA-256: CSV
  `F46216BF196C08ED466200EE34E3F2A7B626EB376E7C0F8A758DCB47B3225641`;
  JSON `F5B8E59504D967B6841AD73E0B6E3D8361162E251CF7FED2F303682C8B8500AF`
- Aggregate run-log SHA-256:
  `6AC1D83E3C90615448F6391350707963D544F4D42CB7FC6205A7A0C3B7189EC5`

The required coverage model includes AES-128/192/256, encrypt/decrypt,
96-bit/non-96-bit IVs, empty/short/one-block/multi-block AAD and payloads,
valid/invalid decrypt authentication, and the key-mode, mode-IV, and
mode-payload crosses. Keys, data bytes, representative lengths, and input gaps
are constrained-random. The scenario matrix guarantees that all required bins
are reachable in each deterministic seed.

The passive reconstruction monitor waits for both the result and the required
payload/tag output. This is necessary because authenticated decrypt can report
its result before releasing plaintext. Orphan output beats are errors.

- ModelSim deterministic UVM 1.2 smoke: **PASS**
- Simulator: ModelSim ALTERA STARTER EDITION 10.5b
- UVM source: `C:/intelFPGA_lite/17.0/modelsim_ase/verilog_src/uvm-1.2/src`
- Test: `aesgcm_uvm_test`
- Scoreboard: `checked=1 failed=0`
- UVM errors/fatals: 0/0
- ModelSim runtime errors: 0
- Simulation completion time: 1.528495 us
- Latest local evidence: `verification/results/uvm/modelsim_20260823_004145/`
- Aggregate run-log SHA-256:
  `01EF5B244A0C6C8FA8FD812E7C7F7437E3EE017CEF67D43EF5A46E783404D0DE`

ModelSim Starter can compile and execute the deterministic UVM 1.2
agents/monitor/scoreboard path. Its license rejects constrained randomization
and covergroups, so those features are exercised by the XSim regression above.
The Starter run therefore uses one fixed AES-128
zero-key/zero-IV/zero-payload encrypt record and explicitly disables
covergroups. The scoreboard checks payload, tag, and the successful encrypt
result code.

The independent scoreboard model was executed without UVM and passed:

`REFERENCE_MODEL_PASS aes_fips197=1 gcm_sp800_38d=1`

The 100% figure is functional coverage for the maintained XSim scenario model;
it is not code coverage, assertion coverage, or exhaustive protocol/security
coverage. Random output backpressure, zeroize phase injection, queue saturation,
and early/late TLAST fault injection remain outside this regression and stay in
the existing directed/SVA suites or future UVM expansion.
