set script_dir [file dirname [file normalize [info script]]]
open_checkpoint [file join $script_dir round52_route_BF73AC63_8F1E6F26_C73046F1 checkpoints aes_gcm_axi_top_routed.dcp]

proc dump {name} {
    set c [get_cells -quiet $name]
    puts "Q52ZS_COUNT label=$name count=[llength $c]"
    foreach cell $c {
        puts "Q52ZS_CELL name=$cell ref=[get_property REF_NAME $cell] init=[get_property -quiet INIT $cell]"
        foreach p [lsort [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}]] {
            set n [get_nets -quiet -of_objects $p]
            set d [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
            puts "Q52ZS_PIN cell=$cell refpin=[get_property REF_PIN_NAME $p] net={$n} drv={$d}"
        }
        set o [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
        set n [get_nets -quiet -of_objects $o]
        set l [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]
        puts "Q52ZS_OUT cell=$cell net={$n} loads={$l}"
    }
}

foreach name {
    {u_core/u_desc_fifo/state[3]_i_15}
    {u_core/u_desc_fifo/state[3]_i_8}
    {u_core/u_desc_fifo/state[2]_i_2}
    {u_core/u_desc_fifo/i_9_LOPT_REMAP}
    {u_core/u_desc_fifo/i_0_LOPT_REMAP_1}
    {u_core/u_desc_fifo/ct_out_byte_index[3]_i_4}
    {u_core/record_last_r_i_6}
    {u_core/state[2]_i_4}
} { dump $name }

set count2 [get_pins -quiet {u_core/zeroize_abort_count_reg[2]/C}]
set state_d [get_pins -quiet -of_objects [get_cells -hier -quiet -filter {NAME =~ u_core/state_reg* && REF_NAME =~ FD*}] -filter {REF_PIN_NAME == D}]
report_timing -quiet -from $count2 -to $state_d -delay_type max -max_paths 4 -nworst 1 -path_type full_clock_expanded -file [file join $script_dir round52_abortcount_to_state_full.rpt]

close_design
exit 0
