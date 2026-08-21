`timescale 1ns / 1ps

module arty_a7_100t_aes_gcm_uart_rsp_top (
    input        clk,
    input        rst_btn,
    input        uart_txd_in,
    output       uart_rxd_out,
    output [3:0] led
);

wire mmcm_clkfb_raw;
wire mmcm_clkfb;
wire core_clk_raw;
wire core_clk;
wire mmcm_locked;
reg [3:0] reset_sync_r = 4'b0000;
reg [25:0] heartbeat_r = 26'd0;

MMCME2_BASE #(
    .BANDWIDTH("OPTIMIZED"),
    .CLKIN1_PERIOD(10.000),
    .CLKFBOUT_MULT_F(7.000),
    .DIVCLK_DIVIDE(1),
    .CLKOUT0_DIVIDE_F(4.000),
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE(0.0),
    .CLKFBOUT_PHASE(0.0),
    .REF_JITTER1(0.010),
    .STARTUP_WAIT("FALSE")
) u_mmcm (
    .CLKIN1(clk),
    .CLKFBIN(mmcm_clkfb),
    .RST(1'b0),
    .PWRDWN(1'b0),
    .CLKFBOUT(mmcm_clkfb_raw),
    .CLKOUT0(core_clk_raw),
    .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(mmcm_locked)
);

BUFG u_feedback_buf (.I(mmcm_clkfb_raw), .O(mmcm_clkfb));
BUFG u_core_clk_buf (.I(core_clk_raw), .O(core_clk));

// Keep all reset release and assertion synchronous to core_clk.  This avoids
// turning reset fanout into asynchronous controls on inferred S-box BRAMs.
always @(posedge core_clk)
begin
    if(!mmcm_locked || !rst_btn)
        reset_sync_r <= 4'b0000;
    else
        reset_sync_r <= {reset_sync_r[2:0], 1'b1};
end

always @(posedge core_clk)
begin
    if(!reset_sync_r[3])
        heartbeat_r <= 26'd0;
    else
        heartbeat_r <= heartbeat_r + 26'd1;
end

wire aresetn = reset_sync_r[3];
wire [2:0] key_mode;
wire [6:0] awaddr;
wire awvalid;
wire awready;
wire [31:0] wdata;
wire [3:0] wstrb;
wire wvalid;
wire wready;
wire [1:0] bresp;
wire bvalid;
wire bready;
wire [6:0] araddr;
wire arvalid;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
wire rready;
wire [7:0] s_data;
wire s_valid;
wire s_ready;
wire s_last;
wire [7:0] data_out;
wire data_valid;
wire data_ready;
wire data_last;
wire [3:0] data_user;
wire [7:0] tag_out;
wire tag_valid;
wire tag_ready;
wire tag_last;
wire [7:0] result_out;
wire result_valid;
wire result_ready;
wire result_last;
wire bridge_busy;
wire last_pass;
wire last_fail;

aes_gcm_uart_rsp_bridge #(
    .UART_CLKS_PER_BIT(1519)
) u_bridge (
    .clk(core_clk), .aresetn(aresetn),
    .uart_rx_i(uart_txd_in), .uart_tx_o(uart_rxd_out),
    .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid),
    .s_axi_awready(awready), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready), .s_axi_bresp(bresp),
    .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid),
    .s_axi_arready(arready), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid),
    .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user),
    .m_axis_tag_tdata(tag_out), .m_axis_tag_tvalid(tag_valid),
    .m_axis_tag_tready(tag_ready), .m_axis_tag_tlast(tag_last),
    .m_axis_result_tdata(result_out), .m_axis_result_tvalid(result_valid),
    .m_axis_result_tready(result_ready), .m_axis_result_tlast(result_last),
    .busy(bridge_busy), .last_pass(last_pass), .last_fail(last_fail)
);

aes_gcm_axi_top #(
    .ALLOW_NIST_TAG_LENGTHS(1'b1)
) u_aes_gcm (
    .aclk(core_clk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
    .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arprot(3'd0),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .s_axis_tdata(s_data),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid), .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

assign led[0] = heartbeat_r[25];
assign led[1] = bridge_busy && mmcm_locked;
assign led[2] = last_pass;
assign led[3] = last_fail || !mmcm_locked;

endmodule
