`timescale 1ns/1ps

// The same properties used in simulation are the control-level formal
// targets. The full-datapath ghash16 checker contains the independent
// 128-step recurrence reference; the queue checker covers request retention.
bind ghash16 ghash16_sva u_ghash16_formal (
    .clk(clk), .rst_n(rst_n), .load_h(load_h), .H(H), .init(init),
    .start(start), .block_in(block_in), .busy(busy), .done(done), .Y(Y),
    .digit_count_r(digit_count_r), .h_r(h_r), .x_work_r(x_work_r),
    .v_work_r(v_work_r), .z_work_r(z_work_r), .v_power_16(v_power_16),
    .digit_product_w(digit_product_w), .z_after_digit_w(z_after_digit_w)
);

bind aes_key_context aes_key_context_sva u_key_context_formal (
    .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .busy(busy), .ready(ready),
    .key_size(key_size), .round_count(round_count), .round_keys(round_keys),
    .state_r(state_r), .sbox_input_r(sbox_input_r),
    .sbox_new_word_w(sbox_new_word_w), .generated_word_r(generated_word_r)
);

bind aes_gcm_stream_core ghash_queue_sva u_ghash_queue_formal (
    .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .queue_clear(queue_clear),
    .ghq_out(ghq_out), .ghq_valid(ghq_valid), .ghq_ready(ghq_ready),
    .ghq_count(ghq_count), .ghash_start(ghash_start), .ghash_busy(ghash_busy)
);
