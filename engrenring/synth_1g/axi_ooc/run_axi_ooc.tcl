# Production out-of-context implementation flow for aes_gcm_axi_top.
# Run from a fresh Vivado process:
#   vivado -mode batch -source run_axi_ooc.tcl

proc axi_ooc_fail {message} {
    puts stderr "AXI_OOC_SUMMARY status=ERROR"
    puts stderr "AXI_OOC_ERROR $message"
    exit 1
}

set script_dir [file dirname [file normalize [info script]]]
set rtl_dir [file normalize [file join $script_dir .. .. rtl source]]
set xdc_file [file join $script_dir axi_175mhz_ooc.xdc]
set top_name aes_gcm_axi_top
set part_name xc7a100tcsg324-1
set clock_period_ns 5.714
set run_mode full
set output_label ""
if {[llength $argv] > 0} {
    set run_mode [lindex $argv 0]
}
if {[llength $argv] > 1} {
    set output_label [lindex $argv 1]
}
if {$run_mode ni {full synth_only}} {
    axi_ooc_fail "Unsupported run mode '$run_mode'; use full or synth_only"
}
if {$output_label ne "" && ![regexp {^[A-Za-z0-9_.-]+$} $output_label]} {
    axi_ooc_fail "Invalid output label '$output_label'"
}
set output_dir $script_dir
if {$output_label ne ""} {
    set output_dir [file join $script_dir $output_label]
}
set report_dir [file join $output_dir reports]
set checkpoint_dir [file join $output_dir checkpoints]

set stream_aes_files [lsort [glob -nocomplain \
    [file join $rtl_dir stream_aes *.v]]]
set stream_axi_files [lsort [glob -nocomplain \
    [file join $rtl_dir stream_axi *.v]]]
set stream_core_files [lsort [glob -nocomplain \
    [file join $rtl_dir stream_core *.v]]]
set sbox_file [file join $rtl_dir aes_core sbox.v]
set ghash_file [file join $rtl_dir stream_ghash ghash16.v]
set top_file [file join $rtl_dir aes_gcm_axi_top.v]

if {![file isdirectory $rtl_dir]} {
    axi_ooc_fail "RTL directory does not exist: $rtl_dir"
}
if {[llength $stream_aes_files] == 0} {
    axi_ooc_fail "No production Verilog found under stream_aes; do not run this flow until stream_aes exists"
}
if {[llength $stream_axi_files] == 0} {
    axi_ooc_fail "No production Verilog found under stream_axi"
}
if {[llength $stream_core_files] == 0} {
    axi_ooc_fail "No production Verilog found under stream_core"
}
foreach required_file [list $sbox_file $ghash_file $top_file $xdc_file] {
    if {![file isfile $required_file]} {
        axi_ooc_fail "Required file is missing: $required_file"
    }
}

set rtl_files [concat \
    [list $sbox_file] \
    $stream_aes_files \
    [list $ghash_file] \
    $stream_axi_files \
    $stream_core_files \
    [list $top_file]]

file mkdir $report_dir
file mkdir $checkpoint_dir

puts "AXI_OOC_BEGIN mode=$run_mode output=$output_dir top=$top_name part=$part_name period_ns=$clock_period_ns"
puts "AXI_OOC_RTL_COUNT [llength $rtl_files]"
foreach rtl_file $rtl_files {
    puts "AXI_OOC_READ $rtl_file"
}

set flow_stage read_rtl
if {[catch {
    foreach rtl_file $rtl_files {
        read_verilog $rtl_file
    }
    read_xdc $xdc_file

    set flow_stage synth_design
    synth_design -mode out_of_context -top $top_name -part $part_name \
        -flatten_hierarchy rebuilt
    write_checkpoint -force [file join $checkpoint_dir ${top_name}_synth.dcp]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_synth.rpt]
    report_timing_summary -delay_type min_max -max_paths 20 \
        -report_unconstrained \
        -file [file join $report_dir timing_synth.rpt]

    if {$run_mode eq "synth_only"} {
        set synth_worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
        if {[llength $synth_worst_setup] == 0} {
            error "No synthesized setup timing path was found"
        }
        set synth_wns [get_property SLACK $synth_worst_setup]
        set synth_timing_status [expr {double($synth_wns) >= 0.0 ? "PASS" : "FAIL"}]
        set synth_wns_text [format "%.3f" $synth_wns]
        puts "AXI_OOC_SYNTH_ONLY status=COMPLETE timing_status=$synth_timing_status setup_wns_ns=$synth_wns_text"
        puts "AXI_OOC_REPORT [file join $report_dir timing_synth.rpt]"
        puts "AXI_OOC_CHECKPOINT [file join $checkpoint_dir ${top_name}_synth.dcp]"
        exit 0
    }

    set flow_stage opt_design
    opt_design -directive ExploreWithRemap

    set flow_stage place_design
    place_design -directive ExtraNetDelay_high

    set flow_stage phys_opt_design
    phys_opt_design -directive AggressiveExplore
    write_checkpoint -force [file join $checkpoint_dir ${top_name}_placed.dcp]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_placed.rpt]
    report_timing_summary -delay_type min_max -max_paths 20 \
        -report_unconstrained \
        -file [file join $report_dir timing_placed.rpt]

    set flow_stage route_design
    route_design -directive Explore
    write_checkpoint -force [file join $checkpoint_dir ${top_name}_routed.dcp]

    set flow_stage routed_reports
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_routed.rpt]
    report_timing_summary -delay_type min_max -max_paths 50 \
        -report_unconstrained \
        -file [file join $report_dir timing_routed.rpt]
    report_route_status -file [file join $report_dir route_status.rpt]
    report_drc -file [file join $report_dir drc_routed.rpt]
    report_methodology -file [file join $report_dir methodology_routed.rpt]

    set flow_stage summarize
    set worst_setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
    set worst_hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
    if {[llength $worst_setup_path] == 0} {
        error "No routed setup timing path was found"
    }
    if {[llength $worst_hold_path] == 0} {
        error "No routed hold timing path was found"
    }

    set setup_wns [get_property SLACK $worst_setup_path]
    set hold_whs [get_property SLACK $worst_hold_path]

    set timing_summary_text [report_timing_summary -delay_type min_max \
        -max_paths 1 -return_string]
    if {![regexp {Setup[ \t]*:[ \t]*([0-9]+)[ \t]+Failing Endpoints,[ \t]+Worst Slack[ \t]+[-0-9.]+ns,[ \t]+Total Violation[ \t]+([-0-9.]+)ns} \
        $timing_summary_text setup_match setup_failing setup_tns]} {
        error "Could not determine routed setup failing endpoints/TNS"
    }
    if {![regexp {Hold[ \t]*:[ \t]*([0-9]+)[ \t]+Failing Endpoints,[ \t]+Worst Slack[ \t]+[-0-9.]+ns,[ \t]+Total Violation[ \t]+([-0-9.]+)ns} \
        $timing_summary_text hold_match hold_failing hold_ths]} {
        error "Could not determine routed hold failing endpoints/THS"
    }

    set route_status_text [report_route_status -return_string]
    set route_error_count -1
    if {![regexp -nocase \
        {nets with routing errors[^:\r\n]*:[ \t]*([0-9]+)} \
        $route_status_text route_match route_error_count]} {
        error "Could not determine routed-net error count"
    }
    set routable_net_count -1
    set fully_routed_net_count -1
    if {![regexp -nocase \
        {# of routable nets[^:]*:[ \t]*([0-9]+)} \
        $route_status_text routable_match routable_net_count]} {
        error "Could not determine routable-net count"
    }
    if {![regexp -nocase \
        {# of fully routed nets[^:]*:[ \t]*([0-9]+)} \
        $route_status_text fully_routed_match fully_routed_net_count]} {
        error "Could not determine fully-routed-net count"
    }
    set unrouted_net_count [expr {$routable_net_count - $fully_routed_net_count}]

    set drc_error_count 0
    foreach drc_violation [get_drc_violations -quiet] {
        if {[string equal -nocase \
            [get_property SEVERITY $drc_violation] "Error"]} {
            incr drc_error_count
        }
    }

    set setup_ok [expr {double($setup_wns) >= 0.0}]
    set hold_ok [expr {double($hold_whs) >= 0.0}]
    set setup_summary_ok [expr {$setup_failing == 0 && \
                                abs(double($setup_tns)) < 0.0005}]
    set hold_summary_ok [expr {$hold_failing == 0 && \
                               abs(double($hold_ths)) < 0.0005}]
    set route_ok [expr {$route_error_count == 0 && \
                        $unrouted_net_count == 0}]
    set drc_ok [expr {$drc_error_count == 0}]

    set setup_text [format "%.3f" $setup_wns]
    set hold_text [format "%.3f" $hold_whs]

    if {$setup_ok && $hold_ok && $setup_summary_ok && $hold_summary_ok &&
        $route_ok && $drc_ok} {
        puts "AXI_OOC_SUMMARY status=PASS top=$top_name part=$part_name period_ns=$clock_period_ns setup_wns_ns=$setup_text setup_tns_ns=$setup_tns setup_failing=$setup_failing hold_whs_ns=$hold_text hold_ths_ns=$hold_ths hold_failing=$hold_failing route_errors=$route_error_count unrouted_nets=$unrouted_net_count drc_errors=$drc_error_count"
        puts "AXI_OOC_REPORT_DIR $report_dir"
        puts "AXI_OOC_CHECKPOINT [file join $checkpoint_dir ${top_name}_routed.dcp]"
    } else {
        puts stderr "AXI_OOC_SUMMARY status=FAIL top=$top_name part=$part_name period_ns=$clock_period_ns setup_wns_ns=$setup_text setup_tns_ns=$setup_tns setup_failing=$setup_failing hold_whs_ns=$hold_text hold_ths_ns=$hold_ths hold_failing=$hold_failing route_errors=$route_error_count unrouted_nets=$unrouted_net_count drc_errors=$drc_error_count"
        puts stderr "AXI_OOC_REPORT_DIR $report_dir"
        exit 2
    }
} flow_error flow_options]} {
    puts stderr "AXI_OOC_SUMMARY status=ERROR stage=$flow_stage"
    puts stderr "AXI_OOC_ERROR $flow_error"
    if {[dict exists $flow_options -errorinfo]} {
        puts stderr [dict get $flow_options -errorinfo]
    }
    exit 1
}

exit 0
