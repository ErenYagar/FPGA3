`timescale 1ns/1ps

module aes_key_context_sva (
    input logic          clk,
    input logic          rst_n,
    input logic          zeroize,
    input logic          busy,
    input logic          ready,
    input logic [1:0]    key_size,
    input logic [3:0]    round_count,
    input logic [1919:0] round_keys,
    input logic [2:0]    state_r,
    input logic [31:0]   sbox_input_r,
    input logic [31:0]   sbox_new_word_w,
    input logic [31:0]   generated_word_r
);

    localparam logic [2:0] ST_SBOX_WAIT    = 3'd2;
    localparam logic [2:0] ST_SBOX_CAPTURE = 3'd3;
    localparam logic [2:0] ST_STORE_WORD   = 3'd4;

    default clocking cb @(posedge clk); endclocking

    ap_wait_to_capture: assert property (disable iff (!rst_n || zeroize)
        state_r == ST_SBOX_WAIT |=> state_r == ST_SBOX_CAPTURE);

    ap_capture_to_store: assert property (disable iff (!rst_n || zeroize)
        state_r == ST_SBOX_CAPTURE |=> state_r == ST_STORE_WORD);

    ap_sbox_input_stable: assert property (disable iff (!rst_n || zeroize)
        state_r == ST_SBOX_WAIT |=> $stable(sbox_input_r));

    ap_generated_word: assert property (disable iff (!rst_n || zeroize)
        state_r == ST_SBOX_CAPTURE |=> generated_word_r == $past(sbox_new_word_w));

    ap_ready_busy_exclusive: assert property (disable iff (!rst_n)
        !(ready && busy));

    ap_ready_round_count: assert property (disable iff (!rst_n)
        ready |-> ((key_size == 2'd0 && round_count == 4'd10) ||
                   (key_size == 2'd1 && round_count == 4'd12) ||
                   (key_size == 2'd2 && round_count == 4'd14)));

    ap_zeroize_scrubs_keys: assert property (disable iff (!rst_n)
        zeroize |=> (!ready && !busy && round_count == 4'd0 &&
                     round_keys == 1920'd0));

endmodule
