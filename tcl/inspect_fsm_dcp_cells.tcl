# Inspect state-bearing registers in the retained 175 MHz synthesized DCP.

set repo_root [file normalize [file join [file dirname [info script]] ..]]
set checkpoint [file join $repo_root engrenring synth_1g board output \
    ece78ce_uart_rsp_175_resetqual4_final_v8 \
    arty_a7_100t_aes_gcm_uart_rsp_top_synth.dcp]

if {![file isfile $checkpoint]} {
    error "Missing synthesized checkpoint: $checkpoint"
}

open_checkpoint $checkpoint

set patterns {
    {u_aes_gcm/u_core/state_reg.*}
    {u_bridge/eng_state_r_reg.*}
    {u_bridge/rx_state_r_reg.*}
    {u_bridge/frame_phase_r_reg.*}
    {u_bridge/u_uart_rx/state_reg.*}
    {u_bridge/u_uart_tx/state_reg.*}
    {u_aes_gcm/u_registers/awaddr_valid_q_reg.*}
    {u_aes_gcm/u_registers/wdata_valid_q_reg.*}
    {u_aes_gcm/u_registers/s_axi_bvalid_reg.*}
    {u_aes_gcm/u_registers/status_read_pending_q_reg.*}
    {u_aes_gcm/u_registers/s_axi_rvalid_reg.*}
}

foreach pattern $patterns {
    puts "PATTERN=$pattern"
    set matches [lsort [get_cells -quiet -hier -regexp $pattern]]
    if {[llength $matches] == 0} {
        puts "  <none>"
    } else {
        foreach cell $matches {
            puts "  $cell REF_NAME=[get_property REF_NAME $cell]"
        }
    }
}

close_design
exit
