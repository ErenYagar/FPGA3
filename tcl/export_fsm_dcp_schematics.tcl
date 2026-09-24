# Export Vivado-native post-synthesis evidence for the retained FSM registers.

if {$argc != 1} {
    error "Usage: export_fsm_dcp_schematics.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set checkpoint [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8 \
    arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp]

if {![file isfile $checkpoint]} {
    error "Missing synthesized checkpoint: $checkpoint"
}

proc exact_reg_bank {pattern description} {
    set regs [lsort [get_cells -quiet -hier -regexp $pattern]]
    if {[llength $regs] == 0} {
        error "$description: no registers matched '$pattern'"
    }
    return $regs
}

proc export_state_cone {view_name regs output_dir base_name} {
    set d_pins [get_pins -quiet -of_objects $regs -filter {REF_PIN_NAME == D}]
    set cone [all_fanin -quiet -flat -only_cells -levels 1 -to $d_pins]
    set objects [lsort -unique [concat $regs $cone]]
    show_schematic -name $view_name $objects
    after 1500
    write_schematic -force -format svg -orientation landscape -scope all \
        -name $view_name [file join $output_dir ${base_name}.svg]
    write_schematic -force -format pdf -orientation landscape -scope all \
        -name $view_name [file join $output_dir ${base_name}.pdf]
    return [list [llength $regs] [llength $objects]]
}

open_checkpoint $checkpoint
start_gui

set core_regs [exact_reg_bank {u_aes_gcm/u_core/state_reg.*} \
    "AES-GCM core main-state bank"]
set bridge_regs [exact_reg_bank {u_bridge/eng_state_r_reg.*} \
    "UART/RSP transaction-engine state bank"]
set parser_regs [exact_reg_bank {u_bridge/rx_state_r_reg.*} \
    "UART/RSP parser state bank"]
set axi_control_regs {}
foreach pattern {
    {u_aes_gcm/u_registers/awaddr_valid_q_reg.*}
    {u_aes_gcm/u_registers/wdata_valid_q_reg.*}
    {u_aes_gcm/u_registers/s_axi_bvalid_reg.*}
    {u_aes_gcm/u_registers/status_read_pending_q_reg.*}
    {u_aes_gcm/u_registers/s_axi_rvalid_reg.*}
} {
    set axi_control_regs [concat $axi_control_regs \
        [exact_reg_bank $pattern "AXI-Lite distributed control flag"]]
}

set core_counts [export_state_cone Synthesis_Core_FSM_State_Cone $core_regs \
    $output_dir 01_synthesis_core_fsm_state_cone]
set bridge_counts [export_state_cone Synthesis_UART_RSP_Engine_State_Cone \
    $bridge_regs $output_dir 02_synthesis_uart_rsp_engine_state_cone]
set parser_counts [export_state_cone Synthesis_UART_RSP_Parser_State_Cone \
    $parser_regs $output_dir 03_synthesis_uart_rsp_parser_state_cone]
set axi_counts [export_state_cone Synthesis_AXI_Lite_Control_Flag_Cone \
    $axi_control_regs $output_dir 04_synthesis_axi_lite_control_flag_cone]

set manifest [open [file join $output_dir fsm_dcp_evidence_manifest.txt] w]
puts $manifest "VIVADO_VERSION=[version -short]"
puts $manifest "TOP=[get_property TOP [current_design]]"
puts $manifest "PART=[get_property PART [current_design]]"
puts $manifest "SYNTH_DCP=$checkpoint"
puts $manifest "CORE_STATE_REGISTERS=[lindex $core_counts 0]"
puts $manifest "CORE_EXPORTED_OBJECTS=[lindex $core_counts 1]"
puts $manifest "BRIDGE_ENGINE_STATE_REGISTERS=[lindex $bridge_counts 0]"
puts $manifest "BRIDGE_ENGINE_EXPORTED_OBJECTS=[lindex $bridge_counts 1]"
puts $manifest "BRIDGE_PARSER_STATE_REGISTERS=[lindex $parser_counts 0]"
puts $manifest "BRIDGE_PARSER_EXPORTED_OBJECTS=[lindex $parser_counts 1]"
puts $manifest "AXI_LITE_CONTROL_FLAG_REGISTERS=[lindex $axi_counts 0]"
puts $manifest "AXI_LITE_EXPORTED_OBJECTS=[lindex $axi_counts 1]"
puts $manifest "INTERPRETATION=Optimized post-synthesis registers and one-level D-input cones; RTL source remains authoritative for semantic state transitions."
close $manifest

stop_gui
close_design
puts "FSM_DCP_EVIDENCE_EXPORT_PASS output_dir=$output_dir"
exit
