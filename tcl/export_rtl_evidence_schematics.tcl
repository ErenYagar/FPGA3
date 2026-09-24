# Export Vivado-native RTL/elaborated and post-synthesis evidence schematics
# for the retained 175 MHz Arty A7-100T AES-GCM design.

if {$argc != 1} {
    error "Usage: export_rtl_evidence_schematics.tcl OUTPUT_DIR"
}

set output_dir [file normalize [lindex $argv 0]]
file mkdir $output_dir

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set rtl_root [file join $repo_root engrenring rtl source]
set checkpoint_dir [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8]
set synth_dcp [file join $checkpoint_dir \
    arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp]
set expected_top arty_a7_100t_aes_gcm_uart_rsp_top
set expected_part xc7a100tcsg324-1
set expected_synth_sha256 \
    C5D9858BDD097622C7AA76A1843CB3D49EF7646470BC4ACDAF9BDB27882914E6

proc require_file {path} {
    if {![file isfile $path]} {
        error "Missing required file: $path"
    }
}

proc collect_exact_cells {names description} {
    set result {}
    foreach name $names {
        set cell [get_cells -quiet $name]
        if {[llength $cell] != 1} {
            error "$description: expected exactly one cell '$name', found [llength $cell]"
        }
        lappend result $cell
    }
    return $result
}

proc export_view {view_name objects output_dir base_name} {
    if {[llength $objects] == 0} {
        error "Cannot export empty schematic '$view_name'"
    }
    show_schematic -name $view_name $objects
    after 1500
    write_schematic -force -format svg -orientation landscape -scope all \
        -name $view_name [file join $output_dir ${base_name}.svg]
    write_schematic -force -format pdf -orientation landscape -scope all \
        -name $view_name [file join $output_dir ${base_name}.pdf]
}

if {[version -short] ne "2021.1" ||
    ![regexp -line {^SW Build 3247384[ \t]} [version]]} {
    error "Vivado 2021.1 SW Build 3247384 is required"
}
require_file $synth_dcp

set_part $expected_part
read_verilog [file join $rtl_root aes_core sbox.v]
read_verilog [file join $rtl_root stream_aes aes_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_first_block_engine.v]
read_verilog [file join $rtl_root stream_aes aes_key_context.v]
read_verilog [file join $rtl_root stream_ghash ghash16.v]
read_verilog [file join $rtl_root stream_axi axi_lite_regs.v]
read_verilog [file join $rtl_root stream_axi axis_output_skid_8.v]
read_verilog [file join $rtl_root stream_core aes_gcm_stream_core.v]
read_verilog [file join $rtl_root stream_core stream_fifo.v]
read_verilog [file join $rtl_root aes_gcm_axi_top.v]
read_verilog [file join $rtl_root board uart_rx.v]
read_verilog [file join $rtl_root board uart_tx.v]
read_verilog [file join $rtl_root board aes_gcm_uart_rsp_bridge.v]
read_verilog [file join $rtl_root board arty_a7_100t_aes_gcm_uart_rsp_top.v]

synth_design -rtl -top $expected_top -part $expected_part
if {[get_property TOP [current_design]] ne $expected_top} {
    error "Unexpected elaborated top: [get_property TOP [current_design]]"
}

start_gui

set top_blocks [collect_exact_cells {
    u_bridge
    u_aes_gcm
} "Top-level RTL hierarchy"]
export_view RTL_Elaborated_Top $top_blocks $output_dir \
    01_rtl_elaborated_top

set wrapper_blocks [collect_exact_cells {
    u_aes_gcm/u_registers
    u_aes_gcm/u_input_queue
    u_aes_gcm/u_core
    u_aes_gcm/u_data_output_register
    u_aes_gcm/u_tag_output_register
} "AES-GCM wrapper RTL hierarchy"]
export_view RTL_Elaborated_AES_GCM_Wrapper $wrapper_blocks $output_dir \
    02_rtl_elaborated_aes_gcm_wrapper

set core_blocks [collect_exact_cells {
    u_aes_gcm/u_core/u_key_context
    u_aes_gcm/u_core/u_aes_first_engine
    u_aes_gcm/u_core/u_aes_second_engine
    u_aes_gcm/u_core/u_aes_engine
    u_aes_gcm/u_core/u_aes_request_fifo
    u_aes_gcm/u_core/u_aes_meta_fifo
    u_aes_gcm/u_core/u_aes_result_fifo
    u_aes_gcm/u_core/u_keystream_fifo
    u_aes_gcm/u_core/u_desc_fifo
    u_aes_gcm/u_core/u_ghash_request_fifo
    u_aes_gcm/u_core/u_ghash
    u_aes_gcm/u_core/u_ciphertext_fifo
    u_aes_gcm/u_core/u_plain_release_fifo
    u_aes_gcm/u_core/u_tag_packet_fifo
} "AES-GCM core RTL hierarchy"]
export_view RTL_Elaborated_Core_Datapath $core_blocks $output_dir \
    03_rtl_elaborated_core_datapath

close_design
open_checkpoint $synth_dcp
if {[get_property TOP [current_design]] ne $expected_top ||
    [get_property PART [current_design]] ne $expected_part} {
    error "Synthesis checkpoint identity mismatch"
}
set worst_setup [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_setup] != 1} {
    error "Expected exactly one post-synthesis worst setup path"
}
export_view Synthesis_Worst_Setup_Path $worst_setup $output_dir \
    04_synthesis_worst_setup_path
report_utilization -hierarchical -hierarchical_depth 4 \
    -file [file join $output_dir 05_synthesis_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 10 -nworst 1 \
    -file [file join $output_dir 06_synthesis_timing_summary.rpt]

set manifest [open [file join $output_dir rtl_evidence_manifest.txt] w]
puts $manifest "VIVADO_VERSION=[version -short]"
puts $manifest "VIVADO_SW_BUILD=3247384"
puts $manifest "TOP=$expected_top"
puts $manifest "PART=$expected_part"
puts $manifest "TARGET_CLOCK_MHZ=175"
puts $manifest "SYNTH_DCP=$synth_dcp"
puts $manifest "SYNTH_DCP_SHA256=$expected_synth_sha256"
puts $manifest "ELABORATED_TOP_BLOCKS=[llength $top_blocks]"
puts $manifest "ELABORATED_WRAPPER_BLOCKS=[llength $wrapper_blocks]"
puts $manifest "ELABORATED_CORE_BLOCKS=[llength $core_blocks]"
puts $manifest "SYNTH_WORST_SETUP_SLACK_NS=[get_property SLACK $worst_setup]"
puts $manifest "SCHEMATIC_EXPORT=Vivado native write_schematic SVG/PDF"
close $manifest

stop_gui
close_design
puts "RTL_EVIDENCE_SCHEMATIC_EXPORT_PASS output_dir=$output_dir"
exit
