# Shared, fail-closed helpers for production PartPin replay.
#
# Approved maps are UTF-8 TSV files with this exact preamble followed by one
# row for every timed, non-clock top-level port bit:
#
# PARTPIN_MAP_VERSION<TAB>1
# PARENT_PLACED_SHA256<TAB><64 hexadecimal characters>
# TOP<TAB>aes_gcm_axi_top
# PART<TAB>xc7a100tcsg324-1
# VIVADO_VERSION<TAB>2021.1
# CLOCK_PORT<TAB>aclk
# CLOCK_PERIOD_NS<TAB>5.000
# ROUTE_DIRECTIVE<TAB>Explore
# PORT_COUNT<TAB>155
# INPUT_PORT_COUNT<TAB>79
# OUTPUT_PORT_COUNT<TAB>76
# UNUSED_INPUT_PORTS<TAB><comma-separated names, or ->
# UNUSED_OUTPUT_PORTS<TAB><comma-separated names, or ->
# CONSTANT_OUTPUT_PORTS<TAB><comma-separated names, or ->
# port<TAB>direction<TAB>partpin_tile
# <port bit><TAB>IN|OUT<TAB>INT_L_*|INT_R_*

namespace eval ::partpin_ooc {
    variable map_version 1
    variable required_metadata [list \
        PARTPIN_MAP_VERSION PARENT_PLACED_SHA256 TOP PART VIVADO_VERSION \
        CLOCK_PORT CLOCK_PERIOD_NS ROUTE_DIRECTIVE PORT_COUNT \
        INPUT_PORT_COUNT OUTPUT_PORT_COUNT UNUSED_INPUT_PORTS \
        UNUSED_OUTPUT_PORTS CONSTANT_OUTPUT_PORTS]
    variable timing_check_names [list \
        no_clock constant_clock pulse_width_clock \
        unconstrained_internal_endpoints no_input_delay no_output_delay \
        multiple_clock generated_clocks loops partial_input_delay \
        partial_output_delay latch_loops]
}

proc ::partpin_ooc::fail {message} {
    return -code error $message
}

proc ::partpin_ooc::normalize_sha256 {value label} {
    set normalized [string toupper [string trim $value]]
    if {![regexp {^[0-9A-F]{64}$} $normalized]} {
        fail "$label is not a 64-digit SHA-256 value"
    }
    return $normalized
}

proc ::partpin_ooc::metadata_name_list {value label} {
    set value [string trim $value]
    if {$value eq "-"} {
        return {}
    }
    set result {}
    foreach name [split $value ,] {
        set name [string trim $name]
        if {$name eq ""} {
            fail "$label contains an empty name"
        }
        if {[lsearch -exact $result $name] >= 0} {
            fail "$label contains duplicate name '$name'"
        }
        lappend result $name
    }
    return [lsort -dictionary $result]
}

proc ::partpin_ooc::parse_map {map_file} {
    variable map_version
    variable required_metadata

    if {![file isfile $map_file]} {
        fail "PartPin map does not exist: $map_file"
    }
    set normalized_map [file normalize $map_file]
    set channel [open $normalized_map r]
    fconfigure $channel -encoding utf-8 -translation auto
    set text [read $channel]
    close $channel

    set metadata [dict create]
    set entries {}
    set header_seen 0
    set line_number 0
    set port_names {}
    set tile_names {}
    foreach raw_line [split $text "\n"] {
        incr line_number
        set line [string trimright $raw_line "\r"]
        if {$line_number == 1} {
            set line [string trimleft $line "\ufeff"]
        }
        if {[string trim $line] eq "" ||
            [string match "#*" [string trimleft $line]]} {
            continue
        }
        set fields [split $line "\t"]
        if {!$header_seen} {
            if {[llength $fields] == 3 &&
                [lindex $fields 0] eq "port" &&
                [lindex $fields 1] eq "direction" &&
                [lindex $fields 2] eq "partpin_tile"} {
                set header_seen 1
                continue
            }
            if {[llength $fields] != 2} {
                fail "Malformed PartPin metadata at line $line_number"
            }
            set key [string trim [lindex $fields 0]]
            set value [string trim [lindex $fields 1]]
            if {[lsearch -exact $required_metadata $key] < 0} {
                fail "Unknown PartPin metadata '$key' at line $line_number"
            }
            if {[dict exists $metadata $key]} {
                fail "Duplicate PartPin metadata '$key' at line $line_number"
            }
            if {$value eq ""} {
                fail "Empty PartPin metadata '$key' at line $line_number"
            }
            dict set metadata $key $value
            continue
        }

        if {[llength $fields] != 3} {
            fail "Malformed PartPin row at line $line_number"
        }
        set port_name [string trim [lindex $fields 0]]
        set direction [string toupper [string trim [lindex $fields 1]]]
        set tile_name [string trim [lindex $fields 2]]
        if {$port_name eq "" || $direction ni {IN OUT} || $tile_name eq ""} {
            fail "Invalid PartPin row at line $line_number"
        }
        if {![regexp {^INT_[LR]_X[0-9]+Y[0-9]+$} $tile_name]} {
            fail "Invalid PartPin tile '$tile_name' at line $line_number"
        }
        if {[lsearch -exact $port_names $port_name] >= 0} {
            fail "Duplicate PartPin port '$port_name' at line $line_number"
        }
        if {[lsearch -exact $tile_names $tile_name] >= 0} {
            fail "Duplicate PartPin tile '$tile_name' at line $line_number"
        }
        lappend port_names $port_name
        lappend tile_names $tile_name
        lappend entries [list $port_name $direction $tile_name]
    }

    if {!$header_seen} {
        fail "PartPin map is missing the port/direction/partpin_tile header"
    }
    foreach key $required_metadata {
        if {![dict exists $metadata $key]} {
            fail "PartPin map is missing metadata '$key'"
        }
    }
    if {[dict get $metadata PARTPIN_MAP_VERSION] ne $map_version} {
        fail "Unsupported PartPin map version '[dict get $metadata PARTPIN_MAP_VERSION]'"
    }
    dict set metadata PARENT_PLACED_SHA256 [normalize_sha256 \
        [dict get $metadata PARENT_PLACED_SHA256] PARENT_PLACED_SHA256]
    foreach key {PORT_COUNT INPUT_PORT_COUNT OUTPUT_PORT_COUNT} {
        set value [dict get $metadata $key]
        if {![string is integer -strict $value] || $value < 0} {
            fail "PartPin metadata $key must be a non-negative integer"
        }
    }
    set period [dict get $metadata CLOCK_PERIOD_NS]
    if {![string is double -strict $period] || double($period) <= 0.0} {
        fail "PartPin CLOCK_PERIOD_NS must be positive"
    }
    if {![regexp {^[A-Za-z0-9_]+$} [dict get $metadata ROUTE_DIRECTIVE]]} {
        fail "PartPin ROUTE_DIRECTIVE contains unsupported characters"
    }
    foreach key {UNUSED_INPUT_PORTS UNUSED_OUTPUT_PORTS CONSTANT_OUTPUT_PORTS} {
        dict set metadata $key [metadata_name_list [dict get $metadata $key] $key]
    }
    if {[llength $entries] == 0} {
        fail "PartPin map contains no port rows"
    }
    return [dict create map_file $normalized_map metadata $metadata entries $entries]
}

proc ::partpin_ooc::one_port {name} {
    set objects [get_ports -quiet [list $name]]
    if {[llength $objects] != 1} {
        fail "Expected exactly one live port named '$name', found [llength $objects]"
    }
    return $objects
}

proc ::partpin_ooc::path_endpoint_name {path property_name} {
    if {[llength $path] != 1} {
        fail "Expected exactly one timing path while reading $property_name"
    }
    return [get_property $property_name $path]
}

proc ::partpin_ooc::verify_io_path_contract {port_name direction max_path \
                                              min_path clock_port} {
    set delay_property [expr {$direction eq "IN" ? "INPUT_DELAY" :
                                                     "OUTPUT_DELAY"}]
    set max_delay [get_property $delay_property $max_path]
    set min_delay [get_property $delay_property $min_path]
    if {![string is double -strict $max_delay] ||
        ![string is double -strict $min_delay] ||
        abs(double($max_delay) - 1.000) >= 0.0005 ||
        abs(double($min_delay) - 0.000) >= 0.0005} {
        fail "$direction port '$port_name' does not have max=1/min=0 ns delay"
    }
    set max_group [get_property GROUP $max_path]
    set min_group [get_property GROUP $min_path]
    set max_start_clock [get_property STARTPOINT_CLOCK $max_path]
    set min_start_clock [get_property STARTPOINT_CLOCK $min_path]
    set max_end_clock [get_property ENDPOINT_CLOCK $max_path]
    set min_end_clock [get_property ENDPOINT_CLOCK $min_path]
    if {$max_group ne $clock_port || $min_group ne $clock_port ||
        $max_start_clock ne $clock_port || $min_start_clock ne $clock_port ||
        $max_end_clock ne $clock_port || $min_end_clock ne $clock_port} {
        fail "$direction port '$port_name' is not timed by clock '$clock_port'"
    }
    return [list [format %.3f $max_delay] [format %.3f $min_delay] $clock_port]
}

proc ::partpin_ooc::collect_live_ports {clock_port} {
    set all_ports [get_ports -quiet]
    set records {}
    set used_inputs {}
    set used_outputs {}
    set unused_inputs {}
    set unused_outputs {}
    set constant_outputs {}
    set untimed_inputs {}
    set untimed_outputs {}
    set input_count 0
    set output_count 0
    set inout_count 0

    foreach port_object $all_ports {
        set port_name [get_property NAME $port_object]
        set direction [string toupper [get_property DIRECTION $port_object]]
        set nets [get_nets -quiet -of_objects $port_object]
        set net_count [llength $nets]
        set logic_value ""
        catch {set logic_value [string tolower [get_property LOGIC_VALUE $port_object]]}

        if {$direction eq "IN"} {
            incr input_count
        } elseif {$direction eq "OUT"} {
            incr output_count
        } else {
            incr inout_count
            lappend records [list $port_name $direction $net_count 0 0 0 \
                unsupported - - -]
            continue
        }

        if {$port_name eq $clock_port} {
            if {$direction ne "IN" || $net_count == 0} {
                fail "Clock port '$clock_port' is not a connected input"
            }
            set loads [get_pins -quiet -leaf -of_objects $nets \
                -filter {DIRECTION == IN}]
            if {[llength $loads] == 0} {
                fail "Clock port '$clock_port' has no internal load"
            }
            lappend records [list $port_name $direction $net_count 0 0 \
                [llength $loads] clock_exempt - - $clock_port]
            continue
        }

        if {$direction eq "OUT" && $logic_value in {zero one}} {
            set max_paths [get_timing_paths -quiet -delay_type max \
                -to $port_object -max_paths 1]
            set min_paths [get_timing_paths -quiet -delay_type min \
                -to $port_object -max_paths 1]
            if {[llength $max_paths] != 0 || [llength $min_paths] != 0} {
                fail "Constant output '$port_name' unexpectedly has a timing path"
            }
            if {$net_count != 1} {
                fail "Constant output '$port_name' must have exactly one constant net"
            }
            set expected_net [expr {$logic_value eq "zero" ? "<const0>" : "<const1>"}]
            if {[get_property NAME [lindex $nets 0]] ne $expected_net} {
                fail "Constant output '$port_name' is not driven by $expected_net"
            }
            lappend constant_outputs $port_name
            lappend records [list $port_name $direction $net_count 0 0 0 \
                constant_$logic_value hash_bound hash_bound $clock_port]
            continue
        }

        if {$net_count == 0} {
            if {$direction eq "IN"} {
                set max_paths [get_timing_paths -quiet -delay_type max \
                    -from $port_object -max_paths 1]
                set min_paths [get_timing_paths -quiet -delay_type min \
                    -from $port_object -max_paths 1]
                lappend unused_inputs $port_name
            } else {
                set max_paths [get_timing_paths -quiet -delay_type max \
                    -to $port_object -max_paths 1]
                set min_paths [get_timing_paths -quiet -delay_type min \
                    -to $port_object -max_paths 1]
                lappend unused_outputs $port_name
            }
            if {[llength $max_paths] != 0 || [llength $min_paths] != 0} {
                fail "Port '$port_name' has timing paths but no live net"
            }
            lappend records [list $port_name $direction 0 0 0 0 optimized_unused \
                hash_bound hash_bound $clock_port]
            continue
        }

        if {$direction eq "IN"} {
            set max_paths [get_timing_paths -quiet -delay_type max \
                -from $port_object -max_paths 1]
            set min_paths [get_timing_paths -quiet -delay_type min \
                -from $port_object -max_paths 1]
            set loads [get_pins -quiet -leaf -of_objects $nets \
                -filter {DIRECTION == IN}]
            if {[llength $max_paths] != 1 || [llength $min_paths] != 1 ||
                [llength $loads] == 0} {
                lappend untimed_inputs $port_name
                lappend records [list $port_name $direction $net_count \
                    [llength $max_paths] [llength $min_paths] [llength $loads] \
                    untimed_connected - - -]
                continue
            }
            if {[path_endpoint_name $max_paths STARTPOINT_PIN] ne $port_name ||
                [path_endpoint_name $min_paths STARTPOINT_PIN] ne $port_name} {
                fail "Input '$port_name' timing path does not start at that port"
            }
            set delay_contract [verify_io_path_contract $port_name $direction \
                $max_paths $min_paths $clock_port]
            lappend used_inputs $port_name
            lappend records [list $port_name $direction $net_count 1 1 \
                [llength $loads] timed_used {*}$delay_contract]
        } else {
            set max_paths [get_timing_paths -quiet -delay_type max \
                -to $port_object -max_paths 1]
            set min_paths [get_timing_paths -quiet -delay_type min \
                -to $port_object -max_paths 1]
            set drivers [get_pins -quiet -leaf -of_objects $nets \
                -filter {DIRECTION == OUT}]
            if {[llength $max_paths] != 1 || [llength $min_paths] != 1 ||
                [llength $drivers] == 0} {
                lappend untimed_outputs $port_name
                lappend records [list $port_name $direction $net_count \
                    [llength $max_paths] [llength $min_paths] [llength $drivers] \
                    untimed_connected - - -]
                continue
            }
            if {[path_endpoint_name $max_paths ENDPOINT_PIN] ne $port_name ||
                [path_endpoint_name $min_paths ENDPOINT_PIN] ne $port_name} {
                fail "Output '$port_name' timing path does not end at that port"
            }
            set delay_contract [verify_io_path_contract $port_name $direction \
                $max_paths $min_paths $clock_port]
            lappend used_outputs $port_name
            lappend records [list $port_name $direction $net_count 1 1 \
                [llength $drivers] timed_used {*}$delay_contract]
        }
    }

    return [dict create \
        port_count [llength $all_ports] \
        input_count $input_count \
        output_count $output_count \
        inout_count $inout_count \
        used_inputs [lsort -dictionary $used_inputs] \
        used_outputs [lsort -dictionary $used_outputs] \
        unused_inputs [lsort -dictionary $unused_inputs] \
        unused_outputs [lsort -dictionary $unused_outputs] \
        constant_outputs [lsort -dictionary $constant_outputs] \
        untimed_inputs [lsort -dictionary $untimed_inputs] \
        untimed_outputs [lsort -dictionary $untimed_outputs] \
        records [lsort -dictionary -index 0 $records] \
        implicit_exempt_count 1]
}

proc ::partpin_ooc::current_part_name {} {
    set part_name ""
    catch {set part_name [get_property PART [current_design]]}
    if {$part_name eq ""} {
        catch {set part_name [get_property PART [current_project]]}
    }
    if {$part_name eq ""} {
        fail "Could not determine the live design part"
    }
    return $part_name
}

proc ::partpin_ooc::verify_identity {map_info expected_parent_sha expected_top \
                                     expected_part expected_vivado_version \
                                     expected_period expected_directive} {
    set metadata [dict get $map_info metadata]
    set parent_sha [normalize_sha256 $expected_parent_sha expected_parent_sha256]
    if {[dict get $metadata PARENT_PLACED_SHA256] ne $parent_sha} {
        fail "PartPin map parent SHA-256 does not match the staged placed DCP"
    }
    foreach {key expected} [list \
        TOP $expected_top \
        PART $expected_part \
        VIVADO_VERSION $expected_vivado_version \
        ROUTE_DIRECTIVE $expected_directive] {
        if {[dict get $metadata $key] ne $expected} {
            fail "PartPin metadata $key does not match expected value '$expected'"
        }
    }
    set design_top [get_property TOP [current_design]]
    if {$design_top ne $expected_top} {
        fail "Opened checkpoint top '$design_top' is not '$expected_top'"
    }
    if {[current_part_name] ne $expected_part} {
        fail "Opened checkpoint part does not match '$expected_part'"
    }
    if {[version -short] ne $expected_vivado_version} {
        fail "Vivado version '[version -short]' is not '$expected_vivado_version'"
    }
    set clock_port [dict get $metadata CLOCK_PORT]
    if {$clock_port ne "aclk"} {
        fail "Production CLOCK_PORT must be literal 'aclk'"
    }
    set all_clocks [get_clocks -quiet]
    set clock_object [get_clocks -quiet [list $clock_port]]
    if {[llength $all_clocks] != 1 || [llength $clock_object] != 1 ||
        [get_property NAME [lindex $all_clocks 0]] ne $clock_port} {
        fail "Expected '$clock_port' to be the only live clock"
    }
    set live_period [get_property PERIOD $clock_object]
    set map_period [dict get $metadata CLOCK_PERIOD_NS]
    if {abs(double($live_period) - double($expected_period)) >= 0.0005 ||
        abs(double($map_period) - double($expected_period)) >= 0.0005} {
        fail "Clock period does not match expected $expected_period ns"
    }
}

proc ::partpin_ooc::write_port_audit {audit_file live_info map_info} {
    file mkdir [file dirname $audit_file]
    set map_by_port [dict create]
    foreach entry [dict get $map_info entries] {
        dict set map_by_port [lindex $entry 0] [lindex $entry 2]
    }
    set channel [open $audit_file w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "port\tdirection\tnet_count\tmax_path_count\tmin_path_count\tload_or_driver_count\tclassification\tmax_delay_ns\tmin_delay_ns\tpath_group\tmapped_tile"
    foreach record [dict get $live_info records] {
        set port_name [lindex $record 0]
        set tile "-"
        if {[dict exists $map_by_port $port_name]} {
            set tile [dict get $map_by_port $port_name]
        }
        puts $channel "[join $record \t]\t$tile"
    }
    close $channel
}

proc ::partpin_ooc::write_effective_xdc {xdc_file map_info} {
    file mkdir [file dirname $xdc_file]
    set channel [open $xdc_file w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "# Effective production PartPin replay constraints."
    foreach entry [lsort -dictionary -index 0 [dict get $map_info entries]] {
        puts $channel [format {set_property HD.PARTPIN_LOCS {%s} [get_ports {%s}]} \
            [lindex $entry 2] [lindex $entry 0]]
    }
    close $channel
}

proc ::partpin_ooc::apply_map {map_info expected_parent_sha expected_top \
                               expected_part expected_vivado_version \
                               expected_period expected_directive \
                               expected_unused_inputs audit_file xdc_file} {
    verify_identity $map_info $expected_parent_sha $expected_top $expected_part \
        $expected_vivado_version $expected_period $expected_directive
    set metadata [dict get $map_info metadata]
    set clock_port [dict get $metadata CLOCK_PORT]
    set live_info [collect_live_ports $clock_port]

    foreach {key live_key} {
        PORT_COUNT port_count
        INPUT_PORT_COUNT input_count
        OUTPUT_PORT_COUNT output_count
    } {
        if {[dict get $metadata $key] != [dict get $live_info $live_key]} {
            fail "$key does not match the live checkpoint"
        }
    }
    if {[dict get $live_info inout_count] != 0} {
        fail "Production checkpoint contains unsupported INOUT ports"
    }
    if {[dict get $live_info port_count] != 155 ||
        [dict get $live_info input_count] != 79 ||
        [dict get $live_info output_count] != 76} {
        fail "Production top-level schema is not 155 ports (79 IN, 76 OUT)"
    }
    set expected_unused_inputs [lsort -dictionary $expected_unused_inputs]
    if {[dict get $live_info unused_inputs] ne $expected_unused_inputs} {
        fail "Live unused inputs are not the approved PROT allowlist"
    }
    if {[dict get $metadata UNUSED_INPUT_PORTS] ne $expected_unused_inputs} {
        fail "Map UNUSED_INPUT_PORTS is not the approved PROT allowlist"
    }
    if {[dict get $metadata UNUSED_OUTPUT_PORTS] ne
        [dict get $live_info unused_outputs]} {
        fail "Map UNUSED_OUTPUT_PORTS does not match the live checkpoint"
    }
    if {[dict get $metadata CONSTANT_OUTPUT_PORTS] ne
        [dict get $live_info constant_outputs]} {
        fail "Map CONSTANT_OUTPUT_PORTS does not match the live checkpoint"
    }
    if {[llength [dict get $live_info untimed_inputs]] != 0 ||
        [llength [dict get $live_info untimed_outputs]] != 0} {
        fail "Connected nonconstant ports without both max/min timing paths were found"
    }

    set required_names [lsort -dictionary [concat \
        [dict get $live_info used_inputs] [dict get $live_info used_outputs]]]
    set mapped_names {}
    foreach entry [dict get $map_info entries] {
        set port_name [lindex $entry 0]
        set direction [lindex $entry 1]
        set tile_name [lindex $entry 2]
        set port_object [one_port $port_name]
        if {[string toupper [get_property DIRECTION $port_object]] ne $direction} {
            fail "Map direction for '$port_name' does not match the checkpoint"
        }
        if {[lsearch -exact $required_names $port_name] < 0} {
            fail "Map contains non-timed or exempt port '$port_name'"
        }
        set tile_object [get_tiles -quiet [list $tile_name]]
        if {[llength $tile_object] != 1 ||
            [get_property TYPE $tile_object] ni {INT_L INT_R}} {
            fail "Map tile '$tile_name' is not one live INT_L/INT_R tile"
        }
        set existing [get_property HD.PARTPIN_LOCS $port_object]
        if {$existing ne ""} {
            fail "Immutable placed checkpoint already has PartPin state on '$port_name'"
        }
        lappend mapped_names $port_name
    }
    set mapped_names [lsort -dictionary $mapped_names]
    if {$mapped_names ne $required_names} {
        fail "PartPin map port set does not exactly cover live timed inputs/outputs"
    }

    foreach entry [lsort -dictionary -index 0 [dict get $map_info entries]] {
        set port_name [lindex $entry 0]
        set tile_name [lindex $entry 2]
        set port_object [one_port $port_name]
        set_property HD.PARTPIN_LOCS $tile_name $port_object
        set applied [get_property HD.PARTPIN_LOCS $port_object]
        if {[llength $applied] != 1 || [lindex $applied 0] ne $tile_name} {
            fail "PartPin property did not apply exactly to '$port_name'"
        }
    }

    write_port_audit $audit_file $live_info $map_info
    write_effective_xdc $xdc_file $map_info
    return $live_info
}

proc ::partpin_ooc::verify_applied_map {map_info live_info} {
    set required_names [lsort -dictionary [concat \
        [dict get $live_info used_inputs] [dict get $live_info used_outputs]]]
    set mapped_names {}
    foreach entry [dict get $map_info entries] {
        set port_name [lindex $entry 0]
        set tile_name [lindex $entry 2]
        set port_object [one_port $port_name]
        set applied [get_property HD.PARTPIN_LOCS $port_object]
        if {[llength $applied] != 1 || [lindex $applied 0] ne $tile_name} {
            fail "Routed checkpoint PartPin mismatch on '$port_name'"
        }
        lappend mapped_names $port_name
    }
    if {[lsort -dictionary $mapped_names] ne $required_names} {
        fail "Routed checkpoint PartPin coverage changed"
    }
}

proc ::partpin_ooc::verify_routed_boundary_identity {map_info clock_port} {
    set clock_object [one_port $clock_port]
    set clock_nets [get_nets -quiet -of_objects $clock_object]
    if {[llength $clock_nets] != 1 ||
        [get_property ROUTE_STATUS [lindex $clock_nets 0]] ne "HIERPORT"} {
        fail "Clock '$clock_port' is not the unique implicit HIERPORT candidate"
    }
    set clock_net_name [get_property NAME [lindex $clock_nets 0]]

    foreach entry [dict get $map_info entries] {
        set port_name [lindex $entry 0]
        set nets [get_nets -quiet -of_objects [one_port $port_name]]
        if {[llength $nets] == 0} {
            fail "Mapped boundary port '$port_name' has no routed net"
        }
        foreach net $nets {
            if {[get_property ROUTE_STATUS $net] eq "HIERPORT"} {
                fail "Mapped boundary port '$port_name' remains implicitly routed"
            }
        }
    }

    set implicit_net_names {}
    foreach port_object [get_ports -quiet] {
        foreach net [get_nets -quiet -of_objects $port_object] {
            if {[get_property ROUTE_STATUS $net] eq "HIERPORT"} {
                set net_name [get_property NAME $net]
                if {[lsearch -exact $implicit_net_names $net_name] < 0} {
                    lappend implicit_net_names $net_name
                }
            }
        }
    }
    if {[llength $implicit_net_names] != 1 ||
        [lindex $implicit_net_names 0] ne $clock_net_name} {
        fail "Implicit HIERPORT identity is not exactly the aclk boundary net"
    }
    return 1
}

proc ::partpin_ooc::audit_ooc_port_properties {report_file io_xdc_file} {
    if {[file exists $io_xdc_file]} {
        fail "Fresh OOC IO-constraint audit file already exists: $io_xdc_file"
    }
    write_xdc -type io $io_xdc_file
    set io_channel [open $io_xdc_file r]
    fconfigure $io_channel -encoding utf-8 -translation auto
    set io_text [read $io_channel]
    close $io_channel
    foreach raw_line [split $io_text "\n"] {
        set line [string trim $raw_line]
        if {$line eq "" || [string match "#*" $line]} {
            continue
        }
        if {[regexp {^current_instance(?:[ \t]|$)} $line]} {
            continue
        }
        fail "Explicit board/IO constraint found in OOC replay: $line"
    }

    file mkdir [file dirname $report_file]
    set channel [open $report_file w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "port\tpackage_pin\tloc\teffective_iostandard\tiostandard_source"
    set package_pin_count 0
    set loc_count 0
    set effective_iostandard_count 0
    foreach port_object [get_ports -quiet] {
        set port_name [get_property NAME $port_object]
        set package_pin [string trim [get_property PACKAGE_PIN $port_object]]
        set loc [string trim [get_property LOC $port_object]]
        set iostandard [string trim [get_property IOSTANDARD $port_object]]
        if {$package_pin ne ""} {
            incr package_pin_count
        }
        if {$loc ne ""} {
            incr loc_count
        }
        if {$iostandard ne ""} {
            incr effective_iostandard_count
        }
        puts $channel "$port_name\t[expr {$package_pin eq "" ? "-" : $package_pin}]\t[expr {$loc eq "" ? "-" : $loc}]\t[expr {$iostandard eq "" ? "-" : $iostandard}]\tsystem_default"
    }
    close $channel
    if {$package_pin_count != 0 || $loc_count != 0} {
        fail "OOC replay contains board PACKAGE_PIN/LOC assignments"
    }
    return [dict create \
        package_pin_ports $package_pin_count \
        loc_ports $loc_count \
        effective_iostandard_ports $effective_iostandard_count \
        explicit_io_constraint_commands 0]
}

proc ::partpin_ooc::parse_timing_summary {summary_text} {
    set result [dict create]
    foreach {label key_prefix} {Setup setup Hold hold PW pw} {
        set expression [format {%s[ \t]*:[ \t]*([0-9]+)[ \t]+Failing Endpoints,[ \t]+Worst Slack[ \t]+([-+0-9.eE]+)ns,[ \t]+Total Violation[ \t]+([-+0-9.eE]+)ns} $label]
        if {![regexp $expression $summary_text match failing worst total]} {
            fail "Could not parse $label timing summary"
        }
        dict set result ${key_prefix}_failing $failing
        dict set result ${key_prefix}_worst $worst
        dict set result ${key_prefix}_total $total
    }
    variable timing_check_names
    foreach check_name $timing_check_names {
        set expression [format {checking[ \t]+%s[ \t]*\(([0-9]+)\)} $check_name]
        if {![regexp $expression $summary_text match count]} {
            fail "Could not parse check_timing category '$check_name'"
        }
        dict set result check_$check_name $count
    }
    return $result
}

proc ::partpin_ooc::parse_route_status {route_text} {
    set result [dict create]
    foreach {key expression} [list \
        route_errors {nets with routing errors[^:\r\n]*:[ \t]*([0-9]+)} \
        routable_nets {# of routable nets[^:]*:[ \t]*([0-9]+)} \
        fully_routed_nets {# of fully routed nets[^:]*:[ \t]*([0-9]+)} \
        implicit_ports {# of implicitly routed ports[^:]*:[ \t]*([0-9]+)}] {
        if {![regexp -nocase $expression $route_text match value]} {
            fail "Could not parse route-status field '$key'"
        }
        dict set result $key $value
    }
    return $result
}

proc ::partpin_ooc::negative_path_exists {delay_type direction ports} {
    if {[llength $ports] == 0} {
        fail "Boundary timing collection for $direction is empty"
    }
    if {$direction eq "from"} {
        set paths [get_timing_paths -quiet -delay_type $delay_type \
            -from $ports -slack_lesser_than 0.0 -max_paths 1]
    } else {
        set paths [get_timing_paths -quiet -delay_type $delay_type \
            -to $ports -slack_lesser_than 0.0 -max_paths 1]
    }
    return [expr {[llength $paths] != 0}]
}

proc ::partpin_ooc::write_summary {summary_file summary} {
    file mkdir [file dirname $summary_file]
    set channel [open $summary_file w]
    fconfigure $channel -encoding utf-8 -translation lf
    puts $channel "field\tvalue"
    foreach key [lsort -dictionary [dict keys $summary]] {
        puts $channel "$key\t[dict get $summary $key]"
    }
    close $channel
}

proc ::partpin_ooc::run_strict_signoff {map_info live_info report_dir \
                                        summary_file} {
    file mkdir $report_dir
    verify_applied_map $map_info $live_info

    # Re-audit the routed design rather than assuming that placed-checkpoint
    # classifications still hold.  No-path PROT/constant ports are constrained
    # by the externally verified parent DCP hash and the zero no/partial-delay
    # check_timing counts below; every dynamic bit is checked directly through
    # its INPUT_DELAY/OUTPUT_DELAY timing-path properties.
    set clock_port [dict get [dict get $map_info metadata] CLOCK_PORT]
    set routed_live_info [collect_live_ports $clock_port]
    foreach key {port_count input_count output_count inout_count used_inputs \
                 used_outputs unused_inputs unused_outputs constant_outputs \
                 untimed_inputs untimed_outputs implicit_exempt_count} {
        if {[dict get $routed_live_info $key] ne [dict get $live_info $key]} {
            fail "Routed live-port classification changed for '$key'"
        }
    }
    set live_info $routed_live_info
    write_port_audit [file join $report_dir routed_port_audit.tsv] \
        $live_info $map_info
    verify_routed_boundary_identity $map_info $clock_port
    set ooc_properties [audit_ooc_port_properties \
        [file join $report_dir ooc_boundary_properties.tsv] \
        [file join $report_dir ooc_io_constraints.xdc]]

    report_methodology -file [file join $report_dir methodology_routed.rpt]
    report_utilization -hierarchical \
        -file [file join $report_dir utilization_routed.rpt]
    report_timing_summary -delay_type min_max -max_paths 50 \
        -report_unconstrained \
        -file [file join $report_dir timing_routed.rpt]
    report_route_status -file [file join $report_dir route_status.rpt]
    report_drc -file [file join $report_dir drc_routed.rpt]
    set exception_text [report_exceptions -return_string]
    set exception_file [file join $report_dir timing_exceptions.rpt]
    set exception_channel [open $exception_file w]
    fconfigure $exception_channel -encoding utf-8 -translation lf
    puts -nonewline $exception_channel $exception_text
    close $exception_channel
    if {![regexp -nocase {No valid timing exceptions found\.} $exception_text]} {
        fail "OOC replay contains timing exceptions"
    }

    set input_ports [get_ports -quiet [dict get $live_info used_inputs]]
    set output_ports [get_ports -quiet [dict get $live_info used_outputs]]
    report_timing -delay_type max -from $input_ports -max_paths 100 \
        -nworst 10 -file [file join $report_dir boundary_input_setup.rpt]
    report_timing -delay_type min -from $input_ports -max_paths 100 \
        -nworst 10 -file [file join $report_dir boundary_input_hold.rpt]
    report_timing -delay_type max -to $output_ports -max_paths 100 \
        -nworst 10 -file [file join $report_dir boundary_output_setup.rpt]
    report_timing -delay_type min -to $output_ports -max_paths 100 \
        -nworst 10 -file [file join $report_dir boundary_output_hold.rpt]

    set reset_port [one_port aresetn]
    set reset_setup [get_timing_paths -quiet -delay_type max \
        -from $reset_port -max_paths 1]
    set reset_hold [get_timing_paths -quiet -delay_type min \
        -from $reset_port -max_paths 1]
    if {[llength $reset_setup] != 1 || [llength $reset_hold] != 1 ||
        [path_endpoint_name $reset_setup STARTPOINT_PIN] ne "aresetn" ||
        [path_endpoint_name $reset_hold STARTPOINT_PIN] ne "aresetn"} {
        fail "aresetn does not have dedicated max/min timing paths"
    }
    verify_io_path_contract aresetn IN $reset_setup $reset_hold $clock_port
    report_timing -delay_type max -from $reset_port -max_paths 100 \
        -nworst 10 -file [file join $report_dir reset_setup.rpt]
    report_timing -delay_type min -from $reset_port -max_paths 100 \
        -nworst 10 -file [file join $report_dir reset_hold.rpt]

    set internal_registers [all_registers -clock $clock_port]
    if {[llength $internal_registers] == 0} {
        fail "No internal registers were found on '$clock_port'"
    }
    set internal_setup [get_timing_paths -quiet -delay_type max \
        -from $internal_registers -to $internal_registers -max_paths 1]
    set internal_hold [get_timing_paths -quiet -delay_type min \
        -from $internal_registers -to $internal_registers -max_paths 1]
    if {[llength $internal_setup] != 1 || [llength $internal_hold] != 1} {
        fail "Internal register-to-register max/min timing paths are missing"
    }
    report_timing -delay_type max -from $internal_registers \
        -to $internal_registers -max_paths 100 -nworst 10 \
        -file [file join $report_dir internal_setup.rpt]
    report_timing -delay_type min -from $internal_registers \
        -to $internal_registers -max_paths 100 -nworst 10 \
        -file [file join $report_dir internal_hold.rpt]

    set timing_text [report_timing_summary -delay_type min_max -max_paths 1 \
        -report_unconstrained -return_string]
    set timing [parse_timing_summary $timing_text]
    set route_text [report_route_status -return_string]
    set route [parse_route_status $route_text]

    set worst_setup [get_timing_paths -quiet -delay_type max -max_paths 1]
    set worst_hold [get_timing_paths -quiet -delay_type min -max_paths 1]
    if {[llength $worst_setup] != 1 || [llength $worst_hold] != 1} {
        fail "Global setup/hold timing paths are missing"
    }
    set setup_wns [get_property SLACK $worst_setup]
    set hold_whs [get_property SLACK $worst_hold]

    set drc_errors 0
    foreach violation [get_drc_violations -quiet] {
        if {[string equal -nocase [get_property SEVERITY $violation] Error]} {
            incr drc_errors
        }
    }

    if {[llength [info commands get_methodology_violations]] != 1} {
        fail "Vivado does not expose methodology violations for machine gating"
    }
    set methodology_errors 0
    set methodology_critical_warnings 0
    foreach violation [get_methodology_violations -quiet] {
        set severity [get_property SEVERITY $violation]
        if {[string equal -nocase $severity Error]} {
            incr methodology_errors
        } elseif {[string equal -nocase $severity "Critical Warning"]} {
            incr methodology_critical_warnings
        }
    }
    set blackboxes [get_cells -quiet -hierarchical -filter {IS_BLACKBOX == 1}]
    set blackbox_count [llength $blackboxes]

    set input_setup_fail [negative_path_exists max from $input_ports]
    set input_hold_fail [negative_path_exists min from $input_ports]
    set output_setup_fail [negative_path_exists max to $output_ports]
    set output_hold_fail [negative_path_exists min to $output_ports]
    set reset_setup_wns [get_property SLACK $reset_setup]
    set reset_hold_whs [get_property SLACK $reset_hold]
    set internal_setup_wns [get_property SLACK $internal_setup]
    set internal_hold_whs [get_property SLACK $internal_hold]

    set checks_ok 1
    variable timing_check_names
    foreach check_name $timing_check_names {
        if {[dict get $timing check_$check_name] != 0} {
            set checks_ok 0
        }
    }
    set setup_ok [expr {double($setup_wns) >= 0.0 &&
        [dict get $timing setup_failing] == 0 &&
        abs(double([dict get $timing setup_total])) < 0.0005}]
    set hold_ok [expr {double($hold_whs) >= 0.0 &&
        [dict get $timing hold_failing] == 0 &&
        abs(double([dict get $timing hold_total])) < 0.0005}]
    set pulse_ok [expr {double([dict get $timing pw_worst]) >= 0.0 &&
        [dict get $timing pw_failing] == 0 &&
        abs(double([dict get $timing pw_total])) < 0.0005}]
    set route_ok [expr {[dict get $route route_errors] == 0 &&
        [dict get $route routable_nets] == [dict get $route fully_routed_nets] &&
        [dict get $route implicit_ports] ==
            [dict get $live_info implicit_exempt_count]}]
    set boundary_ok [expr {!$input_setup_fail && !$input_hold_fail &&
        !$output_setup_fail && !$output_hold_fail}]
    set reset_ok [expr {double($reset_setup_wns) >= 0.0 &&
                              double($reset_hold_whs) >= 0.0}]
    set internal_ok [expr {double($internal_setup_wns) >= 0.0 &&
                                 double($internal_hold_whs) >= 0.0}]
    set methodology_ok [expr {$methodology_errors == 0 &&
        $methodology_critical_warnings == 0 && $blackbox_count == 0}]
    set status [expr {$setup_ok && $hold_ok && $pulse_ok && $route_ok &&
        $checks_ok && $boundary_ok && $reset_ok && $internal_ok &&
        $methodology_ok && $drc_errors == 0 ? "PASS" : "FAIL"}]

    set summary [dict create \
        SCOPE OOC_PARTPIN \
        BOARD_ROUTE 0 \
        status $status \
        setup_wns_ns [format %.3f $setup_wns] \
        setup_tns_ns [dict get $timing setup_total] \
        setup_failing [dict get $timing setup_failing] \
        hold_whs_ns [format %.3f $hold_whs] \
        hold_ths_ns [dict get $timing hold_total] \
        hold_failing [dict get $timing hold_failing] \
        pw_worst_ns [dict get $timing pw_worst] \
        pw_total_ns [dict get $timing pw_total] \
        pw_failing [dict get $timing pw_failing] \
        route_errors [dict get $route route_errors] \
        routable_nets [dict get $route routable_nets] \
        fully_routed_nets [dict get $route fully_routed_nets] \
        implicit_ports [dict get $route implicit_ports] \
        expected_implicit_ports [dict get $live_info implicit_exempt_count] \
        drc_errors $drc_errors \
        input_setup_fail $input_setup_fail \
        input_hold_fail $input_hold_fail \
        output_setup_fail $output_setup_fail \
        output_hold_fail $output_hold_fail \
        reset_setup_wns_ns [format %.3f $reset_setup_wns] \
        reset_hold_whs_ns [format %.3f $reset_hold_whs] \
        internal_setup_wns_ns [format %.3f $internal_setup_wns] \
        internal_hold_whs_ns [format %.3f $internal_hold_whs] \
        methodology_errors $methodology_errors \
        methodology_critical_warnings $methodology_critical_warnings \
        blackboxes $blackbox_count \
        package_pin_ports [dict get $ooc_properties package_pin_ports] \
        loc_ports [dict get $ooc_properties loc_ports] \
        effective_iostandard_ports \
            [dict get $ooc_properties effective_iostandard_ports] \
        explicit_io_constraint_commands \
            [dict get $ooc_properties explicit_io_constraint_commands] \
        timing_exceptions 0 \
        used_inputs [llength [dict get $live_info used_inputs]] \
        used_outputs [llength [dict get $live_info used_outputs]] \
        constant_outputs [llength [dict get $live_info constant_outputs]] \
        hash_bound_no_path_ports [expr {
            [llength [dict get $live_info unused_inputs]] +
            [llength [dict get $live_info unused_outputs]] +
            [llength [dict get $live_info constant_outputs]]}]]
    foreach check_name $timing_check_names {
        dict set summary check_$check_name [dict get $timing check_$check_name]
    }
    write_summary $summary_file $summary
    return $summary
}
