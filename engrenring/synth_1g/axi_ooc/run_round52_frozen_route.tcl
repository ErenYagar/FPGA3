set script_dir [file dirname [file normalize [info script]]]
set source_dcp [file join $script_dir round52_BF73AC63_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_synth.dcp]
set output_dir [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1]
set report_dir [file join $output_dir reports]
set checkpoint_dir [file join $output_dir checkpoints]

if {![file isfile $source_dcp]} {
    error "Frozen source DCP missing: $source_dcp"
}
if {[file exists $output_dir]} {
    error "Frozen route output already exists: $output_dir"
}
file mkdir $report_dir
file mkdir $checkpoint_dir

puts "ROUND52_FROZEN_BEGIN source=$source_dcp output=$output_dir"
open_checkpoint $source_dcp

puts "ROUND52_PHASE opt_design"
opt_design -directive ExploreWithRemap

puts "ROUND52_PHASE place_design"
place_design -directive ExtraNetDelay_high

puts "ROUND52_PHASE phys_opt_design"
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $checkpoint_dir aes_gcm_axi_top_placed.dcp]
report_utilization -hierarchical -file [file join $report_dir utilization_placed.rpt]
report_timing_summary -delay_type min_max -max_paths 50 -report_unconstrained -file [file join $report_dir timing_placed.rpt]

puts "ROUND52_PHASE route_design"
route_design -directive Explore
write_checkpoint -force [file join $checkpoint_dir aes_gcm_axi_top_routed.dcp]

puts "ROUND52_PHASE routed_reports"
report_utilization -hierarchical -file [file join $report_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 100 -report_unconstrained -file [file join $report_dir timing_routed.rpt]
report_timing -delay_type max -max_paths 200 -file [file join $report_dir timing_internal_setup_200.rpt] -from [all_registers] -to [all_registers]
report_timing -delay_type min -max_paths 200 -file [file join $report_dir timing_internal_hold_200.rpt] -from [all_registers] -to [all_registers]
report_route_status -file [file join $report_dir route_status.rpt]
report_drc -file [file join $report_dir drc_routed.rpt]
report_methodology -file [file join $report_dir methodology_routed.rpt]
check_timing -verbose -file [file join $report_dir check_timing_verbose.rpt]

set registers [all_registers]
set setup_failing [get_timing_paths -quiet -from $registers -to $registers -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set setup_tns 0.0
foreach path $setup_failing {
    set setup_tns [expr {$setup_tns + double([get_property SLACK $path])}]
}
set hold_failing [get_timing_paths -quiet -from $registers -to $registers -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set hold_ths 0.0
foreach path $hold_failing {
    set hold_ths [expr {$hold_ths + double([get_property SLACK $path])}]
}
set setup_wns [expr {[llength $setup_failing] > 0 ? [get_property SLACK [lindex $setup_failing 0]] : 0.0}]
set hold_whs [expr {[llength $hold_failing] > 0 ? [get_property SLACK [lindex $hold_failing 0]] : 0.0}]
puts "ROUND52_INTERNAL setup_wns=$setup_wns setup_tns=$setup_tns setup_fep=[llength $setup_failing] hold_whs=$hold_whs hold_ths=$hold_ths hold_fep=[llength $hold_failing]"
puts "ROUND52_FROZEN_COMPLETE placed=[file join $checkpoint_dir aes_gcm_axi_top_placed.dcp] routed=[file join $checkpoint_dir aes_gcm_axi_top_routed.dcp]"
close_design
exit 0
