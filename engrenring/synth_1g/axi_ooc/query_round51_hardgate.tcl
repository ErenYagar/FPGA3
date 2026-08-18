set script_dir [file dirname [file normalize [info script]]]
set dcp [file join $script_dir round51_7C4C8757_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_synth.dcp]
open_checkpoint $dcp

proc q51_pin_report {cell pin_name} {
    set pin_obj [get_pins -quiet ${cell}/${pin_name}]
    if {[llength $pin_obj] == 0} {
        puts "Q51_PIN cell=$cell pin=$pin_name MISSING"
        return
    }
    set net_obj [get_nets -quiet -of_objects $pin_obj]
    set drivers [get_pins -quiet -of_objects $net_obj -filter {DIRECTION == OUT}]
    set driver_cells [get_cells -quiet -of_objects $drivers]
    puts "Q51_PIN cell=$cell pin=$pin_name net={$net_obj} drivers={$drivers} driver_cells={$driver_cells}"
    foreach driver_cell $driver_cells {
        puts "Q51_DRIVER cell=$driver_cell ref=[get_property REF_NAME $driver_cell] init=[get_property -quiet INIT $driver_cell]"
    }
}

set descriptor_cells [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
puts "Q51_DESCRIPTOR_CELL_COUNT [llength $descriptor_cells] cells={$descriptor_cells}"
foreach cell $descriptor_cells {
    puts "Q51_DESCRIPTOR_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] keep=[get_property -quiet KEEP $cell] extract_reset=[get_property -quiet EXTRACT_RESET $cell] extract_enable=[get_property -quiet EXTRACT_ENABLE $cell] eqrm=[get_property -quiet EQUIVALENT_REGISTER_REMOVAL $cell]"
    foreach pin_name {D R CE C Q} {
        q51_pin_report $cell $pin_name
    }
    set r_pin [get_pins -quiet ${cell}/R]
    set ce_pin [get_pins -quiet ${cell}/CE]
    set d_pin [get_pins -quiet ${cell}/D]
    puts "Q51_R_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $r_pin]}"
    puts "Q51_CE_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $ce_pin]}"
    puts "Q51_D_STARTPOINTS {[all_fanin -quiet -flat -startpoints_only -to $d_pin]}"
    report_timing -quiet -to $r_pin -max_paths 20 -path_type full -file [file join $script_dir round51_descriptor_r_paths.rpt]
    report_timing -quiet -to $ce_pin -max_paths 20 -path_type full -file [file join $script_dir round51_descriptor_ce_paths.rpt]
    report_timing -quiet -to $d_pin -max_paths 20 -path_type full -file [file join $script_dir round51_descriptor_d_paths.rpt]
}

set canonical_cells [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r*}]
set core_cells [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_core_r*}]
puts "Q51_CANONICAL_P_COUNT [llength $canonical_cells] cells={$canonical_cells}"
puts "Q51_PCORE_COUNT [llength $core_cells] cells={$core_cells}"
foreach cell $core_cells {
    puts "Q51_PCORE_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] keep=[get_property -quiet KEEP $cell] eqrm=[get_property -quiet EQUIVALENT_REGISTER_REMOVAL $cell]"
    foreach pin_name {D R CE Q} {
        q51_pin_report $cell $pin_name
    }
}

set state_q [get_pins -hier -quiet -filter {REF_PIN_NAME == Q && NAME =~ *state_reg*}]
set descriptor_d {}
if {[llength $descriptor_cells] == 1} {
    set descriptor_d [get_pins [lindex $descriptor_cells 0]/D]
}
if {[llength $state_q] > 0 && [llength $descriptor_d] > 0} {
    set state_to_descriptor [get_timing_paths -quiet -from $state_q -to $descriptor_d -max_paths 100]
    puts "Q51_STATE_TO_DESCRIPTOR_D_PATHS [llength $state_to_descriptor]"
    if {[llength $state_to_descriptor] > 0} {
        report_timing -of_objects $state_to_descriptor -path_type full -file [file join $script_dir round51_state_to_descriptor_d.rpt]
    }
}

set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 20]
set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 20]
puts "Q51_WORST_SETUP_COUNT [llength $worst_setup]"
foreach path $worst_setup {
    puts "Q51_SETUP slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}
puts "Q51_WORST_HOLD_COUNT [llength $worst_hold]"
foreach path $worst_hold {
    puts "Q51_HOLD slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}
report_timing_summary -delay_type min_max -max_paths 20 -report_unconstrained -file [file join $script_dir round51_hardgate_timing_summary.rpt]
close_design
exit 0
