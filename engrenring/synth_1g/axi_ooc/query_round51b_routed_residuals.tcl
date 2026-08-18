set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round51b_route_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc dump_cell {label cell_name} {
    set cell [get_cells -quiet $cell_name]
    puts "Q51BR_${label}_COUNT [llength $cell]"
    if {[llength $cell] == 0} { return }
    puts "Q51BR_${label}_CELL name={$cell} ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell]"
    foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
        set net [get_nets -quiet -of_objects $pin]
        set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        puts "Q51BR_${label}_PIN pin={[get_property REF_PIN_NAME $pin]} net={$net} drivers={$drivers}"
    }
}

dump_cell ABORT0 {u_core/u_desc_fifo/rec_tag_byte_enable_r[15]_i_3}
dump_cell ABORT1 {u_core/result_data_r[4]_i_4}
dump_cell ABORT2 {u_core/bank_allocated[1]_i_3_replica}
dump_cell STATE0 {u_core/u_aes_request_fifo/tag_mask_reg[127]_i_2_rewire}
dump_cell STATE1 {u_core/u_aes_result_fifo/crypto_context_live_r_i_4_rewire}
dump_cell STATE2 {u_core/u_tag_packet_fifo/state[3]_i_13}
dump_cell STATE3 {u_core/u_tag_packet_fifo/i_6_LOPT_REMAP}
dump_cell STATE4 {u_core/u_tag_packet_fifo/i_0_LOPT_REMAP_1}
dump_cell STATE5 {u_core/u_tag_packet_fifo/i_9_LOPT_REMAP}
dump_cell STATE6 {u_core/u_tag_packet_fifo/i_0_LOPT_REMAP_2}

set regs [all_registers]
set mode_c [get_pins -quiet {u_core/input_field_mode_r_reg[0]/C}]
set iv_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ *iv96_shadow_r_reg*}]
set_false_path -from $mode_c -to $iv_d
set residual [get_timing_paths -quiet -from $regs -to $iv_d -delay_type max -max_paths 20 -nworst 1]
puts "Q51BR_MODE_IV_RESIDUAL_COUNT [llength $residual]"
foreach path $residual {
    puts "Q51BR_MODE_IV_RESIDUAL slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

# Direct-source headroom for a state/descriptor-qualified IV96 capture event.
set state_c [get_pins -hier -quiet -filter {REF_PIN_NAME == C && NAME =~ *state_reg*}]
set reciv_c [get_pins -quiet {u_core/rec_iv_is_96_r_reg/C}]
foreach pair [list [list STATE $state_c] [list RECIV $reciv_c]] {
    set label [lindex $pair 0]
    set from [lindex $pair 1]
    set paths [get_timing_paths -quiet -from $from -to $iv_d -delay_type max -max_paths 1000 -nworst 1]
    set neg 0
    foreach path $paths { if {[get_property SLACK $path] < 0.0} { incr neg } }
    puts "Q51BR_${label}_TO_IV_COUNT [llength $paths] NEG $neg"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q51BR_${label}_TO_IV_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

proc internal_summary {label} {
    set regs [all_registers]
    set paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max -slack_lesser_than 0.0 -max_paths 10000 -nworst 1]
    set tns 0.0
    foreach path $paths { set tns [expr {$tns + [get_property SLACK $path]}] }
    set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 8 -nworst 1]
    set wns 0.0
    if {[llength $top] > 0} { set wns [get_property SLACK [lindex $top 0]] }
    puts "Q51BR_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $paths]"
    foreach path $top {
        puts "Q51BR_${label}_PATH slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

# Cumulative ideal masks for the four current top structural families.
set busy_c [get_pins -quiet {u_core/zeroize_busy_r_reg/C}]
set j0_ce [get_pins -hier -quiet -filter {REF_PIN_NAME == CE && NAME =~ *j0_reg_reg*}]
set main_state_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ u_core/state_reg*}]
set abort_c [get_pins -hier -quiet -filter {REF_PIN_NAME == C && NAME =~ *zeroize_abort_count_reg*}]
set final_r [get_pins -hier -quiet -filter {REF_PIN_NAME == R && NAME =~ *final_tag_reg_reg*}]
set_false_path -from $busy_c -to $j0_ce
set_false_path -from $mode_c -to $iv_d
internal_summary NO_J0_MODE
set_false_path -from $busy_c -to $main_state_d
internal_summary NO_J0_MODE_BUSY_STATE
set_false_path -from $abort_c -to $final_r
internal_summary NO_J0_MODE_BUSY_STATE_ABORT_FINAL

close_design
exit 0
