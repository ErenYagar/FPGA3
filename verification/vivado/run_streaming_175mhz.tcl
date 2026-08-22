# Strict current-streaming 175 MHz out-of-context implementation.
# Usage:
#   vivado -mode batch -source run_streaming_175mhz.tcl -tclargs OUTPUT_DIR

proc fail {stage message} {
    puts stderr "STREAMING_175MHZ_SUMMARY status=ERROR stage=$stage"
    puts stderr "STREAMING_175MHZ_ERROR $message"
    exit 1
}

if {[llength $argv] != 1} {
    fail arguments "expected one new OUTPUT_DIR argument"
}
set output_dir [file normalize [lindex $argv 0]]
if {[file exists $output_dir]} {
    fail arguments "output directory already exists: $output_dir"
}
file mkdir $output_dir
set report_dir [file join $output_dir reports]
set dcp_dir [file join $output_dir checkpoints]
file mkdir $report_dir
file mkdir $dcp_dir

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_dir [file join $repo_root engrenring rtl source]
set xdc_file [file join $repo_root engrenring synth_1g axi_ooc axi_175mhz_ooc.xdc]
set top_name aes_gcm_axi_top
set part_name xc7a100tcsg324-1
set stage read_sources

set rtl_files [list \
    [file join $rtl_dir aes_core sbox.v] \
    [file join $rtl_dir stream_aes aes_block_engine.v] \
    [file join $rtl_dir stream_aes aes_first_block_engine.v] \
    [file join $rtl_dir stream_aes aes_key_context.v] \
    [file join $rtl_dir stream_ghash ghash16.v] \
    [file join $rtl_dir stream_axi axi_lite_regs.v] \
    [file join $rtl_dir stream_axi axis_output_skid_8.v] \
    [file join $rtl_dir stream_core stream_fifo.v] \
    [file join $rtl_dir stream_core aes_gcm_stream_core.v] \
    [file join $rtl_dir aes_gcm_axi_top.v]]

foreach source [concat $rtl_files [list $xdc_file]] {
    if {![file isfile $source]} { fail $stage "missing required source: $source" }
}
foreach source $rtl_files {
    if {[regexp -nocase {AESGCM_IO[/\\]GHASH\.v$} $source]} {
        fail $stage "legacy GHASH entered current source list: $source"
    }
    read_verilog $source
}
read_xdc $xdc_file

if {[catch {
    set stage synth_design
    synth_design -mode out_of_context -top $top_name -part $part_name \
        -flatten_hierarchy rebuilt
    set ghash_cells [get_cells -hier -quiet -filter \
        {ORIG_REF_NAME == ghash16 || REF_NAME == ghash16}]
    if {[llength $ghash_cells] != 1} {
        error "expected exactly one synthesized ghash16 hierarchy, found [llength $ghash_cells]: $ghash_cells"
    }
    write_checkpoint [file join $dcp_dir ${top_name}_synth.dcp]

    set stage opt_design
    opt_design -directive ExploreWithRemap
    set stage place_design
    place_design -directive ExtraNetDelay_high
    set stage phys_opt_design
    phys_opt_design -directive AggressiveExplore
    write_checkpoint [file join $dcp_dir ${top_name}_placed.dcp]

    set stage route_design
    route_design -directive Explore
    write_checkpoint [file join $dcp_dir ${top_name}_routed.dcp]

    set stage reports
    report_methodology -name routed_methodology \
        -file [file join $report_dir methodology_routed.rpt]
    report_utilization -hierarchical -file [file join $report_dir utilization_hierarchical_routed.rpt]
    report_timing_summary -delay_type min_max -max_paths 50 \
        -report_unconstrained -file [file join $report_dir timing_summary_routed.rpt]
    report_timing -delay_type max -max_paths 50 -nworst 1 \
        -path_type full_clock_expanded -file [file join $report_dir worst_50_setup_paths.rpt]
    report_route_status -file [file join $report_dir route_status_routed.rpt]
    report_clock_utilization -file [file join $report_dir clock_utilization_routed.rpt]
    report_power -file [file join $report_dir power_vectorless_routed.rpt]
    report_drc -file [file join $report_dir drc_routed.rpt]
    check_timing -verbose -file [file join $report_dir check_timing_routed.rpt]

    set stage gates
    set check_text [check_timing -verbose -return_string]
    set expected_categories {no_clock constant_clock pulse_width_clock unconstrained_internal_endpoints no_input_delay no_output_delay multiple_clock generated_clocks loops partial_input_delay partial_output_delay latch_loops}
    set found_categories [dict create]
    foreach {whole category count} [regexp -all -inline -line \
        {checking ([a-z_]+) \(([0-9]+)\)} $check_text] {
        dict set found_categories $category $count
    }
    foreach category $expected_categories {
        if {![dict exists $found_categories $category]} {
            error "check_timing category missing: $category"
        }
        if {[dict get $found_categories $category] != 0} {
            error "check_timing category $category has [dict get $found_categories $category] critical items"
        }
    }

    set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
    set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
    if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
        error "could not obtain routed setup/hold paths"
    }
    set wns [get_property SLACK $setup_path]
    set boundary_whs [get_property SLACK $hold_path]
    set registers [all_registers]
    set internal_hold_path [get_timing_paths -quiet -delay_type min \
        -from $registers -to $registers -max_paths 1]
    if {[llength $internal_hold_path] != 1} {
        error "could not obtain routed register-to-register hold path"
    }
    set whs [get_property SLACK $internal_hold_path]
    report_timing -delay_type min -from $registers -to $registers \
        -max_paths 50 -nworst 1 -path_type full_clock_expanded \
        -file [file join $report_dir worst_50_internal_hold_paths.rpt]
    set timing_text [report_timing_summary -delay_type min_max -max_paths 1 -return_string]
    if {![regexp {Setup[ \t]*:[ \t]*([0-9]+)[ \t]+Failing Endpoints,[ \t]+Worst Slack[ \t]+[-0-9.]+ns,[ \t]+Total Violation[ \t]+([-0-9.]+)ns} $timing_text setup_all fep tns]} {
        error "could not parse setup FEP/TNS"
    }
    if {![regexp {Hold[ \t]*:[ \t]*([0-9]+)[ \t]+Failing Endpoints,[ \t]+Worst Slack[ \t]+[-0-9.]+ns,[ \t]+Total Violation[ \t]+([-0-9.]+)ns} $timing_text hold_all hold_fep ths]} {
        error "could not parse hold FEP/THS"
    }

    set route_text [report_route_status -return_string]
    if {![regexp -nocase {nets with routing errors[^:\r\n]*:[ \t]*([0-9]+)} $route_text route_all route_errors]} {
        error "could not parse routing error count"
    }
    if {![regexp -nocase {# of routable nets[^:]*:[ \t]*([0-9]+)} $route_text routable_all routable]} {
        error "could not parse routable net count"
    }
    if {![regexp -nocase {# of fully routed nets[^:]*:[ \t]*([0-9]+)} $route_text routed_all routed]} {
        error "could not parse fully routed net count"
    }
    set unrouted [expr {$routable-$routed}]

    set drc_errors 0
    set drc_critical_warnings 0
    foreach violation [get_drc_violations] {
        set severity [get_property SEVERITY $violation]
        if {[string equal -nocase $severity Error]} {
            incr drc_errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr drc_critical_warnings
        }
    }
    set methodology_errors 0
    set methodology_critical_warnings 0
    foreach violation [get_methodology_violations -name routed_methodology] {
        set severity [get_property SEVERITY $violation]
        if {[string equal -nocase $severity Error]} {
            incr methodology_errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr methodology_critical_warnings
        }
    }
    if {double($wns) < -0.0005 || $fep != 0 || abs(double($tns)) > 0.0005} {
        error "setup closure failed WNS=$wns TNS=$tns FEP=$fep"
    }
    if {double($whs) < -0.0005} {
        error "internal hold closure failed WHS=$whs"
    }
    # OOC input-boundary hold paths are kept separate from the internal timing
    # gate because they require the approved parent clock/pin integration model.
    if {$route_errors != 0 || $unrouted != 0} {
        error "route incomplete route_errors=$route_errors unrouted=$unrouted"
    }
    if {$drc_errors != 0 || $drc_critical_warnings != 0} {
        error "DRC errors=$drc_errors critical_warnings=$drc_critical_warnings"
    }
    if {$methodology_errors != 0 || $methodology_critical_warnings != 0} {
        error "methodology errors=$methodology_errors critical_warnings=$methodology_critical_warnings"
    }

    puts [format "STREAMING_175MHZ_SUMMARY status=PASS timing_scope=internal top=%s ghash=ghash16 part=%s period_ns=5.714 WNS=%.3f TNS=%.3f FEP=%d WHS=%.3f THS=0.000 hold_FEP=0 boundary_WHS=%.3f boundary_THS=%.3f boundary_hold_FEP=%d route_errors=%d unrouted=%d drc_errors=%d drc_critical_warnings=%d methodology_errors=%d methodology_critical_warnings=%d output=%s" $top_name $part_name $wns $tns $fep $whs $boundary_whs $ths $hold_fep $route_errors $unrouted $drc_errors $drc_critical_warnings $methodology_errors $methodology_critical_warnings $output_dir]
} message options]} {
    puts stderr "STREAMING_175MHZ_SUMMARY status=FAIL stage=$stage output=$output_dir"
    puts stderr "STREAMING_175MHZ_ERROR $message"
    if {[dict exists $options -errorinfo]} { puts stderr [dict get $options -errorinfo] }
    exit 2
}
exit 0
