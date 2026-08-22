`timescale 1ns/1ps

module axis_output_sva #(
    parameter integer PAYLOAD_WIDTH = 8
) (
    input logic                     clk,
    input logic                     rst_n,
    input logic                     clear,
    input logic [PAYLOAD_WIDTH-1:0] payload,
    input logic                     valid,
    input logic                     ready
);

    default clocking cb @(posedge clk); endclocking

    ap_valid_payload_stable: assert property (disable iff (!rst_n || clear)
        (valid && !ready) |=> (valid && $stable(payload)));

endmodule
