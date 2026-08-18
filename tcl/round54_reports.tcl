# Round54 report bundle for Vivado 2021.1.
#
# Public API:
#   ::r54_reports::run <stage> <experiment> <report_dir>

namespace eval ::r54_reports {
    namespace export run
}

set ::r54_reports::script_dir [file dirname [file normalize [info script]]]
source [file join $::r54_reports::script_dir round53_reports.tcl]
source [file join $::r54_reports::script_dir round54_path_families.tcl]

proc ::r54_reports::_write_design_analysis {stage path} {
    if {[llength [info commands report_design_analysis]] == 0} {
        set channel [open $path w]
        puts $channel "UNSUPPORTED: report_design_analysis"
        close $channel
        return
    }
    if {$stage eq "synth"} {
        report_design_analysis -logic_level_distribution -file $path
    } else {
        report_design_analysis -logic_level_distribution -congestion \
            -file $path
    }
}

proc ::r54_reports::run {stage experiment report_dir} {
    if {$stage ni {synth placed routed}} {
        error "ROUND54_REPORTS: invalid stage '$stage'"
    }
    if {![regexp {^[A-Za-z0-9_.-]+$} $experiment]} {
        error "ROUND54_REPORTS: invalid experiment '$experiment'"
    }
    file mkdir $report_dir
    puts "ROUND54_REPORTS_BEGIN experiment=$experiment stage=$stage dir=$report_dir"

    # Reuse the already-audited Round53 report set.  All Round54 candidates
    # retain the R53-C security architecture, so C is the correct structural
    # identity for these generic reports.
    set metrics [::r53_reports::run $stage C $report_dir]
    set prefix [file join $report_dir \
        r54_[string tolower $experiment]_${stage}]
    _write_design_analysis $stage ${prefix}_design_analysis.rpt
    if {$stage eq "routed"} {
        set decoded [::r54_paths::run ${prefix}_internal]
        foreach key {setup_wns setup_tns setup_fep hold_whs hold_ths hold_fep} {
            if {abs(double([dict get $metrics $key]) -
                    double([dict get $decoded $key])) > 0.0005} {
                error "ROUND54_REPORTS: decoded metric mismatch for $key"
            }
        }
    }
    puts [format "ROUND54_REPORTS_COMPLETE experiment=%s stage=%s setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d" \
        $experiment $stage [dict get $metrics setup_wns] \
        [dict get $metrics setup_tns] [dict get $metrics setup_fep] \
        [dict get $metrics hold_whs] [dict get $metrics hold_ths] \
        [dict get $metrics hold_fep]]
    return $metrics
}
