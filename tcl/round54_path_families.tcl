# Round54 routed internal path-family decoder for Vivado 2021.1.
#
# Public API:
#   ::r54_paths::run <output_prefix>
#
# The caller must have one open design.  The procedure writes
# <output_prefix>_paths.tsv and <output_prefix>_summary.tsv and returns the
# internal timing metric dictionary.  No constraints or design properties are
# changed.

namespace eval ::r54_paths {
    namespace export run collect_metrics
}

proc ::r54_paths::_safe_property {object property} {
    if {$object eq "" || [catch {get_property $property $object} value] ||
        $value eq ""} {
        return "NA"
    }
    return $value
}

proc ::r54_paths::_tsv {value} {
    return [string map [list "\t" " " "\r" " " "\n" " " ] $value]
}

proc ::r54_paths::_parent_cell {pin} {
    set cells [get_cells -quiet -of_objects $pin]
    return [expr {[llength $cells] == 1 ? [lindex $cells 0] : ""}]
}

proc ::r54_paths::_sum_slack {paths} {
    set total 0.0
    foreach path $paths {
        set total [expr {$total + double([get_property SLACK $path])}]
    }
    return $total
}

proc ::r54_paths::collect_metrics {} {
    set registers [all_registers]
    if {[llength $registers] == 0} {
        error "ROUND54_PATHS: all_registers returned no objects"
    }
    set setup_top [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -max_paths 1 -nworst 1]
    set hold_top [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type min -max_paths 1 -nworst 1]
    if {[llength $setup_top] != 1 || [llength $hold_top] != 1} {
        error "ROUND54_PATHS: internal setup/hold path collection is empty"
    }
    set setup_failing [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set hold_failing [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    return [dict create \
        setup_wns [expr {double([get_property SLACK [lindex $setup_top 0]])}] \
        setup_tns [_sum_slack $setup_failing] \
        setup_fep [llength $setup_failing] \
        hold_whs [expr {double([get_property SLACK [lindex $hold_top 0]])}] \
        hold_ths [_sum_slack $hold_failing] \
        hold_fep [llength $hold_failing]]
}

proc ::r54_paths::_xy {cell} {
    set loc [_safe_property $cell LOC]
    if {[regexp {_X([0-9]+)Y([0-9]+)$} $loc whole x y]} {
        return [list $x $y]
    }
    return [list NA NA]
}

proc ::r54_paths::_clock_region {cell} {
    if {$cell eq "" || [llength [info commands get_clock_regions]] == 0} {
        return "NA"
    }
    set regions [get_clock_regions -quiet -of_objects $cell]
    return [expr {[llength $regions] == 1 ? [lindex $regions 0] : "NA"}]
}

proc ::r54_paths::_source_net_info {cell} {
    if {$cell eq ""} {
        return [list NA NA]
    }
    set q_pins [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT && REF_PIN_NAME == Q}]
    if {[llength $q_pins] != 1} {
        return [list NA NA]
    }
    set nets [get_nets -quiet -of_objects [lindex $q_pins 0]]
    if {[llength $nets] != 1} {
        return [list NA NA]
    }
    set net [lindex $nets 0]
    set loads [get_pins -quiet -leaf -of_objects $net \
        -filter {DIRECTION == IN}]
    return [list $net [llength $loads]]
}

proc ::r54_paths::_is_zeroize_source_name {name} {
    return [regexp {(^|/)zeroize_pulse_o_reg(_replica(_[0-9]+)?)?$} $name]
}

proc ::r54_paths::_cone_flags {endpoint_pin} {
    set starts [all_fanin -quiet -flat -startpoints_only -to $endpoint_pin]
    set start_names [join $starts ";"]
    set zeroize 0
    set abort_clear 0
    set zseq 0
    foreach start $starts {
        set start_cell [file dirname $start]
        if {[_is_zeroize_source_name $start_cell]} {set zeroize 1}
        if {[string match "*abort_queue_clear_reg/C" $start]} {set abort_clear 1}
        if {[string match "*zeroize_sequence_active_r_reg/C" $start]} {set zseq 1}
    }
    return [list $zeroize $abort_clear $zseq $start_names]
}

proc ::r54_paths::_family {source_cell endpoint_cell endpoint_ref endpoint_pin_type flags} {
    set source_name [_safe_property $source_cell NAME]
    set endpoint_name [_safe_property $endpoint_cell NAME]
    set source_zeroize [_is_zeroize_source_name $source_name]
    if {$source_zeroize && [string match "*u_ciphertext_fifo/out_data_q_reg*" $endpoint_name] &&
        $endpoint_ref eq "FDRE" && $endpoint_pin_type eq "CE"} {
        return "ciphertext_head_ce"
    }
    if {$source_zeroize && [string match "*u_ciphertext_fifo/mem_reg*" $endpoint_name] &&
        $endpoint_pin_type eq "WE"} {
        return "ciphertext_lutram_we"
    }
    if {$source_zeroize && [string match "*prep_tag_bytes_reg*" $endpoint_name]} {
        return "prep_tag_zeroize"
    }
    if {$source_zeroize && [string match "*tag_byte_mismatch_r_reg*" $endpoint_name]} {
        return "tag_mismatch_zeroize"
    }
    if {$source_zeroize} {
        return "zeroize_other"
    }
    if {[string match "*u_key_context/FSM_sequential_state_r_reg*" $source_name] &&
        [string match "*u_key_context/round_keys_r_reg*" $endpoint_name]} {
        return "round_key_control"
    }
    if {[string match "*u_keystream_fifo/*" $endpoint_name]} {
        return "keystream_fifo_control"
    }
    if {[string match "*result_data_r_reg*" $endpoint_name]} {
        return "result_control"
    }
    return "other"
}

proc ::r54_paths::_zeroize_class {family endpoint_pin_type endpoint_name} {
    switch -- $family {
        ciphertext_head_ce {return "fifo_clear_register_ce"}
        ciphertext_lutram_we {return "fifo_clear_lutram_we"}
        prep_tag_zeroize {return "non_sensitive_metadata_register_r"}
        tag_mismatch_zeroize {return "state_control_register_d"}
    }
    if {[string match "*data_block_index_reg*" $endpoint_name]} {
        return "state_control_register_r"
    }
    if {$endpoint_pin_type in {R S}} {return "register_r_s"}
    if {$endpoint_pin_type eq "CE"} {return "register_ce"}
    if {$endpoint_pin_type eq "D"} {return "register_d"}
    if {$endpoint_pin_type eq "WE"} {return "ram_we"}
    return "other"
}

proc ::r54_paths::_summary_add {summary_name family slack levels logic_delay net_delay} {
    upvar 1 $summary_name summary
    if {![dict exists $summary $family count]} {
        dict set summary $family count 0
        dict set summary $family tns 0.0
        dict set summary $family worst 1.0e30
        dict set summary $family levels 0.0
        dict set summary $family logic 0.0
        dict set summary $family net 0.0
    }
    dict set summary $family count \
        [expr {[dict get $summary $family count] + 1}]
    dict set summary $family tns \
        [expr {[dict get $summary $family tns] + $slack}]
    if {$slack < [dict get $summary $family worst]} {
        dict set summary $family worst $slack
    }
    dict set summary $family levels \
        [expr {[dict get $summary $family levels] + $levels}]
    dict set summary $family logic \
        [expr {[dict get $summary $family logic] + $logic_delay}]
    dict set summary $family net \
        [expr {[dict get $summary $family net] + $net_delay}]
}

proc ::r54_paths::run {output_prefix} {
    if {[llength [current_design -quiet]] != 1} {
        error "ROUND54_PATHS: exactly one open design is required"
    }
    set output_prefix [file normalize $output_prefix]
    file mkdir [file dirname $output_prefix]
    set path_file ${output_prefix}_paths.tsv
    set summary_file ${output_prefix}_summary.tsv
    foreach output [list $path_file $summary_file] {
        if {[file exists $output]} {
            error "ROUND54_PATHS: refusing to overwrite $output"
        }
    }

    set registers [all_registers]
    set paths [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -max_paths 2000 -nworst 1]
    if {[llength $paths] < 2000} {
        error "ROUND54_PATHS: expected at least 2000 internal candidates, got [llength $paths]"
    }
    set metrics [collect_metrics]
    set failing_paths {}
    foreach path $paths {
        if {double([get_property SLACK $path]) < 0.0} {
            lappend failing_paths $path
        }
    }
    set decoded_tns [_sum_slack $failing_paths]
    if {[llength $failing_paths] != [dict get $metrics setup_fep] ||
        abs($decoded_tns - [dict get $metrics setup_tns]) > 0.0005} {
        error "ROUND54_PATHS: candidate collection does not cover all failures: decoded=[llength $failing_paths]/$decoded_tns metrics=[dict get $metrics setup_fep]/[dict get $metrics setup_tns]"
    }

    set channel [open $path_file w]
    puts $channel [join {rank slack_ns negative startpoint_pin startpoint_cell startpoint_ref endpoint_pin endpoint_pin_type endpoint_cell endpoint_ref hierarchy logic_levels datapath_delay_ns logic_delay_ns net_delay_ns source_net source_physical_fanout source_loc source_bel source_clock_region endpoint_loc endpoint_bel endpoint_clock_region manhattan_xy source_zeroize cone_zeroize cone_abort_queue_clear cone_zseq family zeroize_class fanin_startpoints} "\t"]
    set summary [dict create]
    set rank 0
    foreach path $paths {
        incr rank
        set start_pin [get_property STARTPOINT_PIN $path]
        set endpoint_pin [get_property ENDPOINT_PIN $path]
        set start_cell [_parent_cell $start_pin]
        set endpoint_cell [_parent_cell $endpoint_pin]
        set start_ref [_safe_property $start_cell REF_NAME]
        set endpoint_ref [_safe_property $endpoint_cell REF_NAME]
        set endpoint_pin_type [_safe_property $endpoint_pin REF_PIN_NAME]
        set source_net_info [_source_net_info $start_cell]
        set flags [_cone_flags $endpoint_pin]
        set family [_family $start_cell $endpoint_cell $endpoint_ref \
            $endpoint_pin_type $flags]
        set endpoint_name [_safe_property $endpoint_cell NAME]
        set source_zeroize [_is_zeroize_source_name \
            [_safe_property $start_cell NAME]]
        set zeroize_class [expr {$source_zeroize ?
            [_zeroize_class $family $endpoint_pin_type $endpoint_name] : "NA"}]
        set source_xy [_xy $start_cell]
        set endpoint_xy [_xy $endpoint_cell]
        set manhattan NA
        if {[lindex $source_xy 0] ne "NA" && [lindex $endpoint_xy 0] ne "NA"} {
            set manhattan [expr {abs([lindex $source_xy 0]-[lindex $endpoint_xy 0]) +
                                  abs([lindex $source_xy 1]-[lindex $endpoint_xy 1])}]
        }
        set hierarchy [file dirname $endpoint_name]
        if {$hierarchy eq "."} {set hierarchy "TOP"}
        set slack [expr {double([get_property SLACK $path])}]
        set levels [expr {double([get_property LOGIC_LEVELS $path])}]
        set logic_delay [expr {double([get_property DATAPATH_LOGIC_DELAY $path])}]
        set net_delay [expr {double([get_property DATAPATH_NET_DELAY $path])}]
        set negative [expr {$slack < 0.0}]
        if {$negative} {
            _summary_add summary $family $slack $levels $logic_delay $net_delay
            if {$source_zeroize} {
                _summary_add summary "zeroize:$zeroize_class" $slack $levels \
                    $logic_delay $net_delay
            }
        }
        set fields [list $rank $slack $negative $start_pin \
            [_safe_property $start_cell NAME] $start_ref $endpoint_pin \
            $endpoint_pin_type $endpoint_name $endpoint_ref $hierarchy $levels \
            [get_property DATAPATH_DELAY $path] $logic_delay $net_delay \
            [lindex $source_net_info 0] [lindex $source_net_info 1] \
            [_safe_property $start_cell LOC] [_safe_property $start_cell BEL] \
            [_clock_region $start_cell] [_safe_property $endpoint_cell LOC] \
            [_safe_property $endpoint_cell BEL] [_clock_region $endpoint_cell] \
            $manhattan $source_zeroize [lindex $flags 0] [lindex $flags 1] [lindex $flags 2] \
            $family $zeroize_class [lindex $flags 3]]
        set escaped {}
        foreach field $fields {lappend escaped [_tsv $field]}
        puts $channel [join $escaped "\t"]
    }
    close $channel

    set channel [open $summary_file w]
    puts $channel "family\tcount\ttns_ns\tworst_slack_ns\taverage_slack_ns\taverage_logic_levels\tnet_logic_delay_ratio"
    foreach family [lsort [dict keys $summary]] {
        set count [dict get $summary $family count]
        set logic [dict get $summary $family logic]
        set ratio [expr {$logic > 0.0 ? [dict get $summary $family net]/$logic : "NA"}]
        puts $channel [join [list $family $count \
            [dict get $summary $family tns] \
            [dict get $summary $family worst] \
            [expr {[dict get $summary $family tns]/$count}] \
            [expr {[dict get $summary $family levels]/$count}] $ratio] "\t"]
    }
    close $channel
    puts [format "ROUND54_PATHS_COMPLETE candidates=%d negative_count=%d tns=%.3f path_file=%s summary_file=%s" \
        [llength $paths] [llength $failing_paths] $decoded_tns $path_file $summary_file]
    return $metrics
}
