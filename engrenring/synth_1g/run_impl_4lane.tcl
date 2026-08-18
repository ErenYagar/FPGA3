set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir .. rtl source]]
set report_dir [file join $script_dir reports_4lane]
file mkdir $report_dir

set_part xc7a100tcsg324-1

read_verilog [file join $rtl_dir aes_core sbox.v]
read_verilog [file join $rtl_dir aes_core AES_e.v]
read_verilog [file join $rtl_dir ctr aes_ctr_wrapper.v]
read_verilog [file join $rtl_dir AESGCM_IO IV_IN.v]
read_verilog [file join $rtl_dir AESGCM_IO AAD_CT_IN.v]
read_verilog [file join $rtl_dir AESGCM_IO GHASH.v]
read_verilog [file join $rtl_dir aes_gcm_lane.v]
read_verilog [file join $rtl_dir top.v]
read_xdc [file join $script_dir top_200mhz.xdc]

synth_design -top top -part xc7a100tcsg324-1 -generic LANES=4 -flatten_hierarchy rebuilt
write_checkpoint -force [file join $script_dir top_4lane_synth.dcp]
report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir timing_synth.rpt]

opt_design
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
route_design -directive Explore

write_checkpoint -force [file join $script_dir top_4lane_routed.dcp]
report_utilization -file [file join $report_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_routed.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_methodology -file [file join $report_dir methodology_routed.rpt]

puts "IMPLEMENTATION_COMPLETE lanes=4 part=xc7a100tcsg324-1 clock_period_ns=5.000"
exit
