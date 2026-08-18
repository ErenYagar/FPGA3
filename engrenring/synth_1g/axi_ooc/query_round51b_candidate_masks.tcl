set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round51b_route_DDAA307F_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc family {label from_pins to_pins} {
    set paths [get_timing_paths -quiet -from $from_pins -to $to_pins -delay_type max -max_paths 1000 -nworst 1]
    set neg 0
    foreach path $paths { if {[get_property SLACK $path] < 0.0} { incr neg } }
    puts "Q51BC_${label}_COUNT [llength $paths] NEG=$neg"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q51BC_${label}_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

proc summary {label} {
    set regs [all_registers]
    set paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max -slack_lesser_than 0.0 -max_paths 10000 -nworst 1]
    set tns 0.0
    foreach path $paths { set tns [expr {$tns + [get_property SLACK $path]}] }
    set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max -max_paths 6 -nworst 1]
    set wns 0.0
    if {[llength $top] > 0} { set wns [get_property SLACK [lindex $top 0]] }
    puts "Q51BC_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $paths]"
    foreach path $top {
        puts "Q51BC_${label}_PATH slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

set busy_c [get_pins -quiet {u_core/zeroize_busy_r_reg/C}]
set j0_ce [get_pins -hier -quiet -filter {REF_PIN_NAME == CE && NAME =~ *j0_reg_reg*}]
set state_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ u_core/state_reg*}]
set iv_d [get_pins -hier -quiet -filter {REF_PIN_NAME == D && NAME =~ *iv96_shadow_r_reg*}]
set abort_c [get_pins -hier -quiet -filter {REF_PIN_NAME == C && NAME =~ *zeroize_abort_count_reg*}]
set final_r [get_pins -hier -quiet -filter {REF_PIN_NAME == R && NAME =~ *final_tag_reg_reg*}]

set cap_c {}
foreach pat {
    {u_core/input_field_mode_r_reg[0]/C}
    {u_core/input_field_mode_r_reg[1]/C}
    {u_core/input_field_mode_r_reg[2]/C}
    {u_core/gh_input_slot_free_r_reg/C}
    {u_core/data_block_capacity_r_reg/C}
    {u_core/block_beat_15_r_reg/C}
    {u_core/field_last_r_reg/C}
} {
    lappend cap_c {*}[get_pins -quiet $pat]
}

family BUSY_STATE $busy_c $state_d
family BUSY_J0 $busy_c $j0_ce
family CAPACITY_IV $cap_c $iv_d
family ABORT_FINAL $abort_c $final_r
summary BASE

# Ideal structural effect of the approved J0 qualifier and IV96 local event.
set_false_path -from $busy_c -to $j0_ce
foreach source $cap_c { set_false_path -from $source -to $iv_d }
summary J0_AND_IV_EVENT
set_false_path -from $busy_c -to $state_d
summary PLUS_OBSERVE_BUSY
set_false_path -from $abort_c -to $final_r
summary PLUS_ZSEQ_FINAL

close_design
exit 0
