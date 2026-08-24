# Export report figures and physical source data from the retained 175 MHz
# board checkpoints. Vivado 2021.1 requires its IDE graphics engine for
# write_schematic, so this script starts and stops that engine automatically
# while remaining a non-interactive batch run.
#
# Usage:
#   vivado -mode batch -source export_vivado_report_figures.tcl
#       -tclargs OUTPUT_DIR

if {$argc != 1} {
    error "Usage: export_vivado_report_figures.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set dcp_dir [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8]
set synth_dcp [file join $dcp_dir \
    arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp]
set routed_dcp [file join $dcp_dir \
    arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp]

set expected_top arty_a7_100t_aes_gcm_uart_rsp_top
set expected_part xc7a100tcsg324-1
set expected_synth_sha256 \
    C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6
set expected_routed_sha256 \
    A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B

proc clean_tsv {value} {
    return [string map [list "\t" " " "\r" " " "\n" " "] $value]
}

proc classify_cell {name} {
    if {[string match "u_aes_gcm/u_core/u_aes_engine/*" $name]} {
        return AES_MAIN
    }
    if {[string match "u_aes_gcm/u_core/u_aes_first_engine/*" $name]} {
        return AES_FIRST
    }
    if {[string match "u_aes_gcm/u_core/u_aes_second_engine/*" $name]} {
        return AES_SECOND
    }
    if {[string match "u_aes_gcm/u_core/u_ghash/*" $name]} {
        return GHASH
    }
    if {[string match "u_aes_gcm/u_core/u_key_context/*" $name]} {
        return KEY_CONTEXT
    }
    if {[string match "u_aes_gcm/u_core/*fifo*/*" [string tolower $name]]} {
        return CORE_FIFO
    }
    if {[string match "u_aes_gcm/u_core/*" $name]} {
        return CORE_CONTROL
    }
    if {[string match "u_aes_gcm/*" $name]} {
        return AXI_WRAPPER
    }
    if {[string match "u_bridge/*" $name]} {
        return UART_BRIDGE
    }
    return BOARD_LOGIC
}

proc require_design_identity {top part} {
    set actual_top [get_property TOP [current_design]]
    set actual_part [get_property PART [current_design]]
    if {$actual_top ne $top} {
        error "Unexpected top '$actual_top'; expected '$top'"
    }
    if {$actual_part ne $part} {
        error "Unexpected part '$actual_part'; expected '$part'"
    }
}

if {[version -short] ne "2021.1"} {
    error "Vivado 2021.1 is required; detected [version -short]"
}
if {![regexp -line {^SW Build 3247384[ \t]} [version]]} {
    error "Vivado SW Build 3247384 is required"
}
foreach checkpoint [list $synth_dcp $routed_dcp] {
    if {![file isfile $checkpoint]} {
        error "Missing checkpoint: $checkpoint"
    }
}

set gui_started 0

open_checkpoint $synth_dcp
require_design_identity $expected_top $expected_part

set synth_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $synth_path] != 1} {
    error "Expected exactly one worst synthesis setup path"
}
set synth_slack [get_property SLACK $synth_path]
set synth_start [get_property STARTPOINT_PIN $synth_path]
set synth_end [get_property ENDPOINT_PIN $synth_path]

start_gui
set gui_started 1
show_schematic -name Vivado_Synthesis_Critical_Path $synth_path
after 2500
set synth_svg [file join $output_dir \
    vivado_synthesis_critical_path_schematic.svg]
write_schematic -force -format svg -orientation portrait -scope all \
    -name Vivado_Synthesis_Critical_Path $synth_svg
if {![file isfile $synth_svg] || [file size $synth_svg] == 0} {
    error "Vivado did not create the synthesis schematic SVG"
}
report_timing -delay_type max -max_paths 1 -nworst 1 \
    -file [file join $output_dir vivado_synthesis_critical_path_timing.rpt]
close_design

open_checkpoint $routed_dcp
require_design_identity $expected_top $expected_part

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $setup_path] != 1} {
    error "Expected exactly one worst setup path"
}
set setup_slack [get_property SLACK $setup_path]
set setup_start [get_property STARTPOINT_PIN $setup_path]
set setup_end [get_property ENDPOINT_PIN $setup_path]
set setup_logic_levels [get_property LOGIC_LEVELS $setup_path]
set setup_datapath_delay [get_property DATAPATH_DELAY $setup_path]
set setup_logic_delay [get_property DATAPATH_LOGIC_DELAY $setup_path]
set setup_net_delay [get_property DATAPATH_NET_DELAY $setup_path]
if {[expr {double($setup_slack)}] < 0.0} {
    error "Retained routed checkpoint no longer closes setup timing"
}

show_schematic -name Vivado_Implementation_Critical_Path $setup_path
after 2500
set implementation_svg [file join $output_dir \
    vivado_implementation_critical_path_schematic.svg]
write_schematic -force -format svg -orientation portrait -scope all \
    -name Vivado_Implementation_Critical_Path $implementation_svg
if {![file isfile $implementation_svg] || [file size $implementation_svg] == 0} {
    error "Vivado did not create the implementation schematic SVG"
}

set tiles_file [open [file join $output_dir vivado_device_tiles.tsv] w]
puts $tiles_file "tile\ttile_type\tgrid_x\tgrid_y"
foreach tile [get_tiles] {
    puts $tiles_file "[clean_tsv $tile]\t[clean_tsv [get_property TILE_TYPE $tile]]\t[get_property GRID_POINT_X $tile]\t[get_property GRID_POINT_Y $tile]"
}
close $tiles_file

set placement_file [open [file join $output_dir vivado_placement_cells.tsv] w]
puts $placement_file "cell\tref_name\tloc\tbel\ttile\tgrid_x\tgrid_y\tgroup"
set placed_cell_count 0
foreach cell [get_cells -hierarchical -filter {IS_PRIMITIVE}] {
    set site [get_sites -quiet -of_objects $cell]
    if {![llength $site]} {
        continue
    }
    set tile [get_tiles -quiet -of_objects $site]
    if {![llength $tile]} {
        continue
    }
    set name [get_property NAME $cell]
    puts $placement_file "[clean_tsv $name]\t[clean_tsv [get_property REF_NAME $cell]]\t[clean_tsv [get_property LOC $cell]]\t[clean_tsv [get_property BEL $cell]]\t[clean_tsv $tile]\t[get_property GRID_POINT_X $tile]\t[get_property GRID_POINT_Y $tile]\t[classify_cell $name]"
    incr placed_cell_count
}
close $placement_file

set route_cells_file [open [file join $output_dir \
    vivado_critical_path_cells.tsv] w]
puts $route_cells_file "stage\tcell\tref_name\tloc\tbel\ttile\tgrid_x\tgrid_y"
set route_cells [get_cells -of_objects $setup_path]
set cell_stage 0
foreach cell $route_cells {
    set site [get_sites -quiet -of_objects $cell]
    set tile [get_tiles -quiet -of_objects $site]
    if {[llength $site] && [llength $tile]} {
        puts $route_cells_file "$cell_stage\t[clean_tsv $cell]\t[clean_tsv [get_property REF_NAME $cell]]\t[clean_tsv [get_property LOC $cell]]\t[clean_tsv [get_property BEL $cell]]\t[clean_tsv $tile]\t[get_property GRID_POINT_X $tile]\t[get_property GRID_POINT_Y $tile]"
    }
    incr cell_stage
}
close $route_cells_file

set route_file [open [file join $output_dir \
    vivado_critical_path_routed_pips.tsv] w]
puts $route_file "stage\tpip_index\tnet\tdriver_pin\tsink_pin\tpip\ttile\tgrid_x\tgrid_y"
set path_pins [get_pins -of_objects $setup_path]
set route_stage 0
for {set index 0} {$index < [llength $path_pins]} {incr index 2} {
    set driver_pin [lindex $path_pins $index]
    set sink_pin [lindex $path_pins [expr {$index + 1}]]
    if {$sink_pin eq ""} {
        break
    }
    set net [get_nets -quiet -of_objects [list $driver_pin $sink_pin]]
    set driver_site_pin [get_site_pins -quiet -of_objects $driver_pin]
    set sink_site_pin [get_site_pins -quiet -of_objects $sink_pin]
    if {![llength $net] || ![llength $driver_site_pin] ||
        ![llength $sink_site_pin]} {
        error "Cannot resolve routed branch for '$driver_pin' to '$sink_pin'"
    }
    set branch_pips [get_pips -of_objects $net \
        -from $driver_site_pin -to $sink_site_pin]
    if {![llength $branch_pips]} {
        error "No routed PIPs found for '$driver_pin' to '$sink_pin'"
    }
    set pip_index 0
    foreach pip $branch_pips {
        set tile [get_tiles -quiet -of_objects $pip]
        if {[llength $tile]} {
            puts $route_file "$route_stage\t$pip_index\t[clean_tsv $net]\t[clean_tsv $driver_pin]\t[clean_tsv $sink_pin]\t[clean_tsv $pip]\t[clean_tsv $tile]\t[get_property GRID_POINT_X $tile]\t[get_property GRID_POINT_Y $tile]"
        }
        incr pip_index
    }
    incr route_stage
}
close $route_file

report_timing -delay_type max -max_paths 1 -nworst 1 \
    -file [file join $output_dir vivado_critical_path_timing.rpt]

set metrics_file [open [file join $output_dir vivado_figure_metrics.tsv] w]
puts $metrics_file "metric\tvalue"
foreach pair [list \
    [list top $expected_top] \
    [list part $expected_part] \
    [list clock_mhz 175] \
    [list synthesis_setup_slack_ns $synth_slack] \
    [list synthesis_setup_startpoint $synth_start] \
    [list synthesis_setup_endpoint $synth_end] \
    [list setup_slack_ns $setup_slack] \
    [list setup_startpoint $setup_start] \
    [list setup_endpoint $setup_end] \
    [list logic_levels $setup_logic_levels] \
    [list datapath_delay_ns $setup_datapath_delay] \
    [list logic_delay_ns $setup_logic_delay] \
    [list net_delay_ns $setup_net_delay] \
    [list placed_primitive_cells $placed_cell_count] \
    [list critical_path_cells [llength $route_cells]] \
    [list critical_path_routed_nets $route_stage]] {
    puts $metrics_file "[lindex $pair 0]\t[clean_tsv [lindex $pair 1]]"
}
close $metrics_file

set manifest_file [open [file join $output_dir vivado_figure_manifest.txt] w]
puts $manifest_file "VIVADO_VERSION=[version -short]"
puts $manifest_file "VIVADO_SW_BUILD=3247384"
puts $manifest_file "TOP=$expected_top"
puts $manifest_file "PART=$expected_part"
puts $manifest_file "SYNTH_DCP=$synth_dcp"
puts $manifest_file "SYNTH_DCP_SHA256=$expected_synth_sha256"
puts $manifest_file "ROUTED_DCP=$routed_dcp"
puts $manifest_file "ROUTED_DCP_SHA256=$expected_routed_sha256"
puts $manifest_file "SYNTHESIS_SVG=$synth_svg"
puts $manifest_file "SYNTHESIS_SETUP_SLACK_NS=$synth_slack"
puts $manifest_file "SYNTHESIS_SETUP_STARTPOINT=$synth_start"
puts $manifest_file "SYNTHESIS_SETUP_ENDPOINT=$synth_end"
puts $manifest_file "IMPLEMENTATION_SVG=$implementation_svg"
puts $manifest_file "SETUP_SLACK_NS=$setup_slack"
puts $manifest_file "PLACED_PRIMITIVE_CELLS=$placed_cell_count"
puts $manifest_file "CRITICAL_PATH_CELLS=[llength $route_cells]"
puts $manifest_file "CRITICAL_PATH_ROUTED_NETS=$route_stage"
puts $manifest_file "SCHEMATIC_EXPORT=Vivado native write_schematic SVG"
puts $manifest_file "PHYSICAL_EXPORT=Vivado GRID_POINT and ordered routed-PIP data"
close $manifest_file

if {$gui_started} {
    stop_gui
}
close_design
puts "VIVADO_REPORT_FIGURES_PASS output_dir=$output_dir"
exit
