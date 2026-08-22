# AES-GCM UVM environment

The environment contains an active AXI-Lite agent, an active input AXI-Stream
agent, three independently programmable output backpressure agents, a passive
record reconstruction monitor, virtual sequencer, independent FIPS-197 / NIST
SP 800-38D scoreboard, named scenario-class scaffolding, and a coverage model.

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
`NOT_COLLECTED`. The named scenario classes and coverage model are scaffolding;
they are not reported as implemented or passed randomized scenarios. Use a
fully licensed UVM simulator before implementing and measuring those cases.
