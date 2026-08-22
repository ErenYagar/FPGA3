`timescale 1ns/1ps

module aesgcm_tag_sva (
    input logic         clk,
    input logic         rst_n,
    input logic         zeroize,
    input logic         tagq_valid,
    input logic [127:0] queued_tag_value,
    input logic [3:0]   tag_out_index,
    input logic         tag_send_active_r,
    input logic [4:0]   tag_bytes_remaining_r,
    input logic         tag_stream_fire,
    input logic [7:0]   m_axis_tag_tdata,
    input logic         m_axis_tag_tvalid,
    input logic         m_axis_tag_tready,
    input logic         m_axis_tag_tlast
);

    function automatic logic [7:0] msb_byte(
        input logic [127:0] value,
        input logic [3:0] index
    );
        msb_byte = value[127 - (index * 8) -: 8];
    endfunction

    default clocking cb @(posedge clk); endclocking

    ap_index_starts_zero: assert property (disable iff (!rst_n || zeroize)
        (!tag_send_active_r && tagq_valid) |=> tag_out_index == 4'd0);

    ap_selected_byte: assert property (disable iff (!rst_n || zeroize)
        m_axis_tag_tvalid |->
        m_axis_tag_tdata == msb_byte(queued_tag_value, tag_out_index));

    ap_index_advances_on_fire: assert property (disable iff (!rst_n || zeroize)
        (tag_stream_fire && !m_axis_tag_tlast) |=>
        tag_out_index == ($past(tag_out_index) + 4'd1));

    ap_index_holds_without_fire: assert property (disable iff (!rst_n || zeroize)
        (tag_send_active_r && !tag_stream_fire) |=> $stable(tag_out_index));

    ap_remaining_decrements_once: assert property (disable iff (!rst_n || zeroize)
        (tag_stream_fire && !m_axis_tag_tlast) |=>
        tag_bytes_remaining_r == ($past(tag_bytes_remaining_r) - 5'd1));

    ap_remaining_holds: assert property (disable iff (!rst_n || zeroize)
        (tag_send_active_r && !tag_stream_fire) |=>
        $stable(tag_bytes_remaining_r));

    ap_tlast_only_final: assert property (disable iff (!rst_n || zeroize)
        m_axis_tag_tlast |->
        (m_axis_tag_tvalid && tag_bytes_remaining_r == 5'd1));

    ap_final_has_tlast: assert property (disable iff (!rst_n || zeroize)
        (m_axis_tag_tvalid && tag_bytes_remaining_r == 5'd1) |->
        m_axis_tag_tlast);

    ap_tag_stable_under_backpressure: assert property (disable iff (!rst_n || zeroize)
        (m_axis_tag_tvalid && !m_axis_tag_tready) |=>
        (m_axis_tag_tvalid && $stable(m_axis_tag_tdata) &&
         $stable(m_axis_tag_tlast)));

endmodule
