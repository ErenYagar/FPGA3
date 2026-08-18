set script_dir [file dirname [file normalize [info script]]]
set dcp [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_routed.dcp]
open_checkpoint $dcp

proc dump_cell {cell} {
    puts "Q52Z_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell] loc=[get_property -quiet LOC $cell]"
    foreach pin [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
        set net [get_nets -quiet -of_objects $pin]
        set drv [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == OUT}]
        puts "Q52Z_PIN cell=$cell refpin=[get_property REF_PIN_NAME $pin] net={$net} drivers={$drv}"
    }
    set out [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
    set net [get_nets -quiet -of_objects $out]
    set loads [get_pins -quiet -leaf -of_objects $net -filter {DIRECTION == IN}]
    puts "Q52Z_OUT cell=$cell pin={$out} net={$net} load_count=[llength $loads] loads={$loads}"
}

set candidates [concat \
    [get_cells -hier -quiet -regexp {.*result_data_r\[4\]_i_.*}] \
    [get_cells -hier -quiet -regexp {.*zeroize_abort_count\[[0-9]+\]_i_.*}] \
    [get_cells -hier -quiet -regexp {.*zeroize_busy_r_i_.*}]]
set candidates [lsort -unique $candidates]
puts "Q52Z_CANDIDATE_COUNT [llength $candidates]"
foreach cell $candidates { dump_cell $cell }

set zsrc_cells [concat \
    [get_cells -hier -quiet -filter {NAME =~ *zeroize_busy_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *zeroize_abort_count_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *result_valid_r_reg* && REF_NAME =~ FD*}] \
    [get_cells -hier -quiet -filter {NAME =~ *result_data_r_reg* && REF_NAME =~ FD*}]]
set zsrc_c [get_pins -quiet -of_objects $zsrc_cells -filter {REF_PIN_NAME == C}]
set regs [all_registers]
set paths [get_timing_paths -quiet -from $zsrc_c -to $regs -delay_type max -max_paths 10000 -nworst 1]
set neg 0
set tns 0.0
foreach path $paths {
    set slack [get_property SLACK $path]
    if {$slack < 0.0} {
        incr neg
        set tns [expr {$tns + double($slack)}]
        puts "Q52Z_NEG rank=$neg slack=$slack start={[get_property STARTPOINT_PIN $path]} end={[get_property ENDPOINT_PIN $path]} levels=[get_property LOGIC_LEVELS $path]"
    }
}
puts "Q52Z_FAMILY paths=[llength $paths] neg=$neg tns=$tns"

close_design
exit 0
