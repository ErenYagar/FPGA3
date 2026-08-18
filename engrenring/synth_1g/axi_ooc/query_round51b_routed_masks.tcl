set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round51b_route_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc dump_cell {label cell_name} {
    set cell [get_cells -quiet $cell_name]
    puts "Q51BM_${label}_COUNT [llength $cell]"
    if {[llength $cell] == 0} { return }
    puts "Q51BM_${label}_CELL name={$cell} ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell]"
    foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
        set net [get_nets -quiet -of_objects $pin]
        set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        puts "Q51BM_${label}_PIN pin={[get_property REF_PIN_NAME $pin]} net={$net} drivers={$drivers}"
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
    puts "Q51BM_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $paths]"
    foreach path $top {
        puts "Q51BM_${label}_PATH slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

# Upstream controls which complete the exact IV-shadow and zeroize-count cones.
dump_cell MODE_CAP_ALT {u_core/crypto_context_live_r_i_6}
dump_cell MODE_STATE {u_core/iv96_shadow_r[95]_i_4}
dump_cell ABORT0 {u_core/zeroize_abort_count[2]_i_7}
dump_cell ABORT1 {u_core/zeroize_abort_count[2]_i_6}
dump_cell ABORT2 {u_core/final_tag_reg[127]_i_1_replica}

set busy_c [get_pins -quiet {u_core/zeroize_busy_r_reg/C}]
set j0_ce [get_pins -hier -quiet -filter {REF_PIN_NAME == CE && NAME =~ *j0_reg_reg*}]
set mode_c [get_pins -quiet {u_core/input_field_mode_r_reg[0]/C}]
set iv_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ *iv96_shadow_r_reg*}]
set abort_c [get_pins -hier -quiet -filter {REF_PIN_NAME == C && NAME =~ *zeroize_abort_count_reg*}]
set final_r [get_pins -hier -quiet -filter {REF_PIN_NAME == R && NAME =~ *final_tag_reg_reg*}]
puts "Q51BM_OBJECTS busyc=[llength $busy_c] j0ce=[llength $j0_ce] modec=[llength $mode_c] ivd=[llength $iv_d] abortc=[llength $abort_c] finalr=[llength $final_r]"

internal_summary BASE
set_false_path -from $busy_c -to $j0_ce
internal_summary NO_BUSY_J0
set_false_path -from $mode_c -to $iv_d
internal_summary NO_BUSY_J0_MODE_IV
set_false_path -from $abort_c -to $final_r
internal_summary NO_BUSY_J0_MODE_IV_ABORT_FINAL

close_design
exit 0
