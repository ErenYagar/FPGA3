set script_dir [file dirname [file normalize [info script]]]
set dcp [file join $script_dir round51b_DDAA307F_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_synth.dcp]
open_checkpoint $dcp

proc q51b_pin {cell pin_name} {
    set pin_obj [get_pins -quiet ${cell}/${pin_name}]
    set net_obj [get_nets -quiet -of_objects $pin_obj]
    set drivers [get_pins -quiet -leaf -of_objects $net_obj -filter {DIRECTION == OUT}]
    set driver_cells [get_cells -quiet -of_objects $drivers]
    puts "Q51B_PIN cell=$cell pin=$pin_name net={$net_obj} drivers={$drivers} driver_cells={$driver_cells}"
    foreach driver_cell $driver_cells {
        puts "Q51B_DRIVER cell=$driver_cell ref=[get_property REF_NAME $driver_cell] init=[get_property -quiet INIT $driver_cell]"
    }
}

set token_cells [get_cells -hier -quiet -filter {NAME =~ *u_descriptor_idle_token_ff* && REF_NAME =~ FD*}]
puts "Q51B_TOKEN_COUNT [llength $token_cells] cells={$token_cells}"
foreach cell $token_cells {
    puts "Q51B_TOKEN name=$cell ref=[get_property REF_NAME $cell] init=[get_property INIT $cell] keep=[get_property -quiet KEEP $cell] dont_touch=[get_property -quiet DONT_TOUCH $cell]"
    foreach pin_name {D R CE C Q} { q51b_pin $cell $pin_name }
    set d_pin [get_pins $cell/D]
    set r_pin [get_pins $cell/R]
    set ce_pin [get_pins $cell/CE]
    puts "Q51B_D_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $d_pin]}"
    puts "Q51B_R_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $r_pin]}"
    puts "Q51B_CE_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $ce_pin]}"
    report_timing -quiet -to $r_pin -max_paths 50 -path_type full -file [file join $script_dir round51b_token_r_paths.rpt]
    report_timing -quiet -to $ce_pin -max_paths 50 -path_type full -file [file join $script_dir round51b_token_ce_paths.rpt]
}

set old_token_cells [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
set canonical_p [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r_reg* && REF_NAME =~ FD*}]
set pcore [get_cells -hier -quiet -filter {NAME =~ public_frames_idle_core_r_reg && REF_NAME =~ FD*}]
puts "Q51B_OLD_INFERRED_TOKEN_COUNT [llength $old_token_cells] cells={$old_token_cells}"
puts "Q51B_CANONICAL_P_COUNT [llength $canonical_p] cells={$canonical_p}"
puts "Q51B_PCORE_COUNT [llength $pcore] cells={$pcore}"
foreach cell $pcore {
    puts "Q51B_PCORE name=$cell ref=[get_property REF_NAME $cell] init=[get_property INIT $cell] keep=[get_property -quiet KEEP $cell] eqrm=[get_property -quiet EQUIVALENT_REGISTER_REMOVAL $cell]"
}

if {[llength $token_cells] == 1} {
    set token_d [get_pins [lindex $token_cells 0]/D]
    set state_q [get_pins -hier -quiet -filter {REF_PIN_NAME == Q && NAME =~ *state_reg*}]
    set state_to_d [get_timing_paths -quiet -from $state_q -to $token_d -max_paths 100]
    puts "Q51B_STATE_TO_TOKEN_D_PATHS [llength $state_to_d]"
}

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 30]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 5]
foreach path $setup_paths {
    puts "Q51B_SETUP slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}
foreach path $hold_paths {
    puts "Q51B_HOLD slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained -file [file join $script_dir round51b_hardgate_timing_summary.rpt]
close_design
exit 0
