`timescale 1ns / 1ps

// Arty A7-100T board top.  LED0=heartbeat, LED1=running,
// LED2=known-answer PASS, LED3=FAIL (or MMCM not locked).
module arty_a7_100t_aes_gcm_selftest_top (
    input  wire       clk,
    input  wire       rst_btn,
    output wire [3:0] led
);

wire core_clk_mmcm;
wire core_clk;
wire mmcm_clkfb_raw;
wire mmcm_clkfb;
wire mmcm_locked;
reg [3:0] reset_sync_r = 4'b0000;
reg [27:0] heartbeat_r;

MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(10.000),
    .DIVCLK_DIVIDE(1),
    .CLKFBOUT_MULT_F(7.0),
    .CLKOUT0_DIVIDE_F(4.0),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0.0),
    .STARTUP_WAIT("FALSE")
) u_mmcm (
    .CLKIN1(clk),
    .CLKFBIN(mmcm_clkfb),
    .RST(~rst_btn),
    .PWRDWN(1'b0),
    .CLKFBOUT(mmcm_clkfb_raw),
    .CLKOUT0(core_clk_mmcm),
    .LOCKED(mmcm_locked),
    .CLKFBOUTB(),
    .CLKOUT0B(),
    .CLKOUT1(),
    .CLKOUT1B(),
    .CLKOUT2(),
    .CLKOUT2B(),
    .CLKOUT3(),
    .CLKOUT3B(),
    .CLKOUT4(),
    .CLKOUT5(),
    .CLKOUT6()
);

BUFG u_feedback_buf (.I(mmcm_clkfb_raw), .O(mmcm_clkfb));
BUFG u_core_clk_buf (.I(core_clk_mmcm), .O(core_clk));

// Keep the reset delivered to the AES core fully synchronous.  In
// particular, an asynchronously reset synchronizer FF must not feed the
// reset pins of the inferred S-box RAMBs (Vivado REQP-1840).
always @(posedge core_clk)
begin
    if(!mmcm_locked || !rst_btn)
        reset_sync_r <= 4'b0000;
    else
        reset_sync_r <= {reset_sync_r[2:0], 1'b1};
end

wire aresetn = reset_sync_r[3];

always @(posedge core_clk)
begin
    if(!aresetn)
        heartbeat_r <= 28'd0;
    else
        heartbeat_r <= heartbeat_r + 28'd1;
end

wire [6:0]  awaddr;
wire        awvalid;
wire        awready;
wire [31:0] wdata;
wire [3:0]  wstrb;
wire        wvalid;
wire        wready;
wire [1:0]  bresp;
wire        bvalid;
wire        bready;
wire [7:0]  stream_data;
wire        stream_valid;
wire        stream_ready;
wire        stream_last;
wire [7:0]  data_out;
wire        data_valid;
wire        data_last;
wire [3:0]  data_user;
wire [7:0]  tag_out;
wire        tag_valid;
wire        tag_last;
wire [7:0]  result_out;
wire        result_valid;
wire        result_last;
wire        selftest_running;
wire        selftest_pass;
wire        selftest_fail;

aes_gcm_board_selftest u_selftest (
    .clk(core_clk), .aresetn(aresetn),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
    .s_axi_awready(awready), .s_axi_wdata(wdata),
    .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
    .s_axi_wready(wready), .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axis_tdata(stream_data), .s_axis_tvalid(stream_valid),
    .s_axis_tready(stream_ready), .s_axis_tlast(stream_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tlast(data_last), .m_axis_data_tuser(data_user),
    .m_axis_tag_tdata(tag_out), .m_axis_tag_tvalid(tag_valid),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid), .m_axis_result_tlast(result_last),
    .running(selftest_running), .pass(selftest_pass), .fail(selftest_fail)
);

aes_gcm_axi_top u_aes_gcm (
    .aclk(core_clk), .aresetn(aresetn), .key_mode(3'd0),
    .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(7'd0), .s_axi_arprot(3'd0), .s_axi_arvalid(1'b0),
    .s_axi_arready(), .s_axi_rdata(), .s_axi_rresp(),
    .s_axi_rvalid(), .s_axi_rready(1'b0),
    .s_axis_tdata(stream_data), .s_axis_tvalid(stream_valid),
    .s_axis_tready(stream_ready), .s_axis_tlast(stream_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(1'b1), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(1'b1),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid), .m_axis_result_tready(1'b1),
    .m_axis_result_tlast(result_last)
);

assign led[0] = heartbeat_r[25];
assign led[1] = selftest_running && mmcm_locked;
assign led[2] = selftest_pass;
assign led[3] = selftest_fail || !mmcm_locked;

endmodule
