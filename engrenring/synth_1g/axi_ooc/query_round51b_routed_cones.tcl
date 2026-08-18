set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round51b_route_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc dump_cell {label cell_name} {
    set cell [get_cells -quiet $cell_name]
    puts "Q51B_CONE_${label}_COUNT [llength $cell]"
    if {[llength $cell] == 0} { return }
    puts "Q51B_CONE_${label}_CELL name={$cell} ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell]"
    foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
        set net [get_nets -quiet -of_objects $pin]
        set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        puts "Q51B_CONE_${label}_PIN pin={[get_property REF_PIN_NAME $pin]} net={$net} drivers={$drivers}"
    }
}

proc report_family {label from_pin to_pins} {
    set paths [get_timing_paths -quiet -from $from_pin -to $to_pins -delay_type max -max_paths 1000 -nworst 1]
    set neg 0
    set worst ""
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} { incr neg }
        if {$worst eq ""} { set worst $path }
    }
    puts "Q51B_CONE_${label}_PATHS [llength $paths] NEG $neg"
    if {$worst ne ""} {
        puts "Q51B_CONE_${label}_WORST slack=[get_property SLACK $worst] start={[get_property STARTPOINT_PIN $worst]} end={[get_property ENDPOINT_PIN $worst]} levels=[get_property LOGIC_LEVELS $worst] delay=[get_property DATAPATH_DELAY $worst]"
    }
}

proc report_internal {label} {
    set regs [all_registers]
    set paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 5 -nworst 1]
    puts "Q51B_MASK_${label}_COUNT [llength $paths]"
    foreach path $paths {
        puts "Q51B_MASK_${label} slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

# Exact cells on the routed worst busy -> J0 CE path.
dump_cell BUSY0 {u_core/u_aes_request_fifo/tag_mask_reg[127]_i_2_replica}
dump_cell BUSY1 {u_core/u_ghash/input_field_mode_r[2]_i_4}
dump_cell BUSY2 {u_core/u_ghash/j0_reg[127]_i_1_replica}

# Exact cells on the routed worst field-mode -> IV96-shadow D path.
dump_cell MODE0 {u_core/crypto_context_live_r_i_5}
dump_cell MODE1 {u_core/abort_code[0]_i_3}
dump_cell MODE2 {u_core/iv96_shadow_r[95]_i_3}
dump_cell MODE3 {u_core/iv96_shadow_r[71]_i_2}
dump_cell MODE4 {u_core/iv96_shadow_r[66]_i_1}

set busy_q [get_pins -quiet {u_core/zeroize_busy_r_reg/Q}]
set j0_ce [get_pins -hier -quiet -filter {REF_PIN_NAME == CE && NAME =~ *j0_reg_reg*}]
set mode_q [get_pins -quiet {u_core/input_field_mode_r_reg[0]/Q}]
set iv_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ *iv96_shadow_r_reg*}]
set abort_q [get_pins -hier -quiet -filter {REF_PIN_NAME == Q && NAME =~ *zeroize_abort_count_reg*}]
set final_r [get_pins -hier -quiet -filter {REF_PIN_NAME == R && NAME =~ *final_tag_reg_reg*}]

puts "Q51B_CONE_OBJECTS busy=[llength $busy_q] j0ce=[llength $j0_ce] mode=[llength $mode_q] ivd=[llength $iv_d] abortq=[llength $abort_q] finalr=[llength $final_r]"
report_family BUSY_TO_J0 $busy_q $j0_ce
report_family MODE_TO_IV $mode_q $iv_d
report_family ABORT_TO_FINAL $abort_q $final_r
report_internal BASE

# Cumulative ideal family masks, kept only in this in-memory routed design.
set_false_path -from $busy_q -to $j0_ce
report_internal NO_BUSY_J0
set_false_path -from $mode_q -to $iv_d
report_internal NO_BUSY_J0_MODE_IV
set_false_path -from $abort_q -to $final_r
report_internal NO_BUSY_J0_MODE_IV_ABORT_FINAL

close_design
exit 0
