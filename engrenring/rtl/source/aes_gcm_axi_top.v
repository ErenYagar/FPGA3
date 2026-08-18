`timescale 1ns / 1ps

// Production single-stream AES-GCM IP top.
module aes_gcm_axi_top #(
    parameter ALLOW_NIST_TAG_LENGTHS = 1'b0,
    parameter integer C_S_AXI_ADDR_WIDTH = 7
)(
    input                               aclk,
    input                               aresetn,
    input      [2:0]                    key_mode,

    input      [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input      [2:0]                    s_axi_awprot,
    input                               s_axi_awvalid,
    output                              s_axi_awready,
    input      [31:0]                   s_axi_wdata,
    input      [3:0]                    s_axi_wstrb,
    input                               s_axi_wvalid,
    output                              s_axi_wready,
    output     [1:0]                    s_axi_bresp,
    output                              s_axi_bvalid,
    input                               s_axi_bready,
    input      [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input      [2:0]                    s_axi_arprot,
    input                               s_axi_arvalid,
    output                              s_axi_arready,
    output     [31:0]                   s_axi_rdata,
    output     [1:0]                    s_axi_rresp,
    output                              s_axi_rvalid,
    input                               s_axi_rready,

    input      [7:0]                    s_axis_tdata,
    input                               s_axis_tvalid,
    output                              s_axis_tready,
    input                               s_axis_tlast,

    output     [7:0]                    m_axis_data_tdata,
    output                              m_axis_data_tvalid,
    input                               m_axis_data_tready,
    output                              m_axis_data_tlast,
    output     [3:0]                    m_axis_data_tuser,

    output     [7:0]                    m_axis_tag_tdata,
    output                              m_axis_tag_tvalid,
    input                               m_axis_tag_tready,
    output                              m_axis_tag_tlast,

    output     [7:0]                    m_axis_result_tdata,
    output                              m_axis_result_tvalid,
    input                               m_axis_result_tready,
    output                              m_axis_result_tlast
);

wire cmd_push_pulse;
wire key_commit_pulse;
wire zeroize_pulse;
wire cfg_decrypt;
wire [7:0] cfg_tag_bits;
wire [10:0] iv_len_bits;
wire [10:0] aad_len_bits;
wire [10:0] data_len_bits;
wire [255:0] key_staging;

wire core_key_ready;
wire core_key_busy;
wire core_key_quiescent;
wire core_cmd_full;
wire core_cmd_pending;
wire core_record_active;
wire core_output_pending;
wire core_zeroize_busy;
wire core_zeroize_defer;
wire data_skid_valid;
wire tag_skid_valid;

function tag_length_allowed;
input [7:0] tag_bits;
begin
    if(tag_bits == 8'd128)
        tag_length_allowed = 1'b1;
    else if(ALLOW_NIST_TAG_LENGTHS)
    begin
        case(tag_bits)
            8'd32, 8'd64, 8'd96, 8'd104, 8'd112, 8'd120:
                tag_length_allowed = 1'b1;
            default: tag_length_allowed = 1'b0;
        endcase
    end
    else
        tag_length_allowed = 1'b0;
end
endfunction

wire reject_cmd_push = !core_key_ready || core_cmd_full ||
                       core_zeroize_busy || (iv_len_bits == 0) ||
                       !tag_length_allowed(cfg_tag_bits);
wire reject_key_commit = (key_mode > 3'd2) || core_key_busy ||
                         !core_key_quiescent ||
                         data_skid_valid || tag_skid_valid ||
                         core_zeroize_busy;
// ZEROIZE is always accepted.  It has priority over preserving an in-flight
// public frame: the boundary registers and frame trackers below are cleared
// synchronously, while the core returns one abort result per unfinished
// accepted descriptor after scrubbing.

axi_lite_regs #(
    .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
    .ALLOW_NIST_TAG_LENGTHS(ALLOW_NIST_TAG_LENGTHS)
) u_registers (
    .s_axi_aclk(aclk), .s_axi_aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot),
    .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
    .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata),
    .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rready(s_axi_rready),
    .key_ready_i(core_key_ready && !key_commit_pulse && !zeroize_pulse),
    .key_busy_i(core_key_busy || key_commit_pulse),
    .cmd_full_i(core_cmd_full),
    .record_active_i(core_record_active),
    .output_pending_i(core_output_pending || data_skid_valid ||
                      tag_skid_valid),
    .zeroize_busy_i(core_zeroize_busy || zeroize_pulse),
    .reject_cmd_push_i(reject_cmd_push),
    .reject_key_commit_i(reject_key_commit),
    .reject_zeroize_i(1'b0),
    .cmd_push_pulse_o(cmd_push_pulse),
    .key_commit_pulse_o(key_commit_pulse),
    .zeroize_pulse_o(zeroize_pulse), .cfg_decrypt_o(cfg_decrypt),
    .cfg_tag_bits_o(cfg_tag_bits), .iv_len_bits_o(iv_len_bits),
    .aad_len_bits_o(aad_len_bits), .data_len_bits_o(data_len_bits),
    .key_staging_o(key_staging)
);

// A two-entry registered-head queue cuts the core's byte-level acceptance
// logic away from the public ready path while sustaining one byte per clock.
// Public READY is registered.  A small credit count tracks accepted record
// descriptors at the public boundary, so data without a successful CMD_PUSH
// can never enter the queue and a record credit is retired exactly when its
// public TLAST handshakes (including an early TLAST).
wire [7:0] core_s_tdata;
wire core_s_tvalid;
wire core_s_tready;
wire core_s_tlast;
wire [8:0] inputq_out_data;
wire inputq_in_ready;
wire inputq_out_valid;
wire [1:0] inputq_count;
reg  [1:0] input_frame_credits;
reg        s_axis_tready_r;

// ZEROIZE gates READY in the command pulse cycle, before the registered
// value is cleared at the following active clock edge.
assign s_axis_tready = s_axis_tready_r && !zeroize_pulse;

wire public_input_fire = s_axis_tvalid && s_axis_tready;
wire public_frame_done = public_input_fire && s_axis_tlast;
wire inputq_pop = inputq_out_valid && core_s_tready;

reg [1:0] input_frame_credits_next;
always @(*)
begin
    input_frame_credits_next = input_frame_credits;
    case({cmd_push_pulse, public_frame_done})
        2'b10:
            if(input_frame_credits != 2'd3)
                input_frame_credits_next = input_frame_credits + 2'd1;
        2'b01:
            input_frame_credits_next = input_frame_credits - 2'd1;
        default:
            input_frame_credits_next = input_frame_credits;
    endcase
end

// Predict occupancy after the current edge.  READY may remain asserted only
// if the two-entry queue will still have room for the following cycle.  This
// is the standard registered-ready look-ahead rule and prevents an overflow
// without restoring a combinational core-to-port path.
wire [2:0] inputq_count_next = {1'b0, inputq_count} +
                               (public_input_fire ? 3'd1 : 3'd0) -
                               (inputq_pop ? 3'd1 : 3'd0);

always @(posedge aclk)
begin
    if(!aresetn || zeroize_pulse)
    begin
        input_frame_credits <= 2'd0;
        s_axis_tready_r     <= 1'b0;
    end
    else
    begin
        input_frame_credits <= input_frame_credits_next;
        if(core_zeroize_busy)
            s_axis_tready_r <= 1'b0;
        else
            s_axis_tready_r <= (input_frame_credits_next != 2'd0) &&
                               (inputq_count_next < 3'd2);
    end
end

stream_fifo #(.WIDTH(9), .DEPTH(2), .ADDR_W(1)) u_input_queue (
    .clk(aclk), .rst_n(aresetn), .clear(zeroize_pulse),
    .in_data({s_axis_tlast, s_axis_tdata}),
    .in_valid(public_input_fire),
    .in_ready(inputq_in_ready), .out_data(inputq_out_data),
    .out_valid(inputq_out_valid), .out_ready(core_s_tready),
    .count(inputq_count)
);

assign core_s_tdata = inputq_out_data[7:0];
assign core_s_tvalid = inputq_out_valid;
assign core_s_tlast = inputq_out_data[8];

wire [7:0] core_data_tdata;
wire core_data_tvalid;
wire core_data_tready;
wire core_data_tlast;
wire [3:0] core_data_tuser;
wire [7:0] core_tag_tdata;
wire core_tag_tvalid;
wire core_tag_tready;
wire core_tag_tlast;
wire [7:0] core_result_tdata;
wire core_result_tvalid;
wire core_result_tready;
wire core_result_tlast;

aes_gcm_stream_core #(
    .ALLOW_NIST_TAG_LENGTHS(ALLOW_NIST_TAG_LENGTHS)
) u_core (
    .clk(aclk), .rst_n(aresetn), .key_commit(key_commit_pulse),
    .zeroize(zeroize_pulse), .key_mode(key_mode), .key_data(key_staging),
    .key_ready(core_key_ready), .key_busy(core_key_busy),
    .key_quiescent(core_key_quiescent),
    .cmd_push(cmd_push_pulse), .cmd_decrypt(cfg_decrypt),
    .cmd_tag_bits(cfg_tag_bits), .cmd_iv_bits(iv_len_bits),
    .cmd_aad_bits(aad_len_bits), .cmd_data_bits(data_len_bits),
    .cmd_full(core_cmd_full), .cmd_pending(core_cmd_pending),
    .record_active(core_record_active),
    .output_pending(core_output_pending),
    .zeroize_busy(core_zeroize_busy),
    .zeroize_defer(core_zeroize_defer), .s_axis_tdata(core_s_tdata),
    .s_axis_tvalid(core_s_tvalid), .s_axis_tready(core_s_tready),
    .s_axis_tlast(core_s_tlast), .m_axis_data_tdata(core_data_tdata),
    .m_axis_data_tvalid(core_data_tvalid),
    .m_axis_data_tready(core_data_tready),
    .m_axis_data_tlast(core_data_tlast),
    .m_axis_data_tuser(core_data_tuser),
    .m_axis_tag_tdata(core_tag_tdata),
    .m_axis_tag_tvalid(core_tag_tvalid),
    .m_axis_tag_tready(core_tag_tready),
    .m_axis_tag_tlast(core_tag_tlast),
    .m_axis_result_tdata(core_result_tdata),
    .m_axis_result_tvalid(core_result_tvalid),
    .m_axis_result_tready(core_result_tready),
    .m_axis_result_tlast(core_result_tlast)
);

// Register the two byte outputs at the OOC boundary.  Frame ownership is
// tracked from the outermost handshakes, so bubbles between 16-byte plaintext
// blocks cannot expose a later result.  Registered boundary-idle eligibility
// keeps a stalled result stable until its public handshake.
wire [7:0] data_skid_tdata;
wire data_skid_tkeep;
wire data_skid_tlast;
wire [3:0] data_skid_tuser;
wire data_skid_sready;
wire [7:0] tag_skid_tdata;
wire tag_skid_tlast;
wire tag_skid_sready;
wire tag_skid_raw_valid;
wire [8:0] tag_fifo_out;
wire [1:0] tag_fifo_count;
wire tag_may_leave;

(* keep = "true", equivalent_register_removal = "no" *)
reg data_boundary_idle_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg tag_boundary_idle_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg public_frames_idle_core_r;

wire data_public_valid = data_skid_valid && !zeroize_pulse;
wire data_public_fire = data_public_valid && m_axis_data_tready;
wire result_owns_public = core_result_tvalid && public_frames_idle_core_r;
wire result_public_valid = core_result_tvalid && result_owns_public &&
                           !zeroize_pulse;
wire data_input_allowed = tag_boundary_idle_r &&
                          !result_owns_public && !zeroize_pulse;
wire tag_input_allowed = !result_owns_public && !zeroize_pulse;
wire data_boundary_push_w = core_data_tvalid && data_input_allowed &&
                            data_skid_sready;
wire tag_boundary_push_w = core_tag_tvalid && tag_input_allowed &&
                           tag_skid_sready;
wire tag_boundary_pop_w = tag_skid_raw_valid && m_axis_tag_tready &&
                          tag_may_leave;
wire data_boundary_idle_next_w = data_boundary_push_w ? 1'b0 :
                                 (data_public_fire && data_skid_tlast) ?
                                 1'b1 : data_boundary_idle_r;
wire tag_boundary_idle_next_w = tag_boundary_push_w ? 1'b0 :
                                (tag_boundary_pop_w && tag_skid_tlast &&
                                 (tag_fifo_count == 2'd1)) ?
                                1'b1 : tag_boundary_idle_r;

always @(posedge aclk)
begin
    if(!aresetn || zeroize_pulse)
    begin
        data_boundary_idle_r <= 1'b1;
        tag_boundary_idle_r  <= 1'b1;
        public_frames_idle_core_r <= 1'b1;
    end
    else
    begin
        data_boundary_idle_r <= data_boundary_idle_next_w;
        tag_boundary_idle_r  <= tag_boundary_idle_next_w;
        public_frames_idle_core_r <= data_boundary_idle_next_w &&
                                     tag_boundary_idle_next_w;
    end
end

axis_output_skid_8 #(.USER_WIDTH(4)) u_data_output_register (
    .aclk(aclk), .aresetn(aresetn), .clear(zeroize_pulse),
    .s_axis_tdata(core_data_tdata), .s_axis_tkeep(1'b1),
    .s_axis_tlast(core_data_tlast), .s_axis_tuser(core_data_tuser),
    .s_axis_tvalid(core_data_tvalid && data_input_allowed),
    .s_axis_tready(data_skid_sready),
    .m_axis_tdata(data_skid_tdata), .m_axis_tkeep(data_skid_tkeep),
    .m_axis_tlast(data_skid_tlast), .m_axis_tuser(data_skid_tuser),
    .m_axis_tvalid(data_skid_valid), .m_axis_tready(m_axis_data_tready)
);

assign core_data_tready = data_skid_sready && data_input_allowed;
assign m_axis_data_tdata = data_skid_tdata;
assign m_axis_data_tvalid = data_public_valid;
assign m_axis_data_tlast = data_skid_tlast;
assign m_axis_data_tuser = data_skid_tuser;

assign tag_may_leave = data_boundary_idle_r &&
                       !result_owns_public && !zeroize_pulse;

// Two entries decouple the core's tag-byte accept event from the public
// output slot.  The input-ready signal depends only on the registered FIFO
// count, while the second entry hides the one-cycle refill after a full FIFO
// starts draining.
stream_fifo #(.WIDTH(9), .DEPTH(2), .ADDR_W(1)) u_tag_output_register (
    .clk(aclk), .rst_n(aresetn), .clear(zeroize_pulse),
    .in_data({core_tag_tlast, core_tag_tdata}),
    .in_valid(core_tag_tvalid && tag_input_allowed),
    .in_ready(tag_skid_sready), .out_data(tag_fifo_out),
    .out_valid(tag_skid_raw_valid),
    .out_ready(m_axis_tag_tready && tag_may_leave),
    .count(tag_fifo_count)
);

assign tag_skid_tdata = tag_fifo_out[7:0];
assign tag_skid_tlast = tag_fifo_out[8];
assign tag_skid_valid = tag_skid_raw_valid;
assign core_tag_tready = tag_skid_sready && tag_input_allowed;
assign m_axis_tag_tdata = tag_skid_tdata;
assign m_axis_tag_tvalid = tag_skid_raw_valid && tag_may_leave &&
                           !zeroize_pulse;
assign m_axis_tag_tlast = tag_skid_tlast;

assign m_axis_result_tdata = core_result_tdata;
assign m_axis_result_tvalid = result_public_valid;
assign m_axis_result_tlast = core_result_tlast && result_owns_public &&
                             !zeroize_pulse;
// READY may be asserted before VALID.  Keeping eligibility independent of
// core_result_tvalid cuts the result-valid/grant/ready feedback cone while
// preserving the same public and core handshake edge.
assign core_result_tready = m_axis_result_tready &&
                            public_frames_idle_core_r &&
                            !zeroize_pulse;

endmodule
