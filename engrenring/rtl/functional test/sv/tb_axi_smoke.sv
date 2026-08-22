`timescale 1ns / 1ps

module tb_axi_smoke;

localparam [1:0] OKAY   = 2'b00;
localparam [1:0] SLVERR = 2'b10;

reg aclk = 1'b0;
always #2.857 aclk = ~aclk;

reg aresetn = 1'b0;
reg [2:0] key_mode = 3'd0;

reg [6:0] awaddr;
reg [2:0] awprot = 3'd0;
reg awvalid;
wire awready;
reg [31:0] wdata;
reg [3:0] wstrb;
reg wvalid;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready;
reg [6:0] araddr;
reg [2:0] arprot = 3'd0;
reg arvalid;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready;

reg [7:0] s_data;
reg s_valid;
wire s_ready;
reg s_last;

wire [7:0] data_out;
wire data_valid;
reg data_ready = 1'b1;
wire data_last;
wire [3:0] data_user;
wire [7:0] tag_out;
wire tag_valid;
reg tag_ready = 1'b1;
wire tag_last;
wire [7:0] result_out;
wire result_valid;
reg result_ready = 1'b1;
wire result_last;

aes_gcm_axi_top dut (
    .aclk(aclk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arprot(arprot),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid),
    .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid),
    .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

integer cycle_count;
integer data_count;
integer data_last_count;
integer tag_count;
integer result_count;
integer result_last_count;
integer first_data_cycle;
integer result_cycle;
integer input_handshake_count;
integer input_last_handshake_count;
integer aw_handshake_count;
integer w_handshake_count;
integer b_handshake_count;
integer ar_handshake_count;
integer r_handshake_count;
integer public_frame_credits;
integer input_handshake_baseline;
integer aw_handshake_baseline;
integer w_handshake_baseline;
integer b_handshake_baseline;
integer ar_handshake_baseline;
integer r_handshake_baseline;
reg [2047:0] captured_data;
reg [127:0] captured_tag;
reg [7:0] captured_result;
reg [7:0] result_history [0:7];
reg [3:0] captured_last_user;
reg [7:0] stalled_output_data;
reg [3:0] stalled_output_user;
reg stalled_output_last;
reg [7:0] stalled_tag_data;
reg stalled_tag_last;
reg [31:0] stalled_read_data;
reg [1:0] stalled_read_resp;
reg [7:0] gap_lfsr;

always @(posedge aclk)
begin
    cycle_count <= cycle_count + 1;
    if(data_valid && data_ready)
    begin
        captured_data <= {captured_data[2039:0], data_out};
        data_count <= data_count + 1;
        if(first_data_cycle < 0)
            first_data_cycle <= cycle_count;
        if(data_last)
        begin
            captured_last_user <= data_user;
            data_last_count <= data_last_count + 1;
        end
    end
    if(tag_valid && tag_ready)
    begin
        captured_tag <= {captured_tag[119:0], tag_out};
        tag_count <= tag_count + 1;
    end
    if(result_valid && result_ready)
    begin
        captured_result <= result_out;
        if(result_count < 8)
            result_history[result_count] <= result_out;
        result_count <= result_count + 1;
        result_cycle <= cycle_count;
        if(result_last)
            result_last_count <= result_last_count + 1;
    end

    // The input queue is intentionally opaque at the public boundary.  Count
    // only real handshakes; end-to-end frame/result checks below prove that
    // every acknowledged beat is either processed or explicitly aborted.
    if(!aresetn)
    begin
        input_handshake_count <= 0;
        input_last_handshake_count <= 0;
        aw_handshake_count <= 0;
        w_handshake_count <= 0;
        b_handshake_count <= 0;
        ar_handshake_count <= 0;
        r_handshake_count <= 0;
    end
    else
    begin
        if(s_valid && s_ready)
        begin
            input_handshake_count <= input_handshake_count + 1;
            if(s_last)
                input_last_handshake_count <=
                    input_last_handshake_count + 1;
        end
        if(awvalid && awready)
            aw_handshake_count <= aw_handshake_count + 1;
        if(wvalid && wready)
            w_handshake_count <= w_handshake_count + 1;
        if(bvalid && bready)
            b_handshake_count <= b_handshake_count + 1;
        if(arvalid && arready)
            ar_handshake_count <= ar_handshake_count + 1;
        if(rvalid && rready)
            r_handshake_count <= r_handshake_count + 1;

    end
end

task clear_capture;
begin
    @(negedge aclk);
    data_count = 0;
    data_last_count = 0;
    tag_count = 0;
    result_count = 0;
    result_last_count = 0;
    first_data_cycle = -1;
    result_cycle = -1;
    input_handshake_count = 0;
    input_last_handshake_count = 0;
    aw_handshake_count = 0;
    w_handshake_count = 0;
    b_handshake_count = 0;
    ar_handshake_count = 0;
    r_handshake_count = 0;
    public_frame_credits = 0;
    captured_data = 2048'd0;
    captured_tag = 128'd0;
    captured_result = 8'hff;
    captured_last_user = 4'd0;
end
endtask

task axi_write;
input [6:0] address;
input [31:0] value;
input [1:0] expected_response;
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
    if(bresp !== expected_response)
    begin
        $display("AXI_WRITE_RESPONSE_ERROR addr=%02x got=%b expected=%b",
                 address, bresp, expected_response);
        $fatal(1);
    end
    @(negedge aclk);
    bready = 1'b0;
end
endtask

task axi_write_skew;
input [6:0] address;
input [31:0] value;
input address_first;
input integer skew_cycles;
input [1:0] expected_response;
begin
    @(negedge aclk);
    awaddr = address;
    wdata = value;
    wstrb = 4'hf;
    bready = 1'b1;
    awvalid = address_first;
    wvalid = !address_first;

    if(address_first)
    begin
        while(!(awvalid && awready))
            @(posedge aclk);
        @(negedge aclk);
        awvalid = 1'b0;
    end
    else
    begin
        while(!(wvalid && wready))
            @(posedge aclk);
        @(negedge aclk);
        wvalid = 1'b0;
    end

    repeat(skew_cycles) @(posedge aclk);
    @(negedge aclk);
    awvalid = !address_first;
    wvalid = address_first;
    if(address_first)
    begin
        while(!(wvalid && wready))
            @(posedge aclk);
        @(negedge aclk);
        wvalid = 1'b0;
    end
    else
    begin
        while(!(awvalid && awready))
            @(posedge aclk);
        @(negedge aclk);
        awvalid = 1'b0;
    end

    while(!bvalid)
        @(posedge aclk);
    if(bresp !== expected_response)
        $fatal(1,
               "AXI_SKEW_WRITE_RESPONSE_ERROR addr=%02x got=%b expected=%b",
               address, bresp, expected_response);
    @(negedge aclk);
    bready = 1'b0;
end
endtask

task axi_read;
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
        $fatal(1, "AXI_READ_RESPONSE_ERROR addr=%02x resp=%b", address, rresp);
    value = rdata;
    @(negedge aclk);
    rready = 1'b0;
end
endtask

task send_byte;
input [7:0] value;
input last_byte;
begin
    s_data = value;
    s_last = last_byte;
    s_valid = 1'b1;
    while(!(s_valid && s_ready))
        @(posedge aclk);
    @(negedge aclk);
    if(last_byte)
    begin
        if(public_frame_credits <= 0)
            $fatal(1, "PUBLIC_TLAST_WITHOUT_ACCEPTED_COMMAND");
        public_frame_credits = public_frame_credits - 1;
    end
    s_valid = 1'b0;
    s_last = 1'b0;
end
endtask

task send_byte_lfsr_gap;
input [7:0] value;
input last_byte;
integer gap_cycles;
begin
    gap_lfsr = {gap_lfsr[6:0],
                gap_lfsr[7] ^ gap_lfsr[5] ^ gap_lfsr[4] ^ gap_lfsr[3]};
    gap_cycles = gap_lfsr[1:0];
    s_valid = 1'b0;
    s_last = 1'b0;
    repeat(gap_cycles) @(posedge aclk);
    @(negedge aclk);
    send_byte(value, last_byte);
end
endtask

task program_record;
input decrypt;
input [10:0] iv_bits;
input [10:0] aad_bits;
input [10:0] payload_bits;
input [1:0] expected_push_response;
begin
    axi_write(7'h08, {16'd0, 8'd128, 7'd0, decrypt}, OKAY);
    axi_write(7'h0c, iv_bits, OKAY);
    axi_write(7'h10, aad_bits, OKAY);
    axi_write(7'h14, payload_bits, OKAY);
    axi_write(7'h00, 32'h00000001, expected_push_response);
    if(expected_push_response == OKAY)
    begin
        if(public_frame_credits >= 3)
            $fatal(1, "PUBLIC_COMMAND_CREDIT_OVERFLOW credits=%0d",
                   public_frame_credits);
        public_frame_credits = public_frame_credits + 1;
    end
end
endtask

task send_zero_iv;
integer index;
begin
    for(index = 0; index < 12; index = index + 1)
        send_byte(8'h00, 1'b0);
end
endtask

task wait_for_result;
integer timeout;
reg [31:0] timeout_status;
begin
    timeout = 0;
    while((result_count == 0) && (timeout < 10000))
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(timeout == 10000)
    begin
        axi_read(7'h04, timeout_status);
        $fatal(1,
               "RESULT_TIMEOUT status=%08x s_ready=%b data_valid=%b tag_valid=%b result_valid=%b in_hs=%0d in_last_hs=%0d",
               timeout_status, s_ready, data_valid, tag_valid, result_valid,
               input_handshake_count, input_last_handshake_count);
    end
end
endtask

// A completed record must not be rediscovered from stale finalization state
// while a new key is being expanded.  Observe only public interfaces: clear
// the completed record's counters, re-key without reset/ZEROIZE, and require
// silence through KEY_READY and a guard window before the next CMD_PUSH.
task rekey_after_completed_record_quiet;
input [7:0] phase_id;
integer quiet_cycle;
reg [31:0] rekey_status;
begin
    clear_capture();
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    rekey_status = 0;
    while(!rekey_status[0])
        axi_read(7'h04, rekey_status);

    for(quiet_cycle = 0; quiet_cycle < 32;
        quiet_cycle = quiet_cycle + 1)
    begin
        @(posedge aclk);
        if(data_valid || tag_valid || result_valid)
            $fatal(1,
                   "NORMAL_REKEY_STALE_VALID phase=%02x cycle=%0d data=%b tag=%b result=%b",
                   phase_id, quiet_cycle, data_valid, tag_valid,
                   result_valid);
    end
    @(negedge aclk);
    if(data_count != 0 || data_last_count != 0 || tag_count != 0 ||
       result_count != 0 || result_last_count != 0)
        $fatal(1,
               "NORMAL_REKEY_DUPLICATE_OUTPUT phase=%02x data=%0d data_last=%0d tag=%0d result=%0d result_last=%0d",
               phase_id, data_count, data_last_count, tag_count,
               result_count, result_last_count);
end
endtask

// Independent AES-GCM references for an all-zero AES-128 key/IV, no AAD,
// and seventeen 8'hff input bytes with only the requested high bits valid.
function [127:0] partial_tag_reference;
input [10:0] payload_bits;
begin
    case(payload_bits)
        11'd129: partial_tag_reference = 128'hb306302f7f2cdb07dd045291db3ba2e6;
        11'd130: partial_tag_reference = 128'h44eb55e7420304250a7292e1bf886a3d;
        11'd131: partial_tag_reference = 128'h164f895f56e64ec4b8a0d2ce63e6d274;
        11'd132: partial_tag_reference = 128'h69319e77385cba60a49f120176effb8a;
        11'd133: partial_tag_reference = 128'hbc63dbce97f2e811791d0bfceee48ac7;
        11'd134: partial_tag_reference = 128'h4b8ebe06aadd3733ae6bcb8c8a57421c;
        11'd135: partial_tag_reference = 128'h192a62bebe387dd21cb98ba35639fa55;
        11'd136: partial_tag_reference = 128'hb572905677a8de7b96144a12a04511e0;
        default: partial_tag_reference = 128'd0;
    endcase
end
endfunction

integer i;
integer prefetch_count;
integer partial_bits;
reg [31:0] status_word;
reg [127:0] known_ct;
reg [127:0] known_tag;
reg [127:0] aad_flip_ct;
reg [127:0] aad_flip_tag;
reg [2047:0] long_ct;
reg [127:0] long_tag;
reg [135:0] partial_expected_ct;
reg [127:0] partial_expected_tag;
reg [135:0] partial_expected_plain;
reg [135:0] partial_cipher;
reg [7:0] boundary_cipher;
reg [127:0] boundary_tag;

initial
begin
    cycle_count = 0;
    data_count = 0;
    data_last_count = 0;
    tag_count = 0;
    result_count = 0;
    result_last_count = 0;
    first_data_cycle = -1;
    result_cycle = -1;
    captured_data = 0;
    captured_tag = 0;
    captured_result = 0;
    captured_last_user = 0;
    gap_lfsr = 8'h1;
    awaddr = 0;
    awvalid = 0;
    wdata = 0;
    wstrb = 0;
    wvalid = 0;
    bready = 0;
    araddr = 0;
    arvalid = 0;
    rready = 0;
    s_data = 0;
    s_valid = 0;
    s_last = 0;

    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;

    // AES-128 all-zero key.  Key registers are write-only.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);

    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    // STATUS is an exact snapshot of the AR handshake cycle.  Stage a
    // ZEROIZE write, then accept STATUS AR on the cycle which produces the
    // write pulse.  The source status changes before the delayed read
    // response, but the response must retain the captured KEY_READY value.
    // A second AR is held continuously and must not handshake while either
    // the STATUS snapshot or its backpressured response is outstanding.
    @(negedge aclk);
    while(!(awready && wready && arready))
        @(negedge aclk);
    aw_handshake_baseline = aw_handshake_count;
    w_handshake_baseline = w_handshake_count;
    b_handshake_baseline = b_handshake_count;
    ar_handshake_baseline = ar_handshake_count;
    r_handshake_baseline = r_handshake_count;
    awaddr = 7'h00;
    awvalid = 1'b1;
    wdata = 32'h00000004;
    wstrb = 4'hf;
    wvalid = 1'b1;
    bready = 1'b1;
    @(posedge aclk);
    @(negedge aclk);
    if((aw_handshake_count != (aw_handshake_baseline + 1)) ||
       (w_handshake_count != (w_handshake_baseline + 1)))
        $fatal(1,
               "STATUS_SNAPSHOT_ZEROIZE_STAGE_ERROR aw=%0d w=%0d",
               aw_handshake_count - aw_handshake_baseline,
               w_handshake_count - w_handshake_baseline);
    awvalid = 1'b0;
    wvalid = 1'b0;
    araddr = 7'h04;
    arvalid = 1'b1;
    rready = 1'b0;
    @(posedge aclk);
    @(negedge aclk);
    if((ar_handshake_count != (ar_handshake_baseline + 1)) || rvalid ||
       arready || !bvalid || (bresp !== OKAY))
        $fatal(1,
               "STATUS_SNAPSHOT_PENDING_ERROR ar=%0d arready=%b rvalid=%b bvalid=%b bresp=%b",
               ar_handshake_count - ar_handshake_baseline, arready, rvalid,
               bvalid, bresp);

    // Present the next address immediately after the STATUS AR handshake.
    // It must remain unaccepted through both the pending and RVALID phases.
    araddr = 7'h40;
    @(posedge aclk);
    @(negedge aclk);
    bready = 1'b0;
    if(!rvalid || (rresp !== OKAY) || (rdata[5:0] !== 6'b000001) ||
       arready || (ar_handshake_count != (ar_handshake_baseline + 1)) ||
       (b_handshake_count != (b_handshake_baseline + 1)))
        $fatal(1,
               "STATUS_SNAPSHOT_RESPONSE_ERROR data=%08x resp=%b valid=%b arready=%b ar=%0d b=%0d",
               rdata, rresp, rvalid, arready,
               ar_handshake_count - ar_handshake_baseline,
               b_handshake_count - b_handshake_baseline);
    stalled_read_data = rdata;
    stalled_read_resp = rresp;
    repeat(3)
    begin
        @(posedge aclk);
        @(negedge aclk);
        if(!rvalid || arready || (rdata !== stalled_read_data) ||
           (rresp !== stalled_read_resp) ||
           (ar_handshake_count != (ar_handshake_baseline + 1)) ||
           (r_handshake_count != r_handshake_baseline))
            $fatal(1,
                   "STATUS_SNAPSHOT_STALL_CHANGED valid=%b arready=%b data=%08x resp=%b ar=%0d r=%0d",
                   rvalid, arready, rdata, rresp,
                   ar_handshake_count - ar_handshake_baseline,
                   r_handshake_count - r_handshake_baseline);
    end

    rready = 1'b1;
    @(posedge aclk);
    @(negedge aclk);
    rready = 1'b0;
    if((r_handshake_count != (r_handshake_baseline + 1)) || !arready ||
       (ar_handshake_count != (ar_handshake_baseline + 1)))
        $fatal(1,
               "STATUS_SNAPSHOT_RETIRE_ERROR arready=%b ar=%0d r=%0d",
               arready, ar_handshake_count - ar_handshake_baseline,
               r_handshake_count - r_handshake_baseline);

    // The held CAPABILITY request is accepted only after STATUS retires and,
    // unlike STATUS, produces its response at the existing AR latency.
    @(posedge aclk);
    @(negedge aclk);
    if((ar_handshake_count != (ar_handshake_baseline + 2)) || !rvalid ||
       (rresp !== OKAY) || (rdata !== 32'h0107b7ff))
        $fatal(1,
               "STATUS_SNAPSHOT_SECOND_AR_ERROR ar=%0d valid=%b data=%08x resp=%b",
               ar_handshake_count - ar_handshake_baseline, rvalid, rdata,
               rresp);
    arvalid = 1'b0;
    rready = 1'b1;
    @(posedge aclk);
    @(negedge aclk);
    rready = 1'b0;
    if(r_handshake_count != (r_handshake_baseline + 2))
        $fatal(1, "STATUS_SNAPSHOT_SECOND_R_ERROR r=%0d",
               r_handshake_count - r_handshake_baseline);

    // The first response retained KEY_READY=1 even though ZEROIZE invalidated
    // the key before RVALID.  A later public STATUS read observes the new
    // source state and waits for the scrub sequence to finish.
    axi_read(7'h04, status_word);
    if(status_word[0] !== 1'b0)
        $fatal(1, "STATUS_SNAPSHOT_SOURCE_DID_NOT_CHANGE status=%08x",
               status_word);
    while(status_word[5])
        axi_read(7'h04, status_word);

    // Restore the key destroyed by the directed snapshot test.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    // A stream beat has no ownership until a descriptor has been accepted.
    // Hold TVALID for several clocks and prove that READY and the queue stay
    // unowned without a successful CMD_PUSH.  Queue occupancy is private;
    // public STATUS, READY, and handshake counts establish the same protocol
    // property without depending on its implementation.
    prefetch_count = input_handshake_count;
    @(negedge aclk);
    s_data = 8'ha5;
    s_last = 1'b0;
    s_valid = 1'b1;
    repeat(4)
    begin
        @(posedge aclk);
        if(s_ready)
            $fatal(1, "NO_CMD_STREAM_READY_WITHOUT_COMMAND");
    end
    @(negedge aclk);
    s_valid = 1'b0;
    axi_read(7'h04, status_word);
    if(status_word[3] || status_word[4] ||
       (input_handshake_count != prefetch_count) || data_valid || tag_valid ||
       result_valid || (public_frame_credits != 0))
        $fatal(1,
               "NO_CMD_PUBLIC_OWNERSHIP status=%08x input_hs=%0d baseline=%0d data=%b tag=%b result=%b credits=%0d",
               status_word, input_handshake_count, prefetch_count, data_valid,
               tag_valid, result_valid, public_frame_credits);

    // AXI4-Lite permits AW and W to arrive independently.  Exercise both
    // legal skew directions and read back the resulting register values.
    axi_write_skew(7'h08, 32'h00008000, 1'b1, 3, OKAY);
    axi_read(7'h08, status_word);
    if(status_word !== 32'h00008000)
        $fatal(1, "AXI_AW_FIRST_SKEW_ERROR cfg=%08x", status_word);
    axi_write_skew(7'h0c, 32'd96, 1'b0, 2, OKAY);
    axi_read(7'h0c, status_word);
    if(status_word !== 32'd96)
        $fatal(1, "AXI_W_FIRST_SKEW_ERROR iv_bits=%08x", status_word);

    // Every out-of-range public key_mode must reject KEY_COMMIT without
    // disturbing the already committed key or creating a result beat.
    clear_capture();
    for(i = 3; i < 8; i = i + 1)
    begin
        key_mode = i[2:0];
        axi_write(7'h00, 32'h00000002, SLVERR);
    end
    key_mode = 3'd0;
    axi_read(7'h04, status_word);
    if(!status_word[0] || result_count != 0 || data_valid || tag_valid ||
       result_valid)
        $fatal(1,
               "INVALID_KEY_MODE_SIDE_EFFECT status=%08x results=%0d data=%b tag=%b result=%b",
               status_word, result_count, data_valid, tag_valid, result_valid);

    // Keep one descriptor active, fill both descriptor-FIFO entries behind
    // it, then prove that the third queued CMD_PUSH is rejected.  The three
    // successful pushes must still retire as exactly three ordered results.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd0, OKAY);
    status_word = 0;
    prefetch_count = 0;
    while(!status_word[3] && (prefetch_count < 100))
    begin
        axi_read(7'h04, status_word);
        prefetch_count = prefetch_count + 1;
    end
    if(!status_word[3])
        $fatal(1, "DESCRIPTOR_ACTIVE_TIMEOUT status=%08x", status_word);
    program_record(1'b0, 11'd96, 11'd0, 11'd0, OKAY);
    program_record(1'b0, 11'd96, 11'd0, 11'd0, OKAY);
    axi_read(7'h04, status_word);
    if(!status_word[2] || public_frame_credits != 3)
        $fatal(1, "DESCRIPTOR_FIFO_NOT_FULL status=%08x credits=%0d",
               status_word, public_frame_credits);
    program_record(1'b0, 11'd96, 11'd0, 11'd0, SLVERR);
    if(public_frame_credits != 3)
        $fatal(1, "REJECTED_CMD_GAINED_CREDIT credits=%0d",
               public_frame_credits);

    for(i = 0; i < 3; i = i + 1)
    begin
        for(prefetch_count = 0; prefetch_count < 12;
            prefetch_count = prefetch_count + 1)
            send_byte(8'h00, prefetch_count == 11);
    end
    prefetch_count = 0;
    while((result_count < 3) && (prefetch_count < 10000))
    begin
        @(posedge aclk);
        prefetch_count = prefetch_count + 1;
    end
    repeat(20) @(posedge aclk);
    if(result_count != 3 || result_last_count != 3 ||
       result_history[0] !== 8'h00 || result_history[1] !== 8'h00 ||
       result_history[2] !== 8'h00 || tag_count != 48 || data_count != 0 ||
       public_frame_credits != 0)
        $fatal(1,
               "DESCRIPTOR_RESULT_CARDINALITY results=%0d lasts=%0d r0=%02x r1=%02x r2=%02x tags=%0d data=%0d credits=%0d",
               result_count, result_last_count, result_history[0],
               result_history[1], result_history[2], tag_count, data_count,
               public_frame_credits);

    // Assert the public synchronous reset while a descriptor owns a partial
    // input frame.  Reset is the documented exception to result cardinality:
    // it must discard the record, invalidate the key, and leave no stale beat.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    for(i = 0; i < 4; i = i + 1)
        send_byte_lfsr_gap(8'h00, 1'b0);
    axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1, "ACTIVE_RESET_SETUP_ERROR status=%08x", status_word);
    @(negedge aclk);
    aresetn = 1'b0;
    public_frame_credits = 0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    bready = 1'b0;
    arvalid = 1'b0;
    rready = 1'b0;
    s_valid = 1'b0;
    s_last = 1'b0;
    repeat(4) @(posedge aclk);
    @(negedge aclk);
    if(data_valid || tag_valid || result_valid)
        $fatal(1, "ACTIVE_RESET_OUTPUT_NOT_CLEARED data=%b tag=%b result=%b",
               data_valid, tag_valid, result_valid);
    aresetn = 1'b1;
    repeat(6) @(posedge aclk);
    @(negedge aclk);
    if(data_count != 0 || tag_count != 0 || result_count != 0 ||
       result_last_count != 0 || data_valid || tag_valid || result_valid)
        $fatal(1,
               "ACTIVE_RESET_STALE_OUTPUT data=%0d tag=%0d results=%0d lasts=%0d",
               data_count, tag_count, result_count, result_last_count);
    axi_read(7'h04, status_word);
    if(status_word[5:0] !== 6'b000000)
        $fatal(1, "ACTIVE_RESET_STATUS_ERROR status=%08x", status_word);

    // Re-key after reset; the known-answer record below proves recovery.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    known_ct  = 128'h0388dace60b6a392f328c2b971b2fe78;
    known_tag = 128'hab6e47d42cec13bdf53a67b21257bddf;

    // Encrypt one all-zero block.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    wait_for_result();
    if(data_count != 16 || captured_data[127:0] !== known_ct)
        $fatal(1, "ENCRYPT_CT_MISMATCH count=%0d got=%032x", data_count,
               captured_data[127:0]);
    if(tag_count != 16 || captured_tag !== known_tag)
        $fatal(1, "ENCRYPT_TAG_MISMATCH count=%0d got=%032x", tag_count,
               captured_tag);
    if(captured_result !== 8'h00)
        $fatal(1, "ENCRYPT_RESULT_MISMATCH got=%02x", captured_result);

    // Re-key directly from a normally retired encryption record.  No reset or
    // ZEROIZE may hide a stale tag/result producer before the next command.
    rekey_after_completed_record_quiet(8'he0);

    // Decrypt: result handshake must precede the first plaintext byte.
    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    while(data_count != 16)
        @(posedge aclk);
    if(captured_result !== 8'h01 || captured_data[127:0] !== 128'd0)
        $fatal(1, "DECRYPT_SUCCESS_MISMATCH result=%02x data=%032x",
               captured_result, captured_data[127:0]);
    if(first_data_cycle <= result_cycle)
        $fatal(1, "AUTH_RELEASE_ORDER_ERROR result_cycle=%0d data_cycle=%0d",
               result_cycle, first_data_cycle);

    // Repeat the same public re-key watchdog after AUTH_OK and complete
    // plaintext release so stale compare state cannot recreate a result.
    rekey_after_completed_record_quiet(8'hd0);

    // Bad tag: explicit failure result and no plaintext release.
    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8] ^ ((i == 0) ? 8'h80 : 8'h00),
                  i == 15);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(captured_result !== 8'h02 || data_count != 0)
        $fatal(1, "BAD_TAG_RELEASE_ERROR result=%02x bytes=%0d",
               captured_result, data_count);

    // A one-bit change in each authenticated input class must fail closed.
    // Reuse the same public known-answer record for IV and ciphertext flips.
    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    for(i = 0; i < 12; i = i + 1)
        send_byte((i == 0) ? 8'h80 : 8'h00, 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || result_last_count != 1 ||
       captured_result !== 8'h02 || data_count != 0)
        $fatal(1,
               "IV_BIT_FLIP_RELEASE_ERROR result=%02x results=%0d lasts=%0d bytes=%0d",
               captured_result, result_count, result_last_count, data_count);

    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8] ^
                  ((i == 0) ? 8'h80 : 8'h00), 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || result_last_count != 1 ||
       captured_result !== 8'h02 || data_count != 0)
        $fatal(1,
               "CT_BIT_FLIP_RELEASE_ERROR result=%02x results=%0d lasts=%0d bytes=%0d",
               captured_result, result_count, result_last_count, data_count);

    // Generate the AAD-bearing reference through the public encrypt path,
    // then replay it for decrypt with exactly one AAD bit inverted.  The
    // deterministic LFSR inserts valid gaps without using random system tasks.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd8, 11'd128, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    wait_for_result();
    if(result_count != 1 || captured_result !== 8'h00 || data_count != 16 ||
       tag_count != 16)
        $fatal(1,
               "AAD_REFERENCE_ENCRYPT_ERROR result=%02x results=%0d data=%0d tag=%0d",
               captured_result, result_count, data_count, tag_count);
    aad_flip_ct = captured_data[127:0];
    aad_flip_tag = captured_tag;

    clear_capture();
    program_record(1'b1, 11'd96, 11'd8, 11'd128, OKAY);
    for(i = 0; i < 12; i = i + 1)
        send_byte_lfsr_gap(8'h00, 1'b0);
    send_byte_lfsr_gap(8'h80, 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte_lfsr_gap(aad_flip_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte_lfsr_gap(aad_flip_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || result_last_count != 1 ||
       captured_result !== 8'h02 || data_count != 0)
        $fatal(1,
               "AAD_BIT_FLIP_RELEASE_ERROR result=%02x results=%0d lasts=%0d bytes=%0d",
               captured_result, result_count, result_last_count, data_count);

    // One partial byte in each non-96-bit field exercises the registered
    // GHASH producer slot across IV -> AAD -> decrypt ciphertext boundaries.
    // Generate the matching ciphertext/tag through the public interface,
    // then require authenticated plaintext release on the decrypt record.
    clear_capture();
    program_record(1'b0, 11'd1, 11'd1, 11'd1, OKAY);
    send_byte(8'h80, 1'b0);
    send_byte(8'h80, 1'b0);
    send_byte(8'h80, 1'b1);
    wait_for_result();
    if(captured_result !== 8'h00 || data_count != 1 ||
       data_last_count != 1 || captured_last_user != 4'd1 ||
       tag_count != 16)
        $fatal(1,
               "NON96_PARTIAL_ENCRYPT_ERROR result=%02x data=%0d last=%0d user=%0d tag=%0d",
               captured_result, data_count, data_last_count,
               captured_last_user, tag_count);
    boundary_cipher = captured_data[7:0];
    boundary_tag = captured_tag;

    clear_capture();
    program_record(1'b1, 11'd1, 11'd1, 11'd1, OKAY);
    send_byte(8'h80, 1'b0);
    send_byte(8'h80, 1'b0);
    send_byte(boundary_cipher, 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(boundary_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    while(data_count != 1)
        @(posedge aclk);
    if(captured_result !== 8'h01 || data_count != 1 ||
       data_last_count != 1 || captured_data[7:0] !== 8'h80 ||
       captured_last_user != 4'd1 || tag_count != 0)
        $fatal(1,
               "NON96_PARTIAL_DECRYPT_ERROR result=%02x data=%0d last=%0d plain=%02x user=%0d tag=%0d",
               captured_result, data_count, data_last_count,
               captured_data[7:0], captured_last_user, tag_count);

    // AUTH_OK must cross the public result handshake before plaintext starts.
    clear_capture();
    result_ready = 1'b0;
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    while(!result_valid) @(posedge aclk);
    repeat(20) @(posedge aclk);
    if(data_count != 0 || result_count != 0)
        $fatal(1, "RESULT_BACKPRESSURE_RELEASE_ERROR data=%0d results=%0d",
               data_count, result_count);
    @(negedge aclk);
    result_ready = 1'b1;
    wait_for_result();
    while(data_count != 16) @(posedge aclk);

    // A stalled final tag beat must prevent ENC_OK from overtaking the tag.
    clear_capture();
    tag_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    while(!tag_valid) @(posedge aclk);
    stalled_tag_data = tag_out;
    stalled_tag_last = tag_last;
    repeat(20) @(posedge aclk);
    if(!tag_valid || (tag_out !== stalled_tag_data) ||
       (tag_last !== stalled_tag_last) || (result_count != 0))
        $fatal(1,
               "TAG_BACKPRESSURE_STABILITY_ERROR valid=%b data=%02x expected=%02x last=%b expected_last=%b result=%02x",
               tag_valid, tag_out, stalled_tag_data, tag_last,
               stalled_tag_last, captured_result);
    @(negedge aclk);
    tag_ready = 1'b1;
    wait_for_result();

    // A stalled ciphertext beat at the public boundary must also hold the
    // tag and ENC_OK behind it, even though the core can fill its output
    // register internally.
    clear_capture();
    data_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    while(!data_valid)
        @(posedge aclk);
    stalled_output_data = data_out;
    stalled_output_last = data_last;
    stalled_output_user = data_user;
    repeat(20) @(posedge aclk);
    if(!data_valid || (data_out !== stalled_output_data) ||
       (data_last !== stalled_output_last) ||
       (data_user !== stalled_output_user) || tag_count != 0 ||
       result_count != 0)
        $fatal(1,
               "DATA_BACKPRESSURE_STABILITY_ERROR valid=%b data=%02x expected=%02x last=%b expected_last=%b user=%0d expected_user=%0d tags=%0d results=%0d",
               data_valid, data_out, stalled_output_data, data_last,
               stalled_output_last, data_user, stalled_output_user,
               tag_count, result_count);
    @(negedge aclk);
    data_ready = 1'b1;
    wait_for_result();

    // An encryption result may be backpressured while the next descriptor
    // executes.  The older ENC_OK must remain stable and must cross the
    // public result handshake before E2's ciphertext, tag, and ENC_OK.
    clear_capture();
    result_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd1, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b1);
    while(!result_valid)
        @(posedge aclk);
    if((result_out !== 8'h00) || !result_last)
        $fatal(1, "PENDING_RESULT_SETUP_ERROR got=%02x last=%b",
               result_out, result_last);

    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    status_word = 0;
    for(i = 0; (i < 100) && !status_word[3]; i = i + 1)
        axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1, "PENDING_RESULT_DESCRIPTOR_NOT_STARTED status=%08x",
               status_word);

    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || (result_out !== 8'h00) || !result_last ||
           (result_count != 0))
            $fatal(1,
                   "PENDING_RESULT_NOT_STABLE valid=%b data=%02x last=%b count=%0d",
                   result_valid, result_out, result_last, result_count);
    end
    @(negedge aclk);
    result_ready = 1'b1;
    while(result_count != 2)
        @(posedge aclk);
    @(negedge aclk);
    if(result_history[0] !== 8'h00 || result_history[1] !== 8'h00 ||
       data_count != 17 || data_last_count != 2 || tag_count != 32)
        $fatal(1,
               "PENDING_RESULT_ORDER_ERROR r0=%02x r1=%02x data=%0d last=%0d tag=%0d",
               result_history[0], result_history[1], data_count,
               data_last_count, tag_count);

    // Exercise the distinct completion path too: E2 starts while E1's
    // ENC_OK is already stalled, then detects an early TLAST.  The 0x10
    // framing result must remain behind the older 0x00 result.
    clear_capture();
    result_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd1, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b1);
    while(!result_valid)
        @(posedge aclk);
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    status_word = 0;
    for(i = 0; (i < 100) && !status_word[3]; i = i + 1)
        axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1, "PENDING_RESULT_ABORT_NOT_STARTED status=%08x",
               status_word);
    send_byte(8'h00, 1'b1);
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid || (result_out !== 8'h00) || !result_last ||
           (result_count != 0))
            $fatal(1,
                   "PENDING_RESULT_ABORT_OVERTAKE valid=%b data=%02x last=%b count=%0d",
                   result_valid, result_out, result_last, result_count);
    end
    @(negedge aclk);
    result_ready = 1'b1;
    while(result_count != 2)
        @(posedge aclk);
    @(negedge aclk);
    if(result_history[0] !== 8'h00 || result_history[1] !== 8'h10 ||
       data_count != 1 || data_last_count != 1 || tag_count != 16)
        $fatal(1,
               "PENDING_RESULT_ABORT_ORDER r0=%02x r1=%02x data=%0d last=%0d tag=%0d",
               result_history[0], result_history[1], data_count,
               data_last_count, tag_count);

    // Continuous IV->data transition with a one-bit payload exercises the
    // tag-mask/data AES request arbiter and partial-byte masking.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd1, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b1);
    wait_for_result();
    if(data_count != 1 || captured_data[7:0] !== 8'h00 ||
       captured_last_user != 4'd1)
        $fatal(1, "ONE_BIT_DATA_ERROR count=%0d data=%02x user=%0d",
               data_count, captured_data[7:0], captured_last_user);

    // Maximum advertised payload length must produce 256 output bytes, not
    // overflow the ceil(bits/8) calculation back to zero.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd2047, OKAY);
    send_zero_iv();
    for(i = 0; i < 256; i = i + 1)
        send_byte(8'h00, i == 255);
    wait_for_result();
    if(data_count != 256 || captured_last_user != 4'd7)
        $fatal(1, "MAX_LENGTH_ERROR count=%0d user=%0d", data_count,
               captured_last_user);
    long_ct = captured_data;
    long_tag = captured_tag;

    // A later framing-error result must not overtake an older encryption tag
    // and ENC_OK.  Descriptor execution is still allowed while the tag is
    // stalled; only the completion register is ordered.
    clear_capture();
    tag_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd1, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b1);
    while(!tag_valid)
        @(posedge aclk);
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    send_byte(8'h00, 1'b1);
    repeat(50) @(posedge aclk);
    if(result_count != 0)
        $fatal(1, "OLDER_ENCRYPT_BARRIER_EARLY_RESULT count=%0d", result_count);
    @(negedge aclk);
    tag_ready = 1'b1;
    while(result_count != 2)
        @(posedge aclk);
    @(negedge aclk);
    if(result_history[0] !== 8'h00 || result_history[1] !== 8'h10 ||
       tag_count != 16)
        $fatal(1,
               "OLDER_ENCRYPT_BARRIER_ORDER r0=%02x r1=%02x tags=%0d",
               result_history[0], result_history[1], tag_count);

    // Two decrypt banks may execute concurrently, but D2's result must stay
    // hidden through every load bubble in D1's authenticated plaintext frame.
    // Once exposed under backpressure, RESULT_TVALID must remain asserted.
    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd2047, OKAY);
    send_zero_iv();
    for(i = 0; i < 256; i = i + 1)
        send_byte(long_ct[2047-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(long_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    @(negedge aclk);
    result_ready = 1'b0;
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    while(data_last_count == 0)
    begin
        // Sample on the falling edge so the capture counters from the final
        // public handshake have completed their nonblocking updates.
        @(negedge aclk);
        if((data_last_count == 0) && result_valid)
            $fatal(1, "RESULT_OVERSHOT_ACTIVE_DATA_FRAME bytes=%0d",
                   data_count);
    end
    while(!result_valid)
        @(posedge aclk);
    repeat(20)
    begin
        @(posedge aclk);
        if(!result_valid)
            $fatal(1, "RESULT_TVALID_REVOKED_UNDER_BACKPRESSURE");
    end
    @(negedge aclk);
    result_ready = 1'b1;
    while(result_count != 2)
        @(posedge aclk);
    while(data_last_count != 2)
        @(posedge aclk);
    @(negedge aclk);
    if(result_history[0] !== 8'h01 || result_history[1] !== 8'h01)
        $fatal(1, "TWO_BANK_RESULT_ORDER r0=%02x r1=%02x",
               result_history[0], result_history[1]);

    // A queued encryption must not take ownership of the shared data stream
    // while the final authenticated-plaintext beat is backpressured.  Once
    // that public TLAST crosses, the completed release-FIFO head may retire
    // while the encryption descriptor starts; it must never replay plaintext.
    clear_capture();
    data_ready = 1'b1;
    tag_ready = 1'b1;
    result_ready = 1'b1;
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    while(result_count != 1)
        @(posedge aclk);
    while(data_count != 15)
        @(negedge aclk);
    data_ready = 1'b0;
    while(!(data_valid && data_last))
        @(negedge aclk);
    stalled_output_data = data_out;
    stalled_output_last = data_last;
    stalled_output_user = data_user;

    // The encryption may execute behind the occupied output skid, but no
    // byte, tag, or result may overtake the stalled plaintext boundary beat.
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    if(result_count != 1 || data_count != 15 || tag_valid || !data_valid ||
       (data_out !== stalled_output_data) ||
       (data_last !== stalled_output_last) ||
       (data_user !== stalled_output_user))
        $fatal(1,
               "PLAIN_LAST_STALL_ORDER results=%0d bytes=%0d tag=%b valid=%b last=%b data=%02x user=%0d",
               result_count, data_count, tag_valid, data_valid, data_last,
               data_out, data_user);
    repeat(8)
    begin
        @(posedge aclk);
        if(result_count != 1 || data_count != 15 || !data_valid ||
           (data_out !== stalled_output_data) ||
           (data_last !== stalled_output_last) ||
           (data_user !== stalled_output_user))
            $fatal(1,
                   "PLAIN_LAST_STALL_CHANGED results=%0d bytes=%0d valid=%b last=%b data=%02x user=%0d",
                   result_count, data_count, data_valid, data_last, data_out,
                   data_user);
    end

    @(negedge aclk);
    data_ready = 1'b1;
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, i == 15);
    for(i = 0; (i < 10000) && (result_count != 2); i = i + 1)
        @(posedge aclk);
    @(negedge aclk);
    if(result_count != 2 || result_history[0] !== 8'h01 ||
       result_history[1] !== 8'h00 || data_count != 32 ||
       data_last_count != 2 || captured_data[255:128] !== 128'd0 ||
       captured_data[127:0] !== known_ct || tag_count != 16 ||
       captured_tag !== known_tag)
        $fatal(1,
               "PLAIN_LAST_THEN_ENCRYPT results=%0d r0=%02x r1=%02x bytes=%0d lasts=%0d data=%064x tags=%0d tag=%032x",
               result_count, result_history[0], result_history[1],
               data_count, data_last_count, captured_data[255:0],
               tag_count, captured_tag);

    // Production build rejects non-128-bit tags before accepting a record.
    axi_write(7'h08, {16'd0, 8'd96, 8'd0}, OKAY);
    axi_write(7'h00, 32'h00000001, SLVERR);

    // Early TLAST is reported on the result stream.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    send_byte(8'h00, 1'b1);
    if((public_frame_credits != 0) || s_ready)
        $fatal(1, "EARLY_TLAST_CREDIT_NOT_RETIRED ready=%b credits=%0d",
               s_ready, public_frame_credits);
    wait_for_result();
    if(captured_result !== 8'h10)
        $fatal(1, "EARLY_TLAST_RESULT_ERROR got=%02x", captured_result);

    // If ciphertext was already released before an input framing error, the
    // core must terminate that AXI data frame explicitly.  TUSER=0 marks the
    // synthetic abort terminator; otherwise the next record would be joined
    // to an unterminated ciphertext frame.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd256, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, 1'b0);
    while(data_count == 0)
        @(posedge aclk);
    @(negedge aclk);
    send_byte(8'h00, 1'b1);
    wait_for_result();
    if(captured_result !== 8'h10 || data_last_count != 1 ||
       captured_last_user != 4'd0)
        $fatal(1,
               "EARLY_TLAST_FRAME_ERROR result=%02x last_count=%0d user=%0d",
               captured_result, data_last_count, captured_last_user);

    // The early-TLAST edge immediately following the first completed input
    // block collides with ct_prod_valid entering an empty CT FIFO.  Registered
    // abort cleanup must suppress that not-yet-visible block rather than open
    // a public frame with no TLAST and strand the 0x10 result behind it.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd256, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, 1'b0);
    send_byte(8'h00, 1'b1);
    for(i = 0; (i < 500) && (result_count == 0); i = i + 1)
        @(posedge aclk);
    if(result_count != 1 || captured_result !== 8'h10 ||
       data_count != 0 || data_last_count != 0 || tag_count != 0)
        $fatal(1,
               "EARLY_TLAST_REGISTERED_CLEAR_ERROR result=%02x results=%0d data=%0d last=%0d tag=%0d",
               captured_result, result_count, data_count, data_last_count,
               tag_count);

    // Late TLAST enters ST_DRAIN.  The first ciphertext block was already
    // released, but the block containing the missing TLAST must be discarded;
    // a single TUSER=0 terminator closes the public frame before one 0x11
    // result is returned.
    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd256, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, 1'b0);
    while(data_count == 0)
        @(posedge aclk);
    @(negedge aclk);
    for(i = 0; i < 16; i = i + 1)
        send_byte(8'h00, 1'b0);
    axi_read(7'h04, status_word);
    if((public_frame_credits != 1) || !status_word[3])
        $fatal(1,
               "LATE_TLAST_RECORD_NOT_ACTIVE status=%08x credits=%0d",
               status_word, public_frame_credits);
    // ST_DRAIN must discard an arbitrary number of bytes without
    // reclassifying the eventual TLAST as a new early-TLAST error.
    send_byte(8'ha5, 1'b0);
    send_byte(8'h3c, 1'b0);
    send_byte(8'h5a, 1'b1);
    if((public_frame_credits != 0) || s_ready)
        $fatal(1, "DRAIN_TLAST_CREDIT_NOT_RETIRED ready=%b credits=%0d",
               s_ready, public_frame_credits);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(captured_result !== 8'h11 || result_count != 1 ||
       data_count != 17 || data_last_count != 1 ||
       captured_last_user != 4'd0 || tag_count != 0)
        $fatal(1,
               "LATE_TLAST_CLEANUP_ERROR result=%02x results=%0d data=%0d last=%0d user=%0d tag=%0d",
               captured_result, result_count, data_count, data_last_count,
               captured_last_user, tag_count);

    // Exercise the one-byte second block on both sides of the delayed
    // keystream pop.  send_byte reasserts TVALID in the same negedge delta,
    // so no sampled idle cycle is inserted between payload bytes.  The tags
    // below are independent bit-length AES-GCM references.
    for(partial_bits = 129; partial_bits <= 136;
        partial_bits = partial_bits + 1)
    begin
        partial_expected_ct = (partial_bits < 133) ?
            136'hfc7725319f495c6d0cd73d468e4d018700 :
            136'hfc7725319f495c6d0cd73d468e4d018708;
        partial_expected_tag = partial_tag_reference(partial_bits[10:0]);
        partial_expected_plain = {136{1'b1}};
        if(partial_bits[2:0] != 0)
            partial_expected_plain[7:0] =
                8'hff << (8 - partial_bits[2:0]);

        clear_capture();
        program_record(1'b0, 11'd96, 11'd0, partial_bits[10:0], OKAY);
        send_zero_iv();
        for(i = 0; i < 17; i = i + 1)
            send_byte(8'hff, i == 16);
        wait_for_result();
        if(result_count != 1 || captured_result !== 8'h00 ||
           data_count != 17 || captured_data[135:0] !== partial_expected_ct ||
           tag_count != 16 || captured_tag !== partial_expected_tag ||
           captured_last_user !== ((partial_bits[2:0] == 0) ?
                                    4'd8 : {1'b0, partial_bits[2:0]}))
            $fatal(1,
                   "PARTIAL_ENCRYPT_ERROR bits=%0d result=%02x data_count=%0d data=%034x tag_count=%0d tag=%032x user=%0d",
                   partial_bits, captured_result, data_count,
                   captured_data[135:0], tag_count, captured_tag,
                   captured_last_user);
        partial_cipher = captured_data[135:0];

        clear_capture();
        program_record(1'b1, 11'd96, 11'd0, partial_bits[10:0], OKAY);
        send_zero_iv();
        for(i = 0; i < 17; i = i + 1)
            send_byte(partial_cipher[135-i*8 -: 8], 1'b0);
        for(i = 0; i < 16; i = i + 1)
            send_byte(partial_expected_tag[127-i*8 -: 8], i == 15);
        wait_for_result();
        i = 0;
        while((data_count != 17) && (i < 10000))
        begin
            @(posedge aclk);
            i = i + 1;
        end
        if(result_count != 1 || captured_result !== 8'h01 ||
           data_count != 17 ||
           captured_data[135:0] !== partial_expected_plain ||
           tag_count != 0 ||
           captured_last_user !== ((partial_bits[2:0] == 0) ?
                                    4'd8 : {1'b0, partial_bits[2:0]}))
            $fatal(1,
                   "PARTIAL_DECRYPT_ERROR bits=%0d result=%02x data_count=%0d data=%034x tag_count=%0d user=%0d",
                   partial_bits, captured_result, data_count,
                   captured_data[135:0], tag_count, captured_last_user);
    end

    // Abort on the first byte after a complete decrypt block.  The completed
    // block may already be in the registered plaintext write command, but an
    // early TLAST must never authenticate or release it.  A following valid
    // decrypt proves that the freed bank contains no publicly visible stale
    // record state.
    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd256, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    send_byte(8'h00, 1'b1);
    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || captured_result !== 8'h10 ||
       data_count != 0 || data_last_count != 0 || tag_count != 0 ||
       data_valid)
        $fatal(1,
               "DECRYPT_NEXT_BLOCK_EARLY_TLAST_ERROR result=%02x results=%0d data=%0d last=%0d tag=%0d valid=%b",
               captured_result, result_count, data_count, data_last_count,
               tag_count, data_valid);

    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    for(i = 0; i < 16; i = i + 1)
        send_byte(known_tag[127-i*8 -: 8], i == 15);
    wait_for_result();
    while(data_count != 16)
        @(posedge aclk);
    if(result_count != 1 || captured_result !== 8'h01 ||
       captured_data[127:0] !== 128'd0 || data_last_count != 1 ||
       tag_count != 0)
        $fatal(1,
               "DECRYPT_AFTER_PENDING_ABORT_ERROR result=%02x results=%0d data=%032x last=%0d tag=%0d",
               captured_result, result_count, captured_data[127:0],
               data_last_count, tag_count);

    // ZEROIZE is always accepted even with a stalled public boundary beat.
    // Security clearing has priority over completing that frame: the stale
    // byte is discarded, no synthetic terminator reappears, and the accepted
    // descriptor still receives exactly one ZEROIZE_ABORT result.
    clear_capture();
    data_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd2047, OKAY);
    send_zero_iv();
    // With public output stalled, hold continuous legal input until public
    // READY applies backpressure.  Exact queue occupancy is intentionally
    // private; observing a stable stalled beat after many acknowledged bytes
    // establishes the protocol property this test needs.  Briefly release one
    // output beat so the held input can complete legally, then ZEROIZE must
    // flush every accepted byte and the stalled boundary output.
    input_handshake_baseline = input_handshake_count;
    i = 0;
    @(negedge aclk);
    s_data = 8'h5a;
    s_last = 1'b0;
    s_valid = 1'b1;
    while(s_ready && (i < 192))
    begin
        @(posedge aclk);
        @(negedge aclk);
        i = i + 1;
    end
    if(s_ready)
        $fatal(1, "ZEROIZE_PUBLIC_BACKPRESSURE_TIMEOUT attempts=%0d", i);
    repeat(3)
    begin
        @(posedge aclk);
        if(s_ready || !s_valid || (s_data !== 8'h5a) || s_last)
            $fatal(1,
                   "ZEROIZE_STALLED_INPUT_CHANGED ready=%b valid=%b data=%02x last=%b",
                   s_ready, s_valid, s_data, s_last);
    end
    @(negedge aclk);
    data_ready = 1'b1;
    while(!(s_valid && s_ready))
        @(posedge aclk);
    @(negedge aclk);
    s_valid = 1'b0;
    data_ready = 1'b0;
    prefetch_count = input_handshake_count - input_handshake_baseline;
    if(prefetch_count < 16)
        $fatal(1,
               "ZEROIZE_PUBLIC_PREFILL_TOO_SHORT accepted=%0d",
               prefetch_count);
    clear_capture();
    axi_write(7'h00, 32'h00000004, OKAY);
    public_frame_credits = 0;
    // A repeated command during scrubbing is accepted but must not overwrite
    // the first command's saved descriptor/result count.
    axi_write(7'h00, 32'h00000004, OKAY);
    @(negedge aclk);
    data_ready = 1'b1;
    repeat(20)
    begin
        @(posedge aclk);
        if(data_valid || tag_valid || s_ready)
            $fatal(1,
                   "ZEROIZE_STALE_PUBLIC_BEAT data=%b tag=%b input_ready=%b",
                   data_valid, tag_valid, s_ready);
    end
    wait_for_result();
    if(captured_result !== 8'h13 || result_count != 1 || data_count != 0 ||
       data_last_count != 0 || tag_count != 0)
        $fatal(1,
               "ZEROIZE_ABORT_ERROR result=%02x results=%0d data=%0d last=%0d tag=%0d",
               captured_result, result_count, data_count, data_last_count,
               tag_count);
    axi_read(7'h04, status_word);
    if(status_word[0] !== 1'b0)
        $fatal(1, "ZEROIZE_KEY_NOT_INVALIDATED status=%08x", status_word);

    // Re-key after the preceding destructive test.  A new descriptor may
    // start while an older ENC_OK is stalled in the shared result register.
    // ZEROIZE owes one abort result to each accepted descriptor.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    clear_capture();
    tag_ready = 1'b1;
    result_ready = 1'b0;
    program_record(1'b0, 11'd96, 11'd0, 11'd1, OKAY);
    send_zero_iv();
    send_byte(8'h00, 1'b1);
    while(!result_valid)
        @(posedge aclk);
    if((result_out !== 8'h00) || !result_last)
        $fatal(1, "ZEROIZE_OLDER_ENC_SETUP_RESULT got=%02x last=%b",
               result_out, result_last);

    // Start E2 after E1's ENC_OK is already backpressured.  E2 deliberately
    // remains active waiting for its IV.
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    status_word = 0;
    for(i = 0; (i < 100) && !status_word[3]; i = i + 1)
        axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1, "ZEROIZE_OLDER_ENC_SETUP_NOT_ACTIVE status=%08x",
               status_word);

    // Discard E1's already observed data/tag counters, but keep its result
    // stalled.  After ZEROIZE no stale boundary beat may survive.
    clear_capture();
    axi_write(7'h00, 32'h00000004, OKAY);
    public_frame_credits = 0;
    @(negedge aclk);
    result_ready = 1'b1;
    for(i = 0; (i < 200) && (result_count < 2); i = i + 1)
        @(posedge aclk);
    repeat(20) @(posedge aclk);
    @(negedge aclk);
    if(result_count != 2 || result_history[0] !== 8'h13 ||
       result_history[1] !== 8'h13 || data_count != 0 || tag_count != 0)
        $fatal(1,
               "ZEROIZE_OLDER_ENC_COUNT_ERROR results=%0d r0=%02x r1=%02x data=%0d tag=%0d",
               result_count, result_history[0], result_history[1], data_count,
               tag_count);
    axi_read(7'h04, status_word);
    if(status_word[0] !== 1'b0)
        $fatal(1, "ZEROIZE_OLDER_ENC_KEY_NOT_INVALIDATED status=%08x",
               status_word);

    // Re-key once more and present CONTROL.ZEROIZE and an early TLAST on the
    // same public cycle.  Internal queue/state alignment is deliberately not
    // observed: the public property is that all three input handshakes occur,
    // the accepted ZEROIZE has security priority over the pending framing
    // error, and exactly one 0x13 result emerges with no stale output.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    clear_capture();
    program_record(1'b0, 11'd96, 11'd0, 11'd128, OKAY);
    for(i = 0; i < 11; i = i + 1)
        send_byte(8'h00, 1'b0);
    axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_RECORD_NOT_ACTIVE status=%08x",
               status_word);

    @(negedge aclk);
    while(!(awready && wready && s_ready))
        @(negedge aclk);
    aw_handshake_baseline = aw_handshake_count;
    w_handshake_baseline = w_handshake_count;
    b_handshake_baseline = b_handshake_count;
    input_handshake_baseline = input_handshake_count;
    awaddr = 7'h00;
    awvalid = 1'b1;
    wdata = 32'h00000004;
    wstrb = 4'hf;
    wvalid = 1'b1;
    bready = 1'b1;
    s_data = 8'h00;
    s_last = 1'b1;
    s_valid = 1'b1;
    @(posedge aclk);
    @(negedge aclk);
    if((aw_handshake_count != (aw_handshake_baseline + 1)) ||
       (w_handshake_count != (w_handshake_baseline + 1)) ||
       (input_handshake_count != (input_handshake_baseline + 1)))
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_HANDSHAKE_ERROR aw=%0d/%0d w=%0d/%0d input=%0d/%0d",
               aw_handshake_count, aw_handshake_baseline,
               w_handshake_count, w_handshake_baseline,
               input_handshake_count, input_handshake_baseline);
    if(public_frame_credits != 1)
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_CREDIT_SETUP credits=%0d",
               public_frame_credits);
    public_frame_credits = 0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    s_valid = 1'b0;
    s_last = 1'b0;

    while(!bvalid)
        @(posedge aclk);
    if(bresp !== OKAY)
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_RESPONSE_ERROR bresp=%b", bresp);
    @(posedge aclk);
    @(negedge aclk);
    if(b_handshake_count != (b_handshake_baseline + 1))
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_B_HANDSHAKE_ERROR count=%0d baseline=%0d",
               b_handshake_count, b_handshake_baseline);
    bready = 1'b0;

    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || captured_result !== 8'h13 ||
       data_count != 0 || data_last_count != 0 || tag_count != 0 ||
       data_valid || tag_valid)
        $fatal(1,
               "ZEROIZE_ABORT_COLLISION_RESULT result=%02x results=%0d data=%0d last=%0d tag=%0d data_valid=%b tag_valid=%b",
               captured_result, result_count, data_count, data_last_count,
               tag_count, data_valid, tag_valid);
    axi_read(7'h04, status_word);
    if(status_word[0] !== 1'b0)
        $fatal(1, "ZEROIZE_ABORT_COLLISION_KEY_NOT_INVALIDATED status=%08x",
               status_word);

    // Re-key and collide ZEROIZE with the public handshake of a decrypt
    // record's final ciphertext byte.  The beat is acknowledged before the
    // tag field, so the pending plaintext write must be discarded/scrubbed
    // and the descriptor must produce only ZEROIZE_ABORT.
    axi_write(7'h20, 32'd0, OKAY);
    axi_write(7'h24, 32'd0, OKAY);
    axi_write(7'h28, 32'd0, OKAY);
    axi_write(7'h2c, 32'd0, OKAY);
    axi_write(7'h00, 32'h00000002, OKAY);
    status_word = 0;
    while(!status_word[0])
        axi_read(7'h04, status_word);

    clear_capture();
    program_record(1'b1, 11'd96, 11'd0, 11'd128, OKAY);
    send_zero_iv();
    for(i = 0; i < 15; i = i + 1)
        send_byte(known_ct[127-i*8 -: 8], 1'b0);
    axi_read(7'h04, status_word);
    if(!status_word[3])
        $fatal(1,
               "ZEROIZE_FINAL_CT_RECORD_NOT_ACTIVE status=%08x",
               status_word);

    @(negedge aclk);
    while(!(awready && wready && s_ready))
        @(negedge aclk);
    aw_handshake_baseline = aw_handshake_count;
    w_handshake_baseline = w_handshake_count;
    b_handshake_baseline = b_handshake_count;
    input_handshake_baseline = input_handshake_count;
    awaddr = 7'h00;
    awvalid = 1'b1;
    wdata = 32'h00000004;
    wstrb = 4'hf;
    wvalid = 1'b1;
    bready = 1'b1;
    s_data = known_ct[7:0];
    s_last = 1'b0;
    s_valid = 1'b1;
    @(posedge aclk);
    @(negedge aclk);
    if((aw_handshake_count != (aw_handshake_baseline + 1)) ||
       (w_handshake_count != (w_handshake_baseline + 1)) ||
       (input_handshake_count != (input_handshake_baseline + 1)))
        $fatal(1,
               "ZEROIZE_FINAL_CT_HANDSHAKE_ERROR aw=%0d/%0d w=%0d/%0d input=%0d/%0d",
               aw_handshake_count, aw_handshake_baseline,
               w_handshake_count, w_handshake_baseline,
               input_handshake_count, input_handshake_baseline);
    if(public_frame_credits != 1)
        $fatal(1, "ZEROIZE_FINAL_CT_CREDIT_SETUP credits=%0d",
               public_frame_credits);
    public_frame_credits = 0;
    awvalid = 1'b0;
    wvalid = 1'b0;
    s_valid = 1'b0;
    s_last = 1'b0;

    while(!bvalid)
        @(posedge aclk);
    if(bresp !== OKAY)
        $fatal(1, "ZEROIZE_FINAL_CT_RESPONSE_ERROR bresp=%b", bresp);
    @(posedge aclk);
    @(negedge aclk);
    if(b_handshake_count != (b_handshake_baseline + 1))
        $fatal(1,
               "ZEROIZE_FINAL_CT_B_HANDSHAKE_ERROR count=%0d baseline=%0d",
               b_handshake_count, b_handshake_baseline);
    bready = 1'b0;

    wait_for_result();
    repeat(20) @(posedge aclk);
    if(result_count != 1 || captured_result !== 8'h13 ||
       data_count != 0 || data_last_count != 0 || tag_count != 0 ||
       data_valid || tag_valid)
        $fatal(1,
               "ZEROIZE_FINAL_CT_RESULT_ERROR result=%02x results=%0d data=%0d last=%0d tag=%0d data_valid=%b tag_valid=%b",
               captured_result, result_count, data_count, data_last_count,
               tag_count, data_valid, tag_valid);
    axi_read(7'h04, status_word);
    if(status_word[0] !== 1'b0)
        $fatal(1, "ZEROIZE_FINAL_CT_KEY_NOT_INVALIDATED status=%08x",
               status_word);

    $display("AXI_SMOKE_PASS cycles=%0d", cycle_count);
    $finish;
end

endmodule
