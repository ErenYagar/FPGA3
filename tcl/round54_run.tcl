# Reproducible Round54 Vivado 2021.1 OOC implementation driver.
#
# Usage:
#   vivado -mode batch -source round54_run.tcl -tclargs \
#     <experiment> <fresh_full|from_synth|from_placed|audit_dcp> <label> \
#     <expected_core_sha256> ?input_dcp expected_dcp_sha256 stage directive?
#
# Exit 0: all requested gates pass, including setup when routed.
# Exit 2: legal routed design with clean hold/security gates but setup is open.
# Exit 1: provenance, structural, tool, legality, hold, or DRC failure.
#
# Optional clock profile:
#   set R54_CLOCK_MHZ=175
# If unset, the historical 200 MHz contract remains the default.

proc ::r54_fail {message} {
    puts stderr "ROUND54_RUN_SUMMARY status=ERROR"
    puts stderr "ROUND54_RUN_ERROR $message"
    exit 1
}

proc ::r54_sha256 {path} {
    if {![file isfile $path]} {error "missing file: $path"}
    if {$::tcl_platform(platform) eq "windows"} {
        set output [exec certutil.exe -hashfile [file nativename $path] SHA256]
        foreach line [split $output "\n"] {
            set value [string toupper [string map \
                [list " " "" "\r" "" "\t" ""] $line]]
            if {[regexp {^[0-9A-F]{64}$} $value]} {return $value}
        }
    }
    error "no usable SHA-256 implementation"
}

proc ::r54_check_hash {path expected label} {
    if {![regexp {^[0-9A-Fa-f]{64}$} $expected]} {
        error "$label expected hash is malformed"
    }
    set actual [::r54_sha256 $path]
    if {![string equal -nocase $actual $expected]} {
        error "$label hash mismatch: expected=$expected actual=$actual path=$path"
    }
    puts "ROUND54_HASH_OK label=$label sha256=$actual path=$path"
    return $actual
}

proc ::r54_scan_xdc {path} {
    set channel [open $path r]
    set contents [read $channel]
    close $channel
    set line_number 0
    foreach line [split $contents "\n"] {
        incr line_number
        set code [lindex [split $line #] 0]
        if {[regexp -nocase {(^|[;[:space:]])(set_false_path|set_multicycle_path|set_max_delay|set_min_delay|set_case_analysis|set_disable_timing|set_clock_groups)([;[:space:]]|$)} $code match command]} {
            error "forbidden timing command '$command' at $path:$line_number"
        }
    }
}

proc ::r54_write_provenance {path values rtl_files} {
    set channel [open $path w]
    foreach key [lsort [dict keys $values]] {
        puts $channel "$key=[dict get $values $key]"
    }
    foreach rtl $rtl_files {
        puts $channel "rtl_sha256=[::r54_sha256 $rtl] rtl_file=$rtl"
    }
    close $channel
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set rtl_dir [file join $repo_dir engrenring rtl source]
set ooc_dir [file join $repo_dir engrenring synth_1g axi_ooc]
set top_name aes_gcm_axi_top
set part_name xc7a100tcsg324-1
set clock_mhz 200
if {[info exists ::env(R54_CLOCK_MHZ)]} {
    set clock_mhz $::env(R54_CLOCK_MHZ)
}
if {$clock_mhz eq "200"} {
    set period_ns 5.000
    set xdc_file [file join $ooc_dir axi_200mhz_ooc.xdc]
} elseif {$clock_mhz eq "175"} {
    set period_ns 5.714
    set xdc_file [file join $ooc_dir axi_175mhz_ooc.xdc]
} else {
    ::r54_fail "unsupported R54_CLOCK_MHZ '$clock_mhz'; expected 175 or 200"
}
set allowed_directives {Explore AggressiveExplore MoreGlobalIterations HigherDelayCost}

set usage "<experiment> <fresh_full|from_synth|from_placed|audit_dcp> <label> <expected_core_sha256> ?input_dcp expected_dcp_sha256 stage directive?"
if {[llength $argv] < 4 || [llength $argv] > 8} {::r54_fail "usage: $usage"}
set experiment [string toupper [lindex $argv 0]]
set mode [lindex $argv 1]
set label [lindex $argv 2]
set expected_core_sha [lindex $argv 3]
set input_dcp [expr {[llength $argv] >= 5 ? [file normalize [lindex $argv 4]] : ""}]
set expected_dcp_sha [expr {[llength $argv] >= 6 ? [lindex $argv 5] : ""}]
set input_stage [expr {[llength $argv] >= 7 ? [lindex $argv 6] : ""}]
set route_directive [expr {[llength $argv] >= 8 ? [lindex $argv 7] : "Explore"}]

if {![regexp {^[A-Z0-9_.-]+$} $experiment] ||
    ![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    ::r54_fail "invalid experiment or label"
}
if {$mode ni {fresh_full from_synth from_placed audit_dcp}} {
    ::r54_fail "invalid mode '$mode'; usage: $usage"
}
if {$route_directive ni $allowed_directives} {
    ::r54_fail "unsupported route directive '$route_directive'"
}
if {$mode eq "fresh_full"} {
    if {[llength $argv] != 4} {::r54_fail "fresh_full takes no DCP arguments"}
} else {
    if {$input_dcp eq "" || $expected_dcp_sha eq "" || $input_stage eq ""} {
        ::r54_fail "$mode requires input DCP, hash, and stage"
    }
    if {$input_stage ni {synth placed routed}} {::r54_fail "invalid input stage"}
    if {$mode eq "from_synth" && $input_stage ne "synth"} {
        ::r54_fail "from_synth requires synth stage"
    }
    if {$mode eq "from_placed" && $input_stage ne "placed"} {
        ::r54_fail "from_placed requires placed stage"
    }
}

set rtl_files [list \
    [file join $rtl_dir aes_core sbox.v] \
    [file join $rtl_dir stream_aes aes_block_engine.v] \
    [file join $rtl_dir stream_aes aes_first_block_engine.v] \
    [file join $rtl_dir stream_aes aes_key_context.v] \
    [file join $rtl_dir stream_ghash ghash16.v] \
    [file join $rtl_dir stream_axi axi_lite_regs.v] \
    [file join $rtl_dir stream_axi axis_output_skid_8.v] \
    [file join $rtl_dir stream_core aes_gcm_stream_core.v] \
    [file join $rtl_dir stream_core stream_fifo.v] \
    [file join $rtl_dir aes_gcm_axi_top.v]]
set core_file [file join $rtl_dir stream_core aes_gcm_stream_core.v]
foreach required [concat $rtl_files [list $xdc_file \
        [file join $script_dir round54_reports.tcl] \
        [file join $script_dir round54_hard_gate.tcl] \
        [file join $script_dir round54_path_families.tcl]]] {
    if {![file isfile $required]} {::r54_fail "required file missing: $required"}
}

if {[catch {
    set git_branch [string trim [exec git -C $repo_dir branch --show-current]]
    set git_commit [string trim [exec git -C $repo_dir rev-parse HEAD]]
    set git_status [string trim [exec git -C $repo_dir status --porcelain]]
} git_error]} {::r54_fail "Git provenance failed: $git_error"}
if {![string match "timing/round54-*" $git_branch] &&
    ![string match "timing/round55-*" $git_branch]} {
    ::r54_fail "branch '$git_branch' is not a Round54/Round55 timing branch"
}
if {$git_status ne ""} {
    ::r54_fail "working tree is not clean: $git_status"
}
if {![string match "2021.1*" [version -short]]} {
    ::r54_fail "Vivado [version -short] is not 2021.1"
}

if {[catch {
    ::r54_check_hash $core_file $expected_core_sha CORE
    ::r54_scan_xdc $xdc_file
    set input_dcp_actual_sha ""
    if {$input_dcp ne ""} {
        set input_dcp_actual_sha [::r54_check_hash $input_dcp \
            $expected_dcp_sha INPUT_DCP]
    }
} validation_error]} {::r54_fail $validation_error}

set output_dir [file join $ooc_dir \
    r54_[string tolower $experiment]_${label}]
if {[file exists $output_dir]} {
    ::r54_fail "refusing to overwrite output directory: $output_dir"
}
set report_dir [file join $output_dir reports]
set checkpoint_dir [file join $output_dir checkpoints]
file mkdir $report_dir
file mkdir $checkpoint_dir
source [file join $script_dir round54_reports.tcl]
set ::r53_hg_expected_period_ns $period_ns
source [file join $script_dir round54_hard_gate.tcl]

set provenance [dict create experiment $experiment mode $mode label $label \
    git_branch $git_branch git_commit $git_commit vivado_version [version -short] \
    top $top_name part $part_name clock_mhz $clock_mhz period_ns $period_ns \
    core_sha256 [::r54_sha256 $core_file] xdc_sha256 [::r54_sha256 $xdc_file] \
    input_dcp $input_dcp input_dcp_sha256 $input_dcp_actual_sha \
    input_stage $input_stage route_directive $route_directive]
::r54_write_provenance [file join $output_dir provenance.txt] $provenance $rtl_files

proc ::r54_audit {experiment stage report_dir} {
    set stage_dir [file join $report_dir $stage]
    set metrics [::r54_reports::run $stage $experiment $stage_dir]
    set gates [::r54_hg::run $experiment $stage \
        [file join $stage_dir r54_[string tolower $experiment]_${stage}_hard_gate.txt]]
    foreach key {setup_wns setup_tns setup_fep hold_whs hold_ths hold_fep} {
        if {abs(double([dict get $metrics $key]) - double([dict get $gates $key])) > 0.0005} {
            error "report/hard-gate mismatch for $key"
        }
    }
    return $metrics
}

proc ::r54_apply_prep_remap {} {
    set cells [get_cells -hier -quiet \
        -filter {NAME =~ *prep_tag_bytes_reg* && REF_NAME =~ FD*}]
    if {[llength $cells] != 5} {
        error "targeted remap expected 5 prep_tag cells, found [llength $cells]"
    }
    set_property CONTROL_SET_REMAP RESET $cells
    foreach cell $cells {
        if {[get_property CONTROL_SET_REMAP $cell] ne "RESET"} {
            error "CONTROL_SET_REMAP did not apply to $cell"
        }
    }
    puts "ROUND54_TARGETED_REMAP cells={$cells} value=RESET"
    opt_design -property_opt_only
}

proc ::r54_force_zeroize_replication {} {
    set driver [get_cells -quiet u_registers/zeroize_pulse_o_reg]
    if {[llength $driver] != 1 || [get_property REF_NAME $driver] ne "FDRE"} {
        error "exact ZEROIZE FDRE driver was not found"
    }
    set q [get_pins -quiet ${driver}/Q]
    set net [get_nets -quiet -of_objects $q]
    if {[llength $net] != 1} {error "exact ZEROIZE net was not found"}
    puts "ROUND54_FORCE_REPLICATION driver=$driver net=$net"
    phys_opt_design -force_replication_on_nets $net
}

proc ::r54_force_input_mode_replication {} {
    set driver [get_cells -quiet {u_core/input_field_mode_r_reg[2]}]
    if {[llength $driver] != 1 || [get_property REF_NAME $driver] ne "FDRE"} {
        error "exact input-field-mode FDRE driver was not found"
    }
    set q [get_pins -quiet -of_objects $driver -filter {REF_PIN_NAME == Q}]
    set net [get_nets -quiet -of_objects $q]
    if {[llength $net] != 1 || $net ne {u_core/input_field_mode_r[2]}} {
        error "exact input-field-mode net was not found: '$net'"
    }
    puts "ROUND54_FORCE_INPUT_MODE_REPLICATION driver=$driver net=$net fanout=[get_property FLAT_PIN_COUNT $net]"
    phys_opt_design -force_replication_on_nets $net
}

set flow_stage initialize
set final_metrics [dict create]
if {[catch {
    puts "ROUND54_RUN_BEGIN experiment=$experiment mode=$mode output=$output_dir"
    if {$mode eq "fresh_full"} {
        set flow_stage read_rtl
        foreach rtl $rtl_files {read_verilog $rtl}
        read_xdc $xdc_file
        set flow_stage synth_design
        synth_design -mode out_of_context -top $top_name -part $part_name \
            -flatten_hierarchy rebuilt
        set synth_dcp [file join $checkpoint_dir ${top_name}_synth.dcp]
        write_checkpoint $synth_dcp
        set final_metrics [::r54_audit $experiment synth $report_dir]
        puts "ROUND54_DCP stage=synth sha256=[::r54_sha256 $synth_dcp] path=$synth_dcp"
    } else {
        set flow_stage open_checkpoint
        open_checkpoint $input_dcp
        if {$clock_mhz ne "200"} {
            set flow_stage apply_clock_profile
            reset_timing
            read_xdc $xdc_file
        }
        set final_metrics [::r54_audit $experiment $input_stage $report_dir]
    }

    if {$mode eq "audit_dcp"} {
        if {$clock_mhz ne "200"} {
            set flow_stage write_reclocked_checkpoint
            set audited_dcp [file join $checkpoint_dir \
                ${top_name}_${clock_mhz}mhz_routed.dcp]
            write_checkpoint $audited_dcp
            puts "ROUND54_DCP stage=routed clock_mhz=$clock_mhz sha256=[::r54_sha256 $audited_dcp] path=$audited_dcp"
        }
        set flow_stage finalize
    } elseif {$mode in {fresh_full from_synth}} {
        if {[string match "C*" $experiment]} {
            set flow_stage targeted_control_set_remap
            ::r54_apply_prep_remap
        }
        set flow_stage opt_design
        opt_design -directive ExploreWithRemap
        set flow_stage place_design
        place_design -directive ExtraNetDelay_high
        set flow_stage phys_opt_design
        phys_opt_design -directive AggressiveExplore
        set placed_dcp [file join $checkpoint_dir ${top_name}_placed.dcp]
        write_checkpoint $placed_dcp
        set final_metrics [::r54_audit $experiment placed $report_dir]
        puts "ROUND54_DCP stage=placed sha256=[::r54_sha256 $placed_dcp] path=$placed_dcp"
        set flow_stage route_design
        route_design -directive $route_directive
        set routed_dcp [file join $checkpoint_dir ${top_name}_routed.dcp]
        write_checkpoint $routed_dcp
        set final_metrics [::r54_audit $experiment routed $report_dir]
        puts "ROUND54_DCP stage=routed sha256=[::r54_sha256 $routed_dcp] path=$routed_dcp"
    } elseif {$mode eq "from_placed"} {
        if {[string match "E*" $experiment]} {
            set flow_stage force_zeroize_replication
            ::r54_force_zeroize_replication
            set flow_stage audit_replicated_placed
            set final_metrics [::r54_audit $experiment placed \
                [file join $output_dir reports_after_replication]]
        }
        if {[string match "G*" $experiment]} {
            set flow_stage force_input_mode_replication
            ::r54_force_input_mode_replication
            set flow_stage audit_replicated_placed
            set final_metrics [::r54_audit $experiment placed \
                [file join $output_dir reports_after_replication]]
        }
        set placed_dcp [file join $checkpoint_dir ${top_name}_placed.dcp]
        write_checkpoint $placed_dcp
        set flow_stage route_design
        route_design -directive $route_directive
        set routed_dcp [file join $checkpoint_dir ${top_name}_routed.dcp]
        write_checkpoint $routed_dcp
        set final_metrics [::r54_audit $experiment routed $report_dir]
        puts "ROUND54_DCP stage=routed sha256=[::r54_sha256 $routed_dcp] path=$routed_dcp"
    }
    set flow_stage finalize
} flow_error flow_options]} {
    puts stderr "ROUND54_RUN_SUMMARY status=ERROR experiment=$experiment mode=$mode stage=$flow_stage output=$output_dir"
    puts stderr "ROUND54_RUN_ERROR $flow_error"
    if {[dict exists $flow_options -errorinfo]} {
        puts stderr [dict get $flow_options -errorinfo]
    }
    catch {close_design}
    exit 1
}

set routed_requested [expr {$mode in {fresh_full from_synth from_placed} ||
    ($mode eq "audit_dcp" && $input_stage eq "routed")}]
set setup_closed [expr {[dict get $final_metrics setup_wns] >= -0.0005 &&
    [dict get $final_metrics setup_fep] == 0 &&
    abs([dict get $final_metrics setup_tns]) <= 0.0005}]
set status [expr {$routed_requested && !$setup_closed ? "SETUP_FAIL" : "PASS"}]
puts [format "ROUND54_RUN_SUMMARY status=%s experiment=%s mode=%s setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d output=%s" \
    $status $experiment $mode [dict get $final_metrics setup_wns] \
    [dict get $final_metrics setup_tns] [dict get $final_metrics setup_fep] \
    [dict get $final_metrics hold_whs] [dict get $final_metrics hold_ths] \
    [dict get $final_metrics hold_fep] $output_dir]
catch {close_design}
exit [expr {$status eq "SETUP_FAIL" ? 2 : 0}]
