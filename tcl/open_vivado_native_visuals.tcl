# Prepare the retained 175 MHz routed checkpoint for native Vivado GUI capture.

if {$argc != 1} {
    error "Usage: open_vivado_native_visuals.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
set repo_root [file normalize [file join [file dirname [info script]] ..]]
set routed_dcp [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8 \
    arty_a7_100t_aes_gcm_uart_rsp_top_routed.dcp]

if {[version -short] ne "2021.1" ||
    ![regexp -line {^SW Build 3247384[ \t]} [version]]} {
    error "Vivado 2021.1 SW Build 3247384 is required"
}

open_checkpoint $routed_dcp
if {[get_property TOP [current_design]] ne
    "arty_a7_100t_aes_gcm_uart_rsp_top" ||
    [get_property PART [current_design]] ne "xc7a100tcsg324-1"} {
    error "Unexpected routed checkpoint identity"
}

set setup_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]

report_timing_summary -delay_type min_max -max_paths 10 -nworst 1 \
    -name Native_Timing_Summary
report_timing -delay_type max -max_paths 1 -nworst 1 -input_pins \
    -name Native_Worst_Setup_Path
report_timing -delay_type min -max_paths 1 -nworst 1 -input_pins \
    -name Native_Worst_Hold_Path
report_design_analysis -congestion -min_congestion_level 3 \
    -name Native_Congestion
report_utilization -name Native_Utilization
report_clock_interaction -delay_type min_max -significant_digits 3 \
    -name Native_Clock_Interaction
report_clock_networks -levels 4 -name Native_Clock_Networks
report_power -advisory -name Native_Power
report_drc -name Native_DRC

show_objects -name Native_Worst_Setup_Objects \
    [concat [get_cells -of_objects $setup_path] [get_nets -of_objects $setup_path]]
highlight_objects -color red [get_nets -of_objects $setup_path]
highlight_objects -color yellow -leaf_cells [get_cells -of_objects $setup_path]
show_schematic -name Native_Routed_Worst_Setup $setup_path

puts "VIVADO_NATIVE_GUI_READY output_dir=$output_dir"
