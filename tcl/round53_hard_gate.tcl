# Round53 fail-closed netlist/timing legality audit for Vivado 2021.1.
#
# Public API:
#   ::r53_hg::run <A|B|C|D> <synth|placed|routed> <audit_file>
#
# The caller must have an open aes_gcm_axi_top design.  The procedure returns
# a metrics dictionary.  A routed setup miss is reported in that dictionary;
# structural, hold, constraint, routing, DRC, or check_timing violations throw.
# This script never creates timing exceptions.

namespace eval ::r53_hg {
    namespace export run
    variable audit_channel ""
}

proc ::r53_hg::_log {message} {
    variable audit_channel
    puts $message
    if {$audit_channel ne ""} {
        puts $audit_channel $message
        flush $audit_channel
    }
}

proc ::r53_hg::_fail {message} {
    _log "ROUND53_HARD_GATE_FAIL $message"
    error "ROUND53_HARD_GATE_FAIL: $message"
}

proc ::r53_hg::_true {value} {
    expr {$value eq "1" || [string equal -nocase $value "true"] ||
          [string equal -nocase $value "yes"]}
}

proc ::r53_hg::_false {value} {
    expr {$value eq "0" || [string equal -nocase $value "false"] ||
          [string equal -nocase $value "no"]}
}

proc ::r53_hg::_require_nonempty {objects label} {
    if {[llength $objects] == 0} {
        _fail "$label is an empty collection"
    }
    return $objects
}

proc ::r53_hg::_require_one {objects label} {
    if {[llength $objects] != 1} {
        _fail "$label count is [llength $objects], expected exactly 1; objects={$objects}"
    }
    return [lindex $objects 0]
}

proc ::r53_hg::_pin_drivers {cell pin_name label} {
    set pin [_require_one [get_pins -quiet ${cell}/${pin_name}] "$label $pin_name pin"]
    set net [_require_one [get_nets -quiet -of_objects $pin] "$label $pin_name net"]
    set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
    _require_nonempty $drivers "$label $pin_name drivers"
    set driver_cells [get_cells -quiet -of_objects $drivers]
    _log "ROUND53_HG_PIN label=$label pin=$pin net={$net} drivers={$drivers} driver_cells={$driver_cells}"
    return [list $pin $net $drivers $driver_cells]
}

proc ::r53_hg::_clock_pin {cell pin_name label} {
    set pin [_require_one [get_pins -quiet ${cell}/${pin_name}] "$label $pin_name pin"]
    set net [_require_one [get_nets -quiet -of_objects $pin] "$label $pin_name net"]
    set clock [_require_one [get_clocks -quiet -of_objects $pin] "$label $pin_name clock"]
    if {$clock ne "aclk"} {
        _fail "$label $pin_name clock is '$clock', expected aclk"
    }
    _log "ROUND53_HG_CLOCK_PIN label=$label pin=$pin net={$net} clock=$clock"
    return [list $pin $net $clock]
}

proc ::r53_hg::_timing_count {label from_objects to_objects} {
    _require_nonempty $from_objects "$label startpoints"
    _require_nonempty $to_objects "$label endpoints"
    set paths [get_timing_paths -quiet -from $from_objects -to $to_objects \
        -delay_type max -max_paths 10000 -nworst 1]
    set negative 0
    set tns 0.0
    foreach path $paths {
        set slack [expr {double([get_property SLACK $path])}]
        if {$slack < 0.0} {
            incr negative
            set tns [expr {$tns + $slack}]
        }
    }
    if {[llength $paths] > 0} {
        set worst [lindex $paths 0]
        _log "ROUND53_HG_FAMILY label=$label count=[llength $paths] negative=$negative tns=$tns worst_slack=[get_property SLACK $worst] start={[get_property STARTPOINT_PIN $worst]} end={[get_property ENDPOINT_PIN $worst]} levels=[get_property LOGIC_LEVELS $worst] delay=[get_property DATAPATH_DELAY $worst]"
    } else {
        _log "ROUND53_HG_FAMILY label=$label count=0 negative=0 tns=0.0"
    }
    return [llength $paths]
}

proc ::r53_hg::_check_logic_depth {label from_objects to_objects max_levels} {
    _require_nonempty $from_objects "$label startpoints"
    _require_nonempty $to_objects "$label endpoints"
    set paths [_require_nonempty \
        [get_timing_paths -quiet -from $from_objects -to $to_objects \
            -delay_type max -max_paths 10000 -nworst 1] \
        "$label timing paths"]
    set observed_max 0
    foreach path $paths {
        set levels [get_property LOGIC_LEVELS $path]
        if {$levels > $observed_max} {
            set observed_max $levels
        }
    }
    _log "ROUND53_HG_LOGIC_DEPTH label=$label observed_max=$observed_max allowed_max=$max_levels"
    if {$observed_max > $max_levels} {
        _fail "$label logic depth is $observed_max, exceeds locked maximum $max_levels"
    }
}

proc ::r53_hg::_sum_slack {paths} {
    set total 0.0
    foreach path $paths {
        set total [expr {$total + double([get_property SLACK $path])}]
    }
    return $total
}

proc ::r53_hg::_check_clock {} {
    set clocks [get_clocks -quiet *]
    if {[llength $clocks] != 1} {
        _fail "clock count is [llength $clocks], expected one aclk clock; clocks={$clocks}"
    }
    set clock [_require_one [get_clocks -quiet aclk] "aclk clock"]
    set period [expr {double([get_property PERIOD $clock])}]
    if {abs($period - 5.000) > 0.0005} {
        _fail "aclk period is $period ns, expected 5.000 ns"
    }
    _log [format "ROUND53_HG_CLOCK name=%s period_ns=%.3f" $clock $period]
}

proc ::r53_hg::_check_exceptions {} {
    set text [report_exceptions -summary -return_string]
    set patterns [list \
        false_path {^False Path[ \t]+([0-9]+)} \
        clock_groups {^Clock Groups[ \t]+([0-9]+)} \
        multicycle {^Multicycle Path[ \t]+([0-9]+)} \
        max_delay {^Max Delay[ \t]+([0-9]+)} \
        max_delay_dpo {^Max Delay DPO[ \t]+([0-9]+)} \
        min_delay {^Min Delay[ \t]+([0-9]+)}]
    foreach {label pattern} $patterns {
        if {![regexp -line -- $pattern $text match count]} {
            _fail "could not parse $label from report_exceptions -summary"
        }
        _log "ROUND53_HG_EXCEPTION type=$label constraints=$count"
        if {$count != 0} {
            _fail "$label timing-exception count is $count, expected 0"
        }
    }
}

proc ::r53_hg::_check_timing_categories {} {
    set text [check_timing -verbose -return_string]
    set expected {no_clock constant_clock pulse_width_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock generated_clocks loops partial_input_delay partial_output_delay latch_loops}
    set found [dict create]
    set matches [regexp -all -inline -line {checking ([a-z_]+) \(([0-9]+)\)} $text]
    foreach {whole category count} $matches {
        dict set found $category $count
    }
    foreach category $expected {
        if {![dict exists $found $category]} {
            _fail "check_timing category '$category' was not reported"
        }
        set count [dict get $found $category]
        _log "ROUND53_HG_CHECK_TIMING category=$category count=$count"
        if {$count != 0} {
            _fail "check_timing category '$category' has $count critical items"
        }
    }
    if {[dict size $found] != [llength $expected]} {
        _fail "check_timing category set changed: found={[dict keys $found]}"
    }
}

proc ::r53_hg::_check_multiple_drivers {} {
    set violations {}
    foreach net [get_nets -hier -quiet] {
        set drivers [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        if {[llength $drivers] > 1} {
            lappend violations [list $net $drivers]
        }
    }
    _log "ROUND53_HG_MULTIPLE_DRIVERS count=[llength $violations] violations={$violations}"
    if {[llength $violations] != 0} {
        _fail "multiple-driven nets exist"
    }
}

proc ::r53_hg::_check_cdc {} {
    set text [report_cdc -details -return_string]
    set safe [regexp {All paths are Safely Timed\.} $text]
    _log "ROUND53_HG_CDC all_paths_safely_timed=$safe"
    if {!$safe} {
        _fail "report_cdc did not report all paths safely timed"
    }
}

proc ::r53_hg::_check_methodology {} {
    report_methodology -quiet -return_string
    set errors 0
    set critical 0
    set warnings {}
    foreach violation [get_methodology_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        set check [lindex [split $violation #] 0]
        if {[string equal -nocase $severity "Error"]} {
            incr errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr critical
        } elseif {[string equal -nocase $severity "Warning"]} {
            lappend warnings $check
        }
    }
    set warnings [lsort -unique $warnings]
    _log "ROUND53_HG_METHODOLOGY errors=$errors critical_warnings=$critical warnings={$warnings}"
    if {$errors != 0 || $critical != 0} {
        _fail "methodology has $errors errors and $critical critical warnings"
    }
}

proc ::r53_hg::_check_drc {stage} {
    report_drc -quiet -return_string
    set allowed [expr {$stage eq "routed" ? {CFGBVS-1 RTSTAT-10} : {CFGBVS-1}}]
    set errors 0
    set critical 0
    set warnings {}
    foreach violation [get_drc_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        set rule [lindex [split $violation #] 0]
        if {[string equal -nocase $severity "Error"]} {
            incr errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr critical
        } elseif {[string equal -nocase $severity "Warning"]} {
            lappend warnings $rule
            if {$rule ni $allowed} {
                _fail "unexpected DRC warning $rule at stage $stage"
            }
        }
    }
    set warnings [lsort -unique $warnings]
    _log "ROUND53_HG_DRC errors=$errors critical_warnings=$critical warnings={$warnings}"
    if {$errors != 0 || $critical != 0} {
        _fail "DRC has $errors errors and $critical critical warnings"
    }
}

proc ::r53_hg::_check_route {} {
    set text [report_route_status -return_string]
    foreach {label pattern} [list \
        routable {# of routable nets[^:]*:[ \t]*([0-9]+)} \
        fully {# of fully routed nets[^:]*:[ \t]*([0-9]+)} \
        errors {# of nets with routing errors[^:]*:[ \t]*([0-9]+)}] {
        if {![regexp -nocase -- $pattern $text match value]} {
            _fail "could not parse '$label' from report_route_status"
        }
        set $label $value
    }
    set unrouted [expr {$routable - $fully}]
    _log "ROUND53_HG_ROUTE routable=$routable fully_routed=$fully unrouted=$unrouted errors=$errors"
    if {$errors != 0 || $unrouted != 0 || $fully != $routable} {
        _fail "route is not legal and complete"
    }
}

proc ::r53_hg::_check_descriptor_token {} {
    set token [_require_one \
        [get_cells -hier -quiet -filter {NAME =~ *u_descriptor_idle_token_ff}] \
        "descriptor token"]
    set ref [get_property REF_NAME $token]
    set init [get_property INIT $token]
    set keep [get_property -quiet KEEP $token]
    set dont_touch [get_property -quiet DONT_TOUCH $token]
    _log "ROUND53_HG_DESCRIPTOR_TOKEN cell=$token ref=$ref init=$init keep=$keep dont_touch=$dont_touch"
    if {$ref ne "FDRE" || $init ne "1'b0" || ![_true $keep] ||
        ![_true $dont_touch]} {
        _fail "descriptor token primitive/INIT/KEEP/DONT_TOUCH mapping changed"
    }

    set d_detail [_pin_drivers $token D DESCRIPTOR_TOKEN]
    set d_cells [lindex $d_detail 3]
    if {[llength $d_cells] != 1 || [get_property REF_NAME [lindex $d_cells 0]] ne "VCC"} {
        _fail "descriptor token D is not driven solely by VCC"
    }
    set r_detail [_pin_drivers $token R DESCRIPTOR_TOKEN]
    set ce_detail [_pin_drivers $token CE DESCRIPTOR_TOKEN]
    set r_net [lindex $r_detail 1]
    set ce_net [lindex $ce_detail 1]
    if {![string match "*descriptor_idle_token_clear_w*" $r_net]} {
        _fail "descriptor token R net is '$r_net', expected descriptor_idle_token_clear_w"
    }
    if {![string match "*descriptor_idle_token_set_w*" $ce_net]} {
        _fail "descriptor token CE net is '$ce_net', expected descriptor_idle_token_set_w"
    }

    set old [get_cells -hier -quiet -filter {NAME =~ *descriptor_idle_token_r_reg* && REF_NAME =~ FD*}]
    set canonical [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_r_reg* && REF_NAME =~ FD*}]
    set pcore [get_cells -hier -quiet -filter {NAME =~ *public_frames_idle_core_r_reg* && REF_NAME =~ FD*}]
    if {[llength $old] != 0 || [llength $canonical] != 0} {
        _fail "obsolete descriptor/public-P registers reappeared"
    }
    set pcore [_require_nonempty $pcore "public_frames_idle_core registers"]
    set pcore_primary [_require_one \
        [get_cells -quiet public_frames_idle_core_r_reg] \
        "canonical public_frames_idle_core register"]
    set reference_cones [dict create]
    set mapped_loads [dict create]
    set pcore_replicas {}
    foreach source $pcore {
        if {$source ne $pcore_primary} {lappend pcore_replicas $source}
    }
    set source_index 0
    foreach source [concat [list $pcore_primary] [lsort $pcore_replicas]] {
        if {$source ne $pcore_primary &&
            ![string match "${pcore_primary}_replica*" $source]} {
            _fail "unexpected public_frames_idle_core replica name '$source'"
        }
        if {[get_property REF_NAME $source] ne "FDSE" ||
            [get_property INIT $source] ne "1'b1"} {
            _fail "public_frames_idle_core source '$source' is not FDSE INIT=1"
        }
        _clock_pin $source C PUBLIC_P
        foreach pin_name {D CE S} {
            set pin [_require_one [get_pins -quiet ${source}/${pin_name}] \
                "PUBLIC_P $source $pin_name pin"]
            set cone [lsort [all_fanin -flat -startpoints_only -to $pin]]
            _require_nonempty $cone "PUBLIC_P $source $pin_name startpoints"
            if {$source eq $pcore_primary} {
                dict set reference_cones $pin_name $cone
            } elseif {$cone ne [dict get $reference_cones $pin_name]} {
                _fail "public_frames_idle_core replica '$source' $pin_name cone differs from canonical source; canonical={[dict get $reference_cones $pin_name]} replica={$cone}"
            }
        }
        set q_pin [_require_one [get_pins -quiet ${source}/Q] \
            "PUBLIC_P $source Q pin"]
        set q_net [_require_one [get_nets -quiet -of_objects $q_pin] \
            "PUBLIC_P $source Q net"]
        set q_loads [_require_nonempty \
            [get_pins -quiet -leaf -of_objects $q_net -filter {DIRECTION == IN}] \
            "PUBLIC_P $source Q loads"]
        foreach load $q_loads {
            if {[dict exists $mapped_loads $load]} {
                _fail "public_frames_idle_core load '$load' is mapped to more than one source"
            }
            dict set mapped_loads $load $source
        }
        set role [expr {$source eq $pcore_primary ? "primary" : "replica"}]
        _log "ROUND53_HG_PUBLIC_P_SOURCE index=$source_index role=$role cell=$source ref=FDSE init=1'b1 net=$q_net fanout=[llength $q_loads] loads={$q_loads}"
        incr source_index
    }
    _log "ROUND53_HG_PUBLIC_P_MAPPING source_count=[llength $pcore] replica_count=[expr {[llength $pcore] - 1}] mapped_loads=[dict size $mapped_loads]"
}

proc ::r53_hg::_check_block_patch {experiment} {
    set mode_cells [_require_nonempty \
        [get_cells -hier -quiet -filter {NAME =~ *input_field_mode_r_reg* && REF_NAME =~ FD*}] \
        "input_field_mode registers"]
    set beat_cells [_require_nonempty \
        [get_cells -hier -quiet -filter {NAME =~ *block_beat_15_r_reg* && REF_NAME =~ FD*}] \
        "block_beat_15 registers"]
    set mode_starts [_require_nonempty \
        [get_pins -quiet -of_objects $mode_cells -filter {REF_PIN_NAME == C}] \
        "input_field_mode clock pins"]
    set beat_sinks [_require_nonempty \
        [get_pins -quiet -of_objects $beat_cells -filter {REF_PIN_NAME == D || REF_PIN_NAME == CE || REF_PIN_NAME == R || REF_PIN_NAME == S}] \
        "block_beat_15 data/control pins"]
    set mode_count [_timing_count MODE_TO_BLOCK_BEAT $mode_starts $beat_sinks]

    if {$experiment in {B D}} {
        if {$mode_count != 0} {
            _fail "block-local experiment $experiment still has $mode_count mode-to-block_beat paths"
        }
        foreach {label pattern max_levels} [list \
            STATE {NAME =~ u_core/state_reg* && REF_NAME =~ FD*} 3 \
            RECIV {NAME =~ *rec_iv_is_96_r_reg* && REF_NAME =~ FD*} 3 \
            GHSLOT {NAME =~ *gh_input_slot_free_r_reg* && REF_NAME =~ FD*} 3 \
            DATACAP {NAME =~ *data_block_capacity_r_reg* && REF_NAME =~ FD*} 3] {
            set cells [_require_nonempty [get_cells -hier -quiet -filter $pattern] "$label block-local source registers"]
            set starts [_require_nonempty [get_pins -quiet -of_objects $cells -filter {REF_PIN_NAME == C}] "$label source clock pins"]
            if {[_timing_count ${label}_TO_BLOCK_BEAT $starts $beat_sinks] == 0} {
                _fail "block-local source family $label does not reach block_beat_15"
            }
            _check_logic_depth ${label}_TO_BLOCK_BEAT $starts $beat_sinks $max_levels
        }
    } else {
        if {$mode_count == 0} {
            _fail "baseline experiment $experiment unexpectedly lacks mode-to-block_beat identity path"
        }
        _check_logic_depth MODE_TO_BLOCK_BEAT $mode_starts $beat_sinks 4
    }
}

proc ::r53_hg::_check_zseq_patch {experiment} {
    set zseq_cells [get_cells -hier -quiet -filter {NAME =~ *zeroize_sequence_active_r_reg* && REF_NAME =~ FD*}]
    set state_cells [_require_nonempty \
        [get_cells -hier -quiet -filter {NAME =~ u_core/state_reg* && REF_NAME =~ FD*}] \
        "main state registers"]
    set state_sinks [_require_nonempty \
        [get_pins -quiet -of_objects $state_cells -filter {REF_PIN_NAME == D || REF_PIN_NAME == CE || REF_PIN_NAME == R || REF_PIN_NAME == S}] \
        "main state data/control pins"]
    set result_cells [_require_nonempty \
        [get_cells -hier -quiet -filter {NAME =~ *result_data_r_reg* && REF_NAME =~ FD*}] \
        "result_data registers"]
    set result_starts [_require_nonempty \
        [get_pins -quiet -of_objects $result_cells -filter {REF_PIN_NAME == C}] \
        "result_data source clock pins"]
    set result_state_count [_timing_count RESULT_DATA_TO_MAIN_STATE $result_starts $state_sinks]

    set abort_cells [_require_nonempty \
        [get_cells -hier -quiet -filter {NAME =~ *zeroize_abort_count_reg* && REF_NAME =~ FD*}] \
        "zeroize_abort_count registers"]
    set abort_starts [_require_nonempty \
        [get_pins -quiet -of_objects $abort_cells -filter {REF_PIN_NAME == C}] \
        "zeroize_abort_count source clock pins"]
    if {[_timing_count ABORT_COUNT_TO_MAIN_STATE $abort_starts $state_sinks] == 0} {
        _fail "required zeroize_abort_count admission gate no longer reaches main state"
    }

    if {$experiment in {C D}} {
        set zseq [_require_one $zseq_cells "zeroize sequence token"]
        set ref [get_property REF_NAME $zseq]
        set init [get_property INIT $zseq]
        set keep [get_property -quiet KEEP $zseq]
        set eqrm [get_property -quiet EQUIVALENT_REGISTER_REMOVAL $zseq]
        _log "ROUND53_HG_ZSEQ cell=$zseq ref=$ref init=$init keep=$keep equivalent_register_removal=$eqrm"
        if {$ref ne "FDRE" || $init ne "1'b0" || ![_true $keep] || ![_false $eqrm]} {
            _fail "zseq token primitive/INIT/KEEP/equivalent-register-removal mapping changed"
        }
        set q [_require_one [get_pins -quiet ${zseq}/Q] "zseq Q pin"]
        set q_net [_require_one [get_nets -quiet -of_objects $q] "zseq Q net"]
        set q_loads [get_pins -quiet -leaf -of_objects $q_net -filter {DIRECTION == IN}]
        _require_nonempty $q_loads "zseq Q loads"
        _log "ROUND53_HG_ZSEQ_Q net={$q_net} load_count=[llength $q_loads] loads={$q_loads}"
        if {[_timing_count ZSEQ_TO_MAIN_STATE $q $state_sinks] == 0} {
            _fail "zseq Q does not drive the main-state/descriptor-admission cone"
        }
        if {$result_state_count != 0} {
            _fail "result_data still directly reaches main state in zseq experiment $experiment"
        }
        set d_detail [_pin_drivers $zseq D ZSEQ]
        set d_cells [lindex $d_detail 3]
        if {[llength $d_cells] != 1 ||
            ![string match "LUT*" [get_property REF_NAME [lindex $d_cells 0]]]} {
            _fail "zseq D is not driven by exactly one LUT"
        }
        set d_pin [lindex $d_detail 0]
        set d_starts [all_fanin -flat -startpoints_only -to $d_pin]
        foreach pattern [list \
            *zeroize_pulse* *result_valid_r_reg* *result_data_r_reg* \
            *zeroize_busy_r_reg* *zeroize_index_reg* \
            *zeroize_abort_count_reg* *zeroize_sequence_active_r_reg* \
            m_axis_result_tready] {
            set matched 0
            foreach start $d_starts {
                if {[string match $pattern $start]} {
                    set matched 1
                    break
                }
            }
            if {!$matched} {
                _fail "zseq D startpoints lack required pattern '$pattern'; startpoints={$d_starts}"
            }
        }
        _log "ROUND53_HG_ZSEQ_D_STARTPOINTS startpoints={$d_starts}"
        _clock_pin $zseq C ZSEQ
        set ce_detail [_pin_drivers $zseq CE ZSEQ]
        set ce_cells [lindex $ce_detail 3]
        if {[llength $ce_cells] != 1 ||
            [get_property REF_NAME [lindex $ce_cells 0]] ne "VCC"} {
            _fail "zseq CE is not driven solely by VCC"
        }
        set r_detail [_pin_drivers $zseq R ZSEQ]
        set r_cells [lindex $r_detail 3]
        if {[llength $r_cells] != 1 ||
            [get_property REF_NAME [lindex $r_cells 0]] ne "LUT1"} {
            _fail "zseq R is not driven by exactly one LUT1 reset inverter"
        }
        set r_starts [all_fanin -flat -startpoints_only -to [lindex $r_detail 0]]
        if {[llength $r_starts] != 1 || [lindex $r_starts 0] ne "aresetn"} {
            _fail "zseq R startpoints are '{$r_starts}', expected only aresetn"
        }
        set s_pins [get_pins -quiet ${zseq}/S]
        if {[llength $s_pins] != 0} {
            _fail "zseq unexpectedly has an S pin: {$s_pins}"
        }
        _log "ROUND53_HG_ZSEQ_CONTROL ce_driver={$ce_cells} r_driver={$r_cells} r_startpoints={$r_starts} s_pin_count=0"
    } else {
        if {[llength $zseq_cells] != 0} {
            _fail "baseline experiment $experiment unexpectedly contains a zseq token"
        }
        if {$result_state_count == 0} {
            _fail "baseline experiment $experiment lacks result_data-to-state identity path"
        }
    }
}

proc ::r53_hg::_internal_metrics {stage} {
    set registers [_require_nonempty [all_registers] "all_registers"]
    set setup_top [_require_one \
        [get_timing_paths -quiet -from $registers -to $registers -delay_type max -max_paths 1 -nworst 1] \
        "worst internal setup path"]
    set hold_top [_require_one \
        [get_timing_paths -quiet -from $registers -to $registers -delay_type min -max_paths 1 -nworst 1] \
        "worst internal hold path"]
    set setup_failing [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set hold_failing [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type min -slack_lesser_than 0.0 -max_paths 100000 -nworst 1]
    set metrics [dict create \
        setup_wns [expr {double([get_property SLACK $setup_top])}] \
        setup_tns [_sum_slack $setup_failing] \
        setup_fep [llength $setup_failing] \
        hold_whs [expr {double([get_property SLACK $hold_top])}] \
        hold_ths [_sum_slack $hold_failing] \
        hold_fep [llength $hold_failing]]
    _log [format \
        "ROUND53_HG_INTERNAL setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d" \
        [dict get $metrics setup_wns] [dict get $metrics setup_tns] \
        [dict get $metrics setup_fep] [dict get $metrics hold_whs] \
        [dict get $metrics hold_ths] [dict get $metrics hold_fep]]
    set hold_clean [expr {
        [dict get $metrics hold_whs] >= -0.0005 &&
        [dict get $metrics hold_fep] == 0 &&
        abs([dict get $metrics hold_ths]) <= 0.0005}]
    dict set metrics hold_clean $hold_clean
    if {!$hold_clean && $stage ne "placed"} {
        _fail "internal hold timing is not clean at mandatory stage $stage"
    }
    if {!$hold_clean && $stage eq "placed"} {
        _log "ROUND53_HG_PLACED_HOLD_TRANSIENT allowed=1; routed hold remains mandatory"
    }
    set setup_closed [expr {
        [dict get $metrics setup_wns] >= -0.0005 &&
        [dict get $metrics setup_fep] == 0 &&
        abs([dict get $metrics setup_tns]) <= 0.0005}]
    dict set metrics setup_closed $setup_closed
    return $metrics
}

proc ::r53_hg::_run_body {experiment stage} {
    if {$experiment ni {A B C D}} {
        _fail "invalid experiment '$experiment'; expected A, B, C, or D"
    }
    if {$stage ni {synth placed routed}} {
        _fail "invalid stage '$stage'; expected synth, placed, or routed"
    }
    set designs [current_design -quiet]
    if {[llength $designs] != 1} {
        _fail "open-design count is [llength $designs], expected exactly one"
    }
    set top [get_property TOP [current_design]]
    if {$top ne "aes_gcm_axi_top"} {
        _fail "open design TOP is '$top', expected aes_gcm_axi_top"
    }
    set part [get_property PART [current_design]]
    if {$part ne "xc7a100tcsg324-1"} {
        _fail "part is '$part', expected xc7a100tcsg324-1"
    }

    _log "ROUND53_HARD_GATE_BEGIN experiment=$experiment stage=$stage design=[current_design] top=$top part=$part"
    _check_clock
    _check_exceptions
    _check_timing_categories
    _check_multiple_drivers
    _check_cdc

    set latches [get_cells -hier -quiet -filter {REF_NAME =~ LD*}]
    _log "ROUND53_HG_LATCHES count=[llength $latches] cells={$latches}"
    if {[llength $latches] != 0} {
        _fail "unexpected latches exist"
    }

    _check_descriptor_token
    _check_block_patch $experiment
    _check_zseq_patch $experiment
    _check_drc $stage
    _check_methodology
    if {$stage eq "routed"} {
        _check_route
    }
    set metrics [_internal_metrics $stage]
    _log "ROUND53_HARD_GATE_PASS experiment=$experiment stage=$stage setup_closed=[dict get $metrics setup_closed]"
    return $metrics
}

proc ::r53_hg::run {experiment stage audit_file} {
    variable audit_channel
    if {$audit_channel ne ""} {
        error "ROUND53_HARD_GATE: nested run is not supported"
    }
    set parent [file dirname [file normalize $audit_file]]
    file mkdir $parent
    set audit_channel [open $audit_file w]
    if {[catch {_run_body $experiment $stage} result options]} {
        catch {close $audit_channel}
        set audit_channel ""
        return -options $options $result
    }
    close $audit_channel
    set audit_channel ""
    return $result
}
