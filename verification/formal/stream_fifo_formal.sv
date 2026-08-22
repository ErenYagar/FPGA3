`timescale 1ns/1ps

module stream_fifo_formal #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 4,
    parameter integer ADDR_W = 2
) (
    input logic clk,
    input logic rst_n,
    input logic clear,
    input logic [WIDTH-1:0] in_data,
    input logic in_valid,
    input logic in_ready,
    input logic [WIDTH-1:0] out_data,
    input logic out_valid,
    input logic out_ready,
    input logic [ADDR_W:0] count
);
    default clocking cb @(posedge clk); endclocking

    ap_count_bound: assert property (disable iff (!rst_n)
        count <= DEPTH);
    ap_valid_count: assert property (disable iff (!rst_n)
        out_valid == (count != 0));
    ap_ready_count: assert property (disable iff (!rst_n)
        in_ready == (count != DEPTH));
    ap_clear: assert property (disable iff (!rst_n)
        clear |=> count == 0 && !out_valid);
    ap_stable_head: assert property (disable iff (!rst_n || clear)
        out_valid && !out_ready |=> out_valid && $stable(out_data));
    ap_push_only: assert property (disable iff (!rst_n || clear)
        in_valid && in_ready && !(out_valid && out_ready) |=>
        count == $past(count) + 1'b1);
    ap_pop_only: assert property (disable iff (!rst_n || clear)
        !(in_valid && in_ready) && out_valid && out_ready |=>
        count == $past(count) - 1'b1);
endmodule

bind stream_fifo stream_fifo_formal #(
    .WIDTH(WIDTH), .DEPTH(DEPTH), .ADDR_W(ADDR_W)
) u_stream_fifo_formal (.*);
