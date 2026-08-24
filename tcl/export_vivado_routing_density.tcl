# Export Vivado's routed-design congestion analysis for report evidence.

if {$argc != 1} {
    error "Usage: export_vivado_routing_density.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir
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
    "arty_a7_100t_aes_gcm_uart_rsp_top"} {
    error "Unexpected routed checkpoint top"
}
if {[get_property PART [current_design]] ne "xc7a100tcsg324-1"} {
    error "Unexpected routed checkpoint part"
}

report_design_analysis -congestion -file [file join $output_dir \
    vivado_congestion_analysis.rpt]
puts "VIVADO_CONGESTION_REPORT_PASS"
close_design
exit
