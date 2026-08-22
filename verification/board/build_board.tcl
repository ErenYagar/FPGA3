# OOC validation build for the generic shell. This intentionally does not
# generate a bitstream until an approved board wrapper/XDC is supplied.
proc board_fail {message} { puts stderr "BOARD_BUILD_SUMMARY status=FAIL error={$message}"; exit 1 }
if {[llength $argv]!=1} { board_fail "expected one new output directory" }
set output_dir [file normalize [lindex $argv 0]]
if {[file exists $output_dir]} { board_fail "output already exists: $output_dir" }
file mkdir $output_dir
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir .. ..]]
set rtl_dir [file join $repo_root engrenring rtl source]
set sources [list [file join $rtl_dir aes_core sbox.v] \
 [file join $rtl_dir stream_aes aes_block_engine.v] \
 [file join $rtl_dir stream_aes aes_first_block_engine.v] \
 [file join $rtl_dir stream_aes aes_key_context.v] \
 [file join $rtl_dir stream_ghash ghash16.v] \
 [file join $rtl_dir stream_axi axi_lite_regs.v] \
 [file join $rtl_dir stream_axi axis_output_skid_8.v] \
 [file join $rtl_dir stream_core stream_fifo.v] \
 [file join $rtl_dir stream_core aes_gcm_stream_core.v] \
 [file join $rtl_dir aes_gcm_axi_top.v] [file join $script_dir board_test_shell.sv]]
foreach source $sources { if {![file isfile $source]} {board_fail "missing $source"}; read_verilog -sv $source }
read_xdc [file join $repo_root engrenring synth_1g axi_ooc axi_200mhz_ooc.xdc]
if {[catch {
 synth_design -mode out_of_context -top board_test_shell -part xc7a100tcsg324-1 -flatten_hierarchy rebuilt
 set input_bram_cells [get_cells -hier -quiet -filter {REF_NAME == RAMB18E1 && NAME =~ *input_bram*}]
 set output_bram_cells [get_cells -hier -quiet -filter {REF_NAME == RAMB18E1 && NAME =~ *output_bram*}]
 if {[llength $input_bram_cells]!=1||[llength $output_bram_cells]!=1} {
  error "shell BRAM mapping mismatch input={[llength $input_bram_cells]} output={[llength $output_bram_cells]}"
 }
 write_checkpoint [file join $output_dir board_test_shell_synth.dcp]
 report_utilization -hierarchical -file [file join $output_dir utilization_synth.rpt]
 report_timing_summary -report_unconstrained -file [file join $output_dir timing_synth.rpt]
 check_timing -verbose -file [file join $output_dir check_timing_synth.rpt]
 puts "BOARD_BUILD_SUMMARY status=OOC_PASS top=board_test_shell input_RAMB18=1 output_RAMB18=1 bitstream=NOT_GENERATED reason=board_wrapper_xdc_required output=$output_dir"
} message options]} { board_fail $message }
exit 0
