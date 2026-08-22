`timescale 1ns/1ps

bind ghash16 ghash16_sva u_ghash16_sva (
    .clk(clk), .rst_n(rst_n), .load_h(load_h), .H(H), .init(init),
    .start(start), .block_in(block_in), .busy(busy), .done(done), .Y(Y),
    .digit_count_r(digit_count_r), .h_r(h_r), .x_work_r(x_work_r),
    .v_work_r(v_work_r), .z_work_r(z_work_r), .v_power_16(v_power_16),
    .digit_product_w(digit_product_w), .z_after_digit_w(z_after_digit_w)
);

bind aes_key_context aes_key_context_sva u_aes_key_context_sva (
    .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .busy(busy), .ready(ready),
    .key_size(key_size), .round_count(round_count), .round_keys(round_keys),
    .state_r(state_r), .sbox_input_r(sbox_input_r),
    .sbox_new_word_w(sbox_new_word_w), .generated_word_r(generated_word_r)
);

bind aes_gcm_stream_core ghash_queue_sva u_ghash_queue_sva (
    .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .queue_clear(queue_clear),
    .ghq_out(ghq_out), .ghq_valid(ghq_valid), .ghq_ready(ghq_ready),
    .ghq_count(ghq_count), .ghash_start(ghash_start), .ghash_busy(ghash_busy)
);

bind aes_gcm_stream_core aesgcm_tag_sva u_aesgcm_tag_sva (
    .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .tagq_valid(tagq_valid),
    .queued_tag_value(queued_tag_value), .tag_out_index(tag_out_index),
    .tag_send_active_r(tag_send_active_r),
    .tag_bytes_remaining_r(tag_bytes_remaining_r),
    .tag_stream_fire(tag_stream_fire), .m_axis_tag_tdata(m_axis_tag_tdata),
    .m_axis_tag_tvalid(m_axis_tag_tvalid),
    .m_axis_tag_tready(m_axis_tag_tready),
    .m_axis_tag_tlast(m_axis_tag_tlast)
);

bind aes_gcm_axi_top axis_output_sva #(.PAYLOAD_WIDTH(13)) u_data_output_sva (
    .clk(aclk), .rst_n(aresetn), .clear(zeroize_pulse),
    .payload({m_axis_data_tuser, m_axis_data_tlast, m_axis_data_tdata}),
    .valid(m_axis_data_tvalid), .ready(m_axis_data_tready)
);

bind aes_gcm_axi_top axis_output_sva #(.PAYLOAD_WIDTH(9)) u_tag_output_sva (
    .clk(aclk), .rst_n(aresetn), .clear(zeroize_pulse),
    .payload({m_axis_tag_tlast, m_axis_tag_tdata}),
    .valid(m_axis_tag_tvalid), .ready(m_axis_tag_tready)
);

bind aes_gcm_axi_top axis_output_sva #(.PAYLOAD_WIDTH(9)) u_result_output_sva (
    .clk(aclk), .rst_n(aresetn), .clear(zeroize_pulse),
    .payload({m_axis_result_tlast, m_axis_result_tdata}),
    .valid(m_axis_result_tvalid), .ready(m_axis_result_tready)
);
