set script_dir [file dirname [file normalize [info script]]]
set report_dir [file join $script_dir reports_4lane]
file mkdir $report_dir

open_checkpoint [file join $script_dir top_4lane_synth.dcp]

opt_design -directive ExploreWithRemap
place_design -directive ExtraNetDelay_high
phys_opt_design -directive AggressiveExplore

report_utilization -file [file join $report_dir utilization_placed.rpt]
report_timing_summary -delay_type max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_placed.rpt]
write_checkpoint -force [file join $script_dir top_4lane_placed.dcp]

route_design -directive Explore
phys_opt_design -directive AggressiveExplore

write_checkpoint -force [file join $script_dir top_4lane_routed.dcp]
report_utilization -file [file join $report_dir utilization_routed.rpt]
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained \
    -file [file join $report_dir timing_routed.rpt]
report_route_status -file [file join $report_dir route_status.rpt]
report_methodology -file [file join $report_dir methodology_routed.rpt]

puts "IMPLEMENTATION_COMPLETE lanes=4 part=xc7a100tcsg324-1 clock_period_ns=5.000"
exit
