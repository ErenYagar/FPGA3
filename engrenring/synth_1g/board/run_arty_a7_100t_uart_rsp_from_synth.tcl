set script_dir [file dirname [file normalize [info script]]]
set output_root [file join $script_dir output]
set top_name arty_a7_100t_aes_gcm_uart_rsp_top

if {$argc != 4} {
    error "Usage: run_arty_a7_100t_uart_rsp_from_synth.tcl <synth_dcp> <sha256> <unique_label> <place_directive>"
}
set input_dcp [file normalize [lindex $argv 0]]
set expected_hash [string toupper [lindex $argv 1]]
set label [lindex $argv 2]
set place_directive [lindex $argv 3]
if {![file isfile $input_dcp]} {
    error "Synth checkpoint not found: $input_dcp"
}
if {![regexp {^[0-9A-F]{64}$} $expected_hash]} {
    error "Expected SHA-256 must be 64 uppercase hexadecimal characters"
}
if {![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    error "Invalid label '$label'"
}
if {![regexp {^[A-Za-z0-9_]+$} $place_directive]} {
    error "Invalid place directive '$place_directive'"
}

set hash_command "(Get-FileHash -Algorithm SHA256 -LiteralPath '$input_dcp').Hash"
set powershell_exe {C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe}
set actual_hash [string toupper [string trim [exec $powershell_exe -NoProfile -NonInteractive -Command $hash_command]]]
if {$actual_hash ne $expected_hash} {
    error "Synth checkpoint SHA-256 mismatch: expected=$expected_hash actual=$actual_hash"
}

set output_dir [file join $output_root $label]
if {[file exists $output_dir]} {
    error "Refusing to overwrite output directory $output_dir"
}
file mkdir $output_dir

open_checkpoint $input_dcp
place_design -directive $place_directive
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

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 100000 -slack_lesser_than 0]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 100000 -slack_lesser_than 0]
set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $worst_setup] != 1 || [llength $worst_hold] != 1} {
    error "Unable to obtain routed setup/hold paths"
}
set setup_wns [get_property SLACK $worst_setup]
set hold_whs [get_property SLACK $worst_hold]
set setup_tns 0.0
foreach path $setup_paths {
    set setup_tns [expr {$setup_tns + [get_property SLACK $path]}]
}
set hold_ths 0.0
foreach path $hold_paths {
    set hold_ths [expr {$hold_ths + [get_property SLACK $path]}]
}
set setup_fep [llength $setup_paths]
set hold_fep [llength $hold_paths]
set drc_errors [llength [get_drc_violations -quiet -filter {SEVERITY == "Error"}]]
set drc_critical [llength [get_drc_violations -quiet -filter {SEVERITY == "Critical Warning"}]]

set metrics [open [file join $output_dir signoff_metrics.txt] w]
puts $metrics "top=$top_name"
puts $metrics "input_synth_dcp=$input_dcp"
puts $metrics "input_synth_sha256=$actual_hash"
puts $metrics "place_directive=$place_directive"
puts $metrics "phys_opt_directive=AggressiveExplore"
puts $metrics "route_directive=Explore"
puts $metrics "core_clock_mhz=175"
puts $metrics "uart_baud=115200"
puts $metrics "setup_wns_ns=$setup_wns"
puts $metrics "setup_tns_ns=$setup_tns"
puts $metrics "setup_failing_endpoints=$setup_fep"
puts $metrics "hold_whs_ns=$hold_whs"
puts $metrics "hold_ths_ns=$hold_ths"
puts $metrics "hold_failing_endpoints=$hold_fep"
puts $metrics "drc_errors=$drc_errors"
puts $metrics "drc_critical_warnings=$drc_critical"
close $metrics

if {$setup_wns < 0.0 || $setup_fep != 0 || $hold_whs < 0.0 || $hold_fep != 0} {
    error "Board timing failed: WNS=$setup_wns TNS=$setup_tns FEP=$setup_fep WHS=$hold_whs THS=$hold_ths hold_FEP=$hold_fep"
}
if {$drc_errors != 0 || $drc_critical != 0} {
    error "Board DRC failed: errors=$drc_errors critical_warnings=$drc_critical"
}

set bit_file [file join $output_dir ${top_name}.bit]
write_bitstream -force -bin_file $bit_file
puts "ARTY_UART_RSP_RESUME_PASS WNS=$setup_wns WHS=$hold_whs bit=$bit_file"
exit
