`timescale 1ns / 1ps

// Round53 direct-core security regression for ZEROIZE during a live GHASH.
// The descriptor uses a 128-bit IV, so it cannot take the 96-bit fast path.
// The test waits for the verification-only observation dut.ghash_busy before
// pulsing ZEROIZE; all pass/fail output checks use the core's public ports.
module tb_round53_non96_ghash_zeroize_directed;

localparam [7:0] RESULT_ZEROIZE_ABORT = 8'h13;

reg clk = 1'b0;
always #2.5 clk = ~clk;

reg rst_n = 1'b0;
reg key_commit = 1'b0;
reg zeroize = 1'b0;
reg [2:0] key_mode = 3'd0;
reg [255:0] key_data = 256'd0;
wire key_ready;
wire key_busy;
wire key_quiescent;

reg cmd_push = 1'b0;
reg cmd_decrypt = 1'b0;
reg [7:0] cmd_tag_bits = 8'd128;
reg [10:0] cmd_iv_bits = 11'd128;
reg [10:0] cmd_aad_bits = 11'd0;
reg [10:0] cmd_data_bits = 11'd0;
wire cmd_full;
wire cmd_pending;
wire record_active;
wire output_pending;
wire zeroize_busy;
wire zeroize_defer;

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
reg m_axis_result_tready = 1'b0;
wire m_axis_result_tlast;

integer data_fire_count = 0;
integer tag_fire_count = 0;
integer result_fire_count = 0;
integer result_last_count = 0;
integer input_fire_count = 0;
integer timeout;
integer index;
reg [7:0] captured_result = 8'hff;
reg saw_live_non96_ghash = 1'b0;

aes_gcm_stream_core dut (
    .clk(clk), .rst_n(rst_n), .key_commit(key_commit),
    .zeroize(zeroize), .key_mode(key_mode), .key_data(key_data),
    .key_ready(key_ready), .key_busy(key_busy),
    .key_quiescent(key_quiescent), .cmd_push(cmd_push),
    .cmd_decrypt(cmd_decrypt), .cmd_tag_bits(cmd_tag_bits),
    .cmd_iv_bits(cmd_iv_bits), .cmd_aad_bits(cmd_aad_bits),
    .cmd_data_bits(cmd_data_bits), .cmd_full(cmd_full),
    .cmd_pending(cmd_pending), .record_active(record_active),
    .output_pending(output_pending), .zeroize_busy(zeroize_busy),
    .zeroize_defer(zeroize_defer), .s_axis_tdata(s_axis_tdata),
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

always @(posedge clk)
begin
    if(s_axis_tvalid && s_axis_tready)
        input_fire_count = input_fire_count + 1;
    if(m_axis_data_tvalid && m_axis_data_tready)
        data_fire_count = data_fire_count + 1;
    if(m_axis_tag_tvalid && m_axis_tag_tready)
        tag_fire_count = tag_fire_count + 1;
    if(m_axis_result_tvalid && m_axis_result_tready)
    begin
        captured_result = m_axis_result_tdata;
        result_fire_count = result_fire_count + 1;
        if(m_axis_result_tlast)
            result_last_count = result_last_count + 1;
    end
end

task automatic pulse_key_commit;
begin
    @(negedge clk);
    key_commit = 1'b1;
    @(posedge clk);
    @(negedge clk);
    key_commit = 1'b0;
end
endtask

task automatic push_record;
begin
    if(cmd_full)
        $fatal(1, "NON96_DESCRIPTOR_FIFO_FULL");
    @(negedge clk);
    cmd_push = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cmd_push = 1'b0;
end
endtask

task automatic send_iv_byte;
input [7:0] value;
input last_byte;
begin
    @(negedge clk);
    s_axis_tdata = value;
    s_axis_tlast = last_byte;
    s_axis_tvalid = 1'b1;
    timeout = 0;
    while(!(s_axis_tvalid && s_axis_tready) && timeout < 500)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!(s_axis_tvalid && s_axis_tready))
        $fatal(1, "NON96_INPUT_TIMEOUT index=%0d", input_fire_count);
    @(negedge clk);
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
end
endtask

initial
begin
    repeat(8) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    pulse_key_commit();
    timeout = 0;
    while(!key_ready && timeout < 4000)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!key_ready || key_busy)
        $fatal(1, "NON96_KEY_READY_TIMEOUT cycles=%0d busy=%b",
               timeout, key_busy);

    push_record();
    timeout = 0;
    while(!record_active && timeout < 200)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!record_active)
        $fatal(1, "NON96_RECORD_ACTIVE_TIMEOUT pending=%b", cmd_pending);

    for(index = 0; index < 16; index = index + 1)
        send_iv_byte(index[7:0], index == 15);
    if(input_fire_count != 16)
        $fatal(1, "NON96_INPUT_CARDINALITY count=%0d", input_fire_count);

    // Verification-only proof that this is the requested mid-operation
    // collision, rather than a ZEROIZE before GHASH starts or after it ends.
    timeout = 0;
    while(!dut.ghash_busy && timeout < 100)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!dut.ghash_busy || !record_active || (cmd_iv_bits == 11'd96))
        $fatal(1,
               "NON96_GHASH_NOT_ACTIVE cycles=%0d ghash_busy=%b active=%b iv_bits=%0d",
               timeout, dut.ghash_busy, record_active, cmd_iv_bits);

    @(negedge clk);
    if(!dut.ghash_busy)
        $fatal(1, "NON96_GHASH_ENDED_BEFORE_ZEROIZE_PULSE");
    saw_live_non96_ghash = 1'b1;
    zeroize = 1'b1;
    @(posedge clk);
    @(negedge clk);
    zeroize = 1'b0;

    if(!zeroize_busy || key_ready || record_active || dut.ghash_busy)
        $fatal(1,
               "NON96_ZEROIZE_DID_NOT_CLEAR busy=%b key=%b active=%b ghash=%b",
               zeroize_busy, key_ready, record_active, dut.ghash_busy);
    if(m_axis_data_tvalid || m_axis_tag_tvalid || m_axis_result_tvalid)
        $fatal(1,
               "NON96_STALE_VALID_AT_ZEROIZE data=%b tag=%b result=%b",
               m_axis_data_tvalid, m_axis_tag_tvalid,
               m_axis_result_tvalid);

    timeout = 0;
    while(!m_axis_result_tvalid && timeout < 300)
    begin
        @(posedge clk);
        timeout = timeout + 1;
        if(m_axis_data_tvalid || m_axis_tag_tvalid)
            $fatal(1, "NON96_STALE_OUTPUT_DURING_SCRUB data=%b tag=%b",
                   m_axis_data_tvalid, m_axis_tag_tvalid);
    end
    if(!m_axis_result_tvalid ||
       (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
       !m_axis_result_tlast)
        $fatal(1,
               "NON96_ABORT_NOT_STAGED cycles=%0d valid=%b data=%02x last=%b",
               timeout, m_axis_result_tvalid, m_axis_result_tdata,
               m_axis_result_tlast);

    repeat(3)
    begin
        @(posedge clk);
        #1;
        if(!m_axis_result_tvalid ||
           (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
           !m_axis_result_tlast || (result_fire_count != 0))
            $fatal(1,
                   "NON96_ABORT_STALL_CHANGED valid=%b data=%02x last=%b fires=%0d",
                   m_axis_result_tvalid, m_axis_result_tdata,
                   m_axis_result_tlast, result_fire_count);
    end

    @(negedge clk);
    m_axis_result_tready = 1'b1;
    timeout = 0;
    while(result_fire_count < 1 && timeout < 100)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    repeat(32) @(posedge clk);
    @(negedge clk);

    if(!saw_live_non96_ghash || result_fire_count != 1 ||
       result_last_count != 1 ||
       (captured_result !== RESULT_ZEROIZE_ABORT) ||
       m_axis_result_tvalid || output_pending ||
       data_fire_count != 0 || tag_fire_count != 0)
        $fatal(1,
               "NON96_ZEROIZE_CARDINALITY proof=%b results=%0d lasts=%0d code=%02x valid=%b pending=%b data=%0d tag=%0d",
               saw_live_non96_ghash, result_fire_count, result_last_count,
               captured_result, m_axis_result_tvalid, output_pending,
               data_fire_count, tag_fire_count);

    $display("ROUND53_NON96_GHASH_ZEROIZE_PASS iv_bits=128 ghash_busy_at_pulse=1 abort_results=1 stale_outputs=0");
    $finish;
end

endmodule
