`timescale 1ns / 1ps

module tb_board_reset_qualifier;

reg core_clk_tb = 1'b0;
reg rst_btn = 1'b0;
reg uart_txd_in = 1'b1;
reg mmcm_locked_tb = 1'b0;
wire uart_rxd_out;
wire [3:0] led;

always #2.857 core_clk_tb = ~core_clk_tb;

arty_a7_100t_aes_gcm_uart_rsp_top dut (
    .clk(1'b0),
    .rst_btn(rst_btn),
    .uart_txd_in(uart_txd_in),
    .uart_rxd_out(uart_rxd_out),
    .led(led)
);

task expect_reset_n;
    input expected;
    input [8*48-1:0] step_name;
    begin
        @(posedge core_clk_tb);
        #0.001;
        if(dut.aresetn !== expected)
            $fatal(1, "BOARD_RESET_QUALIFIER_FAIL step=%0s expected=%0b actual=%0b",
                step_name, expected, dut.aresetn);
    end
endtask

integer i;
integer pulse_edges;
initial begin
    force dut.core_clk = core_clk_tb;
    force dut.mmcm_locked = mmcm_locked_tb;

    repeat(3) expect_reset_n(1'b0, "initial_reset");

    // Button pulses shorter than the old four-consecutive-sample threshold
    // must never emerge later as a reset release.
    mmcm_locked_tb = 1'b1;
    for(pulse_edges = 1; pulse_edges <= 3; pulse_edges = pulse_edges + 1) begin
        @(negedge core_clk_tb);
        rst_btn = 1'b1;
        for(i = 0; i < pulse_edges; i = i + 1)
            expect_reset_n(1'b0, "button_short_pulse_sample");
        @(negedge core_clk_tb);
        rst_btn = 1'b0;
        for(i = 0; i < 8; i = i + 1)
            expect_reset_n(1'b0, "button_short_pulse_rejected");
    end

    // The same guarantee applies when MMCM LOCKED is the pulsing source.
    mmcm_locked_tb = 1'b0;
    rst_btn = 1'b1;
    for(pulse_edges = 1; pulse_edges <= 3; pulse_edges = pulse_edges + 1) begin
        @(negedge core_clk_tb);
        mmcm_locked_tb = 1'b1;
        for(i = 0; i < pulse_edges; i = i + 1)
            expect_reset_n(1'b0, "lock_short_pulse_sample");
        @(negedge core_clk_tb);
        mmcm_locked_tb = 1'b0;
        for(i = 0; i < 8; i = i + 1)
            expect_reset_n(1'b0, "lock_short_pulse_rejected");
    end

    // Alternating request chatter without four consecutive high samples must
    // also remain in reset even though synchronization delays each transition.
    mmcm_locked_tb = 1'b1;
    for(i = 0; i < 8; i = i + 1) begin
        @(negedge core_clk_tb);
        rst_btn = ~rst_btn;
        expect_reset_n(1'b0, "alternating_chatter_rejected");
    end
    @(negedge core_clk_tb);
    rst_btn = 1'b0;
    repeat(8) expect_reset_n(1'b0, "chatter_pipeline_drained");

    // Two synchronizer stages plus four stable-high qualifier stages release
    // reset on the sixth sampled core edge while preserving the old rule that
    // at least four raw high samples are required.
    @(negedge core_clk_tb);
    mmcm_locked_tb = 1'b1;
    rst_btn = 1'b1;
    expect_reset_n(1'b0, "release_edge_1");
    expect_reset_n(1'b0, "release_edge_2");
    expect_reset_n(1'b0, "release_edge_3");
    expect_reset_n(1'b0, "release_edge_4");
    expect_reset_n(1'b0, "release_edge_5");
    expect_reset_n(1'b1, "release_edge_6");

    // A low request crosses the two-stage synchronizer and asserts the
    // distributed reset on the third sampled edge.
    @(negedge core_clk_tb);
    rst_btn = 1'b0;
    expect_reset_n(1'b1, "assert_edge_1");
    expect_reset_n(1'b1, "assert_edge_2");
    expect_reset_n(1'b0, "assert_edge_3");

    $display("BOARD_RESET_QUALIFIER_PASS button_pulses_1_to_3_rejected=1 lock_pulses_1_to_3_rejected=1 chatter_rejected=1 release_edges=6 assertion_edges=3");
    $finish;
end

endmodule
