# CANDIDATE / DISCOVERY ONLY.
#
# Generate one deterministic, replay-schema-compatible PartPin candidate map
# from an exact immutable placed checkpoint.  This script never applies the
# candidate, never writes a checkpoint, and never performs implementation.
# Geometry discovery is not timing closure, signoff, or production approval.

namespace eval ::partpin_discovery_candidate {
    variable algorithm_version critical_slack_nearest_unique_v1
    variable approved_helper_sha \
        70829CE2389225E611F48CEE7305FC77DBE5B0905316C267CCC0B65814BD542B
}

proc ::partpin_discovery_candidate::fail {message} {
    return -code error $message
}

proc ::partpin_discovery_candidate::normalize_sha256 {value label} {
    set normalized [string toupper [string trim $value]]
    if {![regexp {^[0-9A-F]{64}$} $normalized]} {
        fail "$label is not a 64-digit SHA-256 value"
    }
    return $normalized
}

proc ::partpin_discovery_candidate::sha256_file {path} {
    if {![file isfile $path]} {
        fail "SHA-256 input is not a file: $path"
    }
    if {[catch {exec certutil.exe -hashfile $path SHA256} output]} {
        fail "certutil SHA-256 failed for '$path': $output"
    }
    set hashes {}
    foreach line [split $output "\n"] {
        set candidate [string trim $line " \t\r"]
        if {[regexp {^[0-9A-Fa-f]{64}$} $candidate]} {
            lappend hashes [string toupper $candidate]
        }
    }
    if {[llength $hashes] != 1} {
        fail "certutil did not return exactly one SHA-256 value for '$path'"
    }
    return [lindex $hashes 0]
}

proc ::partpin_discovery_candidate::metadata_names {names} {
    set names [lsort -dictionary $names]
    if {[llength $names] == 0} {
        return -
    }
    return [join $names ,]
}

proc ::partpin_discovery_candidate::compare_anchor_records {left right} {
    set left_slack [expr {double([lindex $left 0])}]
    set right_slack [expr {double([lindex $right 0])}]
    if {$left_slack < $right_slack} {
        return -1
    }
    if {$left_slack > $right_slack} {
        return 1
    }
    return [string compare [lindex $left 1] [lindex $right 1]]
}

proc ::partpin_discovery_candidate::resolve_anchor {port_name direction} {
    set port_object [get_ports -quiet [list $port_name]]
    if {[llength $port_object] != 1} {
        fail "Expected exactly one live port '$port_name'"
    }
    if {$direction eq "IN"} {
        set paths [get_timing_paths -quiet -delay_type max \
            -from $port_object -max_paths 1]
        set anchor_property ENDPOINT_PIN
    } else {
        set paths [get_timing_paths -quiet -delay_type max \
            -to $port_object -max_paths 1]
        set anchor_property STARTPOINT_PIN
    }
    if {[llength $paths] != 1} {
        fail "$direction port '$port_name' has no unique worst setup path"
    }
    set slack [get_property SLACK $paths]
    if {![string is double -strict $slack]} {
        fail "$direction port '$port_name' has non-numeric setup slack '$slack'"
    }
    set anchor_name [get_property $anchor_property $paths]
    set anchor_pin [get_pins -quiet [list $anchor_name]]
    if {[llength $anchor_pin] != 1} {
        fail "$direction port '$port_name' has an ambiguous $anchor_property"
    }
    set anchor_cell [get_cells -quiet -of_objects $anchor_pin]
    if {[llength $anchor_cell] != 1} {
        fail "$direction port '$port_name' anchor does not resolve to one cell"
    }
    set anchor_site [get_sites -quiet -of_objects $anchor_cell]
    if {[llength $anchor_site] != 1} {
        fail "$direction port '$port_name' anchor is absent, ambiguous, or unplaced"
    }
    set anchor_tile [get_tiles -quiet -of_objects $anchor_site]
    if {[llength $anchor_tile] != 1} {
        fail "$direction port '$port_name' anchor does not resolve to one tile"
    }
    set anchor_tile_name [get_property NAME $anchor_tile]
    set anchor_x [get_property GRID_POINT_X $anchor_tile]
    set anchor_y [get_property GRID_POINT_Y $anchor_tile]
    if {![string is integer -strict $anchor_x] ||
        ![string is integer -strict $anchor_y]} {
        fail "$direction port '$port_name' anchor has invalid grid coordinates"
    }
    return [list $slack $port_name $direction $anchor_name \
        $anchor_tile_name $anchor_x $anchor_y]
}

proc ::partpin_discovery_candidate::write_map {path parent_sha top part \
                                                vivado_version clock_port \
                                                period live_info entries \
                                                generator_sha helper_sha} {
    if {[file exists $path]} {
        fail "Candidate map work file already exists: $path"
    }
    set channel [open $path {WRONLY CREAT EXCL}]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "# CANDIDATE_DISCOVERY_ONLY - NOT APPROVED FOR REPLAY."
    puts $channel "# Geometry proposal only; no implementation or signoff was run."
    puts $channel "# GENERATOR_SHA256\t$generator_sha"
    puts $channel "# REPLAY_HELPER_SHA256\t$helper_sha"
    puts $channel "PARTPIN_MAP_VERSION\t1"
    puts $channel "PARENT_PLACED_SHA256\t$parent_sha"
    puts $channel "TOP\t$top"
    puts $channel "PART\t$part"
    puts $channel "VIVADO_VERSION\t$vivado_version"
    puts $channel "CLOCK_PORT\t$clock_port"
    puts $channel [format "CLOCK_PERIOD_NS\t%.3f" $period]
    puts $channel "ROUTE_DIRECTIVE\tExplore"
    puts $channel "PORT_COUNT\t[dict get $live_info port_count]"
    puts $channel "INPUT_PORT_COUNT\t[dict get $live_info input_count]"
    puts $channel "OUTPUT_PORT_COUNT\t[dict get $live_info output_count]"
    puts $channel "UNUSED_INPUT_PORTS\t[metadata_names \
        [dict get $live_info unused_inputs]]"
    puts $channel "UNUSED_OUTPUT_PORTS\t[metadata_names \
        [dict get $live_info unused_outputs]]"
    puts $channel "CONSTANT_OUTPUT_PORTS\t[metadata_names \
        [dict get $live_info constant_outputs]]"
    puts $channel "port\tdirection\tpartpin_tile"
    foreach entry [lsort -dictionary -index 0 $entries] {
        puts $channel [join $entry "\t"]
    }
    close $channel
}

set candidate_stage bootstrap
set candidate_design_open 0

if {[catch {
    if {[llength $argv] != 8} {
        error "Usage: run_partpin_discovery_candidate.tcl <placed_dcp> <placed_sha256> <fresh_output_dir> <top> <part> <vivado_version> <clock_port> <period_ns>"
    }

    set candidate_script [file normalize [info script]]
    set candidate_script_dir [file dirname $candidate_script]
    set candidate_helper [file join $candidate_script_dir partpin_ooc.tcl]
    set candidate_source_dcp [file normalize [lindex $argv 0]]
    set candidate_expected_sha \
        [::partpin_discovery_candidate::normalize_sha256 \
            [lindex $argv 1] placed_sha256]
    set candidate_output_arg [lindex $argv 2]
    set candidate_top [lindex $argv 3]
    set candidate_part [lindex $argv 4]
    set candidate_vivado [lindex $argv 5]
    set candidate_clock [lindex $argv 6]
    set candidate_period [lindex $argv 7]

    if {$candidate_top ne "aes_gcm_axi_top"} {
        error "Candidate discovery top must be literal aes_gcm_axi_top"
    }
    if {$candidate_part ne "xc7a100tcsg324-1"} {
        error "Candidate discovery part must be literal xc7a100tcsg324-1"
    }
    if {$candidate_vivado ne "2021.1"} {
        error "Candidate discovery Vivado version must be literal 2021.1"
    }
    if {$candidate_clock ne "aclk"} {
        error "Candidate discovery clock must be literal aclk"
    }
    if {![string is double -strict $candidate_period] ||
        abs(double($candidate_period) - 5.714) >= 0.0005} {
        error "Candidate discovery period must be 5.714 ns"
    }
    if {![file isfile $candidate_source_dcp]} {
        error "Placed checkpoint does not exist: $candidate_source_dcp"
    }
    if {![file isfile $candidate_helper]} {
        error "Locked replay helper does not exist: $candidate_helper"
    }

    set candidate_stage verify_source_identity
    set candidate_source_sha_pre \
        [::partpin_discovery_candidate::sha256_file $candidate_source_dcp]
    if {$candidate_source_sha_pre ne $candidate_expected_sha} {
        error "Placed checkpoint SHA-256 does not match the required parent"
    }
    set candidate_helper_sha \
        [::partpin_discovery_candidate::sha256_file $candidate_helper]
    if {$candidate_helper_sha ne \
        $::partpin_discovery_candidate::approved_helper_sha} {
        error "Replay helper SHA-256 is not the locked approved helper"
    }
    set candidate_generator_sha \
        [::partpin_discovery_candidate::sha256_file $candidate_script]

    set candidate_output_parent [file dirname $candidate_output_arg]
    if {![file isdirectory $candidate_output_parent]} {
        error "Candidate output parent directory does not exist: $candidate_output_parent"
    }
    set candidate_output_dir [file normalize $candidate_output_arg]
    if {[file exists $candidate_output_dir]} {
        error "Candidate output directory must be fresh: $candidate_output_dir"
    }
    file mkdir $candidate_output_dir

    # Preserve the checkpoint basename: Vivado derives the in-memory design
    # identity used by checkpoint queries from this name.
    set candidate_staged_dcp [file join $candidate_output_dir \
        [file tail $candidate_source_dcp]]
    set candidate_map_tmp [file join $candidate_output_dir \
        candidate_partpin_map.tsv.incomplete]
    set candidate_map_final [file join $candidate_output_dir \
        candidate_partpin_map.tsv]
    set candidate_audit_tmp [file join $candidate_output_dir \
        candidate_discovery_audit.tsv.incomplete]
    set candidate_audit_final [file join $candidate_output_dir \
        candidate_discovery_audit.tsv]
    set candidate_manifest_tmp [file join $candidate_output_dir \
        candidate_manifest.tsv.incomplete]
    set candidate_manifest_final [file join $candidate_output_dir \
        candidate_manifest.tsv]
    foreach final_artifact [list $candidate_map_final $candidate_audit_final \
        $candidate_manifest_final] {
        if {[file exists $final_artifact]} {
            error "Fresh candidate artifact already exists: $final_artifact"
        }
    }

    set candidate_stage stage_parent
    file copy $candidate_source_dcp $candidate_staged_dcp
    set candidate_staged_sha_pre \
        [::partpin_discovery_candidate::sha256_file $candidate_staged_dcp]
    if {$candidate_staged_sha_pre ne $candidate_expected_sha} {
        error "Staged checkpoint SHA-256 does not match the required parent"
    }

    source $candidate_helper

    set candidate_stage open_checkpoint
    open_checkpoint $candidate_staged_dcp
    set candidate_design_open 1

    set candidate_stage verify_live_schema
    set candidate_design_top [get_property TOP [current_design]]
    if {$candidate_design_top ne $candidate_top} {
        error "Opened checkpoint top is '$candidate_design_top', not '$candidate_top'"
    }
    if {[::partpin_ooc::current_part_name] ne $candidate_part} {
        error "Opened checkpoint part does not match '$candidate_part'"
    }
    if {[version -short] ne $candidate_vivado} {
        error "Vivado version '[version -short]' does not match '$candidate_vivado'"
    }
    set candidate_clocks [get_clocks -quiet]
    if {[llength $candidate_clocks] != 1 ||
        [get_property NAME [lindex $candidate_clocks 0]] ne $candidate_clock} {
        error "The checkpoint must have exactly one clock named '$candidate_clock'"
    }
    if {abs(double([get_property PERIOD [lindex $candidate_clocks 0]]) -
                   double($candidate_period)) >= 0.0005} {
        error "Live clock period does not match $candidate_period ns"
    }

    set candidate_live_info [::partpin_ooc::collect_live_ports $candidate_clock]
    if {[dict get $candidate_live_info port_count] != 155 ||
        [dict get $candidate_live_info input_count] != 79 ||
        [dict get $candidate_live_info output_count] != 76 ||
        [dict get $candidate_live_info inout_count] != 0} {
        error "Live scalar-port schema is not 155 = 79 IN + 76 OUT"
    }
    set candidate_expected_unused_inputs [lsort -dictionary [list \
        {s_axi_awprot[0]} {s_axi_awprot[1]} {s_axi_awprot[2]} \
        {s_axi_arprot[0]} {s_axi_arprot[1]} {s_axi_arprot[2]}]]
    if {[dict get $candidate_live_info unused_inputs] ne \
        $candidate_expected_unused_inputs} {
        error "Unused inputs are not exactly the six approved PROT bits"
    }
    if {[llength [dict get $candidate_live_info unused_outputs]] != 0 ||
        [llength [dict get $candidate_live_info untimed_inputs]] != 0 ||
        [llength [dict get $candidate_live_info untimed_outputs]] != 0} {
        error "Unexpected unused output or connected untimed port was found"
    }
    set candidate_derived_inputs [expr {
        [dict get $candidate_live_info input_count] - 1 -
        [llength [dict get $candidate_live_info unused_inputs]]}]
    set candidate_derived_outputs [expr {
        [dict get $candidate_live_info output_count] -
        [llength [dict get $candidate_live_info constant_outputs]]}]
    if {$candidate_derived_inputs != 72 ||
        [llength [dict get $candidate_live_info used_inputs]] !=
            $candidate_derived_inputs ||
        $candidate_derived_outputs != 59 ||
        [llength [dict get $candidate_live_info used_outputs]] !=
            $candidate_derived_outputs ||
        [llength [dict get $candidate_live_info constant_outputs]] != 17} {
        error "Derived timed-port classification is not 72 IN + 59 OUT"
    }

    foreach port_object [get_ports -quiet] {
        if {[get_property HD.PARTPIN_LOCS $port_object] ne ""} {
            error "Parent checkpoint already has PartPin state on '[get_property NAME $port_object]'"
        }
    }

    set candidate_stage resolve_setup_anchors
    set candidate_anchor_records {}
    foreach port_name [dict get $candidate_live_info used_inputs] {
        lappend candidate_anchor_records \
            [::partpin_discovery_candidate::resolve_anchor $port_name IN]
    }
    foreach port_name [dict get $candidate_live_info used_outputs] {
        lappend candidate_anchor_records \
            [::partpin_discovery_candidate::resolve_anchor $port_name OUT]
    }
    set candidate_anchor_records [lsort -command \
        ::partpin_discovery_candidate::compare_anchor_records \
        $candidate_anchor_records]
    if {[llength $candidate_anchor_records] != 131} {
        error "Setup anchor coverage is not exactly 131 timed ports"
    }

    set candidate_stage enumerate_tiles
    set candidate_tile_objects [get_tiles -quiet \
        -filter {TYPE == INT_L || TYPE == INT_R}]
    set candidate_tile_names [lsort -dictionary \
        [get_property NAME $candidate_tile_objects]]
    if {[llength $candidate_tile_names] < 131} {
        error "Not enough live INT_L/INT_R tiles for unique assignment"
    }
    array set candidate_tile_x {}
    array set candidate_tile_y {}
    foreach tile_name $candidate_tile_names {
        if {![regexp {^INT_[LR]_X[0-9]+Y[0-9]+$} $tile_name]} {
            error "Candidate tile '$tile_name' has an invalid name"
        }
        set tile_object [get_tiles -quiet [list $tile_name]]
        if {[llength $tile_object] != 1 ||
            [get_property TYPE $tile_object] ni {INT_L INT_R}} {
            error "Candidate tile '$tile_name' is not one live INT_L/INT_R tile"
        }
        set tx [get_property GRID_POINT_X $tile_object]
        set ty [get_property GRID_POINT_Y $tile_object]
        if {![string is integer -strict $tx] ||
            ![string is integer -strict $ty]} {
            error "Candidate tile '$tile_name' has invalid grid coordinates"
        }
        set candidate_tile_x($tile_name) $tx
        set candidate_tile_y($tile_name) $ty
    }

    set candidate_stage select_unique_tiles
    array set candidate_tile_taken {}
    set candidate_entries {}
    set candidate_audit_rows {}
    set candidate_selected_by_port [dict create]
    set candidate_rank 0
    foreach anchor $candidate_anchor_records {
        incr candidate_rank
        set setup_slack [lindex $anchor 0]
        set port_name [lindex $anchor 1]
        set direction [lindex $anchor 2]
        set anchor_pin [lindex $anchor 3]
        set anchor_tile [lindex $anchor 4]
        set anchor_x [lindex $anchor 5]
        set anchor_y [lindex $anchor 6]

        set best_tile ""
        set best_distance 0
        set best_abs_dy 0
        set best_abs_dx 0
        foreach tile_name $candidate_tile_names {
            if {[info exists candidate_tile_taken($tile_name)]} {
                continue
            }
            set abs_dx [expr {abs($candidate_tile_x($tile_name) - $anchor_x)}]
            set abs_dy [expr {abs($candidate_tile_y($tile_name) - $anchor_y)}]
            set distance [expr {$abs_dx + $abs_dy}]
            if {$best_tile eq "" ||
                $distance < $best_distance ||
                ($distance == $best_distance && $abs_dy < $best_abs_dy) ||
                ($distance == $best_distance && $abs_dy == $best_abs_dy &&
                 $abs_dx < $best_abs_dx) ||
                ($distance == $best_distance && $abs_dy == $best_abs_dy &&
                 $abs_dx == $best_abs_dx &&
                 [string compare $tile_name $best_tile] < 0)} {
                set best_tile $tile_name
                set best_distance $distance
                set best_abs_dy $abs_dy
                set best_abs_dx $abs_dx
            }
        }
        if {$best_tile eq ""} {
            error "Unique INT_L/INT_R tile universe exhausted at '$port_name'"
        }
        set candidate_tile_taken($best_tile) 1
        dict set candidate_selected_by_port $port_name \
            [list $direction $best_tile]
        lappend candidate_entries [list $port_name $direction $best_tile]
        lappend candidate_audit_rows [list $candidate_rank $port_name $direction \
            [format %.3f $setup_slack] $anchor_pin $anchor_tile \
            $anchor_x $anchor_y $best_tile \
            $candidate_tile_x($best_tile) $candidate_tile_y($best_tile) \
            $best_distance $best_abs_dy $best_abs_dx]
    }

    set candidate_stage write_incomplete_artifacts
    ::partpin_discovery_candidate::write_map $candidate_map_tmp \
        $candidate_expected_sha $candidate_top $candidate_part \
        $candidate_vivado $candidate_clock $candidate_period \
        $candidate_live_info $candidate_entries $candidate_generator_sha \
        $candidate_helper_sha
    set candidate_audit_channel [open $candidate_audit_tmp {WRONLY CREAT EXCL}]
    fconfigure $candidate_audit_channel -encoding utf-8 -translation lf
    puts $candidate_audit_channel "# CANDIDATE_DISCOVERY_ONLY - geometry evidence, not signoff."
    puts $candidate_audit_channel "rank\tport\tdirection\tworst_setup_slack_ns\tanchor_pin\tanchor_tile\tanchor_x\tanchor_y\tselected_tile\tselected_x\tselected_y\tmanhattan_distance\tabs_dy\tabs_dx"
    foreach row $candidate_audit_rows {
        puts $candidate_audit_channel [join $row "\t"]
    }
    close $candidate_audit_channel

    set candidate_stage validate_generated_schema
    set candidate_map_info [::partpin_ooc::parse_map $candidate_map_tmp]
    ::partpin_ooc::verify_identity $candidate_map_info \
        $candidate_expected_sha $candidate_top $candidate_part \
        $candidate_vivado $candidate_period Explore
    set candidate_metadata [dict get $candidate_map_info metadata]
    foreach {metadata_key live_key} {
        PORT_COUNT port_count
        INPUT_PORT_COUNT input_count
        OUTPUT_PORT_COUNT output_count
    } {
        if {[dict get $candidate_metadata $metadata_key] !=
            [dict get $candidate_live_info $live_key]} {
            error "Generated map metadata $metadata_key changed"
        }
    }
    if {[dict get $candidate_metadata UNUSED_INPUT_PORTS] ne
            [dict get $candidate_live_info unused_inputs] ||
        [dict get $candidate_metadata UNUSED_OUTPUT_PORTS] ne
            [dict get $candidate_live_info unused_outputs] ||
        [dict get $candidate_metadata CONSTANT_OUTPUT_PORTS] ne
            [dict get $candidate_live_info constant_outputs]} {
        error "Generated map classification metadata changed"
    }

    set candidate_parsed_entries [dict get $candidate_map_info entries]
    if {[llength $candidate_parsed_entries] != 131} {
        error "Generated map does not contain exactly 131 rows"
    }
    set candidate_parsed_names {}
    foreach entry $candidate_parsed_entries {
        set port_name [lindex $entry 0]
        set direction [lindex $entry 1]
        set tile_name [lindex $entry 2]
        if {![dict exists $candidate_selected_by_port $port_name] ||
            [dict get $candidate_selected_by_port $port_name] ne
                [list $direction $tile_name]} {
            error "Generated map row for '$port_name' changed after selection"
        }
        set port_object [get_ports -quiet [list $port_name]]
        if {[llength $port_object] != 1 ||
            [string toupper [get_property DIRECTION $port_object]] ne $direction} {
            error "Generated map direction for '$port_name' is invalid"
        }
        set tile_object [get_tiles -quiet [list $tile_name]]
        if {[llength $tile_object] != 1 ||
            [get_property TYPE $tile_object] ni {INT_L INT_R}} {
            error "Generated map tile '$tile_name' is invalid"
        }
        if {[get_property HD.PARTPIN_LOCS $port_object] ne ""} {
            error "Discovery unexpectedly changed PartPin state on '$port_name'"
        }
        lappend candidate_parsed_names $port_name
    }
    if {$candidate_parsed_names ne
        [lsort -dictionary $candidate_parsed_names]} {
        error "Generated map rows are not in dictionary port order"
    }
    set candidate_required_names [lsort -dictionary [concat \
        [dict get $candidate_live_info used_inputs] \
        [dict get $candidate_live_info used_outputs]]]
    if {[lsort -dictionary $candidate_parsed_names] ne $candidate_required_names} {
        error "Generated map does not exactly cover the live timed port set"
    }

    set candidate_stage close_checkpoint
    close_design
    set candidate_design_open 0

    set candidate_stage verify_postrun_immutability
    set candidate_source_sha_post \
        [::partpin_discovery_candidate::sha256_file $candidate_source_dcp]
    set candidate_staged_sha_post \
        [::partpin_discovery_candidate::sha256_file $candidate_staged_dcp]
    set candidate_helper_sha_post \
        [::partpin_discovery_candidate::sha256_file $candidate_helper]
    set candidate_generator_sha_post \
        [::partpin_discovery_candidate::sha256_file $candidate_script]
    if {$candidate_source_sha_post ne $candidate_expected_sha ||
        $candidate_staged_sha_post ne $candidate_expected_sha ||
        $candidate_helper_sha_post ne $candidate_helper_sha ||
        $candidate_generator_sha_post ne $candidate_generator_sha} {
        error "Parent, staged parent, helper, or generator changed during discovery"
    }

    set candidate_map_sha \
        [::partpin_discovery_candidate::sha256_file $candidate_map_tmp]
    set candidate_audit_sha \
        [::partpin_discovery_candidate::sha256_file $candidate_audit_tmp]

    set candidate_stage write_manifest
    set candidate_manifest_channel \
        [open $candidate_manifest_tmp {WRONLY CREAT EXCL}]
    fconfigure $candidate_manifest_channel -encoding utf-8 -translation lf
    foreach row [list \
        [list STATUS CANDIDATE] \
        [list SCOPE DISCOVERY_ONLY] \
        [list PROMOTION FORBIDDEN] \
        [list IMPLEMENTATION_EXECUTED 0] \
        [list ALGORITHM_VERSION \
            $::partpin_discovery_candidate::algorithm_version] \
        [list ALGORITHM_ORDER {worst_setup_slack_ascending_then_port_name}] \
        [list ALGORITHM_TILE_SCORE \
            {manhattan_distance_abs_dy_abs_dx_tile_name}] \
        [list GENERATOR_SHA256 $candidate_generator_sha] \
        [list REPLAY_HELPER_SHA256 $candidate_helper_sha] \
        [list PARENT_SOURCE_SHA256_PRE $candidate_source_sha_pre] \
        [list PARENT_STAGED_SHA256_PRE $candidate_staged_sha_pre] \
        [list PARENT_SOURCE_SHA256_POST $candidate_source_sha_post] \
        [list PARENT_STAGED_SHA256_POST $candidate_staged_sha_post] \
        [list TOP $candidate_top] \
        [list PART $candidate_part] \
        [list VIVADO_VERSION $candidate_vivado] \
        [list CLOCK_PORT $candidate_clock] \
        [list CLOCK_PERIOD_NS [format %.3f $candidate_period]] \
        [list ROUTE_DIRECTIVE_METADATA Explore] \
        [list PORT_COUNT [dict get $candidate_live_info port_count]] \
        [list INPUT_PORT_COUNT [dict get $candidate_live_info input_count]] \
        [list OUTPUT_PORT_COUNT [dict get $candidate_live_info output_count]] \
        [list UNUSED_INPUT_COUNT \
            [llength [dict get $candidate_live_info unused_inputs]]] \
        [list CONSTANT_OUTPUT_COUNT \
            [llength [dict get $candidate_live_info constant_outputs]]] \
        [list MAPPED_INPUT_COUNT $candidate_derived_inputs] \
        [list MAPPED_OUTPUT_COUNT $candidate_derived_outputs] \
        [list MAPPED_TOTAL_COUNT [llength $candidate_entries]] \
        [list CANDIDATE_TILE_COUNT [llength $candidate_tile_names]] \
        [list MAP_FILE [file tail $candidate_map_final]] \
        [list MAP_SHA256 $candidate_map_sha] \
        [list AUDIT_FILE [file tail $candidate_audit_final]] \
        [list AUDIT_SHA256 $candidate_audit_sha]] {
        puts $candidate_manifest_channel [join $row "\t"]
    }
    close $candidate_manifest_channel

    set candidate_stage publish_candidate
    file rename $candidate_audit_tmp $candidate_audit_final
    file rename $candidate_manifest_tmp $candidate_manifest_final
    # The map is renamed last.  Any earlier error leaves no consumable map.
    file rename $candidate_map_tmp $candidate_map_final
    catch {puts "PARTPIN_DISCOVERY status=CANDIDATE mapped_inputs=$candidate_derived_inputs mapped_outputs=$candidate_derived_outputs map_sha256=$candidate_map_sha audit_sha256=$candidate_audit_sha implementation_executed=0 promotion=FORBIDDEN"}
} candidate_error candidate_options]} {
    if {$candidate_design_open} {
        catch {close_design}
    }
    puts stderr "PARTPIN_DISCOVERY status=ERROR stage=$candidate_stage"
    puts stderr "PARTPIN_DISCOVERY_ERROR $candidate_error"
    if {[dict exists $candidate_options -errorinfo]} {
        puts stderr [dict get $candidate_options -errorinfo]
    }
    exit 1
}

exit 0
