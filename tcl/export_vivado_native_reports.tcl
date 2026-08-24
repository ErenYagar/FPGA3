# Export Vivado 2021.1 native schematics and interactive/text reports from the
# retained 175 MHz Arty A7-100T checkpoints.

if {$argc != 1} {
    error "Usage: export_vivado_native_reports.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set checkpoint_dir [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8]
set synth_dcp [file join $checkpoint_dir \
    arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp]
set routed_dcp [file join $checkpoint_dir \
    arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp]
set expected_top arty_a7_100t_aes_gcm_uart_rsp_top
set expected_part xc7a100tcsg324-1
set expected_synth_sha256 \
    C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6
set expected_routed_sha256 \
    A91758ED87EB56648EEF0CAB67B2C50D198D00A2D5088E624B507687D99C016B

proc require_file {path} {
    if {![file isfile $path]} {
        error "Missing required file: $path"
    }
}

proc require_design_identity {expected_top expected_part} {
    set actual_top [get_property TOP [current_design]]
    set actual_part [get_property PART [current_design]]
    if {$actual_top ne $expected_top} {
        error "Unexpected top '$actual_top'; expected '$expected_top'"
    }
    if {$actual_part ne $expected_part} {
        error "Unexpected part '$actual_part'; expected '$expected_part'"
    }
}

if {[version -short] ne "2021.1" ||
    ![regexp -line {^SW Build 3247384[ \t]} [version]]} {
    error "Vivado 2021.1 SW Build 3247384 is required"
}
require_file $synth_dcp
require_file $routed_dcp

set gui_started 0
open_checkpoint $synth_dcp
require_design_identity $expected_top $expected_part
set synth_setup [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $synth_setup] != 1} {
    error "Expected exactly one post-synthesis worst setup path"
}

start_gui
set gui_started 1
show_schematic -name Native_Synthesis_Worst_Setup $synth_setup
after 2000
write_schematic -force -format svg -orientation portrait -scope all \
    -name Native_Synthesis_Worst_Setup \
    [file join $output_dir 01_synthesis_worst_setup_schematic.svg]
write_schematic -force -format pdf -orientation portrait -scope all \
    -name Native_Synthesis_Worst_Setup \
    [file join $output_dir 01_synthesis_worst_setup_schematic.pdf]
report_timing_summary -delay_type min_max -max_paths 10 -nworst 1 \
    -file [file join $output_dir 01_synthesis_timing_summary.rpt] \
    -rpx [file join $output_dir 01_synthesis_timing_summary.rpx]
report_utilization -hierarchical -hierarchical_depth 3 \
    -file [file join $output_dir 01_synthesis_utilization_hierarchical.rpt]
set synth_slack [get_property SLACK $synth_setup]
close_design

open_checkpoint $routed_dcp
require_design_identity $expected_top $expected_part
set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
if {[llength $setup_path] != 1 || [llength $hold_path] != 1} {
    error "Expected exactly one routed worst setup and hold path"
}

show_schematic -name Native_Routed_Worst_Setup $setup_path
after 2000
write_schematic -force -format svg -orientation portrait -scope all \
    -name Native_Routed_Worst_Setup \
    [file join $output_dir 02_routed_worst_setup_schematic.svg]
write_schematic -force -format pdf -orientation portrait -scope all \
    -name Native_Routed_Worst_Setup \
    [file join $output_dir 02_routed_worst_setup_schematic.pdf]

show_schematic -name Native_Routed_Worst_Hold $hold_path
after 2000
write_schematic -force -format svg -orientation portrait -scope all \
    -name Native_Routed_Worst_Hold \
    [file join $output_dir 03_routed_worst_hold_schematic.svg]
write_schematic -force -format pdf -orientation portrait -scope all \
    -name Native_Routed_Worst_Hold \
    [file join $output_dir 03_routed_worst_hold_schematic.pdf]

report_timing_summary -delay_type min_max -max_paths 10 -nworst 1 \
    -file [file join $output_dir 04_routed_timing_summary.rpt] \
    -rpx [file join $output_dir 04_routed_timing_summary.rpx]
report_timing -delay_type max -max_paths 10 -nworst 1 -input_pins \
    -file [file join $output_dir 05_worst_setup_paths.rpt]
report_timing -delay_type min -max_paths 10 -nworst 1 -input_pins \
    -file [file join $output_dir 06_worst_hold_paths.rpt]
report_design_analysis -timing -setup -show_all -max_paths 20 \
    -file [file join $output_dir 07_design_analysis_timing.rpt]
report_design_analysis -congestion -min_congestion_level 3 \
    -file [file join $output_dir 08_congestion_analysis.rpt]
report_utilization -hierarchical -hierarchical_depth 4 \
    -file [file join $output_dir 09_utilization_hierarchical.rpt]
report_clock_utilization \
    -file [file join $output_dir 10_clock_utilization.rpt]
report_clock_interaction -delay_type min_max -significant_digits 3 \
    -file [file join $output_dir 11_clock_interaction.rpt]
report_clock_networks -levels 4 \
    -file [file join $output_dir 12_clock_networks.rpt]
report_power -advisory -hier all -hierarchical_depth 4 \
    -file [file join $output_dir 13_power.rpt] \
    -rpx [file join $output_dir 13_power.rpx]
report_drc -file [file join $output_dir 14_drc.rpt] \
    -rpx [file join $output_dir 14_drc.rpx]
report_methodology -file [file join $output_dir 15_methodology.rpt] \
    -rpx [file join $output_dir 15_methodology.rpx]
report_route_status -file [file join $output_dir 16_route_status.rpt]
report_io -file [file join $output_dir 17_io_ports.rpt]

set manifest [open [file join $output_dir vivado_native_manifest.txt] w]
puts $manifest "VIVADO_VERSION=[version -short]"
puts $manifest "VIVADO_SW_BUILD=3247384"
puts $manifest "TOP=$expected_top"
puts $manifest "PART=$expected_part"
puts $manifest "CLOCK_MHZ=175"
puts $manifest "SYNTH_DCP=$synth_dcp"
puts $manifest "SYNTH_DCP_SHA256=$expected_synth_sha256"
puts $manifest "ROUTED_DCP=$routed_dcp"
puts $manifest "ROUTED_DCP_SHA256=$expected_routed_sha256"
puts $manifest "SYNTH_WORST_SETUP_SLACK_NS=$synth_slack"
puts $manifest "ROUTED_WORST_SETUP_SLACK_NS=[get_property SLACK $setup_path]"
puts $manifest "ROUTED_WORST_HOLD_SLACK_NS=[get_property SLACK $hold_path]"
puts $manifest "SETUP_STARTPOINT=[get_property STARTPOINT_PIN $setup_path]"
puts $manifest "SETUP_ENDPOINT=[get_property ENDPOINT_PIN $setup_path]"
puts $manifest "HOLD_STARTPOINT=[get_property STARTPOINT_PIN $hold_path]"
puts $manifest "HOLD_ENDPOINT=[get_property ENDPOINT_PIN $hold_path]"
puts $manifest "SCHEMATIC_EXPORT=Vivado native write_schematic SVG/PDF"
puts $manifest "REPORT_EXPORT=Vivado native RPT/RPX"
close $manifest

if {$gui_started} {
    stop_gui
}
close_design
puts "VIVADO_NATIVE_REPORT_EXPORT_PASS output_dir=$output_dir"
exit
