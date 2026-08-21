`timescale 1ns / 1ps

// Round53 direct-core security and block-boundary regression.  The original
// case pulses ZEROIZE during a live non-96-bit-IV GHASH.  Two later records
// continuously present legal input at block boundaries to reach the
// registered GHASH-slot and AES/data-capacity stalls without force/random.
// Hierarchy only classifies the intended internal operating point and
// coverage; functional stability, cardinality, TLAST and output order are
// checked at the core interfaces.
module tb_round53_non96_ghash_zeroize_directed;

localparam [7:0] RESULT_ENC_OK = 8'h00;
localparam [7:0] RESULT_ZEROIZE_ABORT = 8'h13;
localparam [7:0] EVENT_DATA_LAST = 8'h44;
localparam [7:0] EVENT_TAG_LAST = 8'h54;
localparam [7:0] EVENT_RESULT = 8'h52;

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
integer data_last_count = 0;
integer tag_last_count = 0;
integer input_fire_count = 0;
integer timeout;
integer index;
integer cycle_count = 0;
integer coverage_phase = 0;
integer gh_slot_stall_cycles = 0;
integer gh_block_commit_count = 0;
integer gh_first_stall_cycle = -1;
integer gh_release_cycle = -1;
integer data_capacity_stall_cycles = 0;
integer data_block_commit_count = 0;
integer data_first_stall_cycle = -1;
integer data_release_cycle = -1;
integer terminal_event_count = 0;
reg [7:0] captured_result = 8'hff;
reg saw_live_non96_ghash = 1'b0;
reg stalled_input_pending = 1'b0;
reg [7:0] stalled_input_data = 8'd0;
reg stalled_input_last = 1'b0;
reg gh_release_pending = 1'b0;
reg data_release_pending = 1'b0;
reg [3:0] captured_data_last_user = 4'hf;
reg [7:0] terminal_event_history [0:3];

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
    cycle_count = cycle_count + 1;

    // Public ready/valid stability proof.  Once a beat is stalled, VALID,
    // DATA and TLAST must remain unchanged through its eventual handshake.
    if(s_axis_tvalid && !s_axis_tready)
    begin
        if(stalled_input_pending &&
           ((s_axis_tdata !== stalled_input_data) ||
            (s_axis_tlast !== stalled_input_last)))
            $fatal(1,
                   "BLOCK_STALL_INPUT_CHANGED data=%02x/%02x last=%b/%b",
                   stalled_input_data, s_axis_tdata,
                   stalled_input_last, s_axis_tlast);
        if(!stalled_input_pending)
        begin
            stalled_input_pending = 1'b1;
            stalled_input_data = s_axis_tdata;
            stalled_input_last = s_axis_tlast;
        end
    end
    else if(stalled_input_pending)
    begin
        if(!s_axis_tvalid ||
           (s_axis_tdata !== stalled_input_data) ||
           (s_axis_tlast !== stalled_input_last))
            $fatal(1,
                   "BLOCK_STALL_BEAT_NOT_PRESERVED valid=%b data=%02x/%02x last=%b/%b",
                   s_axis_tvalid, stalled_input_data, s_axis_tdata,
                   stalled_input_last, s_axis_tlast);
        stalled_input_pending = 1'b0;
    end

    if(s_axis_tvalid && s_axis_tready)
        input_fire_count = input_fire_count + 1;
    if(m_axis_data_tvalid && m_axis_data_tready)
    begin
        data_fire_count = data_fire_count + 1;
        if(m_axis_data_tlast)
        begin
            data_last_count = data_last_count + 1;
            captured_data_last_user = m_axis_data_tuser;
            if(coverage_phase == 2)
            begin
                terminal_event_history[terminal_event_count] =
                    EVENT_DATA_LAST;
                terminal_event_count = terminal_event_count + 1;
            end
        end
    end
    if(m_axis_tag_tvalid && m_axis_tag_tready)
    begin
        tag_fire_count = tag_fire_count + 1;
        if(m_axis_tag_tlast)
        begin
            tag_last_count = tag_last_count + 1;
            if(coverage_phase == 2)
            begin
                terminal_event_history[terminal_event_count] =
                    EVENT_TAG_LAST;
                terminal_event_count = terminal_event_count + 1;
            end
        end
    end
    if(m_axis_result_tvalid && m_axis_result_tready)
    begin
        captured_result = m_axis_result_tdata;
        if(coverage_phase == 2)
        begin
            terminal_event_history[terminal_event_count] = EVENT_RESULT;
            terminal_event_count = terminal_event_count + 1;
        end
        result_fire_count = result_fire_count + 1;
        if(m_axis_result_tlast)
            result_last_count = result_last_count + 1;
    end

    // Classification-only coverage for the two registered capacity causes.
    // The corresponding interface checks above prove the offered beat holds
    // and handshakes exactly once after READY returns.
    if((coverage_phase == 1) && s_axis_tvalid && !s_axis_tready &&
       (dut.state == 4'd1) && dut.completing_block_byte &&
       !dut.gh_input_slot_free_r)
    begin
        if(gh_slot_stall_cycles == 0)
            gh_first_stall_cycle = cycle_count;
        gh_slot_stall_cycles = gh_slot_stall_cycles + 1;
        gh_release_pending = 1'b1;
    end
    if((coverage_phase == 1) && s_axis_tvalid && s_axis_tready &&
       (dut.state == 4'd1) && dut.completing_block_byte)
    begin
        gh_block_commit_count = gh_block_commit_count + 1;
        if(gh_release_pending)
        begin
            gh_release_cycle = cycle_count;
            gh_release_pending = 1'b0;
        end
    end

    if((coverage_phase == 2) && s_axis_tvalid && !s_axis_tready &&
       (dut.state == 4'd4) && dut.completing_block_byte &&
       !dut.data_block_capacity_r)
    begin
        if(data_capacity_stall_cycles == 0)
            data_first_stall_cycle = cycle_count;
        data_capacity_stall_cycles = data_capacity_stall_cycles + 1;
        data_release_pending = 1'b1;
    end
    if((coverage_phase == 2) && s_axis_tvalid && s_axis_tready &&
       (dut.state == 4'd4) && dut.completing_block_byte)
    begin
        data_block_commit_count = data_block_commit_count + 1;
        if(data_release_pending)
        begin
            data_release_cycle = cycle_count;
            data_release_pending = 1'b0;
        end
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

task automatic clear_observations;
begin
    data_fire_count = 0;
    data_last_count = 0;
    tag_fire_count = 0;
    tag_last_count = 0;
    result_fire_count = 0;
    result_last_count = 0;
    input_fire_count = 0;
    captured_result = 8'hff;
    captured_data_last_user = 4'hf;
    stalled_input_pending = 1'b0;
    gh_slot_stall_cycles = 0;
    gh_block_commit_count = 0;
    gh_first_stall_cycle = -1;
    gh_release_cycle = -1;
    gh_release_pending = 1'b0;
    data_capacity_stall_cycles = 0;
    data_block_commit_count = 0;
    data_first_stall_cycle = -1;
    data_release_cycle = -1;
    data_release_pending = 1'b0;
    terminal_event_count = 0;
    terminal_event_history[0] = 8'hff;
    terminal_event_history[1] = 8'hff;
    terminal_event_history[2] = 8'hff;
    terminal_event_history[3] = 8'hff;
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
    m_axis_data_tready = 1'b1;
    m_axis_tag_tready = 1'b1;
    m_axis_result_tready = 1'b1;
    coverage_phase = 0;
    repeat(6) @(posedge clk);
    @(negedge clk);
    cycle_count = 0;
    clear_observations();
    rst_n = 1'b1;
end
endtask

task automatic wait_for_key_ready;
integer wait_cycles;
begin
    wait_cycles = 0;
    while(!key_ready && wait_cycles < 4000)
    begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end
    if(!key_ready || key_busy)
        $fatal(1, "BLOCK_STALL_KEY_READY_TIMEOUT cycles=%0d busy=%b",
               wait_cycles, key_busy);
end
endtask

task automatic wait_for_record_active;
integer wait_cycles;
begin
    wait_cycles = 0;
    while(!record_active && wait_cycles < 200)
    begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
    end
    if(!record_active)
        $fatal(1, "BLOCK_STALL_RECORD_ACTIVE_TIMEOUT pending=%b full=%b",
               cmd_pending, cmd_full);
end
endtask

// Present every byte on the immediately following clock.  When READY drops,
// the same public beat remains asserted until its one legal handshake.
task automatic send_contiguous_record;
input integer byte_count;
input [7:0] seed;
integer byte_index;
integer wait_cycles;
begin
    @(negedge clk);
    s_axis_tvalid = 1'b1;
    for(byte_index = 0; byte_index < byte_count;
        byte_index = byte_index + 1)
    begin
        s_axis_tdata = seed + byte_index[7:0];
        s_axis_tlast = (byte_index == (byte_count - 1));
        wait_cycles = 0;
        while(!s_axis_tready && wait_cycles < 20000)
        begin
            @(posedge clk);
            @(negedge clk);
            wait_cycles = wait_cycles + 1;
        end
        if(!s_axis_tready)
            $fatal(1,
                   "BLOCK_STALL_INPUT_TIMEOUT byte=%0d fires=%0d phase=%0d",
                   byte_index, input_fire_count, coverage_phase);
        @(posedge clk);
        @(negedge clk);
    end
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

    // A 17-byte non-96-bit IV creates two legal block commits.  With no
    // idle cycle between byte 16 and the partial final byte, the registered
    // input-GHASH producer is occupied for exactly the boundary wait.
    reset_core();
    cmd_decrypt = 1'b0;
    cmd_tag_bits = 8'd128;
    cmd_iv_bits = 11'd136;
    cmd_aad_bits = 11'd0;
    cmd_data_bits = 11'd0;
    pulse_key_commit();
    wait_for_key_ready();
    push_record();
    wait_for_record_active();
    @(negedge clk);
    coverage_phase = 1;
    send_contiguous_record(17, 8'h20);

    timeout = 0;
    while((tag_fire_count < 16 || result_fire_count < 1) && timeout < 5000)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    repeat(8) @(posedge clk);
    @(negedge clk);
    coverage_phase = 0;

    if(input_fire_count != 17 || gh_slot_stall_cycles <= 0 ||
       gh_block_commit_count != 2 ||
       gh_first_stall_cycle < 0 ||
       (gh_release_cycle - gh_first_stall_cycle) != gh_slot_stall_cycles ||
       stalled_input_pending ||
       data_fire_count != 0 || data_last_count != 0 ||
       tag_fire_count != 16 || tag_last_count != 1 ||
       result_fire_count != 1 || result_last_count != 1 ||
       (captured_result !== RESULT_ENC_OK) ||
       record_active || output_pending || m_axis_tag_tvalid ||
       m_axis_result_tvalid)
        $fatal(1,
               "GHASH_SLOT_STALL_COVERAGE input=%0d stalls=%0d commits=%0d first=%0d release=%0d held=%b data=%0d/%0d tag=%0d/%0d result=%0d/%0d/%02x active=%b pending=%b",
               input_fire_count, gh_slot_stall_cycles,
               gh_block_commit_count, gh_first_stall_cycle,
               gh_release_cycle, stalled_input_pending,
               data_fire_count, data_last_count,
               tag_fire_count, tag_last_count,
               result_fire_count, result_last_count, captured_result,
               record_active, output_pending);
    $display("ROUND53_GHASH_SLOT_STALL_PASS iv_bytes=17 stall_cycles=%0d first_cycle=%0d release_cycle=%0d block_commits=2 input_fires=17 tag=16 result=00",
             gh_slot_stall_cycles, gh_first_stall_cycle, gh_release_cycle);

    // The two-entry data queue must admit the immediately following 16-byte
    // DATA block without waiting for AES, then commit it exactly once when the
    // ordered keystream arrives.
    clear_observations();
    cmd_iv_bits = 11'd96;
    cmd_data_bits = 11'd128;
    push_record();
    wait_for_record_active();
    @(negedge clk);
    coverage_phase = 2;
    send_contiguous_record(28, 8'h40);

    timeout = 0;
    while((data_fire_count < 16 || tag_fire_count < 16 ||
           result_fire_count < 1) && timeout < 10000)
    begin
        @(posedge clk);
        timeout = timeout + 1;
    end
    repeat(8) @(posedge clk);
    @(negedge clk);
    coverage_phase = 0;

    if(input_fire_count != 28 || data_block_commit_count != 1 ||
       data_capacity_stall_cycles != 0 ||
       data_first_stall_cycle >= 0 || data_release_cycle >= 0 ||
       stalled_input_pending ||
       data_fire_count != 16 || data_last_count != 1 ||
       (captured_data_last_user !== 4'd8) ||
       tag_fire_count != 16 || tag_last_count != 1 ||
       result_fire_count != 1 || result_last_count != 1 ||
       (captured_result !== RESULT_ENC_OK) ||
       terminal_event_count != 3 ||
       (terminal_event_history[0] !== EVENT_DATA_LAST) ||
       (terminal_event_history[1] !== EVENT_TAG_LAST) ||
       (terminal_event_history[2] !== EVENT_RESULT) ||
       record_active || output_pending || m_axis_data_tvalid ||
       m_axis_tag_tvalid || m_axis_result_tvalid)
        $fatal(1,
               "DATA_BUFFER_COVERAGE input=%0d commits=%0d stalls=%0d first=%0d release=%0d held=%b data=%0d/%0d/u%0d tag=%0d/%0d result=%0d/%0d/%02x events=%0d:%02x,%02x,%02x active=%b pending=%b",
               input_fire_count, data_block_commit_count,
               data_capacity_stall_cycles,
               data_first_stall_cycle, data_release_cycle,
               stalled_input_pending,
               data_fire_count, data_last_count, captured_data_last_user,
               tag_fire_count, tag_last_count,
               result_fire_count, result_last_count, captured_result,
               terminal_event_count, terminal_event_history[0],
               terminal_event_history[1], terminal_event_history[2],
               record_active, output_pending);
    $display("ROUND55_AES_DATA_BUFFER_PASS input_fires=28 data_blocks=1 stall_cycles=%0d first_cycle=%0d release_cycle=%0d data=16 tag=16 result=00 order=D,T,R",
             data_capacity_stall_cycles,
             data_first_stall_cycle, data_release_cycle);
    $finish;
end

endmodule
