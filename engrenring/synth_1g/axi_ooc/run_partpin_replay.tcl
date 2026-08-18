# Production route replay from one externally SHA-256-verified, immutable
# placed checkpoint and one approved PartPin map.  This script deliberately
# has no source-build or PartPin-discovery path.

set replay_stage bootstrap
set replay_design_open 0

if {[catch {
    if {[llength $argv] != 10} {
        error "Usage: run_partpin_replay.tcl <placed_dcp> <placed_sha256> <map_tsv> <map_sha256> <output_dir> <top> <part> <vivado_version> <period_ns> <route_directive>"
    }

    set replay_script_dir [file dirname [file normalize [info script]]]
    set replay_helper [file join $replay_script_dir partpin_ooc.tcl]
    if {![file isfile $replay_helper]} {
        error "Missing replay helper: $replay_helper"
    }
    source $replay_helper

    set replay_placed_dcp [file normalize [lindex $argv 0]]
    set replay_placed_sha [::partpin_ooc::normalize_sha256 \
        [lindex $argv 1] placed_sha256]
    set replay_map_file [file normalize [lindex $argv 2]]
    set replay_map_sha [::partpin_ooc::normalize_sha256 \
        [lindex $argv 3] map_sha256]
    set replay_output_dir [file normalize [lindex $argv 4]]
    set replay_top [lindex $argv 5]
    set replay_part [lindex $argv 6]
    set replay_vivado_version [lindex $argv 7]
    set replay_period [lindex $argv 8]
    set replay_directive [lindex $argv 9]

    if {![file isfile $replay_placed_dcp]} {
        error "Placed checkpoint does not exist: $replay_placed_dcp"
    }
    if {![file isfile $replay_map_file]} {
        error "PartPin map does not exist: $replay_map_file"
    }
    if {![file isdirectory $replay_output_dir]} {
        error "Fresh replay output directory does not exist: $replay_output_dir"
    }
    if {![string is double -strict $replay_period] ||
        double($replay_period) <= 0.0} {
        error "Expected clock period must be positive"
    }
    if {![regexp {^[A-Za-z0-9_]+$} $replay_directive]} {
        error "Route directive contains unsupported characters"
    }

    set replay_report_dir [file join $replay_output_dir reports]
    set replay_checkpoint_dir [file join $replay_output_dir checkpoints]
    file mkdir $replay_report_dir
    file mkdir $replay_checkpoint_dir
    set replay_partpin_dcp [file join $replay_checkpoint_dir \
        ${replay_top}_placed_partpin.dcp]
    set replay_routed_dcp [file join $replay_checkpoint_dir \
        ${replay_top}_routed.dcp]
    set replay_summary_file [file join $replay_report_dir signoff_summary.tsv]
    foreach new_artifact [list $replay_partpin_dcp $replay_routed_dcp \
        $replay_summary_file] {
        if {[file exists $new_artifact]} {
            error "Fresh replay artifact already exists: $new_artifact"
        }
    }

    set replay_stage open_checkpoint
    open_checkpoint $replay_placed_dcp
    set replay_design_open 1

    set replay_stage parse_map
    set replay_map_info [::partpin_ooc::parse_map $replay_map_file]
    set replay_unused_inputs [list \
        {s_axi_awprot[0]} {s_axi_awprot[1]} {s_axi_awprot[2]} \
        {s_axi_arprot[0]} {s_axi_arprot[1]} {s_axi_arprot[2]}]

    set replay_stage apply_partpins
    set replay_live_info [::partpin_ooc::apply_map \
        $replay_map_info $replay_placed_sha $replay_top $replay_part \
        $replay_vivado_version $replay_period $replay_directive \
        $replay_unused_inputs \
        [file join $replay_report_dir live_port_audit.tsv] \
        [file join $replay_report_dir effective_partpins.xdc]]
    write_xdc [file join $replay_report_dir effective_constraints.xdc]
    write_checkpoint $replay_partpin_dcp

    set replay_stage route_design
    route_design -directive $replay_directive
    write_checkpoint $replay_routed_dcp

    set replay_stage strict_signoff
    set replay_summary [::partpin_ooc::run_strict_signoff \
        $replay_map_info $replay_live_info $replay_report_dir \
        $replay_summary_file]
    if {[dict get $replay_summary status] ne "PASS"} {
        error "Strict routed signoff failed; see $replay_summary_file"
    }

    set replay_stage close_design
    close_design
    set replay_design_open 0

    puts "PARTPIN_REPLAY_TCL_SUMMARY status=PASS scope=OOC_PARTPIN board_route=0 top=$replay_top part=$replay_part placed_sha256=$replay_placed_sha map_sha256=$replay_map_sha setup_wns_ns=[dict get $replay_summary setup_wns_ns] hold_whs_ns=[dict get $replay_summary hold_whs_ns] implicit_ports=[dict get $replay_summary implicit_ports] drc_errors=[dict get $replay_summary drc_errors]"
} replay_error replay_options]} {
    if {$replay_design_open} {
        catch {close_design}
    }
    puts stderr "PARTPIN_REPLAY_TCL_SUMMARY status=ERROR stage=$replay_stage"
    puts stderr "PARTPIN_REPLAY_TCL_ERROR $replay_error"
    if {[dict exists $replay_options -errorinfo]} {
        puts stderr [dict get $replay_options -errorinfo]
    }
    exit 1
}

exit 0
