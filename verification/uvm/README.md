# AES-GCM UVM environment

The environment contains an active AXI-Lite agent, an active input AXI-Stream
agent, three independently programmable output backpressure agents, a passive
record reconstruction monitor, virtual sequencer, independent FIPS-197 / NIST
SP 800-38D scoreboard, constrained-random scenario sequences, and a coverage
model.

The golden model is executable without UVM:

```text
aesgcm_reference_model_pkg.sv
tb_reference_model.sv
```

It passed the FIPS-197 AES-128 example and the SP 800-38D AES-GCM zero-key
example on XSim 2021.1.

ModelSim Starter 10.5b includes the UVM 1.2 source under
`verilog_src/uvm-1.2/src`. `verification/scripts/run_uvm_regression.sh` builds
that library, production RTL, the Vivado FDRE simulation model, and this UVM
environment, then runs a deterministic AES-128 scoreboard smoke at 175 MHz.

Starter licensing does not permit constrained randomization or covergroups.
The script therefore compiles with `MODELSIM_STARTER`, runs one fixed AES-128
zero-key/zero-IV/zero-payload encrypt record through the
agents/monitor/scoreboard path, and reports functional coverage as
`NOT_COLLECTED`.

Vivado Simulator 2021.1 provides a precompiled UVM 1.2 library, constrained
randomization, covergroups, and a functional-coverage database. Run the native
XSim regression with:

```text
& 'C:\Program Files\Git\bin\bash.exe' verification/scripts/run_uvm_xsim.sh
```

It uses seeds `175001`, `175019`, and `175039`. Each seed runs eight serial
records covering AES-128/192/256 in both encrypt and decrypt modes, 96-bit and
non-96-bit IVs, empty/short/one-block/multi-block AAD and payloads, valid
decrypt authentication, and a corrupted-tag decrypt. Keys and record bytes are
constrained-random; scenario categories guarantee all required coverpoint and
cross bins. The regression requires a clean scoreboard and 100% of those bins
for every seed, and writes `summary.csv`, `summary.json`, per-seed logs, and
XSim coverage databases under a timestamped `verification/results/uvm/xsim_*`
directory.
