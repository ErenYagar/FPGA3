`timescale 1ns / 1ps

// VERIFY-ONLY directed coverage for the Round48 public-boundary idle tokens.
// This test uses public AXI-Lite/AXI-Stream ports only.  It is intentionally
// outside the formal regression directory and makes no hierarchy accesses.
module tb_round48_boundary_directed;

localparam [1:0] OKAY = 2'b00;
localparam [7:0] RESULT_ENC_OK = 8'h00;
localparam [7:0] RESULT_ZEROIZE_ABORT = 8'h13;
localparam [127:0] ZERO_KAT_CT  = 128'h0388dace60b6a392f328c2b971b2fe78;
localparam [127:0] ZERO_KAT_TAG = 128'hab6e47d42cec13bdf53a67b21257bddf;

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

reg [7:0] s_data = 8'd0;
reg s_valid = 1'b0;
wire s_ready;
reg s_last = 1'b0;

wire [7:0] data_out;
wire data_valid;
reg data_ready = 1'b1;
wire data_last;
wire [3:0] data_user;

wire [7:0] tag_out;
wire tag_valid;
reg tag_ready = 1'b0;
wire tag_last;

wire [7:0] result_out;
wire result_valid;
reg result_ready = 1'b0;
wire result_last;

integer cycle_count = 0;
integer data_count = 0;
integer data_last_count = 0;
integer tag_count = 0;
integer tag_last_count = 0;
integer result_count = 0;
integer result_last_count = 0;
integer timeout;
reg [127:0] captured_data = 128'd0;
reg [127:0] captured_tag = 128'd0;
reg [7:0] captured_result = 8'hff;
reg [7:0] stalled_value;
reg stalled_last;
reg [31:0] status_word;

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
    .s_axi_rready(rready), .s_axis_tdata(s_data),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tlast(s_last), .m_axis_data_tdata(data_out),
    .m_axis_data_tvalid(data_valid), .m_axis_data_tready(data_ready),
    .m_axis_data_tlast(data_last), .m_axis_data_tuser(data_user),
    .m_axis_tag_tdata(tag_out), .m_axis_tag_tvalid(tag_valid),
    .m_axis_tag_tready(tag_ready), .m_axis_tag_tlast(tag_last),
    .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid),
    .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

always @(posedge aclk)
begin
    cycle_count = cycle_count + 1;
    if(data_valid && data_ready)
    begin
        captured_data = {captured_data[119:0], data_out};
        data_count = data_count + 1;
        if(data_last)
            data_last_count = data_last_count + 1;
    end
    if(tag_valid && tag_ready)
    begin
        captured_tag = {captured_tag[119:0], tag_out};
        tag_count = tag_count + 1;
        if(tag_last)
            tag_last_count = tag_last_count + 1;
    end
    if(result_valid && result_ready)
    begin
        captured_result = result_out;
        result_count = result_count + 1;
        if(result_last)
            result_last_count = result_last_count + 1;
    end
end

task automatic clear_capture;
begin
    @(negedge aclk);
    data_count = 0;
    data_last_count = 0;
    tag_count = 0;
    tag_last_count = 0;
    result_count = 0;
    result_last_count = 0;
    captured_data = 128'd0;
    captured_tag = 128'd0;
    captured_result = 8'hff;
end
endtask

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
        $fatal(1, "WRITE_RESP addr=%02x resp=%b", address, bresp);
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
        $fatal(1, "READ_RESP addr=%02x resp=%b", address, rresp);
    value = rdata;
    @(negedge aclk);
    rready = 1'b0;
end
endtask

task automatic send_byte;
input [7:0] value;
input last_byte;
begin
    @(negedge aclk);
    s_data = value;
    s_last = last_byte;
    s_valid = 1'b1;
    while(!(s_valid && s_ready))
        @(posedge aclk);
    @(negedge aclk);
    s_valid = 1'b0;
    s_last = 1'b0;
end
endtask

task automatic commit_zero_key;
begin
    axi_write(7'h20, 32'd0);
    axi_write(7'h24, 32'd0);
    axi_write(7'h28, 32'd0);
    axi_write(7'h2c, 32'd0);
    axi_write(7'h00, 32'h00000002);
    status_word = 32'd0;
    timeout = 0;
    while(!status_word[0] && timeout < 1000)
    begin
        axi_read(7'h04, status_word);
        timeout = timeout + 1;
    end
    if(!status_word[0])
        $fatal(1, "KEY_READY_TIMEOUT");
end
endtask

task automatic program_zero_block_record;
integer index;
begin
    axi_write(7'h08, {16'd0, 8'd128, 7'd0, 1'b0});
    axi_write(7'h0c, 32'd96);
    axi_write(7'h10, 32'd0);
    axi_write(7'h14, 32'd128);
    axi_write(7'h00, 32'h00000001);
    for(index = 0; index < 12; index = index + 1)
        send_byte(8'h00, 1'b0);
    for(index = 0; index < 16; index = index + 1)
        send_byte(8'h00, index == 15);
end
endtask

initial
begin
    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;

    // Case 1: ZEROIZE must synchronously discard a stalled tag.  Repeating
    // ZEROIZE during the scrub must not duplicate the owed abort result.
    commit_zero_key();
    clear_capture();
    tag_ready = 1'b0;
    result_ready = 1'b0;
    program_zero_block_record();

    timeout = 0;
    while(!tag_valid && timeout < 4000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!tag_valid)
        $fatal(1, "STALLED_TAG_TIMEOUT");
    stalled_value = tag_out;
    stalled_last = tag_last;
    repeat(20)
    begin
        @(posedge aclk);
        if(!tag_valid || tag_out !== stalled_value || tag_last !== stalled_last ||
           result_valid)
            $fatal(1,
                   "STALLED_TAG_CHANGED valid=%b data=%02x/%02x last=%b/%b result=%b",
                   tag_valid, tag_out, stalled_value, tag_last, stalled_last,
                   result_valid);
    end

    axi_write(7'h00, 32'h00000004);
    axi_write(7'h00, 32'h00000004);
    repeat(2) @(posedge aclk);
    if(tag_valid || tag_count != 0 || tag_last_count != 0)
        $fatal(1, "ZEROIZE_TAG_NOT_CLEARED valid=%b count=%0d lasts=%0d",
               tag_valid, tag_count, tag_last_count);

    timeout = 0;
    while(!result_valid && timeout < 1000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
        if(tag_valid)
            $fatal(1, "ZEROIZE_TAG_REAPPEARED");
    end
    if(!result_valid || result_out !== RESULT_ZEROIZE_ABORT || !result_last)
        $fatal(1, "ZEROIZE_ABORT_NOT_PRESENT valid=%b data=%02x last=%b",
               result_valid, result_out, result_last);
    stalled_value = result_out;
    stalled_last = result_last;
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || result_out !== stalled_value ||
           result_last !== stalled_last || tag_valid)
            $fatal(1,
                   "ZEROIZE_ABORT_STALL_CHANGED valid=%b data=%02x last=%b tag=%b",
                   result_valid, result_out, result_last, tag_valid);
    end
    @(negedge aclk);
    result_ready = 1'b1;
    timeout = 0;
    while(result_count != 1 && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    @(negedge aclk);
    result_ready = 1'b0;
    repeat(20) @(posedge aclk);
    if(result_count != 1 || result_last_count != 1 ||
       captured_result !== RESULT_ZEROIZE_ABORT || result_valid || tag_valid)
        $fatal(1,
               "ZEROIZE_ABORT_CARDINALITY count=%0d lasts=%0d data=%02x valid=%b tag=%b",
               result_count, result_last_count, captured_result, result_valid,
               tag_valid);
    axi_read(7'h04, status_word);
    if(status_word[0] || status_word[5])
        $fatal(1, "ZEROIZE_STATUS status=%08x", status_word);
    $display("ROUND48_DIRECTED_CASE1_PASS cycle=%0d", cycle_count);

    // Case 2: fill/stall the two-entry tag boundary, then pause specifically
    // on its final TLAST.  ENC_OK may appear only after that final handshake
    // and must remain stable while RESULT_TREADY is low.
    commit_zero_key();
    clear_capture();
    tag_ready = 1'b0;
    result_ready = 1'b0;
    program_zero_block_record();
    timeout = 0;
    while(!tag_valid && timeout < 4000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!tag_valid)
        $fatal(1, "TAG_FILL_TIMEOUT");
    repeat(20)
    begin
        @(posedge aclk);
        if(!tag_valid || result_valid)
            $fatal(1, "TAG_FILL_STALL_ERROR tag=%b result=%b", tag_valid,
                   result_valid);
    end

    @(negedge aclk);
    tag_ready = 1'b1;
    timeout = 0;
    while(tag_count < 15 && timeout < 1000)
    begin
        @(negedge aclk);
        timeout = timeout + 1;
    end
    tag_ready = 1'b0;
    timeout = 0;
    while((!tag_valid || !tag_last) && timeout < 1000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!tag_valid || !tag_last || tag_count != 15 || result_valid)
        $fatal(1,
               "FINAL_TAG_STALL_SETUP valid=%b last=%b count=%0d result=%b",
               tag_valid, tag_last, tag_count, result_valid);
    stalled_value = tag_out;
    repeat(20)
    begin
        @(posedge aclk);
        if(!tag_valid || !tag_last || tag_out !== stalled_value || result_valid)
            $fatal(1,
                   "FINAL_TAG_STALL_CHANGED valid=%b last=%b data=%02x/%02x result=%b",
                   tag_valid, tag_last, tag_out, stalled_value, result_valid);
    end

    @(negedge aclk);
    tag_ready = 1'b1;
    timeout = 0;
    while(tag_count != 16 && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    @(negedge aclk);
    tag_ready = 1'b0;
    timeout = 0;
    while(!result_valid && timeout < 1000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!result_valid || result_out !== RESULT_ENC_OK || !result_last)
        $fatal(1, "ENC_OK_NOT_STALLED valid=%b data=%02x last=%b",
               result_valid, result_out, result_last);
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || result_out !== RESULT_ENC_OK || !result_last ||
           tag_valid || data_valid)
            $fatal(1,
                   "ENC_OK_STALL_CHANGED valid=%b data=%02x last=%b tag=%b output=%b",
                   result_valid, result_out, result_last, tag_valid, data_valid);
    end
    @(negedge aclk);
    result_ready = 1'b1;
    timeout = 0;
    while(result_count != 1 && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    repeat(10) @(posedge aclk);
    if(result_count != 1 || result_last_count != 1 ||
       captured_result !== RESULT_ENC_OK || data_count != 16 ||
       data_last_count != 1 || captured_data !== ZERO_KAT_CT ||
       tag_count != 16 || tag_last_count != 1 ||
       captured_tag !== ZERO_KAT_TAG)
        $fatal(1,
               "FINAL_TAG_RESULT_ERROR result=%0d/%02x data=%0d/%032x tag=%0d/%032x",
               result_count, captured_result, data_count, captured_data,
               tag_count, captured_tag);
    $display("ROUND48_DIRECTED_CASE2_PASS cycle=%0d", cycle_count);
    $display("ROUND48_BOUNDARY_DIRECTED_PASS cycles=%0d", cycle_count);
    $finish;
end

initial
begin
    #5000000;
    $fatal(1, "ROUND48_DIRECTED_GLOBAL_TIMEOUT");
end

endmodule
