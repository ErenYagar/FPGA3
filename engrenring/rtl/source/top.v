`timescale 1ns / 1ps

// Four independent AES-GCM packet lanes for greater than 1 Gbps aggregate
// packet throughput at a 200 MHz clock.  All lanes use the selected key size.
module top #(
    parameter integer LANES = 4
)
(
input                          clk,
input                          rst,
input      [2:0]               key_mode,
input      [LANES-1:0]         mode,
input      [LANES*8-1:0]       in,
input      [LANES-1:0]         in_valid,
input      [LANES*3-1:0]       in_type,
input      [LANES*11-1:0]      in_valid_bit,
input      [LANES-1:0]         last,
output     [LANES-1:0]         pc_ct_valid,
output     [LANES-1:0]         tag_valid,
output     [LANES*11-1:0]      pc_ct_len_bit,
output     [LANES*4-1:0]       pc_ct_valid_bit,
output     [LANES*8-1:0]       out
);

genvar lane;
generate
    for(lane = 0; lane < LANES; lane = lane + 1)
    begin : GEN_LANES
        legacy_stream_adapter u_lane
        (
            .clk             (clk),
            .rst             (rst),
            .key_mode        (key_mode),
            .mode            (mode[lane]),
            .in              (in[lane*8 +: 8]),
            .in_valid        (in_valid[lane]),
            .in_type         (in_type[lane*3 +: 3]),
            .in_valid_bit    (in_valid_bit[lane*11 +: 11]),
            .last            (last[lane]),
            .pc_ct_valid     (pc_ct_valid[lane]),
            .tag_valid       (tag_valid[lane]),
            .pc_ct_len_bit   (pc_ct_len_bit[lane*11 +: 11]),
            .pc_ct_valid_bit (pc_ct_valid_bit[lane*4 +: 4]),
            .out             (out[lane*8 +: 8])
        );
    end
endgenerate

endmodule
