# UVM status

- ModelSim deterministic UVM 1.2 smoke: **PASS**
- Simulator: ModelSim ALTERA STARTER EDITION 10.5b
- UVM source: `C:/intelFPGA_lite/17.0/modelsim_ase/verilog_src/uvm-1.2/src`
- Test: `aesgcm_uvm_test`
- Scoreboard: `checked=1 failed=0`
- UVM errors/fatals: 0/0
- ModelSim runtime errors: 0
- Simulation completion time: 1.528495 us
- Latest local evidence: `verification/results/uvm/modelsim_20260822_174905/`
- Constrained-random UVM regression: **NOT RUN**
- Functional/code/assertion coverage from UVM: NOT COLLECTED

ModelSim Starter can compile and execute the deterministic UVM 1.2
agents/monitor/scoreboard path. Its license rejects constrained randomization
and covergroups; those require QuestaSim or another simulator with the
verification license. The Starter run therefore uses one fixed AES-128
zero-key/zero-IV/zero-payload encrypt record and explicitly disables
covergroups. The scoreboard checks payload, tag, and the successful encrypt
result code.

The independent scoreboard model was executed without UVM and passed:

`REFERENCE_MODEL_PASS aes_fips197=1 gcm_sp800_38d=1`

The environment source retains named scenario-class and coverage scaffolding
for future implementation on a fully licensed simulator. The deterministic
Starter smoke is not reported as a full constrained-random regression.
