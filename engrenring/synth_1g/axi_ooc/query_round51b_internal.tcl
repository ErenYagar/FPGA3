set script_dir [file dirname [file normalize [info script]]]
set run_dir [file join $script_dir round51b_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $run_dir checkpoints aes_gcm_axi_top_synth.dcp]

set regs [all_registers]
set setup_failing [get_timing_paths -quiet -from $regs -to $regs -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set setup_tns 0.0
foreach path $setup_failing { set setup_tns [expr {$setup_tns + double([get_property SLACK $path])}] }
set hold_failing [get_timing_paths -quiet -from $regs -to $regs -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
set hold_ths 0.0
foreach path $hold_failing { set hold_ths [expr {$hold_ths + double([get_property SLACK $path])}] }
set setup_wns [expr {[llength $setup_failing] > 0 ? [get_property SLACK [lindex $setup_failing 0]] : 0.0}]
set hold_whs [expr {[llength $hold_failing] > 0 ? [get_property SLACK [lindex $hold_failing 0]] : 0.0}]
puts "Q51B_INTERNAL_SUMMARY setup_wns=$setup_wns setup_tns=$setup_tns setup_fep=[llength $setup_failing] hold_whs=$hold_whs hold_ths=$hold_ths hold_fep=[llength $hold_failing]"
set paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 40]
puts "Q51B_INTERNAL_TOP_COUNT [llength $paths]"
foreach path $paths {
    puts "Q51B_INTERNAL slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

set mode0 [get_pins -hier -quiet -filter {NAME =~ *input_field_mode_r_reg\[0\]/Q}]
set state_d [get_pins -hier -quiet -filter {NAME =~ *state_reg*/D}]
set block_ce [get_pins -hier -quiet -filter {NAME =~ *block_byte_index_reg*/CE || NAME =~ *input_block_reg*/CE}]
foreach query [list [list MODE0_TO_STATE $mode0 $state_d] [list MODE0_TO_BLOCK_CE $mode0 $block_ce]] {
    lassign $query label from_obj to_obj
    set qpaths [get_timing_paths -quiet -from $from_obj -to $to_obj -max_paths 100]
    puts "Q51B_${label}_COUNT [llength $qpaths]"
    if {[llength $qpaths] > 0} {
        set qfirst [lindex $qpaths 0]
        puts "Q51B_${label}_WORST slack=[get_property SLACK $qfirst] start={[get_property STARTPOINT_PIN $qfirst]} end={[get_property ENDPOINT_PIN $qfirst]} levels=[get_property LOGIC_LEVELS $qfirst] delay=[get_property DATAPATH_DELAY $qfirst]"
    }
}
close_design
exit 0
