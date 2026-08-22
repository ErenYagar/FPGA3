`timescale 1ns/1ps

module ghash_queue_sva (
    input logic         clk,
    input logic         rst_n,
    input logic         zeroize,
    input logic         queue_clear,
    input logic [131:0] ghq_out,
    input logic         ghq_valid,
    input logic         ghq_ready,
    input logic [2:0]   ghq_count,
    input logic         ghash_start,
    input logic         ghash_busy
);

    default clocking cb @(posedge clk); endclocking

    ap_queue_stable_while_blocked: assert property (disable iff (!rst_n || queue_clear)
        (ghq_valid && !ghq_ready) |=>
        (ghq_valid && $stable(ghq_out)));

    ap_start_is_handshake: assert property (disable iff (!rst_n)
        ghash_start == (ghq_valid && ghq_ready));

    ap_busy_blocks_start: assert property (disable iff (!rst_n)
        ghash_busy |-> (!ghq_ready && !ghash_start));

    ap_no_pop_while_busy: assert property (disable iff (!rst_n || queue_clear)
        (ghash_busy && ghq_valid) |=>
        (ghq_count >= $past(ghq_count) || !ghash_busy));

    ap_flush: assert property (disable iff (!rst_n)
        (zeroize || queue_clear) |=> (!ghq_valid && ghq_count == 3'd0));

endmodule
