`timescale 1ns / 1ps

// Round53 security regression for the bare aes_gcm_stream_core interface.
//
// A ZEROIZE_ABORT is first staged under result backpressure.  ZEROIZE and
// RESULT_READY are then asserted together.  Because ZEROIZE masks RESULT_VALID,
// that clock is not a public handshake and the pending 0x13 beat must survive.
//
// The unmodified Round52/Round53-A core loses the beat.  Run that historical
// implementation with +EXPECT_BASELINE_LOSS to turn the expected negative
// result into an auditable PASS.  The normal regression mode requires the
// Round53 fix and is intended to pass only for experiments C and D.
module tb_round53_core_zeroize_directed;

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
reg [10:0] cmd_iv_bits = 11'd96;
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

integer result_fire_count = 0;
integer data_fire_count = 0;
integer tag_fire_count = 0;
integer timeout;
reg [7:0] captured_result = 8'hff;
reg expect_baseline_loss;

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
    if(m_axis_data_tvalid && m_axis_data_tready)
        data_fire_count = data_fire_count + 1;
    if(m_axis_tag_tvalid && m_axis_tag_tready)
        tag_fire_count = tag_fire_count + 1;
    if(m_axis_result_tvalid && m_axis_result_tready)
    begin
        captured_result = m_axis_result_tdata;
        result_fire_count = result_fire_count + 1;
        if(!m_axis_result_tlast)
            $fatal(1, "ZEROIZE_RESULT_MISSING_TLAST");
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

task automatic push_idle_record;
begin
    if(cmd_full)
        $fatal(1, "DESCRIPTOR_FIFO_FULL_BEFORE_PUSH");
    @(negedge clk);
    cmd_push = 1'b1;
    @(posedge clk);
    @(negedge clk);
    cmd_push = 1'b0;
end
endtask

task automatic pulse_zeroize;
begin
    @(negedge clk);
    zeroize = 1'b1;
    @(posedge clk);
    @(negedge clk);
    zeroize = 1'b0;
end
endtask

task automatic reset_core;
begin
    @(negedge clk);
    rst_n = 1'b0;
    key_commit = 1'b0;
    zeroize = 1'b0;
    cmd_push = 1'b0;
    s_axis_tvalid = 1'b0;
    s_axis_tlast = 1'b0;
    m_axis_result_tready = 1'b0;
    repeat(6) @(posedge clk);
    @(negedge clk);
    result_fire_count = 0;
    data_fire_count = 0;
    tag_fire_count = 0;
    captured_result = 8'hff;
    rst_n = 1'b1;
end
endtask

task automatic wait_for_key_ready;
begin
    timeout = 0;
    while(!key_ready && timeout < 4000)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!key_ready || key_busy)
        $fatal(1, "KEY_READY_TIMEOUT cycles=%0d busy=%b", timeout, key_busy);
end
endtask

task automatic stage_one_zeroize_abort;
begin
    pulse_key_commit();
    wait_for_key_ready();
    push_idle_record();
    timeout = 0;
    while(!record_active && timeout < 200)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!record_active)
        $fatal(1, "RECORD_ACTIVE_TIMEOUT pending=%b full=%b",
               cmd_pending, cmd_full);
    m_axis_result_tready = 1'b0;
    pulse_zeroize();
    timeout = 0;
    while(!m_axis_result_tvalid && timeout < 200)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    if(!m_axis_result_tvalid ||
       (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
       !m_axis_result_tlast)
        $fatal(1,
               "ZEROIZE_ABORT_NOT_STAGED cycles=%0d valid=%b data=%02x last=%b busy=%b pending=%b",
               timeout, m_axis_result_tvalid, m_axis_result_tdata,
               m_axis_result_tlast, zeroize_busy, output_pending);
end
endtask

initial
begin
    expect_baseline_loss = $test$plusargs("EXPECT_BASELINE_LOSS");

    repeat(8) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // The AES-128 key occupies key_data[255:128].  All-zero is sufficient.
    // Accept one descriptor and leave it active awaiting its IV; ZEROIZE
    // therefore owes exactly one externally visible abort result.
    stage_one_zeroize_abort();
    if(key_ready || record_active)
        $fatal(1, "FIRST_ZEROIZE_DID_NOT_INVALIDATE key=%b active=%b",
               key_ready, record_active);

    repeat(3)
    begin
        @(posedge clk);
        #1;
        if(!m_axis_result_tvalid ||
           (m_axis_result_tdata !== RESULT_ZEROIZE_ABORT) ||
           !m_axis_result_tlast || (result_fire_count != 0))
            $fatal(1,
                   "STALLED_ZEROIZE_ABORT_CHANGED valid=%b data=%02x last=%b fires=%0d",
                   m_axis_result_tvalid, m_axis_result_tdata,
                   m_axis_result_tlast, result_fire_count);
    end

    // Critical Round53 collision: VALID is externally masked throughout the
    // repeated ZEROIZE pulse, so READY=1 cannot retire the internal beat.
    @(negedge clk);
    zeroize = 1'b1;
    m_axis_result_tready = 1'b1;
    #1;
    if(m_axis_result_tvalid)
        $fatal(1, "RESULT_VALID_NOT_MASKED_DURING_ZEROIZE");
    @(posedge clk);
    @(negedge clk);
    zeroize = 1'b0;

    repeat(12) @(posedge clk);
    @(negedge clk);

    if(expect_baseline_loss)
    begin
        if(result_fire_count != 0 || m_axis_result_tvalid || output_pending)
            $fatal(1,
                   "BASELINE_LOSS_NOT_REPRODUCED fires=%0d valid=%b pending=%b data=%02x",
                   result_fire_count, m_axis_result_tvalid, output_pending,
                   m_axis_result_tdata);
        if(data_fire_count != 0 || tag_fire_count != 0)
            $fatal(1, "BASELINE_UNEXPECTED_OUTPUT data=%0d tag=%0d",
                   data_fire_count, tag_fire_count);
        $display("ROUND53_CORE_BASELINE_LOSS_REPRODUCED result=13 visible_fires=0");
    end
    else
    begin
        if(result_fire_count != 1 ||
           (captured_result !== RESULT_ZEROIZE_ABORT) ||
           m_axis_result_tvalid || output_pending)
            $fatal(1,
                   "ZEROIZE_ABORT_INVISIBLE_RETIREMENT fires=%0d captured=%02x valid=%b pending=%b",
                   result_fire_count, captured_result,
                   m_axis_result_tvalid, output_pending);
        if(data_fire_count != 0 || tag_fire_count != 0)
            $fatal(1, "ZEROIZE_UNEXPECTED_OUTPUT data=%0d tag=%0d",
                   data_fire_count, tag_fire_count);
        $display("ROUND53_CORE_ZEROIZE_PASS result=13 visible_fires=1");
    end

    // Admission corner.  Recreate a final stalled 0x13, then generate a new
    // H subkey and queue another descriptor without issuing a second
    // ZEROIZE.  The predictive sequence token must keep that descriptor out
    // of active state until the abort's visible handshake.  It may start on
    // the immediately following edge; any further bubble is a regression.
    reset_core();
    stage_one_zeroize_abort();

    pulse_key_commit();
    wait_for_key_ready();
    push_idle_record();
    repeat(8) @(posedge clk);
    #1;

    if(expect_baseline_loss)
    begin
        if(!record_active)
            $fatal(1,
                   "BASELINE_EARLY_ADMISSION_NOT_REPRODUCED pending=%b full=%b",
                   cmd_pending, cmd_full);
        $display("ROUND53_ZSEQ_BASELINE_EARLY_ADMISSION_REPRODUCED active_before_abort=1");
    end
    else if(record_active || !cmd_pending)
        $fatal(1,
               "ZSEQ_ADMITTED_BEFORE_FINAL_ABORT active=%b pending=%b",
               record_active, cmd_pending);

    @(negedge clk);
    m_axis_result_tready = 1'b1;
    @(posedge clk);
    #1;
    if(result_fire_count != 1 ||
       (captured_result !== RESULT_ZEROIZE_ABORT))
        $fatal(1,
               "ZSEQ_FINAL_ABORT_NOT_VISIBLE fires=%0d result=%02x",
               result_fire_count, captured_result);
    if(!expect_baseline_loss && record_active)
        $fatal(1, "ZSEQ_ADMITTED_ON_ABORT_HANDSHAKE_EDGE");

    @(posedge clk);
    #1;
    if(!record_active)
        $fatal(1,
               "ZSEQ_POST_ABORT_ADMISSION_BUBBLE pending=%b full=%b",
               cmd_pending, cmd_full);
    if(!expect_baseline_loss)
        $display("ROUND53_ZSEQ_ADMISSION_PASS held_until_abort=1 admitted_next_edge=1");

    $finish;
end

endmodule
