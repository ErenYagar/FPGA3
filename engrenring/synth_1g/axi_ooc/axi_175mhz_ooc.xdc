# Out-of-context timing contract for aes_gcm_axi_top at 175 MHz.
#
# 5.714 ns is slightly stricter than the exact 175 MHz period
# (5.714285... ns). The existing 1 ns OOC boundary budgets are retained.

create_clock -name aclk -period 5.714 -waveform {0.000 2.857} \
    [get_ports aclk]

set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]

set ooc_input_ports [get_ports -filter \
    {DIRECTION == IN && NAME != aclk}]
set ooc_output_ports [get_ports -filter {DIRECTION == OUT}]

set_input_delay -clock [get_clocks aclk] -max 1.000 $ooc_input_ports
set_input_delay -clock [get_clocks aclk] -min 0.000 $ooc_input_ports
set_output_delay -clock [get_clocks aclk] -max 1.000 $ooc_output_ports
set_output_delay -clock [get_clocks aclk] -min 0.000 $ooc_output_ports

# aresetn remains a synchronous active-low input.  It is deliberately not
# declared asynchronous or false at the lower target frequency.
