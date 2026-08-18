set script_dir [file dirname [file normalize [info script]]]
set route_dir [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1]
set dcp [file join $route_dir checkpoints aes_gcm_axi_top_routed.dcp]

proc path_line {label rank path} {
    puts "Q52A_${label} rank=$rank slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
}

proc endpoint_family {label from_pins to_pins} {
    set paths [get_timing_paths -quiet -from $from_pins -to $to_pins \
        -delay_type max -max_paths 100000 -nworst 1]
    set neg 0
    set tns 0.0
    set rank 0
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} {
            incr neg
            set tns [expr {$tns + double([get_property SLACK $path])}]
            incr rank
            path_line ${label}_NEG $rank $path
        }
    }
    puts "Q52A_${label}_SUMMARY PATHS=[llength $paths] NEG=$neg TNS=$tns"
    if {[llength $paths] > 0} { path_line ${label}_WORST 1 [lindex $paths 0] }
}

proc arc_family {label regs arc_in arc_out} {
    set paths [get_timing_paths -quiet -from $regs -to $regs \
        -through $arc_in -through $arc_out -delay_type max \
        -max_paths 100000 -nworst 1]
    set neg 0
    set tns 0.0
    set rank 0
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} {
            incr neg
            set tns [expr {$tns + double([get_property SLACK $path])}]
            incr rank
            path_line ${label}_NEG $rank $path
        }
    }
    puts "Q52A_${label}_SUMMARY PATHS=[llength $paths] NEG=$neg TNS=$tns"
    if {[llength $paths] > 0} { path_line ${label}_WORST 1 [lindex $paths 0] }
}

proc internal_summary {label} {
    set regs [all_registers]
    set paths [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set tns 0.0
    foreach path $paths { set tns [expr {$tns + double([get_property SLACK $path])}] }
    set top [get_timing_paths -quiet -from $regs -to $regs -delay_type max \
        -max_paths 10 -nworst 1]
    set wns NA
    if {[llength $top] > 0} { set wns [get_property SLACK [lindex $top 0]] }
    puts "Q52A_${label}_SUMMARY WNS=$wns TNS=$tns FEP=[llength $paths]"
    set rank 0
    foreach path $top {
        incr rank
        path_line ${label}_TOP $rank $path
    }
}

proc dump_cell {label cell_name} {
    set cell [get_cells -quiet $cell_name]
    puts "Q52A_${label}_COUNT [llength $cell] cells={$cell}"
    if {[llength $cell] != 1} { return }
    puts "Q52A_${label}_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell] bel=[get_property -quiet BEL $cell]"
    foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
        set net [get_nets -quiet -of_objects $pin]
        set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        puts "Q52A_${label}_PIN refpin=[get_property REF_PIN_NAME $pin] pin=$pin net={$net} drivers={$drivers}"
    }
    set out [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
    set out_net [get_nets -quiet -of_objects $out]
    set loads [get_pins -quiet -leaf -of_objects $out_net -filter {DIRECTION == IN}]
    puts "Q52A_${label}_OUT pin={$out} net={$out_net} loads={$loads}"
}

proc get_objects {} {
    set regs [all_registers]
    set mode1_c [get_pins -quiet {u_core/input_field_mode_r_reg[1]/C}]
    set mode_c [get_pins -hier -quiet -filter {NAME =~ *input_field_mode_r_reg*/C}]
    set beat_d [get_pins -hier -quiet -filter {NAME =~ *block_beat_15_r_reg*/D}]
    set result0_c [get_pins -quiet {u_core/result_data_r_reg[0]/C}]
    set result_data_cells [get_cells -hier -quiet -filter {NAME =~ *result_data_r_reg* && REF_NAME =~ FD*}]
    set result_valid_cells [get_cells -hier -quiet -filter {NAME =~ *result_valid_r_reg* && REF_NAME =~ FD*}]
    set result_data_c [get_pins -quiet -of_objects $result_data_cells -filter {REF_PIN_NAME == C}]
    set result_role_c [concat $result_data_c \
        [get_pins -quiet -of_objects $result_valid_cells -filter {REF_PIN_NAME == C}]]
    set state_d [get_pins -hier -quiet -filter {NAME =~ u_core/state_reg*/D}]
    set mode_arc_in [get_pins -quiet {u_core/data_block_index[4]_i_5/I1}]
    set mode_arc_out [get_pins -quiet {u_core/data_block_index[4]_i_5/O}]
    set result_arc_in [get_pins -quiet {u_core/result_valid_r_i_2/I0}]
    set result_arc_out [get_pins -quiet {u_core/result_valid_r_i_2/O}]
    return [list $regs $mode1_c $mode_c $beat_d $result0_c $result_data_c \
        $result_role_c $state_d $mode_arc_in $mode_arc_out $result_arc_in \
        $result_arc_out]
}

# Decode the exact worst-path cells and quantify unique-endpoint families.
open_checkpoint $dcp
dump_cell MODE_FIRST {u_core/data_block_index[4]_i_5}
dump_cell MODE_SECOND {u_core/crypto_context_live_r_i_4}
dump_cell MODE_THIRD {u_core/block_beat_15_r_i_2}
dump_cell MODE_LAST {u_core/u_desc_fifo/block_beat_15_r_i_1_replica}
dump_cell RESULT_FIRST {u_core/result_valid_r_i_2}
dump_cell RESULT_ROLE {u_core/result_data_r[4]_i_4}
dump_cell RESULT_THIRD {u_core/record_last_r_i_6}
dump_cell RESULT_STATE0 {u_core/state[2]_i_4}
set objects [get_objects]
lassign $objects regs mode1_c mode_c beat_d result0_c result_data_c result_role_c state_d mode_arc_in mode_arc_out result_arc_in result_arc_out
puts "Q52A_OBJECTS regs=[llength $regs] mode1c=[llength $mode1_c] modec=[llength $mode_c] beatd=[llength $beat_d] result0c=[llength $result0_c] resultdatac=[llength $result_data_c] resultrolec=[llength $result_role_c] stated=[llength $state_d] modearcin=[llength $mode_arc_in] modearcout=[llength $mode_arc_out] resultarcin=[llength $result_arc_in] resultarcout=[llength $result_arc_out]"
endpoint_family MODE1_TO_BEAT15 $mode1_c $beat_d
endpoint_family MODE_BITS_TO_BEAT15 $mode_c $beat_d
endpoint_family RESULT0_TO_STATE $result0_c $state_d
endpoint_family RESULT_DATA_TO_STATE $result_data_c $state_d
endpoint_family RESULT_ROLE_TO_STATE $result_role_c $state_d
arc_family MODE_FIRST_ARC $regs $mode_arc_in $mode_arc_out
arc_family RESULT_FIRST_ARC $regs $result_arc_in $result_arc_out
internal_summary BASE
set_false_path -through $mode_arc_in -through $mode_arc_out
internal_summary MASK_MODE_FIRST_ARC
set_false_path -through $result_arc_in -through $result_arc_out
internal_summary MASK_BOTH_FIRST_ARCS
close_design

# Independent #2 full result-role/zseq family mask.
open_checkpoint $dcp
set objects [get_objects]
lassign $objects regs mode1_c mode_c beat_d result0_c result_data_c result_role_c state_d mode_arc_in mode_arc_out result_arc_in result_arc_out
set_false_path -from $result_role_c -to $state_d
internal_summary MASK_RESULT_ROLE_TO_STATE_ONLY
close_design

# Full #1 family mask, then cumulative full #1 + #2 masks.
open_checkpoint $dcp
set objects [get_objects]
lassign $objects regs mode1_c mode_c beat_d result0_c result_data_c result_role_c state_d mode_arc_in mode_arc_out result_arc_in result_arc_out
set_false_path -from $mode_c -to $beat_d
internal_summary MASK_ALL_MODE_BITS_TO_BEAT15
set_false_path -from $result_role_c -to $state_d
internal_summary MASK_FULL_BOTH
close_design
exit 0
