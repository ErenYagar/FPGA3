# UVM status

- Full UVM regression: **NOT RUN**
- Reason: no discoverable UVM 1.2 source or precompiled library in XSim 2021.1
  or ModelSim Starter 10.5b.
- UVM test pass/fail count: 0/0 (not executed)
- Functional/code/assertion coverage from UVM: NOT COLLECTED

The independent scoreboard model was executed without UVM and passed:

`REFERENCE_MODEL_PASS aes_fips197=1 gcm_sp800_38d=1`

The environment source contains the requested agents, passive record monitor,
virtual sequencer, scoreboard, scenario sequence types, coverage points, and
crosses. Source creation is not reported as a UVM test pass.
