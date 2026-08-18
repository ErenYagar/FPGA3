set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round51b_route_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc q51b_one_path {label args} {
    set paths [get_timing_paths -quiet {*}$args -max_paths 1]
    puts "Q51B_ROUTE_${label}_COUNT [llength $paths]"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q51B_ROUTE_${label} slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

set token [get_cells -hier -quiet -filter {NAME =~ *u_descriptor_idle_token_ff && REF_NAME == FDRE}]
puts "Q51B_ROUTE_TOKEN_COUNT [llength $token] cells={$token}"
foreach cell $token {
    puts "Q51B_ROUTE_TOKEN name=$cell ref=[get_property REF_NAME $cell] init=[get_property INIT $cell] keep=[get_property -quiet KEEP $cell] dont_touch=[get_property -quiet DONT_TOUCH $cell]"
    foreach pin_name {D R CE C Q} {
        set pin_obj [get_pins $cell/$pin_name]
        set net_obj [get_nets -quiet -of_objects $pin_obj]
        set drivers [get_pins -quiet -leaf -of_objects $net_obj -filter {DIRECTION == OUT}]
        puts "Q51B_ROUTE_PIN pin=$pin_name net={$net_obj} drivers={$drivers}"
    }
    q51b_one_path TOKEN_R -to [get_pins $cell/R] -delay_type max
    q51b_one_path TOKEN_CE -to [get_pins $cell/CE] -delay_type max
    set state_q [get_pins -hier -quiet -filter {REF_PIN_NAME == Q && NAME =~ *state_reg*}]
    set state_to_d [get_timing_paths -quiet -from $state_q -to [get_pins $cell/D] -max_paths 100]
    puts "Q51B_ROUTE_STATE_TO_TOKEN_D_COUNT [llength $state_to_d]"
}

set old_token [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
set canonical_p [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r_reg* && REF_NAME =~ FD*}]
set pcore [get_cells -hier -quiet -filter {NAME =~ public_frames_idle_core_r_reg && REF_NAME =~ FD*}]
puts "Q51B_ROUTE_OLD_TOKEN_COUNT [llength $old_token]"
puts "Q51B_ROUTE_CANONICAL_P_COUNT [llength $canonical_p]"
puts "Q51B_ROUTE_PCORE_COUNT [llength $pcore] cells={$pcore}"
foreach cell $pcore {
    puts "Q51B_ROUTE_PCORE name=$cell ref=[get_property REF_NAME $cell] init=[get_property INIT $cell] keep=[get_property -quiet KEEP $cell] eqrm=[get_property -quiet EQUIVALENT_REGISTER_REMOVAL $cell]"
}

set regs [all_registers]
set top_paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 30]
foreach path $top_paths {
    puts "Q51B_ROUTE_INTERNAL slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

set zero_busy_q [get_pins -hier -quiet -filter {NAME =~ *zeroize_busy_r_reg*/Q}]
set j0_ce [get_pins -hier -quiet -filter {NAME =~ *j0_reg_reg*/CE}]
set mode0_q [get_pins -hier -quiet -filter {NAME =~ *input_field_mode_r_reg\[0\]/Q}]
set ivshadow_d [get_pins -hier -quiet -filter {NAME =~ *iv96_shadow_r_reg*/D}]
set abort_count_q [get_pins -hier -quiet -filter {NAME =~ *zeroize_abort_count_reg*/Q}]
set final_tag_r [get_pins -hier -quiet -filter {NAME =~ *final_tag_reg_reg*/R}]
q51b_one_path ZERO_BUSY_TO_J0_CE -from $zero_busy_q -to $j0_ce -delay_type max
q51b_one_path MODE0_TO_IVSHADOW_D -from $mode0_q -to $ivshadow_d -delay_type max
q51b_one_path ABORT_COUNT_TO_FINAL_TAG_R -from $abort_count_q -to $final_tag_r -delay_type max

close_design
exit 0
