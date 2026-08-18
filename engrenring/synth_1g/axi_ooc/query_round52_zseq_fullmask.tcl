set script_dir [file dirname [file normalize [info script]]]
set dcp [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_routed.dcp]
open_checkpoint $dcp

proc dump_cell {label name} {
    set cells [get_cells -quiet $name]
    puts "Q52Z_${label}_COUNT [llength $cells] cells={$cells}"
    foreach cell $cells {
        puts "Q52Z_${label}_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell]"
        foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
            set net [get_nets -quiet -of_objects $pin]
            set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
            puts "Q52Z_${label}_PIN refpin=[get_property REF_PIN_NAME $pin] net={$net} drivers={$drivers}"
        }
        set out [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
        set net [get_nets -quiet -of_objects $out]
        set loads [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]
        puts "Q52Z_${label}_OUT pin={$out} net={$net} loads={$loads}"
    }
}

proc summary {label} {
    set regs [all_registers]
    set neg [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set tns 0.0
    foreach path $neg { set tns [expr {$tns + double([get_property SLACK $path])}] }
    set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -max_paths 12 -nworst 1]
    set wns NA
    if {[llength $top] > 0} { set wns [get_property SLACK [lindex $top 0]] }
    puts "Q52Z_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $neg]"
    set rank 0
    foreach path $top {
        incr rank
        puts "Q52Z_${label}_TOP rank=$rank slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

proc family {label from to} {
    set paths [get_timing_paths -quiet -from $from -to $to -delay_type max \
        -max_paths 100000 -nworst 1]
    set neg 0
    set tns 0.0
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} {
            incr neg
            set tns [expr {$tns + double([get_property SLACK $path])}]
        }
    }
    puts "Q52Z_${label}_SUMMARY PATHS=[llength $paths] NEG=$neg TNS=$tns"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q52Z_${label}_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

dump_cell COUNT_OR_A {u_core/zeroize_abort_count[2]_i_7}
dump_cell COUNT_OR_B {u_core/zeroize_abort_count[2]_i_6}
dump_cell COUNT_OR_ROUTE {u_core/u_desc_fifo/result_data_r[4]_i_7}
dump_cell FIRST_ZEROIZE_PRED {u_core/result_data_r[4]_i_4}
dump_cell RESET_COMMON {u_core/final_tag_reg[127]_i_1_replica}

set result_luts [get_cells -hier -quiet -filter {NAME =~ *result_data_r* && REF_NAME =~ LUT*}]
puts "Q52Z_RESULT_LUTS [llength $result_luts] cells={$result_luts}"
foreach cell $result_luts {
    puts "Q52Z_RESULT_LUT cell=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell]"
}
set state1_nets [get_nets -hier -quiet -filter {NAME =~ *state1*}]
puts "Q52Z_STATE1_NETS [llength $state1_nets] nets={$state1_nets}"
foreach net $state1_nets {
    puts "Q52Z_STATE1 net=$net drivers={[get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]} loads={[get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]}"
}

set regs [all_registers]
set abort_c [get_pins -hier -quiet -filter {NAME =~ *zeroize_abort_count_reg*/C}]
set state_d [get_pins -hier -quiet -filter {NAME =~ u_core/state_reg*/D}]
set predicate_out [get_pins -quiet {u_core/result_data_r[4]_i_4/O}]
set mode_c [get_pins -hier -quiet -filter {NAME =~ *input_field_mode_r_reg*/C}]
set beat_d [get_pins -hier -quiet -filter {NAME =~ *block_beat_15_r_reg*/D}]
family ABORT_COUNT_TO_STATE $abort_c $state_d
set through_paths [get_timing_paths -quiet -from $regs -to $regs -through $predicate_out \
    -delay_type max -max_paths 100000 -nworst 1]
set through_neg 0
set through_tns 0.0
foreach path $through_paths {
    if {[get_property SLACK $path] < 0.0} {
        incr through_neg
        set through_tns [expr {$through_tns + double([get_property SLACK $path])}]
    }
}
puts "Q52Z_PREDICATE_OBSERVER_SUMMARY PATHS=[llength $through_paths] NEG=$through_neg TNS=$through_tns"
if {[llength $through_paths] > 0} {
    set path [lindex $through_paths 0]
    puts "Q52Z_PREDICATE_OBSERVER_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

report_timing -quiet -from $abort_c -to $state_d -delay_type max \
    -max_paths 10 -nworst 1 -path_type full_clock_expanded \
    -file [file join $script_dir round52_abort_count_to_state_full.rpt]
summary BASE
set_false_path -through $predicate_out -to $regs
summary MASK_FULL_ZSEQ_PREDICATE_OUTPUT
set_false_path -from $mode_c -to $beat_d
summary MASK_FULL_ZSEQ_PLUS_MODE_BEAT

close_design
exit 0
