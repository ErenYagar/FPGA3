# Round53 reproducible report bundle for Vivado 2021.1.
#
# Public API:
#   ::r53_reports::run <synth|placed|routed> <A|B|C|D> <report_dir>
#
# The caller must have an open aes_gcm_axi_top design.  This file never adds
# or modifies timing constraints.

namespace eval ::r53_reports {
    namespace export run internal_metrics
}

proc ::r53_reports::_require_choice {value choices label} {
    if {$value ni $choices} {
        error "ROUND53_REPORTS: invalid $label '$value'; expected one of {$choices}"
    }
}

proc ::r53_reports::_safe_property {object property} {
    if {[catch {get_property $property $object} value]} {
        return "NA"
    }
    if {$value eq ""} {
        return "NA"
    }
    return $value
}

proc ::r53_reports::_tsv {value} {
    return [string map [list "\t" " " "\r" " " "\n" " "] $value]
}

proc ::r53_reports::_sum_slack {paths} {
    set total 0.0
    foreach path $paths {
        set total [expr {$total + double([get_property SLACK $path])}]
    }
    return $total
}

proc ::r53_reports::internal_metrics {} {
    set registers [all_registers]
    if {[llength $registers] == 0} {
        error "ROUND53_REPORTS: all_registers returned an empty collection"
    }

    set setup_top [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -max_paths 1 -nworst 1]
    set hold_top [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type min -max_paths 1 -nworst 1]
    if {[llength $setup_top] != 1 || [llength $hold_top] != 1} {
        error "ROUND53_REPORTS: internal setup/hold top-path collection is empty"
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

proc ::r53_reports::_write_top1000_tsv {path} {
    set registers [all_registers]
    if {[llength $registers] == 0} {
        error "ROUND53_REPORTS: cannot write top-1000 TSV with no registers"
    }
    set paths [get_timing_paths -quiet -from $registers -to $registers \
        -delay_type max -max_paths 1000 -nworst 1]
    if {[llength $paths] == 0} {
        error "ROUND53_REPORTS: internal top-1000 path collection is empty"
    }

    set channel [open $path w]
    puts $channel "rank\tslack_ns\tstartpoint_pin\tendpoint_pin\tlogic_levels\tdatapath_delay_ns\tlogic_delay_ns\tnet_delay_ns\tmax_fanout"
    set rank 0
    foreach timing_path $paths {
        incr rank
        set fields [list \
            $rank \
            [_safe_property $timing_path SLACK] \
            [_safe_property $timing_path STARTPOINT_PIN] \
            [_safe_property $timing_path ENDPOINT_PIN] \
            [_safe_property $timing_path LOGIC_LEVELS] \
            [_safe_property $timing_path DATAPATH_DELAY] \
            [_safe_property $timing_path DATAPATH_LOGIC_DELAY] \
            [_safe_property $timing_path DATAPATH_NET_DELAY] \
            [_safe_property $timing_path MAX_FANOUT]]
        set escaped {}
        foreach field $fields {
            lappend escaped [_tsv $field]
        }
        puts $channel [join $escaped "\t"]
    }
    close $channel
    return [llength $paths]
}

proc ::r53_reports::_write_optional_report {command arguments output_file} {
    if {[llength [info commands $command]] == 0} {
        set channel [open $output_file w]
        puts $channel "UNSUPPORTED: Vivado command '$command' is unavailable."
        close $channel
        puts "ROUND53_REPORTS_UNSUPPORTED command=$command file=$output_file"
        return
    }
    if {[catch {uplevel #0 [linsert $arguments 0 $command]} message options]} {
        error "ROUND53_REPORTS: '$command' failed: $message" \
            [dict get $options -errorinfo]
    }
}

proc ::r53_reports::run {stage experiment report_dir} {
    _require_choice $stage {synth placed routed} stage
    _require_choice $experiment {A B C D} experiment

    if {[llength [current_design -quiet]] != 1} {
        error "ROUND53_REPORTS: exactly one open design is required"
    }
    if {[file exists $report_dir] && ![file isdirectory $report_dir]} {
        error "ROUND53_REPORTS: report path exists but is not a directory: $report_dir"
    }
    file mkdir $report_dir

    set prefix "r53_[string tolower $experiment]_${stage}"
    puts "ROUND53_REPORTS_BEGIN experiment=$experiment stage=$stage dir=$report_dir"

    report_timing_summary -delay_type min_max -max_paths 100 \
        -report_unconstrained \
        -file [file join $report_dir ${prefix}_timing_summary.rpt]

    set registers [all_registers]
    if {[llength $registers] == 0} {
        error "ROUND53_REPORTS: all_registers returned an empty collection"
    }
    report_timing -quiet -from $registers -to $registers -delay_type max \
        -max_paths 1000 -nworst 1 -path_type full_clock_expanded \
        -file [file join $report_dir ${prefix}_internal_setup_top1000.rpt]
    report_timing -quiet -from $registers -to $registers -delay_type min \
        -max_paths 200 -nworst 1 -path_type full_clock_expanded \
        -file [file join $report_dir ${prefix}_internal_hold_top200.rpt]
    _write_top1000_tsv \
        [file join $report_dir ${prefix}_internal_setup_top1000.tsv]

    report_high_fanout_nets -timing -load_types -max_nets 200 \
        -file [file join $report_dir ${prefix}_high_fanout_nets.rpt]
    report_control_sets -verbose -sort_by {clk clkEn set} \
        -file [file join $report_dir ${prefix}_control_sets.rpt]
    report_utilization -hierarchical \
        -file [file join $report_dir ${prefix}_utilization.rpt]
    report_drc -file [file join $report_dir ${prefix}_drc.rpt]
    report_methodology \
        -file [file join $report_dir ${prefix}_methodology.rpt]
    report_exceptions -summary \
        -file [file join $report_dir ${prefix}_exceptions_summary.rpt]
    report_cdc -details \
        -file [file join $report_dir ${prefix}_cdc.rpt]
    check_timing -verbose \
        -file [file join $report_dir ${prefix}_check_timing.rpt]

    _write_optional_report report_qor_assessment \
        [list -max_paths 100 -file \
            [file join $report_dir ${prefix}_qor_assessment.rpt]] \
        [file join $report_dir ${prefix}_qor_assessment.rpt]
    _write_optional_report report_qor_suggestions \
        [list -max_paths 100 -file \
            [file join $report_dir ${prefix}_qor_suggestions.rpt]] \
        [file join $report_dir ${prefix}_qor_suggestions.rpt]

    if {$stage eq "routed"} {
        report_route_status \
            -file [file join $report_dir ${prefix}_route_status.rpt]
    }

    set metrics [internal_metrics]
    set metrics_file [file join $report_dir ${prefix}_internal_metrics.txt]
    set channel [open $metrics_file w]
    foreach key {setup_wns setup_tns setup_fep hold_whs hold_ths hold_fep} {
        puts $channel "$key=[dict get $metrics $key]"
    }
    close $channel

    puts [format \
        "ROUND53_REPORTS_METRICS experiment=%s stage=%s setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d" \
        $experiment $stage \
        [dict get $metrics setup_wns] [dict get $metrics setup_tns] \
        [dict get $metrics setup_fep] [dict get $metrics hold_whs] \
        [dict get $metrics hold_ths] [dict get $metrics hold_fep]]
    puts "ROUND53_REPORTS_COMPLETE experiment=$experiment stage=$stage"
    return $metrics
}
