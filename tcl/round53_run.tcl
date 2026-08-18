# Reproducible Round53 Vivado 2021.1 OOC implementation driver.
#
# Usage:
#   vivado -mode batch -source round53_run.tcl -tclargs \
#       <A|B|C|D> <fresh_synth|fresh_full|locked_full|audit_dcp> \
#       <label> <expected_core_sha256> \
#       ?input_dcp? ?expected_dcp_sha256? ?synth|placed|routed?
#
# Exit codes:
#   0: requested work completed; all mandatory gates pass (and routed setup
#      is closed when a routed design was requested)
#   2: routed legality/hold/DRC/structure gates pass, but internal setup fails
#   1: provenance, source, structural, legality, hold, DRC, or tool failure

proc ::r53_run_fail {message} {
    puts stderr "ROUND53_RUN_SUMMARY status=ERROR"
    puts stderr "ROUND53_RUN_ERROR $message"
    exit 1
}

proc ::r53_sha256_file {path} {
    if {![file isfile $path]} {
        error "cannot hash missing file: $path"
    }
    if {$::tcl_platform(platform) eq "windows"} {
        set output [exec certutil.exe -hashfile [file nativename $path] SHA256]
        foreach line [split $output "\n"] {
            set candidate [string toupper [string map [list " " "" "\r" "" "\t" ""] $line]]
            if {[regexp {^[0-9A-F]{64}$} $candidate]} {
                return $candidate
            }
        }
    }
    if {![catch {package require sha256}]} {
        return [string toupper [::sha2::sha256 -hex -filename $path]]
    }
    error "no usable SHA-256 implementation is available"
}

proc ::r53_check_hash {path expected label} {
    if {![regexp {^[0-9A-Fa-f]{64}$} $expected]} {
        error "$label expected SHA-256 is not 64 hexadecimal digits: '$expected'"
    }
    set actual [::r53_sha256_file $path]
    if {![string equal -nocase $actual $expected]} {
        error "$label SHA-256 mismatch for $path: expected [string toupper $expected], actual $actual"
    }
    puts "ROUND53_HASH_OK label=$label sha256=$actual path=$path"
    return $actual
}

proc ::r53_scan_xdc {path} {
    set channel [open $path r]
    set contents [read $channel]
    close $channel
    set line_number 0
    foreach line [split $contents "\n"] {
        incr line_number
        set code [lindex [split $line #] 0]
        if {[regexp -nocase {(^|[;[:space:]])(set_false_path|set_multicycle_path|set_max_delay|set_min_delay|set_case_analysis|set_disable_timing|set_clock_groups)([;[:space:]]|$)} $code match command]} {
            error "forbidden timing-exception command '$command' in $path at line $line_number"
        }
    }
}

proc ::r53_write_provenance {path values rtl_files} {
    set channel [open $path w]
    foreach key [lsort [dict keys $values]] {
        puts $channel "$key=[dict get $values $key]"
    }
    foreach rtl_file $rtl_files {
        puts $channel "rtl_sha256=[::r53_sha256_file $rtl_file] rtl_file=$rtl_file"
    }
    close $channel
}

set script_dir [file dirname [file normalize [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set rtl_dir [file normalize [file join $repo_dir engrenring rtl source]]
set ooc_dir [file normalize [file join $repo_dir engrenring synth_1g axi_ooc]]
set xdc_file [file join $ooc_dir axi_200mhz_ooc.xdc]
set top_name aes_gcm_axi_top
set part_name xc7a100tcsg324-1
set clock_period_ns 5.000
set required_branch timing/round53-zero-cycle-closure

set usage "<A|B|C|D> <fresh_synth|fresh_full|locked_full|audit_dcp> <label> <expected_core_sha256> ?input_dcp? ?expected_dcp_sha256? ?synth|placed|routed?"
if {[llength $argv] < 4 || [llength $argv] > 7} {
    ::r53_run_fail "usage: $usage"
}
set experiment [string toupper [lindex $argv 0]]
set run_mode [lindex $argv 1]
set label [lindex $argv 2]
set expected_core_sha256 [lindex $argv 3]
set input_dcp [expr {[llength $argv] >= 5 ? [lindex $argv 4] : ""}]
set expected_dcp_sha256 [expr {[llength $argv] >= 6 ? [lindex $argv 5] : ""}]
set audit_stage [expr {[llength $argv] >= 7 ? [lindex $argv 6] : "routed"}]

if {$experiment ni {A B C D}} {
    ::r53_run_fail "invalid experiment '$experiment'; usage: $usage"
}
if {$run_mode ni {fresh_synth fresh_full locked_full audit_dcp}} {
    ::r53_run_fail "invalid run mode '$run_mode'; usage: $usage"
}
if {![regexp {^[A-Za-z0-9_.-]+$} $label]} {
    ::r53_run_fail "invalid label '$label'; use only letters, digits, dot, underscore, or hyphen"
}
if {$audit_stage ni {synth placed routed}} {
    ::r53_run_fail "invalid DCP stage '$audit_stage'"
}
if {$run_mode in {locked_full audit_dcp}} {
    if {$input_dcp eq "" || $expected_dcp_sha256 eq ""} {
        ::r53_run_fail "$run_mode requires input_dcp and expected_dcp_sha256"
    }
    set input_dcp [file normalize $input_dcp]
} elseif {$input_dcp ne "" || $expected_dcp_sha256 ne "" || [llength $argv] > 4} {
    ::r53_run_fail "$run_mode does not accept DCP arguments"
}
if {$run_mode eq "locked_full" && [llength $argv] >= 7 && $audit_stage ne "synth"} {
    ::r53_run_fail "locked_full input must be a synthesized DCP"
}
if {$run_mode eq "locked_full"} {
    set audit_stage synth
}

set rtl_files [list \
    [file join $rtl_dir aes_core sbox.v] \
    [file join $rtl_dir stream_aes aes_block_engine.v] \
    [file join $rtl_dir stream_aes aes_key_context.v] \
    [file join $rtl_dir stream_ghash ghash16.v] \
    [file join $rtl_dir stream_axi axi_lite_regs.v] \
    [file join $rtl_dir stream_axi axis_output_skid_8.v] \
    [file join $rtl_dir stream_core aes_gcm_stream_core.v] \
    [file join $rtl_dir stream_core stream_fifo.v] \
    [file join $rtl_dir aes_gcm_axi_top.v]]
set core_file [file join $rtl_dir stream_core aes_gcm_stream_core.v]

foreach required [concat $rtl_files [list $xdc_file \
        [file join $script_dir round53_hard_gate.tcl] \
        [file join $script_dir round53_reports.tcl]]] {
    if {![file isfile $required]} {
        ::r53_run_fail "required file is missing: $required"
    }
}

if {[catch {
    set git_branch [string trim [exec git -C $repo_dir rev-parse --abbrev-ref HEAD]]
    set git_commit [string trim [exec git -C $repo_dir rev-parse HEAD]]
} git_error]} {
    ::r53_run_fail "Git provenance query failed: $git_error"
}
if {$git_branch ne $required_branch} {
    ::r53_run_fail "current branch is '$git_branch', expected '$required_branch'"
}

set vivado_version [version -short]
if {![string match "2021.1*" $vivado_version]} {
    ::r53_run_fail "Vivado version is '$vivado_version', expected 2021.1"
}

set input_dcp_actual_sha256 ""
if {[catch {
    ::r53_check_hash $core_file $expected_core_sha256 CORE
    ::r53_scan_xdc $xdc_file
    if {$input_dcp ne ""} {
        set input_dcp_actual_sha256 \
            [::r53_check_hash $input_dcp $expected_dcp_sha256 INPUT_DCP]
    }
} validation_error validation_options]} {
    ::r53_run_fail $validation_error
}

set output_name "r53_[string tolower $experiment]_${label}"
set output_dir [file join $ooc_dir $output_name]
if {[file exists $output_dir]} {
    ::r53_run_fail "refusing to overwrite existing output directory: $output_dir"
}
set report_dir [file join $output_dir reports]
set checkpoint_dir [file join $output_dir checkpoints]
file mkdir $report_dir
file mkdir $checkpoint_dir

source [file join $script_dir round53_reports.tcl]
source [file join $script_dir round53_hard_gate.tcl]

set provenance [dict create \
    experiment $experiment \
    run_mode $run_mode \
    label $label \
    git_branch $git_branch \
    git_commit $git_commit \
    vivado_version $vivado_version \
    top $top_name \
    part $part_name \
    clock_period_ns $clock_period_ns \
    core_sha256 [::r53_sha256_file $core_file] \
    xdc_sha256 [::r53_sha256_file $xdc_file] \
    input_dcp $input_dcp \
    input_dcp_sha256 $input_dcp_actual_sha256]
::r53_write_provenance [file join $output_dir provenance.txt] $provenance $rtl_files

proc ::r53_run_stage_audit {experiment stage report_dir} {
    set stage_report_dir [file join $report_dir $stage]
    set metrics [::r53_reports::run $stage $experiment $stage_report_dir]
    set gate_metrics [::r53_hg::run $experiment $stage \
        [file join $stage_report_dir r53_[string tolower $experiment]_${stage}_hard_gate.txt]]
    foreach key {setup_wns setup_tns setup_fep hold_whs hold_ths hold_fep} {
        if {[dict get $metrics $key] != [dict get $gate_metrics $key]} {
            error "report/hard-gate metric mismatch for $key"
        }
    }
    return $gate_metrics
}

set flow_stage initialize
set final_metrics [dict create]
if {[catch {
    puts "ROUND53_RUN_BEGIN experiment=$experiment mode=$run_mode label=$label output=$output_dir"

    if {$run_mode in {fresh_synth fresh_full}} {
        set flow_stage read_rtl
        foreach rtl_file $rtl_files {
            puts "ROUND53_READ_VERILOG $rtl_file"
            read_verilog $rtl_file
        }
        read_xdc $xdc_file

        set flow_stage synth_design
        synth_design -mode out_of_context -top $top_name -part $part_name \
            -flatten_hierarchy rebuilt
        set synth_dcp [file join $checkpoint_dir ${top_name}_synth.dcp]
        write_checkpoint $synth_dcp
        set flow_stage synth_audit
        set final_metrics [::r53_run_stage_audit $experiment synth $report_dir]
        puts "ROUND53_DCP stage=synth sha256=[::r53_sha256_file $synth_dcp] path=$synth_dcp"
    } else {
        set flow_stage open_checkpoint
        open_checkpoint $input_dcp
        set flow_stage input_dcp_audit
        set final_metrics [::r53_run_stage_audit $experiment $audit_stage $report_dir]
    }

    if {$run_mode in {fresh_full locked_full}} {
        set flow_stage opt_design
        opt_design -directive ExploreWithRemap
        set flow_stage place_design
        place_design -directive ExtraNetDelay_high
        set flow_stage phys_opt_design
        phys_opt_design -directive AggressiveExplore
        set placed_dcp [file join $checkpoint_dir ${top_name}_placed.dcp]
        write_checkpoint $placed_dcp
        set flow_stage placed_audit
        set final_metrics [::r53_run_stage_audit $experiment placed $report_dir]
        puts "ROUND53_DCP stage=placed sha256=[::r53_sha256_file $placed_dcp] path=$placed_dcp"

        set flow_stage route_design
        route_design -directive Explore
        set routed_dcp [file join $checkpoint_dir ${top_name}_routed.dcp]
        write_checkpoint $routed_dcp
        set flow_stage routed_audit
        set final_metrics [::r53_run_stage_audit $experiment routed $report_dir]
        puts "ROUND53_DCP stage=routed sha256=[::r53_sha256_file $routed_dcp] path=$routed_dcp"
    }

    set flow_stage finalize
} flow_error flow_options]} {
    puts stderr "ROUND53_RUN_SUMMARY status=ERROR experiment=$experiment mode=$run_mode stage=$flow_stage output=$output_dir"
    puts stderr "ROUND53_RUN_ERROR $flow_error"
    if {[dict exists $flow_options -errorinfo]} {
        puts stderr [dict get $flow_options -errorinfo]
    }
    catch {close_design}
    exit 1
}

set routed_requested [expr {$run_mode in {fresh_full locked_full} ||
                           ($run_mode eq "audit_dcp" && $audit_stage eq "routed")}]
if {$routed_requested && ![dict get $final_metrics setup_closed]} {
    puts stderr [format \
        "ROUND53_RUN_SUMMARY status=SETUP_FAIL experiment=%s mode=%s setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d output=%s" \
        $experiment $run_mode \
        [dict get $final_metrics setup_wns] [dict get $final_metrics setup_tns] \
        [dict get $final_metrics setup_fep] [dict get $final_metrics hold_whs] \
        [dict get $final_metrics hold_ths] [dict get $final_metrics hold_fep] \
        $output_dir]
    catch {close_design}
    exit 2
}

puts [format \
    "ROUND53_RUN_SUMMARY status=PASS experiment=%s mode=%s setup_wns=%.3f setup_tns=%.3f setup_fep=%d hold_whs=%.3f hold_ths=%.3f hold_fep=%d output=%s" \
    $experiment $run_mode \
    [dict get $final_metrics setup_wns] [dict get $final_metrics setup_tns] \
    [dict get $final_metrics setup_fep] [dict get $final_metrics hold_whs] \
    [dict get $final_metrics hold_ths] [dict get $final_metrics hold_fep] \
    $output_dir]
catch {close_design}
exit 0
