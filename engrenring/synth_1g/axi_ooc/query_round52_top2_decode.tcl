set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1]
open_checkpoint [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc path_line {label rank path} {
    puts "Q52D_${label} rank=$rank slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

proc family {label from_pins to_pins} {
    set paths [get_timing_paths -quiet -from $from_pins -to $to_pins \
        -delay_type max -max_paths 10000 -nworst 10000]
    set neg 0
    set neg_tns 0.0
    set rank 0
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} {
            incr neg
            set neg_tns [expr {$neg_tns + double([get_property SLACK $path])}]
            incr rank
            path_line ${label}_NEG $rank $path
        }
    }
    puts "Q52D_${label}_SUMMARY paths=[llength $paths] neg=$neg neg_tns=$neg_tns"
    if {[llength $paths] > 0} { path_line ${label}_WORST 1 [lindex $paths 0] }
}

proc internal_summary {label} {
    set regs [all_registers]
    set neg_paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set tns 0.0
    foreach path $neg_paths {
        set tns [expr {$tns + double([get_property SLACK $path])}]
    }
    set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -max_paths 8 -nworst 1]
    set wns NA
    if {[llength $top] > 0} { set wns [get_property SLACK [lindex $top 0]] }
    puts "Q52D_MASK_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $neg_paths]"
    set rank 0
    foreach path $top {
        incr rank
        path_line MASK_${label}_TOP $rank $path
    }
}

proc dump_cell {label cell} {
    set cells [get_cells -quiet $cell]
    puts "Q52D_${label}_COUNT [llength $cells] cells={$cells}"
    foreach c $cells {
        puts "Q52D_${label}_CELL name=$c ref=[get_property REF_NAME $c] init=[get_property -quiet INIT $c] loc=[get_property -quiet LOC $c] bel=[get_property -quiet BEL $c]"
        foreach pin [lsort [get_pins -quiet -of_objects $c -filter {DIRECTION == IN}]] {
            set net [get_nets -quiet -of_objects $pin]
            set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
            puts "Q52D_${label}_PIN refpin=[get_property REF_PIN_NAME $pin] pin=$pin net={$net} drivers={$drivers}"
        }
    }
}

set mode1_c [get_pins -quiet {u_core/input_field_mode_r_reg[1]/C}]
set mode1_q [get_pins -quiet {u_core/input_field_mode_r_reg[1]/Q}]
set beat_cells [get_cells -hier -quiet -filter {NAME =~ *block_beat_15_r_reg* && REF_NAME =~ FD*}]
set beat_d [get_pins -quiet -of_objects $beat_cells -filter {REF_PIN_NAME == D}]
set result0_c [get_pins -quiet {u_core/result_data_r_reg[0]/C}]
set result0_q [get_pins -quiet {u_core/result_data_r_reg[0]/Q}]
set state_cells [get_cells -hier -quiet -filter {NAME =~ u_core/state_reg* && REF_NAME =~ FD*}]
set state_d [get_pins -quiet -of_objects $state_cells -filter {REF_PIN_NAME == D}]
set regs [all_registers]
puts "Q52D_OBJECTS mode1c=[llength $mode1_c] mode1q=[llength $mode1_q] beatcells=[llength $beat_cells] beatd=[llength $beat_d] result0c=[llength $result0_c] result0q=[llength $result0_q] statecells=[llength $state_cells] stated=[llength $state_d]"

family MODE1_TO_BEAT15 $mode1_c $beat_d
family RESULT0_TO_STATE $result0_c $state_d
family MODE1_TO_ALL_REGS $mode1_c $regs
family RESULT0_TO_ALL_REGS $result0_c $regs

set mode_worst [get_timing_paths -quiet -from $mode1_c -to $beat_d \
    -delay_type max -max_paths 1 -nworst 1]
set result_worst [get_timing_paths -quiet -from $result0_c -to $state_d \
    -delay_type max -max_paths 1 -nworst 1]
if {[llength $mode_worst] > 0} {
    puts "Q52D_MODE_WORST_PROPERTIES_BEGIN"
    report_property -all [lindex $mode_worst 0]
    puts "Q52D_MODE_WORST_PROPERTIES_END"
}
if {[llength $result_worst] > 0} {
    puts "Q52D_RESULT_WORST_PROPERTIES_BEGIN"
    report_property -all [lindex $result_worst 0]
    puts "Q52D_RESULT_WORST_PROPERTIES_END"
}

report_timing -quiet -from $mode1_q -to $beat_d -delay_type max \
    -max_paths 20 -nworst 20 -path_type full_clock_expanded \
    -file [file join $script_dir round52_mode1_to_beat15_full.rpt]
report_timing -quiet -from $result0_q -to $state_d -delay_type max \
    -max_paths 20 -nworst 20 -path_type full_clock_expanded \
    -file [file join $script_dir round52_result0_to_state_full.rpt]

# Frozen ideal family masks: each exact source/endpoint family is removed only
# in this in-memory routed timing graph. No DCP or source is written.
internal_summary BASE
set_false_path -from $mode1_c -to $beat_d
internal_summary MASK_MODE1_BEAT15
reset_path -from $mode1_c -to $beat_d
set_false_path -from $result0_c -to $state_d
internal_summary MASK_RESULT0_STATE
reset_path -from $result0_c -to $state_d
set_false_path -from $mode1_c -to $beat_d
set_false_path -from $result0_c -to $state_d
internal_summary MASK_BOTH

close_design
exit 0
