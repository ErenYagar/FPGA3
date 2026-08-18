set script_dir [file dirname [file normalize [info script]]]
set dcp [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_routed.dcp]
open_checkpoint $dcp

proc family {label from_objects to_objects} {
    puts "Q52L_${label}_OBJECTS FROM=[llength $from_objects] TO=[llength $to_objects]"
    if {[llength $from_objects] == 0 || [llength $to_objects] == 0} {
        puts "Q52L_${label}_SUMMARY EMPTY"
        return
    }
    set paths [get_timing_paths -quiet -from $from_objects -to $to_objects \
        -delay_type max -max_paths 100000 -nworst 1]
    set neg 0
    set tns 0.0
    foreach path $paths {
        if {[get_property SLACK $path] < 0.0} {
            incr neg
            set tns [expr {$tns + double([get_property SLACK $path])}]
        }
    }
    puts "Q52L_${label}_SUMMARY PATHS=[llength $paths] NEG=$neg TNS=$tns"
    if {[llength $paths] > 0} {
        set path [lindex $paths 0]
        puts "Q52L_${label}_WORST slack=[get_property SLACK $path] start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path] delay=[get_property DATAPATH_DELAY $path]"
    }
}

set beat_d [get_pins -hier -quiet -filter {NAME =~ *block_beat_15_r_reg*/D}]
set state_c [get_pins -hier -quiet -filter {NAME =~ u_core/state_reg*/C}]
set reciv_c [get_pins -hier -quiet -filter {NAME =~ *rec_iv_is_96_r_reg*/C}]
set ghslot_c [get_pins -hier -quiet -filter {NAME =~ *gh_input_slot_free_r_reg*/C}]
set datacap_c [get_pins -hier -quiet -filter {NAME =~ *data_block_capacity_r_reg*/C}]
set fieldlast_c [get_pins -hier -quiet -filter {NAME =~ *field_last_r_reg*/C}]
set blockbeat_c [get_pins -hier -quiet -filter {NAME =~ *block_beat_15_r_reg*/C}]
set recordlast_c [get_pins -hier -quiet -filter {NAME =~ *record_last_r_reg*/C}]
set valid_port [get_ports -quiet s_axis_tvalid]
set tlast_port [get_ports -quiet s_axis_tlast]

family STATE_TO_BEAT15 $state_c $beat_d
family RECIV_TO_BEAT15 $reciv_c $beat_d
family GHSLOT_TO_BEAT15 $ghslot_c $beat_d
family DATACAP_TO_BEAT15 $datacap_c $beat_d
family FIELDLAST_TO_BEAT15 $fieldlast_c $beat_d
family BLOCKBEAT_TO_BEAT15 $blockbeat_c $beat_d
family RECORDLAST_TO_BEAT15 $recordlast_c $beat_d
family S_AXIS_TVALID_TO_BEAT15 $valid_port $beat_d
family S_AXIS_TLAST_TO_BEAT15 $tlast_port $beat_d

close_design
exit 0
