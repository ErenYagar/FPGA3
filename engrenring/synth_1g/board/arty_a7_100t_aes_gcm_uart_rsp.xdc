## Arty A7-100T constraints for the FPGA3 AES-GCM NIST UART runner.
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -name sys_clk_pin -period 10.000 -waveform {0.000 5.000} [get_ports clk]

set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports rst_btn]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_txd_in]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_rxd_out]

## These board inputs have no phase relationship to either FPGA clock.  The
## reset qualifier and UART receiver synchronize them internally, so a
## clock-relative input delay would describe a timing contract that does not
## exist.  Only paths launched at the asynchronous top-level ports are cut;
## the downstream register-to-register synchronizer paths remain timed.
set_false_path -from [get_ports {rst_btn uart_txd_in}]

set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

## UART TX is an asynchronous serial interface and the LEDs are status-only;
## neither is captured by an external device against sys_clk_pin.  Exclude
## only the top-level output paths instead of inventing output delays.
set_false_path -to [get_ports {
    uart_rxd_out led[0] led[1] led[2] led[3]
}]

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
