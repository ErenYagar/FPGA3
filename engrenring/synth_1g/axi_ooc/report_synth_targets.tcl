# Targeted post-synthesis timing diagnostics for the current OOC checkpoint.
set script_dir [file dirname [file normalize [info script]]]
set output_dir $script_dir
if {[llength $argv] > 0} {
    set output_label [lindex $argv 0]
    if {![regexp {^[A-Za-z0-9_.-]+$} $output_label]} {
        error "Invalid output label '$output_label'"
    }
    set output_dir [file join $script_dir $output_label]
}
set checkpoint_file [file join $output_dir checkpoints aes_gcm_axi_top_synth.dcp]
set report_dir [file join $output_dir reports]

if {![file isfile $checkpoint_file]} {
    error "Missing synthesized checkpoint: $checkpoint_file"
}

open_checkpoint $checkpoint_file

proc report_target {label cells report_file} {
    puts "AXI_OOC_TARGET label=$label cells=[llength $cells]"
    if {[llength $cells] == 0} {
        puts "AXI_OOC_TARGET_SKIP label=$label"
        return
    }
    report_timing -delay_type max -max_paths 10 -to $cells \
        -file $report_file
}

set sequential_cells [get_cells -quiet -hierarchical -filter {IS_SEQUENTIAL == 1}]
set ghash_producer_cells [get_cells -quiet -hierarchical -filter \
    {NAME =~ u_core/gh_input_data_reg* ||
     NAME =~ u_core/gh_aes_data_reg* ||
     NAME =~ u_core/gh_ctrl_data_reg*}]
set ghash_cells [get_cells -quiet -hierarchical -filter \
    {NAME =~ u_core/u_ghash/* && IS_SEQUENTIAL == 1}]
set remaining_cells [get_cells -quiet -hierarchical -filter \
    {NAME =~ u_core/record_bytes_remaining_reg*}]

report_target internal $sequential_cells \
    [file join $report_dir timing_synth_internal.rpt]
report_target ghash_producer $ghash_producer_cells \
    [file join $report_dir timing_synth_ghash_producer.rpt]
report_target ghash_primitive $ghash_cells \
    [file join $report_dir timing_synth_ghash_primitive.rpt]
report_target remaining_counter $remaining_cells \
    [file join $report_dir timing_synth_remaining_counter.rpt]

puts "AXI_OOC_TARGET_REPORTS $report_dir"
