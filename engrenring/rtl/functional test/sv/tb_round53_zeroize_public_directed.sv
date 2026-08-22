`timescale 1ns / 1ps

// Round53 public-interface ZEROIZE cardinality check.  This test deliberately
// uses only AXI-Lite and AXI-Stream ports; it makes no hierarchy accesses.
module tb_round53_zeroize_public_directed;

localparam [1:0] OKAY = 2'b00;
localparam [7:0] RESULT_ZEROIZE_ABORT = 8'h13;

reg aclk = 1'b0;
always #2.857 aclk = ~aclk;

reg aresetn = 1'b0;
reg [2:0] key_mode = 3'd0;

reg [6:0] awaddr = 7'd0;
reg [2:0] awprot = 3'd0;
reg awvalid = 1'b0;
wire awready;
reg [31:0] wdata = 32'd0;
reg [3:0] wstrb = 4'd0;
reg wvalid = 1'b0;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready = 1'b0;

reg [6:0] araddr = 7'd0;
reg [2:0] arprot = 3'd0;
reg arvalid = 1'b0;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready = 1'b0;

reg [7:0] s_axis_tdata = 8'd0;
reg s_axis_tvalid = 1'b0;
wire s_axis_tready;
reg s_axis_tlast = 1'b0;

wire [7:0] m_axis_data_tdata;
wire m_axis_data_tvalid;
reg m_axis_data_tready = 1'b1;
wire m_axis_data_tlast;
wire [3:0] m_axis_data_tuser;

wire [7:0] m_axis_tag_tdata;
wire m_axis_tag_tvalid;
reg m_axis_tag_tready = 1'b1;
wire m_axis_tag_tlast;

wire [7:0] m_axis_result_tdata;
wire m_axis_result_tvalid;
reg m_axis_result_tready = 1'b1;
wire m_axis_result_tlast;

integer result_count = 0;
integer result_last_count = 0;
integer data_count = 0;
integer tag_count = 0;
integer timeout;
reg [7:0] result_history [0:3];
reg [31:0] status_word = 32'd0;

aes_gcm_axi_top dut (
    .aclk(aclk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready), .s_axi_araddr(araddr),
    .s_axi_arprot(arprot), .s_axi_arvalid(arvalid),
    .s_axi_arready(arready), .s_axi_rdata(rdata),
    .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    .m_axis_data_tdata(m_axis_data_tdata),
    .m_axis_data_tvalid(m_axis_data_tvalid),
    .m_axis_data_tready(m_axis_data_tready),
    .m_axis_data_tlast(m_axis_data_tlast),
    .m_axis_data_tuser(m_axis_data_tuser),
    .m_axis_tag_tdata(m_axis_tag_tdata),
    .m_axis_tag_tvalid(m_axis_tag_tvalid),
    .m_axis_tag_tready(m_axis_tag_tready),
    .m_axis_tag_tlast(m_axis_tag_tlast),
    .m_axis_result_tdata(m_axis_result_tdata),
    .m_axis_result_tvalid(m_axis_result_tvalid),
    .m_axis_result_tready(m_axis_result_tready),
    .m_axis_result_tlast(m_axis_result_tlast)
);

always @(posedge aclk)
begin
    if(m_axis_data_tvalid && m_axis_data_tready)
        data_count = data_count + 1;
    if(m_axis_tag_tvalid && m_axis_tag_tready)
        tag_count = tag_count + 1;
    if(m_axis_result_tvalid && m_axis_result_tready)
    begin
        if(result_count < 4)
            result_history[result_count] = m_axis_result_tdata;
        result_count = result_count + 1;
        if(m_axis_result_tlast)
            result_last_count = result_last_count + 1;
    end
end

task automatic axi_write;
input [6:0] address;
input [31:0] value;
reg aw_done;
reg w_done;
begin
    @(negedge aclk);
    awaddr = address;
    awvalid = 1'b1;
    wdata = value;
    wstrb = 4'hf;
    wvalid = 1'b1;
    bready = 1'b1;
    aw_done = 1'b0;
    w_done = 1'b0;
    while(!(aw_done && w_done))
    begin
        @(posedge aclk);
        if(awvalid && awready)
            aw_done = 1'b1;
        if(wvalid && wready)
            w_done = 1'b1;
        @(negedge aclk);
        if(aw_done)
            awvalid = 1'b0;
        if(w_done)
            wvalid = 1'b0;
    end
    while(!bvalid)
        @(posedge aclk);
    if(bresp !== OKAY)
        $fatal(1, "AXI_WRITE_RESPONSE addr=%02x resp=%b", address, bresp);
    @(negedge aclk);
    bready = 1'b0;
end
endtask

task automatic axi_read;
input [6:0] address;
output [31:0] value;
begin
    @(negedge aclk);
    araddr = address;
    arvalid = 1'b1;
    rready = 1'b1;
    while(!(arvalid && arready))
        @(posedge aclk);
    @(negedge aclk);
    arvalid = 1'b0;
    while(!rvalid)
        @(posedge aclk);
    if(rresp !== OKAY)
        $fatal(1, "AXI_READ_RESPONSE addr=%02x resp=%b", address, rresp);
    value = rdata;
    @(negedge aclk);
    rready = 1'b0;
end
endtask

task automatic wait_status_bit;
input integer bit_index;
input expected_value;
begin
    timeout = 0;
    status_word = 32'd0;
    while((status_word[bit_index] !== expected_value) && timeout < 2000)
    begin
        axi_read(7'h04, status_word);
        timeout = timeout + 1;
    end
    if(status_word[bit_index] !== expected_value)
        $fatal(1, "STATUS_TIMEOUT bit=%0d expected=%b status=%08x",
               bit_index, expected_value, status_word);
end
endtask

task automatic commit_zero_key;
begin
    axi_write(7'h20, 32'd0);
    axi_write(7'h24, 32'd0);
    axi_write(7'h28, 32'd0);
    axi_write(7'h2c, 32'd0);
    axi_write(7'h00, 32'h00000002);
    wait_status_bit(0, 1'b1);
end
endtask

task automatic program_waiting_record;
begin
    // Encrypt, 128-bit tag, 96-bit IV, no AAD and no payload.  Do not send
    // the IV: the first descriptor remains active while the second queues.
    axi_write(7'h08, {16'd0, 8'd128, 7'd0, 1'b0});
    axi_write(7'h0c, 32'd96);
    axi_write(7'h10, 32'd0);
    axi_write(7'h14, 32'd0);
    axi_write(7'h00, 32'h00000001);
end
endtask

initial
begin
    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;

    // An idle ZEROIZE has no accepted descriptor credit and therefore must
    // emit no abort result.  Repeating it during scrub remains idempotent.
    axi_write(7'h00, 32'h00000004);
    axi_write(7'h00, 32'h00000004);
    repeat(64) @(posedge aclk);
    @(negedge aclk);
    if(result_count != 0 || result_last_count != 0 ||
       m_axis_result_tvalid || data_count != 0 || tag_count != 0)
        $fatal(1,
               "IDLE_ZEROIZE_CARDINALITY results=%0d lasts=%0d valid=%b data=%0d tag=%0d",
               result_count, result_last_count, m_axis_result_tvalid,
               data_count, tag_count);

    commit_zero_key();
    program_waiting_record();
    wait_status_bit(3, 1'b1);
    program_waiting_record();
    // STATUS exposes FIFO-full, not FIFO-pending.  The second command's OKAY
    // BRESP above is the public proof that its descriptor was accepted.

    // Both successful CMD_PUSH writes own a response credit.  Preserve the
    // first 0x13 under backpressure, repeat ZEROIZE, then require exactly two
    // public handshakes and no stale data or tag output.
    m_axis_result_tready = 1'b0;
    axi_write(7'h00, 32'h00000004);
    axi_write(7'h00, 32'h00000004);

    timeout = 0;
    while(!m_axis_result_tvalid && timeout < 400)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!m_axis_result_tvalid ||
       (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
       !m_axis_result_tlast)
        $fatal(1,
               "PUBLIC_ZEROIZE_ABORT_NOT_STAGED cycles=%0d valid=%b data=%02x last=%b",
               timeout, m_axis_result_tvalid, m_axis_result_tdata,
               m_axis_result_tlast);

    repeat(4)
    begin
        @(posedge aclk);
        #1;
        if(!m_axis_result_tvalid ||
           (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
           !m_axis_result_tlast || (result_count != 0))
            $fatal(1,
                   "PUBLIC_ZEROIZE_STALL_CHANGED valid=%b data=%02x last=%b count=%0d",
                   m_axis_result_tvalid, m_axis_result_tdata,
                   m_axis_result_tlast, result_count);
    end

    @(negedge aclk);
    m_axis_result_tready = 1'b1;
    timeout = 0;
    while(result_count < 2 && timeout < 400)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    repeat(32) @(posedge aclk);
    @(negedge aclk);

    if(result_count != 2 || result_last_count != 2 ||
       (result_history[0] !== RESULT_ZEROIZE_ABORT) ||
       (result_history[1] !== RESULT_ZEROIZE_ABORT) ||
       m_axis_result_tvalid || data_count != 0 || tag_count != 0)
        $fatal(1,
               "PUBLIC_ZEROIZE_CARDINALITY results=%0d lasts=%0d r0=%02x r1=%02x valid=%b data=%0d tag=%0d",
               result_count, result_last_count, result_history[0],
               result_history[1], m_axis_result_tvalid,
               data_count, tag_count);

    axi_read(7'h04, status_word);
    if(status_word[0] || status_word[3] || status_word[4] || status_word[5])
        $fatal(1, "PUBLIC_ZEROIZE_FINAL_STATUS status=%08x", status_word);

    $display("ROUND53_PUBLIC_ZEROIZE_PASS idle_results=0 accepted=2 abort_results=2");
    $finish;
end

endmodule
