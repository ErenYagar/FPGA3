# Out-of-context timing contract for aes_gcm_axi_top.
#
# The 1 ns boundary budgets model synchronous logic outside this OOC block;
# they are not substitutes for board-specific PACKAGE_PIN, IOSTANDARD or
# system-level interface timing constraints.

create_clock -name aclk -period 5.000 -waveform {0.000 2.500} \
    [get_ports aclk]

# Representative upstream BUFG site for standalone OOC clock-delay/skew
# estimation.  The integrated design must replace this with the actual BUFG
# location if its clock implementation does not use BUFGCTRL_X0Y0.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]

set ooc_input_ports [get_ports -filter \
    {DIRECTION == IN && NAME != aclk}]
set ooc_output_ports [get_ports -filter {DIRECTION == OUT}]

set_input_delay -clock [get_clocks aclk] -max 1.000 $ooc_input_ports
set_input_delay -clock [get_clocks aclk] -min 0.000 $ooc_input_ports
set_output_delay -clock [get_clocks aclk] -max 1.000 $ooc_output_ports
set_output_delay -clock [get_clocks aclk] -min 0.000 $ooc_output_ports

# aresetn is a synchronous active-low input and is timed by the same 1 ns
# boundary contract; it is intentionally not declared asynchronous/false.
