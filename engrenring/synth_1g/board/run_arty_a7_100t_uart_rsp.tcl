set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. .. ..]]
set rtl_root [file join $repo_root engrenring rtl source]
set output_root [file join $script_dir output]
set top_name arty_a7_100t_aes_gcm_uart_rsp_top
set part_name xc7a100tcsg324-1

if {$argc != 1} {
    error "Usage: run_arty_a7_100t_uart_rsp.tcl <unique_label>"
}
set label [lindex $argv 0]
if {![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    error "Invalid label '$label'"
}
set output_dir [file join $output_root $label]
if {[file exists $output_dir]} {
    error "Refusing to overwrite output directory $output_dir"
}
file mkdir $output_dir

set_part $part_name
read_verilog [file join $rtl_root aes_core sbox.v]
read_verilog [file join $rtl_root stream_aes aes_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_first_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_key_context.v]
read_verilog [file join $rtl_root stream_ghash ghash16.v]
read_verilog [file join $rtl_root stream_axi axi_lite_regs.v]
read_verilog [file join $rtl_root stream_axi axis_output_skid_8.v]
read_verilog [file join $rtl_root stream_core aes_gcm_stream_core.v]
read_verilog [file join $rtl_root stream_core stream_fifo.v]
read_verilog [file join $rtl_root aes_gcm_axi_top.v]
read_verilog [file join $rtl_root board uart_rx.v]
read_verilog [file join $rtl_root board uart_tx.v]
read_verilog [file join $rtl_root board aes_gcm_uart_rsp_bridge.v]
read_verilog [file join $rtl_root board arty_a7_100t_aes_gcm_uart_rsp_top.v]
read_xdc [file join $script_dir arty_a7_100t_aes_gcm_uart_rsp.xdc]

synth_design -top $top_name -part $part_name -flatten_hierarchy rebuilt
write_checkpoint [file join $output_dir ${top_name}_synth.dcp]
report_utilization -hierarchical -file [file join $output_dir utilization_synth.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_synth.rpt]

opt_design -directive ExploreWithRemap
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore
write_checkpoint [file join $output_dir ${top_name}_placed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_placed.rpt]

route_design -directive Explore
write_checkpoint [file join $output_dir ${top_name}_routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $output_dir timing_routed.rpt]
report_timing -delay_type max -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_setup_top200.rpt]
report_timing -delay_type min -max_paths 200 -sort_by slack \
    -file [file join $output_dir timing_hold_top200.rpt]
report_utilization -hierarchical -file [file join $output_dir utilization_routed.rpt]
report_route_status -file [file join $output_dir route_status.rpt]
report_drc -file [file join $output_dir drc_routed.rpt]
report_methodology -file [file join $output_dir methodology_routed.rpt]
report_cdc -details -file [file join $output_dir cdc_routed.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Unable to obtain routed setup/hold paths"
}
set setup_wns [get_property SLACK $setup_path]
set hold_whs [get_property SLACK $hold_path]
set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == "Error"}]]
set drc_critical [llength [get_drc_violations -quiet -filter {SEVERITY == "Critical Warning"}]]
if {$setup_wns < 0.0 || $hold_whs < 0.0} {
    error "Board timing failed: setup_wns=$setup_wns hold_whs=$hold_whs"
}
if {$drc_errors != 0 || $drc_critical != 0} {
    error "Board DRC failed: errors=$drc_errors critical_warnings=$drc_critical"
}

set bit_file [file join $output_dir ${top_name}.bit]
write_bitstream -force -bin_file $bit_file

set metrics [open [file join $output_dir signoff_metrics.txt] w]
puts $metrics "top=$top_name"
puts $metrics "part=$part_name"
puts $metrics "input_clock_mhz=100"
puts $metrics "core_clock_mhz=175"
puts $metrics "uart_baud=115200"
puts $metrics "setup_wns_ns=$setup_wns"
puts $metrics "hold_whs_ns=$hold_whs"
puts $metrics "drc_errors=$drc_errors"
puts $metrics "drc_critical_warnings=$drc_critical"
close $metrics

puts "ARTY_UART_RSP_BUILD_PASS top=$top_name part=$part_name setup_wns=$setup_wns hold_whs=$hold_whs bit=$bit_file"
exit
