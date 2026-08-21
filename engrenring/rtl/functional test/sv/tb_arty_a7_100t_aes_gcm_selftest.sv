`timescale 1ns / 1ps

module tb_arty_a7_100t_aes_gcm_selftest;

reg clk = 1'b0;
reg aresetn = 1'b0;
always #2.857 clk = ~clk;

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
wire [7:0] stream_data;
wire stream_valid;
wire stream_ready;
wire stream_last;
wire [7:0] data_out;
wire data_valid;
wire data_last;
wire [3:0] data_user;
wire [7:0] tag_out;
wire tag_valid;
wire tag_last;
wire [7:0] result_out;
wire result_valid;
wire result_last;
wire running;
wire pass;
wire fail;

aes_gcm_board_selftest u_selftest (
    .clk(clk), .aresetn(aresetn),
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
    .running(running), .pass(pass), .fail(fail)
);

aes_gcm_axi_top u_dut (
    .aclk(clk), .aresetn(aresetn), .key_mode(3'd0),
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

integer cycles;
initial begin
    repeat(8) @(posedge clk);
    aresetn = 1'b1;
    cycles = 0;
    while(!pass && !fail && (cycles < 200000)) begin
        @(posedge clk);
        cycles = cycles + 1;
    end
    if(fail)
        $fatal(1, "ARTY_SELFTEST_FAIL cycles=%0d", cycles);
    if(!pass)
        $fatal(1, "ARTY_SELFTEST_TIMEOUT cycles=%0d", cycles);
    $display("ARTY_SELFTEST_PASS cycles=%0d", cycles);
    $finish;
end

endmodule
