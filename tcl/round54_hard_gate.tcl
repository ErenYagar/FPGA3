# Round54 fail-closed structural/security extension for the Round53 hard gate.
#
# Public API:
#   ::r54_hg::run <experiment> <stage> <audit_file>

namespace eval ::r54_hg {
    namespace export run
    variable audit_channel ""
}

set ::r54_hg::script_dir [file dirname [file normalize [info script]]]
source [file join $::r54_hg::script_dir round53_hard_gate.tcl]

proc ::r54_hg::_log {message} {
    variable audit_channel
    puts $message
    if {$audit_channel ne ""} {
        puts $audit_channel $message
        flush $audit_channel
    }
}

proc ::r54_hg::_fail {message} {
    _log "ROUND54_HARD_GATE_FAIL $message"
    error "ROUND54_HARD_GATE_FAIL: $message"
}

proc ::r54_hg::_one {objects label} {
    if {[llength $objects] != 1} {
        _fail "$label count is [llength $objects], expected 1; objects={$objects}"
    }
    return [lindex $objects 0]
}

proc ::r54_hg::_zeroize_driver {} {
    set cell [_one [get_cells -quiet u_registers/zeroize_pulse_o_reg] \
        "ZEROIZE driver"]
    if {[get_property REF_NAME $cell] ne "FDRE"} {
        _fail "ZEROIZE driver is [get_property REF_NAME $cell], expected FDRE"
    }
    set q [_one [get_pins -quiet ${cell}/Q] "ZEROIZE Q"]
    set net [_one [get_nets -quiet -of_objects $q] "ZEROIZE net"]
    set loads [get_pins -quiet -leaf -of_objects $net \
        -filter {DIRECTION == IN}]
    _log "ROUND54_HG_ZEROIZE_DRIVER cell=$cell ref=FDRE net=$net fanout=[llength $loads] loc=[get_property LOC $cell] bel=[get_property BEL $cell]"
    return [list $cell $q $net]
}

proc ::r54_hg::_pin_net {cell pin_name} {
    set pin [get_pins -quiet ${cell}/${pin_name}]
    if {[llength $pin] == 0} {return ""}
    return [_one [get_nets -quiet -of_objects $pin] "$cell/$pin_name net"]
}

proc ::r54_hg::_zeroize_sources {} {
    set primary [lindex [_zeroize_driver] 0]
    set replicas [get_cells -hier -quiet -filter {
        NAME =~ u_registers/zeroize_pulse_o_reg_replica* && REF_NAME =~ FD*}]
    set sources [concat [list $primary] $replicas]

    set primary_d [get_pins -quiet ${primary}/D]
    set primary_d_net [_one [get_nets -quiet -of_objects $primary_d] \
        "primary ZEROIZE D net"]
    set primary_d_driver_pin [_one [get_pins -quiet -leaf \
        -of_objects $primary_d_net -filter {DIRECTION == OUT}] \
        "primary ZEROIZE D driver"]
    set primary_d_driver [_one [get_cells -quiet -of_objects \
        $primary_d_driver_pin] "primary ZEROIZE D driver cell"]
    set primary_d_ref [get_property REF_NAME $primary_d_driver]
    set primary_d_init [get_property INIT $primary_d_driver]
    set primary_d_starts [lsort [all_fanin -quiet -flat \
        -startpoints_only -to $primary_d]]

    set index 0
    foreach source $sources {
        if {[get_property REF_NAME $source] ne "FDRE" ||
            [get_property INIT $source] ne [get_property INIT $primary]} {
            _fail "ZEROIZE source $source primitive/INIT differs from primary"
        }
        foreach pin_name {C CE R S} {
            if {[_pin_net $source $pin_name] ne
                [_pin_net $primary $pin_name]} {
                _fail "ZEROIZE source $source $pin_name net differs from primary"
            }
        }
        set d_pin [get_pins -quiet ${source}/D]
        set d_net [_one [get_nets -quiet -of_objects $d_pin] \
            "$source D net"]
        set d_driver_pin [_one [get_pins -quiet -leaf -of_objects $d_net \
            -filter {DIRECTION == OUT}] "$source D driver"]
        set d_driver [_one [get_cells -quiet -of_objects $d_driver_pin] \
            "$source D driver cell"]
        set d_starts [lsort [all_fanin -quiet -flat \
            -startpoints_only -to $d_pin]]
        if {[get_property REF_NAME $d_driver] ne $primary_d_ref ||
            [get_property INIT $d_driver] ne $primary_d_init ||
            $d_starts ne $primary_d_starts} {
            _fail "ZEROIZE source $source D cone is not equivalent to primary"
        }
        set q [get_pins -quiet ${source}/Q]
        set net [_one [get_nets -quiet -of_objects $q] "$source Q net"]
        set loads [get_pins -quiet -leaf -of_objects $net \
            -filter {DIRECTION == IN}]
        set role [expr {$source eq $primary ? "primary" : "replica"}]
        _log "ROUND54_HG_ZEROIZE_SOURCE index=$index role=$role cell=$source ref=FDRE d_driver=$d_driver d_ref=$primary_d_ref d_init=$primary_d_init loc=[get_property LOC $source] bel=[get_property BEL $source] net=$net fanout=[llength $loads] loads={$loads}"
        incr index
    }
    _log "ROUND54_HG_ZEROIZE_REPLICAS count=[llength $replicas] sources={$sources}"
    return $sources
}

proc ::r54_hg::_logical_zeroize_reaches {sources pin} {
    set starts [all_fanin -quiet -flat -startpoints_only -to $pin]
    foreach source $sources {
        set c [get_pins -quiet ${source}/C]
        if {$c in $starts} {return 1}
        set q [get_pins -quiet ${source}/Q]
        if {[llength [get_timing_paths -quiet -from $q -to $pin \
                -delay_type max -max_paths 1 -nworst 1]] > 0} {
            return 1
        }
    }
    return 0
}

proc ::r54_hg::_prep_tag {experiment stage} {
    set cells [get_cells -hier -quiet \
        -filter {NAME =~ *prep_tag_bytes_reg* && REF_NAME =~ FD*}]
    if {[llength $cells] != 5} {
        _fail "prep_tag mapped cell count is [llength $cells], expected 5"
    }
    set zeroize_sources [_zeroize_sources]
    set zeroize_bits 0
    set zeroize_pin_paths 0
    set zseq_in_reset_cone 0
    set pin_distribution [dict create]
    foreach cell $cells {
        set bit_has_zeroize 0
        set d_levels "NA"
        set d_pin [get_pins -quiet ${cell}/D]
        if {[llength $d_pin] == 1} {
            set d_path [get_timing_paths -quiet -to $d_pin -delay_type max \
                -max_paths 1 -nworst 1]
            if {[llength $d_path] == 1} {
                set d_levels [get_property LOGIC_LEVELS $d_path]
            }
        }
        foreach pin_name {D CE R S} {
            set pins [get_pins -quiet ${cell}/${pin_name}]
            if {[llength $pins] == 0} {continue}
            dict incr pin_distribution $pin_name
            set pin [lindex $pins 0]
            if {[_logical_zeroize_reaches $zeroize_sources $pin]} {
                incr zeroize_pin_paths
                set bit_has_zeroize 1
            }
            if {$pin_name in {R S}} {
                foreach object [all_fanin -quiet -flat -to $pin] {
                    if {[string match "*zeroize_sequence_active_r_reg*" $object]} {
                        set zseq_in_reset_cone 1
                    }
                }
            }
        }
        if {$bit_has_zeroize} {incr zeroize_bits}
        _log "ROUND54_HG_PREP_TAG_BIT stage=$stage cell=$cell ref=[get_property REF_NAME $cell] pins={[get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]} d_levels=$d_levels loc=[get_property LOC $cell] bel=[get_property BEL $cell]"
    }
    _log "ROUND54_HG_PREP_TAG experiment=$experiment cells=[llength $cells] zeroize_bits=$zeroize_bits zeroize_pin_paths=$zeroize_pin_paths zseq_in_reset_cone=$zseq_in_reset_cone pins={$pin_distribution}"
    if {$zeroize_bits != 5} {
        _fail "raw ZEROIZE reaches $zeroize_bits prep_tag bits, expected 5"
    }
    if {[string match "B*" $experiment] && $zseq_in_reset_cone} {
        _fail "R54-B prep_tag clear cone still contains zseq decode"
    }
    if {[string match "C*" $experiment] && $stage ne "synth" &&
        [dict exists $pin_distribution R]} {
        _fail "R54-C targeted remap retained prep_tag R pins"
    }
}

proc ::r54_hg::_ciphertext_structure {experiment stage} {
    set head_cells [get_cells -hier -quiet \
        -filter {NAME =~ *u_ciphertext_fifo/out_data_q_reg* && REF_NAME =~ FD*}]
    if {[llength $head_cells] == 0} {
        _fail "ciphertext FIFO head registers are missing"
    }
    set zeroize_sources [_zeroize_sources]
    set ce_paths 0
    foreach cell $head_cells {
        set ce [get_pins -quiet ${cell}/CE]
        if {[llength $ce] == 1 &&
            [_logical_zeroize_reaches $zeroize_sources $ce]} {
            incr ce_paths
        }
    }
    set we_cells [get_cells -hier -quiet -filter {
        NAME =~ *u_ciphertext_fifo* && REF_NAME =~ RAM*32}]
    set we_paths 0
    foreach cell $we_cells {
        set we [get_pins -quiet ${cell}/WE]
        if {[llength $we] == 1 &&
            [_logical_zeroize_reaches $zeroize_sources $we]} {
            incr we_paths
        }
    }
    _log "ROUND54_HG_CIPHERTEXT experiment=$experiment stage=$stage head_cells=[llength $head_cells] zeroize_to_ce=$ce_paths we_cells=[llength $we_cells] zeroize_to_we=$we_paths"
    if {[string match "D*" $experiment]} {
        if {$ce_paths >= [llength $head_cells]} {
            _fail "R54-D did not reduce ciphertext head ZEROIZE/CE reachability"
        }
        if {[llength $we_cells] != 36 || $we_paths != 36} {
            _fail "R54-D ciphertext LUTRAM WE structure changed: cells=[llength $we_cells] zeroize_paths=$we_paths expected=36"
        }
    }
}

proc ::r54_hg::_run_body {experiment stage nested_audit_file} {
    if {$stage ni {synth placed routed}} {
        _fail "invalid stage '$stage'"
    }
    # Every Round54 experiment is based on the retained R53-C architecture.
    set metrics [::r53_hg::run C $stage $nested_audit_file]
    _prep_tag $experiment $stage
    _ciphertext_structure $experiment $stage
    _log "ROUND54_HARD_GATE_PASS experiment=$experiment stage=$stage"
    return $metrics
}

proc ::r54_hg::run {experiment stage audit_file} {
    variable audit_channel
    if {$audit_channel ne ""} {error "ROUND54_HARD_GATE: nested run"}
    file mkdir [file dirname [file normalize $audit_file]]
    set audit_channel [open $audit_file w]
    set nested_audit_file ${audit_file}.round53
    if {[catch {_run_body $experiment $stage $nested_audit_file} result options]} {
        catch {close $audit_channel}
        set audit_channel ""
        return -options $options $result
    }
    close $audit_channel
    set audit_channel ""
    return $result
}
