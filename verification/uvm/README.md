# AES-GCM UVM environment

The environment contains an active AXI-Lite agent, an active input AXI-Stream
agent, three independently programmable output backpressure agents, a passive
record reconstruction monitor, virtual sequencer, independent FIPS-197 / NIST
SP 800-38D scoreboard, named scenario sequences, and functional coverage.

The golden model is executable without UVM:

```text
aesgcm_reference_model_pkg.sv
tb_reference_model.sv
```

It passed the FIPS-197 AES-128 example and the SP 800-38D AES-GCM zero-key
example on XSim 2021.1.

Full UVM status on this workstation: **NOT RUN**. Neither XSim 2021.1 nor
ModelSim Starter 10.5b provides a discoverable UVM 1.2 package/library. Run
`verification/scripts/run_uvm_regression.sh` after installing/configuring a
supported UVM simulator. The script reports NOT RUN rather than PASS when the
library is absent.
