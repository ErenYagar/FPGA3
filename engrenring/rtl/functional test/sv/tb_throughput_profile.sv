`timescale 1ns / 1ps

// Diagnostic wrapper for tb_throughput.  It does not drive the DUT; it only
// timestamps ordered public/core events so packet-level bubbles can be
// attributed before changing the production datapath.
module tb_throughput_profile;

tb_throughput u_tb();

integer public_frame_index = 0;
integer core_descriptor_index = 0;
integer result_index = 0;
integer public_stall_cycles = 0;
integer core_stall_cycles = 0;
integer aes_accept_count = 0;
integer aes_done_count = 0;
integer ghash_start_count = 0;
integer ghash_done_count = 0;
reg     public_frame_active = 1'b0;
reg     final_tag_ready_d = 1'b0;

always @(posedge u_tb.aclk)
begin
    final_tag_ready_d <= u_tb.dut.u_core.final_tag_ready;

    if(u_tb.s_valid && !u_tb.s_ready)
        public_stall_cycles = public_stall_cycles + 1;
    if(u_tb.dut.u_core.s_axis_tvalid && !u_tb.dut.u_core.s_axis_tready)
    begin
        core_stall_cycles = core_stall_cycles + 1;
        if((core_descriptor_index % 100) < 3)
            $display("PROFILE_CORE_STALL mode=%0d phase=%0d descriptor=%0d cycle=%0d state=%0d ifm=%0d field_received=%0d block_byte=%0d data_block=%0d ks_count=%0d dataq_count=%0d data_capacity=%0d aesq_count=%0d aes_outstanding=%0d ghq_count=%0d ghash_busy=%0d",
                     u_tb.key_mode, u_tb.run_phase,
                     core_descriptor_index - 1, u_tb.cycle_count,
                     u_tb.dut.u_core.state,
                     u_tb.dut.u_core.input_field_mode_r,
                     u_tb.dut.u_core.field_received,
                     u_tb.dut.u_core.block_byte_index,
                     u_tb.dut.u_core.data_block_index,
                     u_tb.dut.u_core.ks_fifo_count,
                     u_tb.dut.u_core.dataq_count_r,
                     u_tb.dut.u_core.data_block_capacity_r,
                     u_tb.dut.u_core.aesq_count,
                     u_tb.dut.u_core.aes_outstanding_count_r,
                     u_tb.dut.u_core.ghq_count,
                     u_tb.dut.u_core.ghash_busy);
    end

    if(u_tb.s_valid && u_tb.s_ready)
    begin
        if(!public_frame_active)
        begin
            public_frame_active = 1'b1;
            $display("PROFILE_PUBLIC_BEGIN mode=%0d phase=%0d packet=%0d cycle=%0d",
                     u_tb.key_mode, u_tb.run_phase, public_frame_index,
                     u_tb.cycle_count);
        end
        if(u_tb.s_last)
        begin
            $display("PROFILE_PUBLIC_END mode=%0d phase=%0d packet=%0d cycle=%0d public_stalls=%0d",
                     u_tb.key_mode, u_tb.run_phase, public_frame_index,
                     u_tb.cycle_count, public_stall_cycles);
            public_frame_index = public_frame_index + 1;
            public_frame_active = 1'b0;
            public_stall_cycles = 0;
        end
    end

    if(u_tb.dut.u_core.take_descriptor)
    begin
        $display("PROFILE_DESC_TAKE mode=%0d phase=%0d descriptor=%0d cycle=%0d",
                 u_tb.key_mode, u_tb.run_phase, core_descriptor_index,
                 u_tb.cycle_count);
        core_descriptor_index = core_descriptor_index + 1;
        aes_accept_count = 0;
        aes_done_count = 0;
        ghash_start_count = 0;
        ghash_done_count = 0;
        core_stall_cycles = 0;
    end

    if(u_tb.dut.u_core.aes_engine_accept_w)
        aes_accept_count = aes_accept_count + 1;
    if(u_tb.dut.u_core.aes_engine_done)
        aes_done_count = aes_done_count + 1;
    if(u_tb.dut.u_core.ghash_start)
        ghash_start_count = ghash_start_count + 1;
    if(u_tb.dut.u_core.ghash_done)
        ghash_done_count = ghash_done_count + 1;

    if(u_tb.dut.u_core.input_fire && u_tb.dut.u_core.record_last_r)
        $display("PROFILE_CORE_INPUT_END mode=%0d phase=%0d descriptor=%0d cycle=%0d state=%0d core_stalls=%0d",
                 u_tb.key_mode, u_tb.run_phase, core_descriptor_index - 1,
                 u_tb.cycle_count, u_tb.dut.u_core.state,
                 core_stall_cycles);

    if(u_tb.dut.u_core.final_tag_ready && !final_tag_ready_d)
        $display("PROFILE_TAG_READY mode=%0d phase=%0d descriptor=%0d cycle=%0d aes_accept=%0d aes_done=%0d ghash_start=%0d ghash_done=%0d",
                 u_tb.key_mode, u_tb.run_phase, core_descriptor_index - 1,
                 u_tb.cycle_count, aes_accept_count, aes_done_count,
                 ghash_start_count, ghash_done_count);

    if(u_tb.result_valid && u_tb.result_ready)
    begin
        $display("PROFILE_RESULT mode=%0d phase=%0d result=%0d cycle=%0d code=%02x",
                 u_tb.key_mode, u_tb.run_phase, result_index,
                 u_tb.cycle_count, u_tb.result_out);
        result_index = result_index + 1;
    end

    if(u_tb.data_valid && u_tb.data_ready && u_tb.data_last)
        $display("PROFILE_DATA_LAST mode=%0d phase=%0d cycle=%0d",
                 u_tb.key_mode, u_tb.run_phase, u_tb.cycle_count);
end

endmodule
