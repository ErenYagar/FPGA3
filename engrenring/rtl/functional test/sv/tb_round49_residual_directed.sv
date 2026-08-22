`timescale 1ns / 1ps

// VERIFY-ONLY public-port coverage for the Round49 residual timing cuts.
// This file is intentionally outside the formal regression directory.
// It uses no hierarchy references, force statements, or random stimulus.
module tb_round49_residual_directed;

localparam [1:0] OKAY = 2'b00;
localparam [7:0] RESULT_ENC_OK        = 8'h00;
localparam [7:0] RESULT_EARLY_TLAST  = 8'h10;
localparam [7:0] RESULT_ZEROIZE_ABORT= 8'h13;

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

integer cycles = 0;
integer data_count = 0;
integer data_last_count = 0;
integer tag_count = 0;
integer tag_last_count = 0;
integer result_count = 0;
integer result_last_count = 0;
integer event_count = 0;
integer timeout;
integer index;
reg [7:0] data_log [0:255];
reg       data_last_log [0:255];
reg [7:0] tag_log [0:127];
reg [7:0] result_log [0:15];
integer event_log [0:31];
reg guard_old_result = 1'b0;
reg guard_tag_stall = 1'b0;
reg [7:0] guard_tag_data;
reg guard_tag_last;
reg [7:0] stalled_data;
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
    cycles = cycles + 1;
    if(guard_old_result &&
       (!result_valid || result_out !== RESULT_ENC_OK || !result_last))
        $fatal(1, "OLD_ENC_OK_CHANGED valid=%b data=%02x last=%b",
               result_valid, result_out, result_last);
    if(guard_tag_stall &&
       (!tag_valid || tag_out !== guard_tag_data ||
        tag_last !== guard_tag_last || result_valid))
        $fatal(1, "TAG_STALL_CHANGED valid=%b data=%02x/%02x last=%b/%b result=%b",
               tag_valid, tag_out, guard_tag_data, tag_last, guard_tag_last,
               result_valid);

    if(data_valid && data_ready)
    begin
        data_log[data_count] = data_out;
        data_last_log[data_count] = data_last;
        data_count = data_count + 1;
        if(data_last)
            data_last_count = data_last_count + 1;
    end
    if(tag_valid && tag_ready)
    begin
        tag_log[tag_count] = tag_out;
        tag_count = tag_count + 1;
        if(tag_last)
        begin
            tag_last_count = tag_last_count + 1;
            event_log[event_count] = 1;
            event_count = event_count + 1;
        end
    end
    if(result_valid && result_ready)
    begin
        result_log[result_count] = result_out;
        result_count = result_count + 1;
        if(result_last)
            result_last_count = result_last_count + 1;
        event_log[event_count] = 2;
        event_count = event_count + 1;
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
    event_count = 0;
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

task automatic program_record;
input [10:0] data_bits;
input integer byte_count;
input early_last;
integer byte_index;
begin
    axi_write(7'h08, {16'd0, 8'd128, 7'd0, 1'b0});
    axi_write(7'h0c, 32'd96);
    axi_write(7'h10, 32'd0);
    axi_write(7'h14, {21'd0, data_bits});
    axi_write(7'h00, 32'h00000001);
    for(byte_index = 0; byte_index < 12; byte_index = byte_index + 1)
        send_byte(8'h00, 1'b0);
    for(byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
        send_byte(8'h00, early_last ? (byte_index == 0) :
                                      (byte_index == byte_count - 1));
end
endtask

task automatic wait_for_result;
input [7:0] expected;
input integer limit;
begin
    timeout = 0;
    while(!result_valid && timeout < limit)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!result_valid || result_out !== expected || !result_last)
        $fatal(1, "RESULT_WAIT expected=%02x valid=%b data=%02x last=%b",
               expected, result_valid, result_out, result_last);
end
endtask

initial
begin
    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;

    // Case 1/2: an older stalled ENC_OK must not retire the newer active
    // abort.  ZEROIZE of the subsequently stalled active abort result must
    // replace it with exactly one ZEROIZE_ABORT, not count it as detached.
    commit_zero_key();
    clear_capture();
    data_ready = 1'b1;
    tag_ready = 1'b1;
    result_ready = 1'b0;
    program_record(11'd8, 1, 1'b0);
    wait_for_result(RESULT_ENC_OK, 5000);
    guard_old_result = 1'b1;
    program_record(11'd128, 1, 1'b1);
    repeat(100) @(posedge aclk);
    if(!result_valid || result_out !== RESULT_ENC_OK || result_count != 0)
        $fatal(1, "OLDER_RESULT_NOT_HELD valid=%b data=%02x count=%0d",
               result_valid, result_out, result_count);

    @(negedge aclk);
    guard_old_result = 1'b0;
    result_ready = 1'b1;
    timeout = 0;
    while(result_count != 1 && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    @(negedge aclk);
    result_ready = 1'b0;
    if(result_count != 1 || result_log[0] !== RESULT_ENC_OK)
        $fatal(1, "OLDER_ENC_OK_HANDSHAKE count=%0d code=%02x",
               result_count, result_log[0]);
    wait_for_result(RESULT_EARLY_TLAST, 2000);
    stalled_data = result_out;
    stalled_last = result_last;
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || result_out !== stalled_data ||
           result_last !== stalled_last)
            $fatal(1, "ACTIVE_ABORT_STALL_CHANGED");
    end
    axi_write(7'h00, 32'h00000004);
    axi_write(7'h00, 32'h00000004);
    wait_for_result(RESULT_ZEROIZE_ABORT, 2000);
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || result_out !== RESULT_ZEROIZE_ABORT || !result_last)
            $fatal(1, "ZEROIZE_REPLACEMENT_STALL_CHANGED");
    end
    @(negedge aclk);
    result_ready = 1'b1;
    timeout = 0;
    while(result_count != 2 && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    @(negedge aclk);
    result_ready = 1'b0;
    repeat(40) @(posedge aclk);
    if(result_count != 2 || result_last_count != 2 ||
       result_log[0] !== RESULT_ENC_OK ||
       result_log[1] !== RESULT_ZEROIZE_ABORT || result_valid)
        $fatal(1, "ABORT_ZEROIZE_CARDINALITY count=%0d last=%0d r0=%02x r1=%02x valid=%b",
               result_count, result_last_count, result_log[0], result_log[1],
               result_valid);
    $display("ROUND49_DIRECTED_ABORT_TOKEN_PASS cycle=%0d", cycles);

    // Case 3: a 16-byte full block followed by a four-byte partial block.
    // Stall byte 16, then start a one-byte next record; the take event must
    // reset the deliberately stale modulo-16 index left by the partial pop.
    commit_zero_key();
    clear_capture();
    data_ready = 1'b0;
    tag_ready = 1'b1;
    result_ready = 1'b1;
    program_record(11'd160, 20, 1'b0);
    timeout = 0;
    while(!data_valid && timeout < 3000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!data_valid)
        $fatal(1, "FULL_PARTIAL_DATA_TIMEOUT");
    @(negedge aclk);
    data_ready = 1'b1;
    timeout = 0;
    while(data_count < 15 && timeout < 1000)
    begin
        @(negedge aclk);
        timeout = timeout + 1;
    end
    data_ready = 1'b0;
    timeout = 0;
    while(!data_valid && timeout < 100)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!data_valid || data_last)
        $fatal(1, "FULL_BLOCK_BYTE16_SETUP valid=%b last=%b count=%0d",
               data_valid, data_last, data_count);
    stalled_data = data_out;
    repeat(20)
    begin
        @(posedge aclk);
        if(!data_valid || data_out !== stalled_data || data_last)
            $fatal(1, "FULL_BLOCK_BYTE16_STALL_CHANGED");
    end
    @(negedge aclk);
    data_ready = 1'b1;
    timeout = 0;
    while((data_count != 20 || data_last_count != 1 ||
           tag_last_count != 1 || result_count != 1) && timeout < 5000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(data_count != 20 || data_last_count != 1 ||
       tag_count != 16 || tag_last_count != 1 ||
       result_count != 1 || result_log[0] !== RESULT_ENC_OK)
        $fatal(1, "FULL_PARTIAL_COUNTS data=%0d/%0d tag=%0d/%0d result=%0d/%02x",
               data_count, data_last_count, tag_count, tag_last_count,
               result_count, result_log[0]);
    for(index = 0; index < 19; index = index + 1)
        if(data_last_log[index])
            $fatal(1, "EARLY_CT_TLAST index=%0d", index);
    if(!data_last_log[19])
        $fatal(1, "MISSING_PARTIAL_CT_TLAST");

    repeat(20) @(posedge aclk);
    clear_capture();
    data_ready = 1'b0;
    program_record(11'd8, 1, 1'b0);
    timeout = 0;
    while(!data_valid && timeout < 3000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!data_valid || !data_last || data_out !== 8'h03)
        $fatal(1, "NEXT_RECORD_INDEX_NOT_RESET valid=%b last=%b data=%02x",
               data_valid, data_last, data_out);
    stalled_data = data_out;
    repeat(10)
    begin
        @(posedge aclk);
        if(!data_valid || !data_last || data_out !== stalled_data)
            $fatal(1, "ONE_BYTE_NEXT_RECORD_STALL_CHANGED");
    end
    @(negedge aclk);
    data_ready = 1'b1;
    timeout = 0;
    while((data_count != 1 || tag_last_count != 1 || result_count != 1) &&
          timeout < 5000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(data_count != 1 || data_last_count != 1 || data_log[0] !== 8'h03 ||
       tag_count != 16 || tag_last_count != 1 || result_count != 1 ||
       result_log[0] !== RESULT_ENC_OK)
        $fatal(1, "NEXT_RECORD_COUNTS data=%0d/%02x tag=%0d result=%0d/%02x",
               data_count, data_log[0], tag_count, result_count, result_log[0]);
    $display("ROUND49_DIRECTED_CT_INDEX_PASS cycle=%0d", cycles);

    // Case 4: queue the next descriptor/input while the first public tag
    // byte is stalled.  The second ciphertext is correctly held until the
    // old tag/result retire.  Draining with deterministic stalls exercises
    // byte-FIFO replacement and proves TAG1, RESULT1, TAG2, RESULT2 ordering.
    repeat(20) @(posedge aclk);
    clear_capture();
    data_ready = 1'b1;
    tag_ready = 1'b0;
    result_ready = 1'b1;
    program_record(11'd8, 1, 1'b0);
    timeout = 0;
    while(!tag_valid && timeout < 5000)
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(!tag_valid)
        $fatal(1, "FIRST_TAG_STALL_TIMEOUT");
    guard_tag_data = tag_out;
    guard_tag_last = tag_last;
    guard_tag_stall = 1'b1;
    program_record(11'd8, 1, 1'b0);
    repeat(300) @(posedge aclk);
    if(!tag_valid || result_count != 0 || data_count != 1)
        $fatal(1, "TAG_REPLACEMENT_PRECONDITION tag=%b result=%0d data=%0d",
               tag_valid, result_count, data_count);
    @(negedge aclk);
    guard_tag_stall = 1'b0;
    timeout = 0;
    while((tag_last_count != 2 || result_count != 2) && timeout < 8000)
    begin
        tag_ready = ((timeout % 5) != 1) && ((timeout % 5) != 2);
        @(negedge aclk);
        timeout = timeout + 1;
    end
    tag_ready = 1'b0;
    repeat(30) @(posedge aclk);
    if(tag_count != 32 || tag_last_count != 2 ||
       result_count != 2 || result_last_count != 2 ||
       result_log[0] !== RESULT_ENC_OK || result_log[1] !== RESULT_ENC_OK ||
       event_count != 4 || event_log[0] != 1 || event_log[1] != 2 ||
       event_log[2] != 1 || event_log[3] != 2 ||
       data_count != 2 || data_last_count != 2 || tag_valid || result_valid)
        $fatal(1, "TAG_REPLACEMENT_ORDER tag=%0d/%0d result=%0d/%0d events=%0d:%0d,%0d,%0d,%0d data=%0d/%0d",
               tag_count, tag_last_count, result_count, result_last_count,
               event_count, event_log[0], event_log[1], event_log[2],
               event_log[3], data_count, data_last_count);
    $display("ROUND49_DIRECTED_TAG_REPLACEMENT_PASS cycle=%0d", cycles);
    $display("ROUND49_RESIDUAL_DIRECTED_PASS cycles=%0d", cycles);
    $finish;
end

initial
begin
    #20000000;
    $fatal(1, "ROUND49_DIRECTED_GLOBAL_TIMEOUT");
end

endmodule
