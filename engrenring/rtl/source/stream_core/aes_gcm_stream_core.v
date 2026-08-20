`timescale 1ns / 1ps

// Single-record AES-GCM streaming engine.  The byte stream is described by a
// queued descriptor and is consumed in this fixed order:
// IV, AAD, PT/CT, and (for decrypt) the received tag.
//
// Encryption ciphertext is emitted as soon as complete AES blocks return.
// Decryption plaintext is held in one of two packet banks until the tag has
// been checked and the DEC_AUTH_OK result beat has been accepted.
module aes_gcm_stream_core #(
    parameter ALLOW_NIST_TAG_LENGTHS = 1'b0
)(
    input           clk,
    input           rst_n,

    input           key_commit,
    input           zeroize,
    input  [2:0]    key_mode,
    input  [255:0]  key_data,
    output          key_ready,
    output          key_busy,
    output          key_quiescent,

    input           cmd_push,
    input           cmd_decrypt,
    input  [7:0]    cmd_tag_bits,
    input  [10:0]   cmd_iv_bits,
    input  [10:0]   cmd_aad_bits,
    input  [10:0]   cmd_data_bits,
    output          cmd_full,
    output          cmd_pending,
    output          record_active,
    output          output_pending,
    output          zeroize_busy,
    output          zeroize_defer,

    input  [7:0]    s_axis_tdata,
    input           s_axis_tvalid,
    output          s_axis_tready,
    input           s_axis_tlast,

    output [7:0]    m_axis_data_tdata,
    output          m_axis_data_tvalid,
    input           m_axis_data_tready,
    output          m_axis_data_tlast,
    output [3:0]    m_axis_data_tuser,

    output [7:0]    m_axis_tag_tdata,
    output          m_axis_tag_tvalid,
    input           m_axis_tag_tready,
    output          m_axis_tag_tlast,

    output [7:0]    m_axis_result_tdata,
    output          m_axis_result_tvalid,
    input           m_axis_result_tready,
    output          m_axis_result_tlast
);

localparam [7:0] RESULT_ENC_OK           = 8'h00;
localparam [7:0] RESULT_DEC_AUTH_OK      = 8'h01;
localparam [7:0] RESULT_DEC_AUTH_FAIL    = 8'h02;
localparam [7:0] RESULT_EARLY_TLAST      = 8'h10;
localparam [7:0] RESULT_LATE_TLAST       = 8'h11;
localparam [7:0] RESULT_COUNTER_OVERFLOW = 8'h12;
localparam [7:0] RESULT_ZEROIZE_ABORT    = 8'h13;
localparam [7:0] RESULT_INTERNAL_ERROR   = 8'h1f;

localparam [3:0] ST_IDLE       = 4'd0;
localparam [3:0] ST_IV         = 4'd1;
localparam [3:0] ST_IV_WAIT    = 4'd2;
localparam [3:0] ST_AAD        = 4'd3;
localparam [3:0] ST_DATA       = 4'd4;
localparam [3:0] ST_TAG_IN     = 4'd5;
localparam [3:0] ST_FINAL_WAIT = 4'd6;
localparam [3:0] ST_DEC_RESULT = 4'd7;
localparam [3:0] ST_ENC_TAG    = 4'd8;
localparam [3:0] ST_ENC_RESULT = 4'd9;
localparam [3:0] ST_DRAIN      = 4'd10;
localparam [3:0] ST_ABORT_WAIT = 4'd11;
localparam [3:0] ST_DESC_SUM   = 4'd12;
localparam [3:0] ST_DESC_START = 4'd13;
localparam [3:0] ST_DESC_TOTAL = 4'd14;
localparam [3:0] ST_DESC_WAIT  = 4'd15;

localparam [2:0] IFM_NONE   = 3'd0;
localparam [2:0] IFM_START  = 3'd1;
localparam [2:0] IFM_IV96   = 3'd2;
localparam [2:0] IFM_IVHASH = 3'd3;
localparam [2:0] IFM_AAD    = 3'd4;
localparam [2:0] IFM_DATA   = 3'd5;
localparam [2:0] IFM_TAG    = 3'd6;
localparam [2:0] IFM_DRAIN  = 3'd7;

localparam [2:0] AES_KIND_H        = 3'd0;
localparam [2:0] AES_KIND_TAG_MASK = 3'd1;
localparam [2:0] AES_KIND_CTR_PREFETCH = 3'd4;

localparam [2:0] GH_KIND_IV_DATA  = 3'd0;
localparam [2:0] GH_KIND_IV_LEN   = 3'd1;
localparam [2:0] GH_KIND_MSG_DATA = 3'd2;
localparam [2:0] GH_KIND_MSG_LEN  = 3'd3;

reg zeroize_busy_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg zeroize_sequence_active_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg crypto_context_live_r;
wire crypto_event_enable_w = crypto_context_live_r &&
                             !zeroize && !zeroize_busy_r;

function [8:0] bits_to_bytes;
input [10:0] bits;
reg [11:0] rounded;
begin
    rounded = {1'b0, bits} + 12'd7;
    bits_to_bytes = rounded[11:3];
end
endfunction

function [4:0] bits_to_blocks;
input [10:0] bits;
reg [11:0] rounded;
begin
    rounded = {1'b0, bits} + 12'd127;
    bits_to_blocks = rounded[11:7];
end
endfunction

function [3:0] valid_bits_last;
input [10:0] bits;
begin
    valid_bits_last = (bits[2:0] == 3'd0) ? 4'd8 : {1'b0, bits[2:0]};
end
endfunction

function [7:0] mask_final_byte;
input [7:0] value;
input [10:0] bits;
begin
    case(bits[2:0])
        3'd0: mask_final_byte = value;
        3'd1: mask_final_byte = {value[7], 7'd0};
        3'd2: mask_final_byte = {value[7:6], 6'd0};
        3'd3: mask_final_byte = {value[7:5], 5'd0};
        3'd4: mask_final_byte = {value[7:4], 4'd0};
        3'd5: mask_final_byte = {value[7:3], 3'd0};
        3'd6: mask_final_byte = {value[7:2], 2'd0};
        default: mask_final_byte = {value[7:1], 1'b0};
    endcase
end
endfunction

function [127:0] put_block_byte;
input [127:0] block;
input [3:0] index;
input [7:0] value;
reg [127:0] temp;
begin
    temp = block;
    case(index)
        4'd0:  temp[127:120] = value;
        4'd1:  temp[119:112] = value;
        4'd2:  temp[111:104] = value;
        4'd3:  temp[103:96]  = value;
        4'd4:  temp[95:88]   = value;
        4'd5:  temp[87:80]   = value;
        4'd6:  temp[79:72]   = value;
        4'd7:  temp[71:64]   = value;
        4'd8:  temp[63:56]   = value;
        4'd9:  temp[55:48]   = value;
        4'd10: temp[47:40]   = value;
        4'd11: temp[39:32]   = value;
        4'd12: temp[31:24]   = value;
        4'd13: temp[23:16]   = value;
        4'd14: temp[15:8]    = value;
        default: temp[7:0]   = value;
    endcase
    put_block_byte = temp;
end
endfunction

function [4:0] final_block_bytes;
input [10:0] bits;
reg [7:0] remainder;
begin
    remainder = bits[6:0];
    if(remainder == 0)
        final_block_bytes = 5'd16;
    else
        final_block_bytes = (remainder + 7) >> 3;
end
endfunction

function [7:0] get_block_byte;
input [127:0] block;
input [3:0] index;
begin
    case(index)
        4'd0:  get_block_byte = block[127:120];
        4'd1:  get_block_byte = block[119:112];
        4'd2:  get_block_byte = block[111:104];
        4'd3:  get_block_byte = block[103:96];
        4'd4:  get_block_byte = block[95:88];
        4'd5:  get_block_byte = block[87:80];
        4'd6:  get_block_byte = block[79:72];
        4'd7:  get_block_byte = block[71:64];
        4'd8:  get_block_byte = block[63:56];
        4'd9:  get_block_byte = block[55:48];
        4'd10: get_block_byte = block[47:40];
        4'd11: get_block_byte = block[39:32];
        4'd12: get_block_byte = block[31:24];
        4'd13: get_block_byte = block[23:16];
        4'd14: get_block_byte = block[15:8];
        default: get_block_byte = block[7:0];
    endcase
end
endfunction

function [127:0] mask_result_block;
input [127:0] block;
input [4:0] byte_count;
input [10:0] valid_bits;
integer byte_number;
reg [127:0] temp;
reg [7:0] selected_byte;
begin
    temp = 128'd0;
    for(byte_number = 0; byte_number < 16; byte_number = byte_number + 1)
    begin
        if(byte_number < byte_count)
        begin
            selected_byte = get_block_byte(block, byte_number[3:0]);
            if(byte_number == (byte_count - 1))
                selected_byte = mask_final_byte(selected_byte, valid_bits);
            temp = put_block_byte(temp, byte_number[3:0], selected_byte);
        end
    end
    mask_result_block = temp;
end
endfunction

function [15:0] tag_byte_enable_mask;
input [7:0] tag_bits;
begin
    case(tag_bits)
        8'd32:  tag_byte_enable_mask = 16'h000f;
        8'd64:  tag_byte_enable_mask = 16'h00ff;
        8'd96:  tag_byte_enable_mask = 16'h0fff;
        8'd104: tag_byte_enable_mask = 16'h1fff;
        8'd112: tag_byte_enable_mask = 16'h3fff;
        8'd120: tag_byte_enable_mask = 16'h7fff;
        default: tag_byte_enable_mask = 16'hffff;
    endcase
end
endfunction

// -------------------------------------------------------------------------
// Descriptor FIFO
// -------------------------------------------------------------------------
wire [41:0] desc_in_data = {cmd_decrypt, cmd_tag_bits,
                            cmd_iv_bits, cmd_aad_bits, cmd_data_bits};
wire [41:0] desc_out_data;
wire desc_in_ready;
wire desc_out_valid;
wire desc_out_ready;
wire [1:0] desc_count;
wire queue_clear;

stream_fifo #(.WIDTH(42), .DEPTH(2), .ADDR_W(1)) u_desc_fifo (
    .clk(clk), .rst_n(rst_n), .clear(zeroize),
    .in_data(desc_in_data), .in_valid(cmd_push), .in_ready(desc_in_ready),
    .out_data(desc_out_data), .out_valid(desc_out_valid),
    .out_ready(desc_out_ready), .count(desc_count)
);

assign cmd_full = !desc_in_ready;
assign cmd_pending = (desc_count != 0);

// -------------------------------------------------------------------------
// Key context and shared AES block service
// -------------------------------------------------------------------------
wire key_context_busy;
wire key_context_ready;
wire [1:0] expanded_key_size;
wire [1919:0] round_keys;
wire [3:0] round_count;

aes_key_context u_key_context (
    .clk(clk), .rst_n(rst_n), .commit(key_commit), .key_mode(key_mode),
    .key(key_data), .zeroize(zeroize), .busy(key_context_busy),
    .ready(key_context_ready), .key_size(expanded_key_size),
    .round_keys(round_keys), .round_count(round_count)
);

wire aes_engine_ready;
wire aes_engine_busy;
wire aes_engine_done;
wire [127:0] aes_engine_out;
wire aes_engine_offer_w;
wire aes_engine_accept_w;
wire [127:0] aes_engine_in;

aes_block_engine u_aes_engine (
    .clk(clk), .rst_n(rst_n && !zeroize), .start(aes_engine_offer_w),
    .key_size(expanded_key_size), .round_keys(round_keys),
    .block_in(aes_engine_in), .ready(aes_engine_ready),
    .busy(aes_engine_busy), .done(aes_engine_done),
    .block_out(aes_engine_out)
);

// AES request format:
// {pad, kind, AES input, XOR payload, byte count, last, block index, bank}
reg          aes_prod_valid;
reg [271:0]  aes_prod_data;
wire         aes_prod_ready;
wire [271:0] aesq_out;
wire         aesq_valid;
wire         aesq_ready;
wire [2:0]   aesq_count;

stream_fifo #(.WIDTH(272), .DEPTH(4), .ADDR_W(2)) u_aes_request_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(aes_prod_data), .in_valid(aes_prod_valid),
    .in_ready(aes_prod_ready), .out_data(aesq_out),
    .out_valid(aesq_valid), .out_ready(aesq_ready), .count(aesq_count)
);

// Metadata follows accepted AES requests and is matched to in-order results.
wire [142:0] aes_meta_in = {aesq_out[270:268], aesq_out[139:0]};
wire [142:0] aes_meta_out;
wire aes_meta_in_ready;
wire aes_meta_out_valid;
wire aes_meta_out_ready;
wire [2:0] aes_meta_count;
reg [142:0] aes_meta_stage_data_r;
reg aes_meta_stage_valid_r;
wire aes_meta_stage_ready_w = !aes_meta_stage_valid_r || aes_meta_in_ready;

stream_fifo #(.WIDTH(143), .DEPTH(4), .ADDR_W(2)) u_aes_meta_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(aes_meta_stage_data_r), .in_valid(aes_meta_stage_valid_r),
    .in_ready(aes_meta_in_ready), .out_data(aes_meta_out),
    .out_valid(aes_meta_out_valid), .out_ready(aes_meta_out_ready),
    .count(aes_meta_count)
);

// AES results are buffered because the engine itself has no output ready.
wire [270:0] aes_result_in = {aes_engine_out, aes_meta_out};
wire [270:0] aes_result_out;
wire aes_result_in_ready;
wire aes_result_out_valid;
wire aes_result_out_ready_w;
wire [2:0] aes_result_count;
(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg [2:0] aes_outstanding_count_r;

stream_fifo #(.WIDTH(271), .DEPTH(4), .ADDR_W(2)) u_aes_result_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(aes_result_in),
    .in_valid(aes_engine_done && aes_meta_out_valid),
    .in_ready(aes_result_in_ready), .out_data(aes_result_out),
    .out_valid(aes_result_out_valid), .out_ready(aes_result_out_ready_w),
    .count(aes_result_count)
);

// Mirror the result FIFO's non-empty state across a register boundary.  The
// FIFO keeps its raw valid/ready handshake; this copy is used only by the
// control observer so the FIFO count does not feed the state decoder.
(* KEEP = "TRUE", EQUIVALENT_REGISTER_REMOVAL = "NO" *)
reg aes_result_available_r;
wire aes_result_push_w = aes_engine_done && aes_meta_out_valid &&
                         aes_result_in_ready;
wire aes_result_pop_w = aes_result_out_valid && aes_result_out_ready_w;

// This counter mirrors stage_valid + metadata FIFO count + result FIFO count.
// Internal stage/FIFO transfers preserve the total; only an accepted request or
// a consumed result changes it.  The raw FIFO counts remain authoritative for
// abort draining, while this registered copy keeps their sum off AES launch.
always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        aes_outstanding_count_r <= 3'd0;
    else if(aes_engine_accept_w && !aes_result_pop_w)
        aes_outstanding_count_r <= aes_outstanding_count_r + 3'd1;
    else if(aes_result_pop_w && !aes_engine_accept_w)
        aes_outstanding_count_r <= aes_outstanding_count_r - 3'd1;
end

always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        aes_result_available_r <= 1'b0;
    else if(aes_result_push_w && !aes_result_pop_w)
        aes_result_available_r <= 1'b1;
    else if(aes_result_pop_w && !aes_result_push_w &&
            (aes_result_count == 3'd1))
        aes_result_available_r <= 1'b0;
end

// Decouple AES launch control from the distributed-RAM metadata write enable.
// When the old stage entry advances, the same edge may speculatively capture
// the next request payload and replace its valid bit with the accepted event. The
// payload has no reset because it is meaningful only while stage_valid is set.
always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        aes_meta_stage_valid_r <= 1'b0;
    else if(aes_meta_stage_ready_w)
    begin
        aes_meta_stage_valid_r <= aes_engine_accept_w;
        aes_meta_stage_data_r  <= aes_meta_in;
    end
end

assign aesq_ready = crypto_event_enable_w && aes_engine_ready &&
                    !aes_outstanding_count_r[2];
assign aes_engine_offer_w = aesq_valid && crypto_event_enable_w &&
                            !aes_outstanding_count_r[2];
assign aes_engine_accept_w = aes_engine_offer_w && aes_engine_ready;
assign aes_engine_in = aesq_out[267:140];
assign aes_meta_out_ready = aes_engine_done && aes_result_in_ready;

wire [127:0] aes_res_block   = aes_result_out[270:143];
wire [2:0]   aes_res_kind    = aes_result_out[142:140];
wire [127:0] aes_res_payload = aes_result_out[139:12];
wire [4:0]   aes_res_bytes   = aes_result_out[11:7];
wire         aes_res_last    = aes_result_out[6];
wire [4:0]   aes_res_index   = aes_result_out[5:1];
wire         aes_res_bank    = aes_result_out[0];
wire aes_result_kind_legal_w = (aes_res_kind == AES_KIND_H) ||
                               (aes_res_kind == AES_KIND_TAG_MASK) ||
                               (aes_res_kind == AES_KIND_CTR_PREFETCH);
wire aes_result_observe_w = aes_result_available_r &&
                            crypto_context_live_r;
wire unexpected_aes_kind_event_w = aes_result_observe_w &&
                                   !aes_result_kind_legal_w;
reg  [10:0]  rec_data_bits;
wire [127:0] aes_res_xor     = aes_res_block ^ aes_res_payload;
wire [127:0] aes_res_masked  = aes_res_last ?
                               mask_result_block(aes_res_xor, aes_res_bytes,
                                                 rec_data_bits) : aes_res_xor;

// Counter-mode AES is issued ahead of the byte stream.  The complete
// keystream is shallow (at most sixteen blocks for the 11-bit descriptor)
// and is consumed in block-index order by ST_DATA.  This removes the final
// input block from the AES recurrence latency without changing the AES
// engine initiation interval.
wire [133:0] ks_fifo_in_data = {aes_res_block, aes_res_index, aes_res_last};
wire         ks_fifo_in_valid = aes_result_out_valid &&
                                (aes_res_kind == AES_KIND_CTR_PREFETCH);
wire         ks_fifo_in_ready;
wire [133:0] ks_fifo_out;
wire         ks_fifo_out_valid;
wire         ks_fifo_out_ready;
wire [4:0]   ks_fifo_count;
reg          ks_pop_pending_r;
reg          ks_block_ready_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg          data_block_capacity_r;
wire [127:0] ks_head_block = ks_fifo_out[133:6];
wire [4:0]   ks_head_index = ks_fifo_out[5:1];
wire         ks_head_last  = ks_fifo_out[0];

stream_fifo #(.WIDTH(134), .DEPTH(16), .ADDR_W(4)) u_keystream_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(ks_fifo_in_data), .in_valid(ks_fifo_in_valid),
    .in_ready(ks_fifo_in_ready), .out_data(ks_fifo_out),
    .out_valid(ks_fifo_out_valid), .out_ready(ks_fifo_out_ready),
    .count(ks_fifo_count)
);

// -------------------------------------------------------------------------
// GHASH request queue and 16-bit digit-serial multiplier
// -------------------------------------------------------------------------
reg          gh_input_valid;
(* keep = "true", equivalent_register_removal = "no" *)
reg          gh_input_slot_free_r;
reg [131:0]  gh_input_data;
reg          gh_aes_valid;
reg [131:0]  gh_aes_data;
reg          gh_ctrl_valid;
reg [131:0]  gh_ctrl_data;
wire         gh_fifo_in_ready;
wire         gh_fifo_in_valid;
wire [131:0] gh_fifo_in_data;
wire         gh_input_pop;
wire         gh_aes_pop;
wire         gh_ctrl_pop;
wire [131:0] ghq_out;
wire         ghq_valid;
wire         ghq_ready;
wire [2:0]   ghq_count;

stream_fifo #(.WIDTH(132), .DEPTH(4), .ADDR_W(2)) u_ghash_request_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(gh_fifo_in_data), .in_valid(gh_fifo_in_valid),
    .in_ready(gh_fifo_in_ready), .out_data(ghq_out),
    .out_valid(ghq_valid), .out_ready(ghq_ready), .count(ghq_count)
);

// Independent registered producers keep input assembly, AES completion and
// control/length requests out of one 132-bit D-input mux.  Fixed priority is
// also the required GCM order at every legal collision: input ciphertext/AAD
// before AES ciphertext, and either data source before the trailing length.
assign gh_fifo_in_valid = gh_input_valid || gh_aes_valid || gh_ctrl_valid;
assign gh_fifo_in_data = gh_input_valid ? gh_input_data :
                         gh_aes_valid   ? gh_aes_data   : gh_ctrl_data;
assign gh_input_pop = gh_fifo_in_ready && gh_input_valid;
assign gh_aes_pop = gh_fifo_in_ready && !gh_input_valid && gh_aes_valid;
assign gh_ctrl_pop = gh_fifo_in_ready && !gh_input_valid && !gh_aes_valid &&
                     gh_ctrl_valid;

reg [2:0] gh_active_kind;
reg       ghash_load_h;
reg [127:0] h_reg;
wire ghash_busy;
wire ghash_done;
wire [127:0] ghash_y;
wire ghash_start = ghq_valid && ghq_ready;
assign ghq_ready = !queue_clear && !zeroize && !ghash_busy;

ghash16 u_ghash (
    .clk(clk), .rst_n(rst_n && !zeroize),
    .load_h(ghash_load_h), .H(h_reg),
    .init(ghq_out[128]), .start(ghash_start),
    .block_in(ghq_out[127:0]), .busy(ghash_busy),
    .done(ghash_done), .Y(ghash_y)
);

// -------------------------------------------------------------------------
// Ciphertext output FIFO
// -------------------------------------------------------------------------
reg          ct_prod_valid;
reg [133:0]  ct_prod_data;
wire         ct_prod_ready;
wire [133:0] ctq_out;
wire         ctq_valid;
wire         ctq_ready;
wire [2:0]   ctq_count;

assign aes_result_out_ready_w = aes_result_out_valid &&
                                ((aes_res_kind != AES_KIND_CTR_PREFETCH) ||
                                 ks_fifo_in_ready);

stream_fifo #(.WIDTH(134), .DEPTH(4), .ADDR_W(2)) u_ciphertext_fifo (
    .clk(clk), .rst_n(rst_n), .clear(queue_clear),
    .in_data(ct_prod_data), .in_valid(ct_prod_valid),
    .in_ready(ct_prod_ready), .out_data(ctq_out),
    .out_valid(ctq_valid), .out_ready(ctq_ready), .count(ctq_count)
);

// Completed encryption tags are queued independently from packet parsing.
// This lets the 16-byte tag of packet N drain while packet N+1 is entering.
reg          tag_prod_valid;
reg [135:0]  tag_prod_data;
wire         tag_prod_ready;
wire [135:0] tagq_out;
wire         tagq_valid;
wire         tagq_ready;
wire [1:0]   tagq_count;

stream_fifo #(.WIDTH(136), .DEPTH(2), .ADDR_W(1)) u_tag_packet_fifo (
    .clk(clk), .rst_n(rst_n), .clear(zeroize),
    .in_data(tag_prod_data), .in_valid(tag_prod_valid),
    .in_ready(tag_prod_ready), .out_data(tagq_out),
    .out_valid(tagq_valid), .out_ready(tagq_ready), .count(tagq_count)
);

// -------------------------------------------------------------------------
// Authenticated plaintext holding banks and release queue
// -------------------------------------------------------------------------
(* ram_style = "block" *) reg [127:0] plain_bank0 [0:15];
(* ram_style = "block" *) reg [127:0] plain_bank1 [0:15];
reg [1:0] bank_allocated;
reg         plain_write_pending_valid_r;
reg         plain_write_bank_r;
reg [3:0]   plain_write_index_r;
reg [127:0] plain_write_data_r;

reg         plain_release_valid;
reg [11:0]  plain_release_data;
wire        plain_release_ready;
reg         plain_pop_pending_r;
wire [11:0] plainq_out;
wire        plainq_valid;
wire        plainq_ready;
wire [1:0]  plainq_count;

stream_fifo #(.WIDTH(12), .DEPTH(2), .ADDR_W(1)) u_plain_release_fifo (
    .clk(clk), .rst_n(rst_n), .clear(zeroize),
    .in_data(plain_release_data), .in_valid(plain_release_valid),
    .in_ready(plain_release_ready), .out_data(plainq_out),
    .out_valid(plainq_valid), .out_ready(plainq_ready), .count(plainq_count)
);

localparam [1:0] PO_IDLE = 2'd0;
localparam [1:0] PO_LOAD = 2'd1;
localparam [1:0] PO_SEND = 2'd2;
reg [1:0] plain_out_state;
reg plain_out_bank;
reg [4:0] plain_out_block;
reg [3:0] plain_out_byte;
reg [127:0] plain_read_data;
reg [8:0] plain_out_bytes_remaining;
reg       plain_out_last_r;
reg [3:0] plain_out_valid_bits_r;

wire plain_stream_valid = (plain_out_state == PO_SEND);
wire plain_stream_fire;
wire plain_record_done = plain_stream_fire && plain_out_last_r;
assign plainq_ready = plain_pop_pending_r;

// Retire a completed plaintext descriptor one clock after its final public
// byte.  This keeps the bit-count/add/compare cone off the registered-head
// release FIFO enable.  A simultaneous abort queue clear must preserve the
// just-completed pop request because this FIFO intentionally survives an
// unrelated active-record abort; ordinary queue clears discard no pending
// request.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
        plain_pop_pending_r <= 1'b0;
    else if(plain_record_done)
        plain_pop_pending_r <= 1'b1;
    else if(queue_clear || plain_pop_pending_r)
        plain_pop_pending_r <= 1'b0;
end

// -------------------------------------------------------------------------
// Active record state
// -------------------------------------------------------------------------
reg [3:0] state;
wire descriptor_idle_token_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg encryption_data_owner_r;
reg [2:0] accepted_record_count_r;
reg [1:0] postauth_plain_count_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg key_quiescent_r;
reg rec_decrypt;
reg [7:0] rec_tag_bits;
reg [15:0] rec_tag_byte_enable_r;
reg [15:0] tag_byte_mismatch_r;
reg tag_compare_ready_r;
reg [10:0] rec_iv_bits;
reg rec_iv_is_96_r;
reg [10:0] rec_aad_bits;
reg rec_bank;

reg [9:0] record_bytes_remaining;
reg record_last_r;
reg [8:0] field_bytes_remaining;
reg field_last_r;
reg [8:0] field_received;
reg [3:0] block_byte_index;
(* keep = "true", equivalent_register_removal = "no" *)
reg [2:0] input_field_mode_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg tag_input_active_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg block_beat_15_r;
reg [4:0] data_block_index;
reg [127:0] input_block;
reg [127:0] tag_input;
(* extract_reset = "no" *) reg [95:0] iv96_shadow_r;
reg [127:0] j0_reg;
reg [127:0] tag_mask_reg;
reg [127:0] hash_reg;
reg [127:0] final_tag_reg;
reg tag_mask_ready;
reg final_hash_ready;
reg final_tag_ready;
reg tag_request_pending;
reg iv_length_pending;
reg message_length_pending;
reg message_length_enqueued;
reg main_init_pending;
reg all_cipher_blocks_ready;
reg enc_data_sent;
reg [31:0] ctr_value;
reg [7:0] abort_code;
reg abort_queue_clear;
reg key_ready_r;
reg h_request_pending;
reg h_request_sent;
reg [4:0] ctr_request_index_r;
reg [4:0] ctr_request_total_r;
reg [31:0] ctr_request_value_r;
reg ctr_issue_pending_r;
reg iv96_ctr_load_pending_r;
reg [3:0] tag_out_index;
reg tag_send_active_r;
reg [4:0] tag_bytes_remaining_r;
reg tag_last_r;
reg [3:0] ct_out_byte_index;
reg enc_frame_started;
reg enc_frame_finished;
reg abort_terminator_pending;
reg result_valid_r;
reg [7:0] result_data_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg active_abort_result_r;
reg [2:0] zeroize_abort_count;
reg [4:0] zeroize_index;
reg enc_result_pending;
(* keep = "true", equivalent_register_removal = "no" *)
reg abort_crypto_drained_r;
reg [8:0] prep_iv_bytes;
reg [8:0] prep_aad_bytes;
reg [8:0] prep_data_bytes;
wire [8:0] prep_tag_bytes;
reg [9:0] prep_header_bytes;
reg [9:0] prep_payload_bytes;
reg [9:0] prep_record_bytes;
wire tag_stream_last;
wire tag_stream_fire;

wire active_record = (state != ST_IDLE);
wire free_plain_bank = !bank_allocated[0] ? 1'b0 : 1'b1;
wire can_start_decrypt = (bank_allocated != 2'b11);
wire can_start_encrypt = (bank_allocated == 2'b00) && tag_prod_ready;
wire descriptor_crypto_active_w = !descriptor_idle_token_r && key_ready_r &&
                                  crypto_event_enable_w;
wire take_descriptor = descriptor_idle_token_r && key_ready_r &&
                       desc_out_valid &&
                       !queue_clear && !zeroize &&
                       !zeroize_sequence_active_r &&
                       (zeroize_abort_count == 0);
wire descriptor_resource_ready_w = rec_decrypt ? can_start_decrypt :
                                                 can_start_encrypt;
assign desc_out_ready = take_descriptor;

// Remaining-byte counters make the current-beat TLAST decisions without a
// wide add/subtract/compare cone feeding every crypto request register.
wire completing_field_byte = field_last_r;
wire completing_block_byte = block_beat_15_r || completing_field_byte;
wire [127:0] completed_input_block_w = put_block_byte(
    input_block, block_byte_index,
    completing_field_byte ? mask_final_byte(s_axis_tdata, rec_data_bits) :
                            s_axis_tdata);
wire [127:0] data_result_xor_w = ks_head_block ^ completed_input_block_w;
wire [4:0] completed_data_bytes_w = completing_field_byte ?
                                    final_block_bytes(rec_data_bits) : 5'd16;
wire [127:0] data_result_w = completing_field_byte ?
                             mask_result_block(data_result_xor_w,
                                               completed_data_bytes_w,
                                               rec_data_bits) :
                             data_result_xor_w;

reg input_capacity_ok;
always @(*)
begin
    input_capacity_ok = 1'b0;
    case(input_field_mode_r)
        IFM_IV96,
        IFM_TAG,
        IFM_DRAIN:
            input_capacity_ok = 1'b1;
        IFM_IVHASH,
        IFM_AAD:
            input_capacity_ok = !completing_block_byte ||
                                gh_input_slot_free_r;
        IFM_DATA:
            input_capacity_ok = !completing_block_byte ||
                                data_block_capacity_r;
        default:
            input_capacity_ok = 1'b0;
    endcase
end

assign s_axis_tready = input_capacity_ok && !zeroize;
wire input_fire = s_axis_tvalid && s_axis_tready;
wire tag_input_capture_w = s_axis_tvalid && tag_input_active_r;
wire tag_mismatch_w = |tag_byte_mismatch_r;
wire data_block_fire_w = input_fire && (state == ST_DATA) &&
                         completing_block_byte;
wire ks_head_matches_data_w = ks_fifo_out_valid &&
                              (ks_head_index == data_block_index);
wire ks_block_ready_next_w = ks_block_ready_r || ks_head_matches_data_w;
wire data_sink_ready_raw_w = rec_decrypt ? gh_input_slot_free_r :
                                          (!ct_prod_valid && !gh_aes_valid);
assign ks_fifo_out_ready = ks_pop_pending_r;

// The current keystream head is consumed by the data path on the block's
// final byte.  Delay only the FIFO pop by one clock so that byte-level input
// control cannot drive the registered 134-bit FIFO head enable directly.
always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        ks_pop_pending_r <= 1'b0;
    else
        ks_pop_pending_r <= input_fire && (state == ST_DATA) &&
                            completing_block_byte;
end

// Qualify the ordered keystream head once per data block.  Full blocks have
// fifteen byte clocks in which the next registered FIFO head can be checked,
// so only a short first/partial block can incur an extra wait cycle.  The
// final-byte ready path itself now depends on this one-bit register rather
// than the 134-bit FIFO head and its index comparator.
always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        ks_block_ready_r <= 1'b0;
    else if(state != ST_DATA)
        ks_block_ready_r <= 1'b0;
    else if(input_fire && completing_block_byte)
        ks_block_ready_r <= 1'b0;
    else if(ks_head_matches_data_w)
        ks_block_ready_r <= 1'b1;
end

// Prequalify the complete data-block commit condition while the preceding
// bytes are being assembled.  Including the current or newly matching
// keystream head preserves a same-cycle FIFO arrival.  Block and
// state-boundary clears have priority so a one-byte data field cannot reuse
// stale readiness from AAD or from the preceding full block.
always @(posedge clk)
begin
    if(!rst_n || zeroize || queue_clear)
        data_block_capacity_r <= 1'b0;
    else if(state != ST_DATA)
        data_block_capacity_r <= 1'b0;
    else if(data_block_fire_w)
        data_block_capacity_r <= 1'b0;
    else
        data_block_capacity_r <= ks_block_ready_next_w &&
                                 data_sink_ready_raw_w;
end

wire expected_record_last = record_last_r;
wire early_tlast_now = input_fire && s_axis_tlast && !expected_record_last;
wire late_tlast_now = input_fire && !s_axis_tlast && expected_record_last;
wire framing_abort_event_w = (input_field_mode_r != IFM_DRAIN) &&
                             (early_tlast_now || late_tlast_now);
wire data_block_index_advance_w = data_block_fire_w &&
                                  !early_tlast_now && !late_tlast_now;
wire plain_write_capture_w = data_block_fire_w && rec_decrypt &&
                             !early_tlast_now && !late_tlast_now &&
                             !queue_clear && !zeroize_busy_r;
wire normal_crypto_state = (state != ST_ABORT_WAIT) &&
                           (state != ST_DRAIN);
wire tag_beat_fire_w = tag_input_capture_w;
wire tag_final_legal_w = tag_beat_fire_w && completing_field_byte &&
                         !early_tlast_now && !late_tlast_now;
wire [127:0] final_tag_value_w = hash_reg ^ tag_mask_reg;
wire final_tag_form_w = final_hash_ready && tag_mask_ready &&
                        !final_tag_ready && !queue_clear &&
                        crypto_context_live_r;
wire tag_compare_ready_set_w = rec_decrypt &&
    ((tag_final_legal_w && (final_tag_ready || final_tag_form_w)) ||
     (final_tag_form_w && (state == ST_FINAL_WAIT)));
wire non96_j0_load_w = ghash_done && !queue_clear &&
                       crypto_context_live_r &&
                       (gh_active_kind == GH_KIND_IV_LEN);
wire input_field_normal_w = (input_field_mode_r != IFM_NONE) &&
                            (input_field_mode_r != IFM_START) &&
                            (input_field_mode_r != IFM_DRAIN);
wire input_field_block_w = (input_field_mode_r == IFM_IV96) ||
                           (input_field_mode_r == IFM_IVHASH) ||
                           (input_field_mode_r == IFM_AAD) ||
                           (input_field_mode_r == IFM_DATA);
wire normal_byte_commit_w = input_fire && input_field_normal_w &&
                            !early_tlast_now && !late_tlast_now;
wire block_phase_commit_w = normal_byte_commit_w && input_field_block_w;
wire field_end_commit_w = normal_byte_commit_w && completing_field_byte;
wire gh_input_write_w = normal_byte_commit_w && completing_block_byte &&
    ((input_field_mode_r == IFM_IVHASH) ||
     (input_field_mode_r == IFM_AAD) ||
     ((input_field_mode_r == IFM_DATA) && rec_decrypt));
wire [8:0] field_after_iv_bytes_w =
    (prep_aad_bytes != 9'd0) ? prep_aad_bytes :
    (prep_data_bytes != 9'd0) ? prep_data_bytes : prep_tag_bytes;
wire [8:0] field_after_aad_bytes_w =
    (prep_data_bytes != 9'd0) ? prep_data_bytes : prep_tag_bytes;
wire [2:0] input_mode_after_iv_w =
    (prep_aad_bytes != 9'd0) ? IFM_AAD :
    (prep_data_bytes != 9'd0) ? IFM_DATA :
    rec_decrypt ? IFM_TAG : IFM_NONE;
wire [2:0] input_mode_after_aad_w =
    (prep_data_bytes != 9'd0) ? IFM_DATA :
    rec_decrypt ? IFM_TAG : IFM_NONE;

// Mirror the registered input-GHASH producer slot.  A legal block write wins
// over a same-edge FIFO pop, matching the producer's pop-and-replace order.
always @(posedge clk)
begin
    if(!rst_n || queue_clear)
        gh_input_slot_free_r <= 1'b1;
    else if(gh_input_write_w)
        gh_input_slot_free_r <= 1'b0;
    else if(gh_input_pop)
        gh_input_slot_free_r <= 1'b1;
end

// Keep the input-field class local to the byte admission and countdown
// logic.  START occupies the existing descriptor-start cycle, so the IV
// countdown is loaded on the same edge as before without exposing the main
// state register to the per-byte counter mux.  A late-TLAST drain must retain
// IFM_DRAIN across the registered queue-clear pulse until its terminating
// TLAST arrives.
always @(posedge clk)
begin
    if(!rst_n || zeroize || zeroize_busy_r)
        input_field_mode_r <= IFM_NONE;
    else if(framing_abort_event_w)
        input_field_mode_r <= late_tlast_now ? IFM_DRAIN : IFM_NONE;
    else if(unexpected_aes_kind_event_w)
        input_field_mode_r <= IFM_NONE;
    else if(take_descriptor)
        input_field_mode_r <= IFM_NONE;
    else if(state == ST_DESC_TOTAL)
        input_field_mode_r <= IFM_START;
    else if(input_field_mode_r == IFM_START)
        input_field_mode_r <= rec_iv_is_96_r ? IFM_IV96 : IFM_IVHASH;
    else if(non96_j0_load_w)
        input_field_mode_r <= input_mode_after_iv_w;
    else if(input_fire && (input_field_mode_r == IFM_DRAIN))
    begin
        if(s_axis_tlast)
            input_field_mode_r <= IFM_NONE;
    end
    else if(field_end_commit_w)
    begin
        case(input_field_mode_r)
            IFM_IV96:
                input_field_mode_r <= input_mode_after_iv_w;
            IFM_IVHASH:
                input_field_mode_r <= IFM_NONE;
            IFM_AAD:
                input_field_mode_r <= input_mode_after_aad_w;
            IFM_DATA:
                input_field_mode_r <= rec_decrypt ? IFM_TAG : IFM_NONE;
            IFM_TAG:
                input_field_mode_r <= IFM_NONE;
            default:
                input_field_mode_r <= IFM_NONE;
        endcase
    end
end

// Predict the TAG input phase on the same transition which updates the
// multi-bit field mode.  TAG always has input capacity, so this one-bit token
// is an exact zero-cycle handshake qualifier without the field-mode decode on
// every tag-compare payload register.
always @(posedge clk)
begin
    if(!rst_n || zeroize || zeroize_busy_r)
        tag_input_active_r <= 1'b0;
    else if(framing_abort_event_w || unexpected_aes_kind_event_w ||
            take_descriptor)
        tag_input_active_r <= 1'b0;
    else if(non96_j0_load_w)
        tag_input_active_r <= (input_mode_after_iv_w == IFM_TAG);
    else if(field_end_commit_w)
    begin
        case(input_field_mode_r)
            IFM_IV96:
                tag_input_active_r <= (input_mode_after_iv_w == IFM_TAG);
            IFM_AAD:
                tag_input_active_r <= (input_mode_after_aad_w == IFM_TAG);
            IFM_DATA:
                tag_input_active_r <= rec_decrypt;
            default:
                tag_input_active_r <= 1'b0;
        endcase
    end
end

// Mirror whether the current assembly position is byte 15.  Only a legal
// committed assembly byte advances the phase; stale abort/zeroize payload is
// harmless because every accepted descriptor reinitializes it before input.
always @(posedge clk)
begin
    if(!rst_n || take_descriptor)
        block_beat_15_r <= 1'b0;
    else if(block_phase_commit_w)
        block_beat_15_r <= !field_last_r &&
                           (block_byte_index == 4'd14);
end

// Keep the per-field byte countdown out of the main record-control mux.  A
// legal accepted byte always writes this register in the same cycle; final
// bytes replace the decrement with the next precomputed field length.  The
// explicit hold preserves the main process priority during abort/zeroize and
// descriptor capture without adding those events as payload clears.
always @(posedge clk)
begin
    if(!rst_n)
        field_bytes_remaining <= 9'd0;
    else if(zeroize || zeroize_busy_r || queue_clear || take_descriptor)
        field_bytes_remaining <= field_bytes_remaining;
    else if(input_field_mode_r == IFM_START)
        field_bytes_remaining <= prep_iv_bytes;
    else if(non96_j0_load_w)
        field_bytes_remaining <= field_after_iv_bytes_w;
    else if(field_end_commit_w && (input_field_mode_r == IFM_IV96))
        field_bytes_remaining <= field_after_iv_bytes_w;
    else if(field_end_commit_w && (input_field_mode_r == IFM_AAD))
        field_bytes_remaining <= field_after_aad_bytes_w;
    else if(field_end_commit_w && (input_field_mode_r == IFM_DATA) &&
            rec_decrypt)
        field_bytes_remaining <= prep_tag_bytes;
    else if(normal_byte_commit_w)
        field_bytes_remaining <= field_bytes_remaining - 9'd1;
end

// Keep the ordered keystream index out of the main record-control process.
// A framing-error beat is not a committed data block; ZEROIZE and an abort
// leave this payload stale until the next accepted descriptor clears it.
always @(posedge clk)
begin
    if(!rst_n)
        data_block_index <= 5'd0;
    else if(take_descriptor)
        data_block_index <= 5'd0;
    else if(data_block_index_advance_w)
        data_block_index <= data_block_index + 5'd1;
end

// Capture a 96-bit IV one byte at a time.  The pending bit below is the sole
// validity token, so ordinary reset need not clear this payload register.
always @(posedge clk)
begin
    if(zeroize)
        iv96_shadow_r <= 96'd0;
    else if(rst_n && s_axis_tvalid && !zeroize &&
            (state == ST_IV) && rec_iv_is_96_r)
    begin
        case(block_byte_index)
            4'd0:  iv96_shadow_r[95:88] <= s_axis_tdata;
            4'd1:  iv96_shadow_r[87:80] <= s_axis_tdata;
            4'd2:  iv96_shadow_r[79:72] <= s_axis_tdata;
            4'd3:  iv96_shadow_r[71:64] <= s_axis_tdata;
            4'd4:  iv96_shadow_r[63:56] <= s_axis_tdata;
            4'd5:  iv96_shadow_r[55:48] <= s_axis_tdata;
            4'd6:  iv96_shadow_r[47:40] <= s_axis_tdata;
            4'd7:  iv96_shadow_r[39:32] <= s_axis_tdata;
            4'd8:  iv96_shadow_r[31:24] <= s_axis_tdata;
            4'd9:  iv96_shadow_r[23:16] <= s_axis_tdata;
            4'd10: iv96_shadow_r[15:8]  <= s_axis_tdata;
            4'd11: iv96_shadow_r[7:0]   <= s_axis_tdata;
            default: ;
        endcase
    end
end

// J0 has only two functional writers.  Keeping them in this dedicated
// process prevents the wide register enable from sharing the main record,
// plaintext-bank and producer control cones.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
        j0_reg <= 128'd0;
    else if(iv96_ctr_load_pending_r)
        j0_reg <= {iv96_shadow_r, 32'd1};
    else if(non96_j0_load_w)
        j0_reg <= ghash_y;
end

// Keep the decrypt-tag byte store out of the main record-control process.
// ST_TAG_IN always has input capacity, so this registered-state qualifier is
// exactly the stream handshake for a non-zeroize cycle.  Every valid tag byte
// is overwritten before authentication; for short tags the untouched trailing
// bytes are excluded by the byte-enable mask.  Framing errors never compare.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
        tag_input <= 128'd0;
    else if(tag_input_capture_w)
        tag_input <= put_block_byte(tag_input, field_received[3:0],
                                    s_axis_tdata);
end

// Decode the public tag length once when its descriptor becomes active.
// This datapath register deliberately has no reset: state is the validity
// control, and every reachable authentication compare follows a complete
// formation snapshot below.
always @(posedge clk)
begin
    if(take_descriptor)
        rec_tag_byte_enable_r <=
            tag_byte_enable_mask(desc_out_data[40:33]);
end

// prep_tag_bytes is non-sensitive public framing metadata.  Five bits hold
// the byte count; the upper bits are constant.  Explicit FDRE control pins
// keep the descriptor-load decode out of the reset cone while preserving a
// direct same-edge clear from every raw ZEROIZE command.
wire prep_tag_clear_w = !rst_n || zeroize;
wire [4:0] prep_tag_load_w = {5{desc_out_data[41]}} &
                             desc_out_data[40:36];
assign prep_tag_bytes[8:5] = 4'd0;
genvar prep_tag_bit;
generate
for(prep_tag_bit = 0; prep_tag_bit < 5; prep_tag_bit = prep_tag_bit + 1)
begin : gen_prep_tag_bytes
    FDRE #(.INIT(1'b0)) prep_tag_bytes_reg (
        .C(clk),
        .CE(take_descriptor),
        .D(prep_tag_load_w[prep_tag_bit]),
        .Q(prep_tag_bytes[prep_tag_bit]),
        .R(prep_tag_clear_w)
    );
end
endgenerate

// Compare each tag byte in an independent one-bit datapath.  Formation writes
// a deterministic snapshot for all bytes; a simultaneous stream beat uses the
// live byte only in its matching slice.  Once final_tag_reg is ready, each
// later stream beat overwrites just its own flag.  Framing only controls the
// ready token below, so TLAST/counter logic does not feed these payload FFs.
genvar tag_byte_index_g;
generate
for(tag_byte_index_g = 0; tag_byte_index_g < 16;
    tag_byte_index_g = tag_byte_index_g + 1)
begin : gen_tag_byte_mismatch
    localparam integer TAG_BYTE_MSB = 127 - (tag_byte_index_g * 8);
    localparam [3:0] TAG_BYTE_INDEX = tag_byte_index_g;
    wire tag_byte_selected_w = tag_beat_fire_w &&
                               (field_received[3:0] == TAG_BYTE_INDEX);
    wire [7:0] formation_received_byte_w = tag_byte_selected_w ?
                                            s_axis_tdata :
                                            tag_input[TAG_BYTE_MSB -: 8];
    wire formation_mismatch_w = rec_tag_byte_enable_r[tag_byte_index_g] &&
        (|(final_tag_value_w[TAG_BYTE_MSB -: 8] ^
           formation_received_byte_w));
    wire ready_mismatch_w = rec_tag_byte_enable_r[tag_byte_index_g] &&
        (|(final_tag_reg[TAG_BYTE_MSB -: 8] ^ s_axis_tdata));

    always @(posedge clk)
    begin
        if(zeroize)
            tag_byte_mismatch_r[tag_byte_index_g] <= 1'b0;
        else if(rst_n)
        begin
            if(rec_decrypt && final_tag_form_w)
                tag_byte_mismatch_r[tag_byte_index_g] <=
                    formation_mismatch_w;
            else if(rec_decrypt && final_tag_ready && tag_byte_selected_w)
                tag_byte_mismatch_r[tag_byte_index_g] <= ready_mismatch_w;
        end
    end
end
endgenerate

// Ready is the sole validity token for the mismatch vector.  A legal final
// input beat bypasses its completion into this rendezvous, while ST_FINAL_WAIT
// proves that all tag bytes were accepted when final-tag formation is later.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
        tag_compare_ready_r <= 1'b0;
    else if(queue_clear || take_descriptor)
        tag_compare_ready_r <= 1'b0;
    else if(tag_compare_ready_set_w)
        tag_compare_ready_r <= 1'b1;
end

// Encryption and released-plaintext share the data output channel.  An
// encryption descriptor waiting for a plaintext bank must not mask the old
// plaintext stream whose completion will release that bank.
wire encryption_owns_data = encryption_data_owner_r;
wire [127:0] ct_head_block = ctq_out[133:6];
wire [4:0] ct_head_bytes = ctq_out[5:1];
wire ct_head_last = ctq_out[0];
wire ct_block_last_byte = (ct_out_byte_index + 5'd1) == ct_head_bytes;
wire ct_record_last_byte = ct_head_last && ct_block_last_byte;
// A registered protocol-abort clear is high for the cycle in which the
// active ciphertext FIFO is synchronously discarded.  Suppress its old
// registered head during that cycle so no unterminated stale beat can reach
// the public frame boundary before the abort terminator/result.
wire ct_stream_valid = encryption_owns_data && ctq_valid && !queue_clear;
wire ct_stream_fire = ct_stream_valid && !zeroize && m_axis_data_tready;
assign ctq_ready = ct_stream_fire && ct_block_last_byte;
wire abort_stream_valid = abort_terminator_pending && !zeroize;
wire abort_stream_fire = abort_stream_valid && m_axis_data_tready;

assign m_axis_data_tvalid = abort_stream_valid || (!zeroize &&
                            (ct_stream_valid ||
                             (!encryption_owns_data && plain_stream_valid)));
assign m_axis_data_tdata = abort_stream_valid ? 8'd0 : ct_stream_valid ?
                           get_block_byte(ct_head_block, ct_out_byte_index) :
                           get_block_byte(plain_read_data, plain_out_byte);
assign m_axis_data_tlast = abort_stream_valid ? 1'b1 :
                           ct_stream_valid ? ct_record_last_byte :
                           (!encryption_owns_data && plain_stream_valid &&
                            plain_out_last_r);
assign m_axis_data_tuser = abort_stream_valid ? 4'd0 :
                           ct_stream_valid ?
                           (ct_record_last_byte ?
                            valid_bits_last(rec_data_bits) : 4'd0) :
                           ((!encryption_owns_data && plain_stream_valid &&
                             plain_out_last_r) ?
                            plain_out_valid_bits_r : 4'd0);
assign plain_stream_fire = !zeroize && !encryption_owns_data && plain_stream_valid &&
                           m_axis_data_tready;

wire [7:0] queued_tag_bits = tagq_out[135:128];
wire [127:0] queued_tag_value = tagq_out[127:0];
wire [8:0] tag_bytes = {1'b0, queued_tag_bits} >> 3;
assign tag_stream_last = tag_last_r;
// A completed encryption owns tag/result ordering until ENC_OK is accepted.
// Holding the next tag frame here also gives the public boundary a clean
// inter-frame arbitration point without blocking descriptor execution.
assign m_axis_tag_tvalid = !zeroize && tag_send_active_r &&
                           !enc_result_pending && !result_valid_r;
assign m_axis_tag_tdata = get_block_byte(queued_tag_value, tag_out_index);
assign m_axis_tag_tlast = m_axis_tag_tvalid && tag_stream_last;
assign tag_stream_fire = m_axis_tag_tvalid && m_axis_tag_tready;
assign tagq_ready = tag_stream_fire && tag_last_r;

assign m_axis_result_tdata = result_data_r;
assign m_axis_result_tvalid = result_valid_r && !zeroize;
assign m_axis_result_tlast = result_valid_r && !zeroize;

assign key_ready = key_ready_r;
assign key_busy = key_context_busy || (key_context_ready && !key_ready_r);
assign key_quiescent = key_quiescent_r;
assign record_active = active_record;
assign output_pending = result_valid_r || ctq_valid || plainq_valid ||
                        (plain_out_state != PO_IDLE) ||
                        tagq_valid || tag_prod_valid || (bank_allocated != 0) ||
                        abort_terminator_pending || enc_result_pending ||
                        ks_fifo_out_valid ||
                        ctr_issue_pending_r ||
                        iv96_ctr_load_pending_r ||
                        (zeroize_abort_count != 0) || zeroize_busy_r;
assign zeroize_busy = zeroize_busy_r;
// Once a tag frame, a result beat, or authenticated plaintext has become
// externally visible it must drain rather than be truncated by ZEROIZE.
// Active encryption ciphertext is excluded: it has an explicit TUSER=0
// abort terminator.
assign zeroize_defer = tagq_valid || tag_prod_valid || result_valid_r ||
                       enc_result_pending ||
                       plainq_valid || (plain_out_state != PO_IDLE);
assign queue_clear = zeroize || abort_queue_clear;

// A decrypt/authentication or framing-error result belongs to the active
// descriptor, while queued tag state belongs to an older encryption
// descriptor.  The active descriptor may continue executing, but its result
// cannot occupy the one-entry result register until the older tag and ENC_OK
// have crossed their handshakes.
wire older_encryption_completion_pending = tagq_valid || tag_prod_valid ||
                                             enc_result_pending ||
                                             result_valid_r;
wire abort_crypto_drained_w = !aes_engine_busy && !ghash_busy &&
                              (aesq_count == 0) &&
                              (aes_meta_count == 0) &&
                              !aes_meta_stage_valid_r &&
                              (aes_result_count == 0);
wire active_abort_result_load_w = (state == ST_ABORT_WAIT) &&
                                  abort_crypto_drained_r &&
                                  !older_encryption_completion_pending &&
                                  !abort_terminator_pending;
// The shared result register can hold an older ENC_OK while a newer record is
// active.  Results generated by ST_DEC_RESULT or by the active abort state are
// already represented by active_record; every other occupied result belongs
// to a detached, previously accepted descriptor.
wire result_owned_by_active_record = result_valid_r &&
                                     ((state == ST_DEC_RESULT) ||
                                      ((state == ST_ABORT_WAIT) &&
                                       active_abort_result_r));
wire detached_result_pending = result_valid_r &&
                               !result_owned_by_active_record;
wire result_visible_fire_w = result_valid_r && m_axis_result_tready &&
                             !zeroize;
wire zeroize_abort_result_fire_w = result_visible_fire_w &&
                                    (result_data_r == RESULT_ZEROIZE_ABORT);
wire first_zeroize_event_w = zeroize && !zeroize_sequence_active_r;
wire zeroize_sequence_empty_done_w = zeroize_sequence_active_r &&
                                      zeroize_busy_r &&
                                      (zeroize_index == 5'd15) &&
                                      (zeroize_abort_count == 0);
wire zeroize_sequence_last_abort_done_w = zeroize_sequence_active_r &&
                                           zeroize_abort_result_fire_w &&
                                           (zeroize_abort_count == 0);

// This registered token is the descriptor-admission form of ST_IDLE.  It is
// set only on the four events which make an idle core usable, and cleared on
// every event which invalidates or consumes that availability.  Keeping the
// token separate removes the wide state-retire/decode cone from the next
// descriptor's state-register input without changing descriptor ordering.
wire descriptor_h_ready_event = aes_result_observe_w &&
                                (aes_res_kind == AES_KIND_H);
wire descriptor_enc_retire_event = (state == ST_FINAL_WAIT) &&
                                   final_tag_ready &&
                                   all_cipher_blocks_ready &&
                                   !result_valid_r &&
                                   !enc_result_pending &&
                                   !rec_decrypt && enc_data_sent &&
                                   !tag_prod_valid;
wire descriptor_dec_retire_event = (state == ST_DEC_RESULT) &&
                                   result_valid_r &&
                                   m_axis_result_tready;
wire descriptor_abort_retire_event = (state == ST_ABORT_WAIT) &&
                                     result_valid_r &&
                                     active_abort_result_r &&
                                     m_axis_result_tready;
wire descriptor_idle_token_clear_w = !rst_n || zeroize || key_commit ||
                                     take_descriptor;
wire descriptor_idle_token_set_w = descriptor_h_ready_event ||
                                   descriptor_enc_retire_event ||
                                   descriptor_dec_retire_event ||
                                   descriptor_abort_retire_event;

// Account accepted descriptors until their public result handshake.  A
// successful non-empty decrypt has a second, post-result lifetime while its
// authenticated plaintext drains from the release FIFO.  Registering the
// predictive empty condition gives KEY_COMMIT one narrow, cycle-exact
// admission signal instead of the wide collection of packet/output state.
wire accepted_record_event_w = cmd_push && desc_in_ready && !zeroize;
wire accepted_result_event_w = result_visible_fire_w;
wire postauth_plain_start_w = accepted_result_event_w &&
                              (result_data_r == RESULT_DEC_AUTH_OK) &&
                              (ctr_request_total_r != 5'd0);
wire postauth_plain_pop_w = plainq_valid && plainq_ready;
reg [2:0] accepted_record_count_next;
reg [1:0] postauth_plain_count_next;

always @(*)
begin
    accepted_record_count_next = accepted_record_count_r;
    case({accepted_record_event_w, accepted_result_event_w})
        2'b10: accepted_record_count_next = accepted_record_count_r + 3'd1;
        2'b01: accepted_record_count_next = accepted_record_count_r - 3'd1;
        default: accepted_record_count_next = accepted_record_count_r;
    endcase
end

always @(*)
begin
    if(zeroize)
        postauth_plain_count_next = 2'd0;
    else
    begin
        postauth_plain_count_next = postauth_plain_count_r;
        case({postauth_plain_start_w, postauth_plain_pop_w})
            2'b10: postauth_plain_count_next = postauth_plain_count_r + 2'd1;
            2'b01: postauth_plain_count_next = postauth_plain_count_r - 2'd1;
            default: postauth_plain_count_next = postauth_plain_count_r;
        endcase
    end
end

always @(posedge clk)
begin
    if(!rst_n)
        accepted_record_count_r <= 3'd0;
    else
        accepted_record_count_r <= accepted_record_count_next;
end

always @(posedge clk)
begin
    if(!rst_n || zeroize)
        postauth_plain_count_r <= 2'd0;
    else
        postauth_plain_count_r <= postauth_plain_count_next;
end

always @(posedge clk)
begin
    if(!rst_n)
        key_quiescent_r <= 1'b1;
    else
        key_quiescent_r <= (accepted_record_count_next == 3'd0) &&
                           (postauth_plain_count_next == 2'd0);
end

// Register permission for AES request/result events across a protocol abort.
// ZEROIZE gates the permission directly and leaves this token live for clean
// recovery after scrubbing.  FIFO and producer invalidation still use
// queue_clear.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
        crypto_context_live_r <= 1'b1;
    else if(framing_abort_event_w || unexpected_aes_kind_event_w)
        crypto_context_live_r <= 1'b0;
    else if(descriptor_abort_retire_event)
        crypto_context_live_r <= 1'b1;
end

// Crypto/FIFO drain is monotonic after an abort has disabled new work.  Keep
// the older-encryption and public abort-terminator barriers live in the
// result condition so this sticky timing cut cannot authorize a stale result.
always @(posedge clk)
begin
    if(!rst_n || zeroize || (state != ST_ABORT_WAIT))
        abort_crypto_drained_r <= 1'b0;
    else if(abort_crypto_drained_w)
        abort_crypto_drained_r <= 1'b1;
end

always @(posedge clk)
begin
    if(!rst_n || zeroize)
        active_abort_result_r <= 1'b0;
    else if(active_abort_result_load_w)
        active_abort_result_r <= 1'b1;
    else if(descriptor_abort_retire_event)
        active_abort_result_r <= 1'b0;
end

// Track one complete ZEROIZE lifecycle.  The token is set by the first
// command, remains set across scrub and result backpressure, and clears only
// when an empty scrub completes or the final visible ZEROIZE_ABORT retires.
always @(posedge clk)
begin
    if(!rst_n)
        zeroize_sequence_active_r <= 1'b0;
    else if(first_zeroize_event_w)
        zeroize_sequence_active_r <= 1'b1;
    else if(zeroize_sequence_empty_done_w ||
            zeroize_sequence_last_abort_done_w)
        zeroize_sequence_active_r <= 1'b0;
end

(* keep = "true", dont_touch = "true" *)
FDRE #(.INIT(1'b0)) u_descriptor_idle_token_ff (
    .Q(descriptor_idle_token_r),
    .C(clk),
    .CE(descriptor_idle_token_set_w),
    .D(1'b1),
    .R(descriptor_idle_token_clear_w)
);

always @(posedge clk)
begin
    if(!rst_n || zeroize)
        encryption_data_owner_r <= 1'b0;
    else if((state == ST_DESC_WAIT) && descriptor_resource_ready_w &&
            !rec_decrypt)
        encryption_data_owner_r <= 1'b1;
    else if(descriptor_enc_retire_event || descriptor_abort_retire_event)
        encryption_data_owner_r <= 1'b0;
end

always @(posedge clk)
begin
    if(!rst_n)
        ct_out_byte_index <= 4'd0;
    else if(take_descriptor)
        ct_out_byte_index <= 4'd0;
    else if(ct_stream_fire)
        ct_out_byte_index <= ct_out_byte_index + 4'd1;
end

// A queued request is dispatched in order.  Remember GHASH request kind so
// the completion pulse can identify IV and message length blocks.
always @(posedge clk)
begin
    if(!rst_n)
        gh_active_kind <= GH_KIND_IV_DATA;
    else if(ghash_start)
        gh_active_kind <= ghq_out[131:129];
end

// Plaintext BRAM read/output sequencer.
always @(posedge clk)
begin
    if(!rst_n || zeroize)
    begin
        plain_out_state <= PO_IDLE;
        plain_out_bank  <= 1'b0;
        plain_out_block <= 5'd0;
        plain_out_byte  <= 4'd0;
        plain_read_data <= 128'd0;
        plain_out_bytes_remaining <= 9'd0;
        plain_out_last_r <= 1'b0;
        plain_out_valid_bits_r <= 4'd0;
    end
    else
    begin
        case(plain_out_state)
            PO_IDLE:
            begin
                if(plainq_valid && !plain_pop_pending_r &&
                   !encryption_owns_data)
                begin
                    plain_out_bank  <= plainq_out[11];
                    plain_out_block <= 5'd0;
                    plain_out_byte  <= 4'd0;
                    plain_out_bytes_remaining <=
                        bits_to_bytes(plainq_out[10:0]);
                    plain_out_valid_bits_r <=
                        valid_bits_last(plainq_out[10:0]);
                    plain_out_last_r <= 1'b0;
                    plain_out_state <= PO_LOAD;
                end
            end
            PO_LOAD:
            begin
                plain_read_data <= plain_out_bank ?
                                   plain_bank1[plain_out_block[3:0]] :
                                   plain_bank0[plain_out_block[3:0]];
                plain_out_byte  <= 4'd0;
                plain_out_last_r <=
                    (plain_out_bytes_remaining == 9'd1);
                plain_out_state <= PO_SEND;
            end
            PO_SEND:
            begin
                if(plain_stream_fire)
                begin
                    if(plain_out_last_r)
                    begin
                        plain_out_bytes_remaining <= 9'd0;
                        plain_out_last_r <= 1'b0;
                        plain_out_state <= PO_IDLE;
                    end
                    else if(plain_out_byte == 4'd15)
                    begin
                        plain_out_bytes_remaining <=
                            plain_out_bytes_remaining - 9'd1;
                        plain_out_block <= plain_out_block + 5'd1;
                        plain_out_last_r <= 1'b0;
                        plain_out_state <= PO_LOAD;
                    end
                    else
                    begin
                        plain_out_bytes_remaining <=
                            plain_out_bytes_remaining - 9'd1;
                        plain_out_byte <= plain_out_byte + 4'd1;
                        plain_out_last_r <=
                            (plain_out_bytes_remaining == 9'd2);
                    end
                end
            end
            default: plain_out_state <= PO_IDLE;
        endcase
    end
end

// Capture completed decrypt blocks outside the main control process, then
// perform every plaintext-memory write from this one process.  The pending
// command is consumed and replaced on the same edge, so a full block followed
// immediately by a one-byte partial block does not add input backpressure.
// A repeated ZEROIZE must not skip a scrub address: zeroize_busy_r therefore
// owns the RAM write ports even when another zeroize pulse is present.
always @(posedge clk)
begin
    if(!rst_n)
        plain_write_pending_valid_r <= 1'b0;
    else
    begin
        if(zeroize_busy_r)
        begin
            plain_bank0[zeroize_index[3:0]] <= 128'd0;
            plain_bank1[zeroize_index[3:0]] <= 128'd0;
        end
        else if(plain_write_pending_valid_r && !zeroize && !queue_clear)
        begin
            if(plain_write_bank_r)
                plain_bank1[plain_write_index_r] <= plain_write_data_r;
            else
                plain_bank0[plain_write_index_r] <= plain_write_data_r;
        end

        if(zeroize)
        begin
            plain_write_pending_valid_r <= 1'b0;
            plain_write_bank_r          <= 1'b0;
            plain_write_index_r         <= 4'd0;
            plain_write_data_r          <= 128'd0;
        end
        else if(queue_clear || zeroize_busy_r)
            plain_write_pending_valid_r <= 1'b0;
        else
        begin
            plain_write_pending_valid_r <= plain_write_capture_w;
            if(plain_write_capture_w)
            begin
                plain_write_bank_r  <= rec_bank;
                plain_write_index_r <= data_block_index[3:0];
                plain_write_data_r  <= data_result_w;
            end
        end
    end
end

// The request payload is meaningful only while aes_prod_valid is set.  Write
// it speculatively outside the reset/zeroize control process so those public
// control pulses cannot become reset or enable inputs on this wide register.
wire aes_payload_h_select_w = h_request_pending && !aes_prod_valid;
wire aes_payload_tag_select_w = tag_request_pending && !aes_prod_valid &&
                                !ctr_issue_pending_r &&
                                !iv96_ctr_load_pending_r;
wire aes_payload_ctr_select_w = ctr_issue_pending_r && !aes_prod_valid &&
                                !h_request_pending &&
                                !iv96_ctr_load_pending_r;

always @(posedge clk)
begin
    if(aes_payload_ctr_select_w)
        aes_prod_data <= {1'b0, AES_KIND_CTR_PREFETCH,
                          {j0_reg[127:32], ctr_request_value_r},
                          128'd0, 5'd16,
                          ((ctr_request_index_r + 5'd1) ==
                           ctr_request_total_r),
                          ctr_request_index_r, rec_bank};
    else if(aes_payload_tag_select_w)
        aes_prod_data <= {1'b0, AES_KIND_TAG_MASK, j0_reg,
                          128'd0, 5'd16, 1'b0, 5'd0, rec_bank};
    else if(aes_payload_h_select_w)
        aes_prod_data <= {1'b0, AES_KIND_H, 128'd0, 128'd0,
                          5'd16, 1'b0, 5'd0, 1'b0};
end

wire gh_ctrl_iv_payload_select_w = iv_length_pending && !gh_ctrl_valid &&
                                   !abort_queue_clear;
wire gh_ctrl_msg_payload_select_w = message_length_pending &&
                                    !message_length_enqueued &&
                                    !gh_ctrl_valid &&
                                    !abort_queue_clear;

always @(posedge clk)
begin
    if(!rst_n)
        gh_ctrl_data <= 132'd0;
    else if(gh_ctrl_msg_payload_select_w)
        gh_ctrl_data <= {GH_KIND_MSG_LEN, main_init_pending,
                         53'd0, rec_aad_bits, 53'd0, rec_data_bits};
    else if(gh_ctrl_iv_payload_select_w)
        gh_ctrl_data <= {GH_KIND_IV_LEN, 1'b0,
                         64'd0, 53'd0, rec_iv_bits};
end

// Main control, input assembly, crypto result handling and authenticated
// release.  Payload memories intentionally have no ordinary reset.
integer clear_index;
always @(posedge clk)
begin
    if(!rst_n)
    begin
        state                    <= ST_IDLE;
        rec_decrypt              <= 1'b0;
        rec_tag_bits             <= 8'd128;
        rec_iv_bits              <= 11'd0;
        rec_iv_is_96_r           <= 1'b0;
        rec_aad_bits             <= 11'd0;
        rec_data_bits            <= 11'd0;
        rec_bank                 <= 1'b0;
        record_bytes_remaining   <= 10'd0;
        record_last_r             <= 1'b0;
        field_last_r              <= 1'b0;
        field_received           <= 9'd0;
        block_byte_index         <= 4'd0;
        input_block              <= 128'd0;
        tag_mask_reg             <= 128'd0;
        hash_reg                 <= 128'd0;
        final_tag_reg            <= 128'd0;
        tag_mask_ready           <= 1'b0;
        final_hash_ready         <= 1'b0;
        final_tag_ready          <= 1'b0;
        tag_request_pending      <= 1'b0;
        iv_length_pending        <= 1'b0;
        message_length_pending   <= 1'b0;
        message_length_enqueued  <= 1'b0;
        main_init_pending        <= 1'b0;
        all_cipher_blocks_ready  <= 1'b0;
        enc_data_sent            <= 1'b0;
        ctr_value                <= 32'd0;
        abort_code               <= RESULT_INTERNAL_ERROR;
        abort_queue_clear        <= 1'b0;
        key_ready_r              <= 1'b0;
        h_request_pending        <= 1'b0;
        h_request_sent           <= 1'b0;
        ctr_request_index_r      <= 5'd0;
        ctr_request_total_r      <= 5'd0;
        ctr_request_value_r      <= 32'd0;
        ctr_issue_pending_r      <= 1'b0;
        iv96_ctr_load_pending_r  <= 1'b0;
        h_reg                    <= 128'd0;
        ghash_load_h             <= 1'b0;
        aes_prod_valid           <= 1'b0;
        gh_input_valid           <= 1'b0;
        gh_input_data            <= 132'd0;
        gh_aes_valid             <= 1'b0;
        gh_aes_data              <= 132'd0;
        gh_ctrl_valid            <= 1'b0;
        ct_prod_valid            <= 1'b0;
        ct_prod_data             <= 134'd0;
        tag_prod_valid           <= 1'b0;
        tag_prod_data            <= 136'd0;
        plain_release_valid      <= 1'b0;
        plain_release_data       <= 12'd0;
        bank_allocated           <= 2'b00;
        tag_out_index            <= 4'd0;
        tag_send_active_r         <= 1'b0;
        tag_bytes_remaining_r     <= 5'd0;
        tag_last_r                <= 1'b0;
        enc_frame_started        <= 1'b0;
        enc_frame_finished       <= 1'b0;
        abort_terminator_pending <= 1'b0;
        result_valid_r           <= 1'b0;
        result_data_r            <= RESULT_INTERNAL_ERROR;
        zeroize_abort_count      <= 3'd0;
        zeroize_busy_r           <= 1'b0;
        zeroize_index            <= 5'd0;
        enc_result_pending       <= 1'b0;
        prep_iv_bytes            <= 9'd0;
        prep_aad_bytes           <= 9'd0;
        prep_data_bytes          <= 9'd0;
        prep_header_bytes        <= 10'd0;
        prep_payload_bytes       <= 10'd0;
        prep_record_bytes        <= 10'd0;
    end
    else
    begin
        abort_queue_clear      <= 1'b0;
        ghash_load_h           <= 1'b0;

        if(aes_prod_valid && aes_prod_ready)
            aes_prod_valid <= 1'b0;
        if(gh_input_pop)
            gh_input_valid <= 1'b0;
        if(gh_aes_pop)
            gh_aes_valid <= 1'b0;
        if(gh_ctrl_pop)
            gh_ctrl_valid <= 1'b0;
        if(ct_prod_valid && ct_prod_ready)
            ct_prod_valid <= 1'b0;
        if(tag_prod_valid && tag_prod_ready)
            tag_prod_valid <= 1'b0;
        if(plain_release_valid && plain_release_ready)
            plain_release_valid <= 1'b0;

        // queue_clear is registered for protocol/internal aborts.  Clear the
        // producer state from that registered pulse instead of feeding the
        // accepted input beat and TLAST checks into wide valid/counter reset
        // pins on the same clock edge.
        if(abort_queue_clear)
        begin
            aes_prod_valid       <= 1'b0;
            gh_input_valid       <= 1'b0;
            gh_aes_valid         <= 1'b0;
            gh_ctrl_valid        <= 1'b0;
            ct_prod_valid        <= 1'b0;
            ctr_issue_pending_r  <= 1'b0;
            iv96_ctr_load_pending_r <= 1'b0;
            record_last_r        <= 1'b0;
        end

        if(plain_record_done)
            bank_allocated[plain_out_bank] <= 1'b0;

        if(ct_stream_fire)
        begin
            enc_frame_started <= 1'b1;
            if(ct_block_last_byte)
            begin
                if(ct_head_last)
                begin
                    enc_data_sent <= 1'b1;
                    enc_frame_finished <= 1'b1;
                end
            end
        end

        if(abort_stream_fire)
            abort_terminator_pending <= 1'b0;

        // Load one registered tag-send context from the FIFO head before
        // exposing its first byte.  Thereafter TLAST depends only on the
        // registered remaining-byte state, so the output and FIFO-pop paths
        // do not feed tag_out_index back through a variable-length compare.
        if(zeroize)
        begin
            tag_send_active_r     <= 1'b0;
            tag_bytes_remaining_r <= 5'd0;
            tag_last_r            <= 1'b0;
            tag_out_index         <= 4'd0;
        end
        else if(!tag_send_active_r)
        begin
            if(tagq_valid)
            begin
                tag_send_active_r     <= 1'b1;
                tag_bytes_remaining_r <= tag_bytes[4:0];
                tag_last_r            <= (tag_bytes == 9'd1);
                tag_out_index         <= 4'd0;
            end
        end
        else if(tag_stream_fire)
        begin
            if(tag_last_r)
            begin
                tag_send_active_r     <= 1'b0;
                enc_result_pending    <= 1'b1;
            end
            else
            begin
                tag_bytes_remaining_r <= tag_bytes_remaining_r - 5'd1;
                tag_last_r <= (tag_bytes_remaining_r == 5'd2);
                tag_out_index <= tag_out_index + 4'd1;
            end
        end

        // Explicit zeroize invalidates everything immediately, then scrubs
        // the two plaintext banks over sixteen clocks.
        // Repeated ZEROIZE commands are idempotent.  They may reset the
        // external boundary again, but must not recompute and overwrite the
        // abort count captured by the first command.
        if(first_zeroize_event_w)
        begin
            zeroize_abort_count <= {1'b0, desc_count} +
                                   (active_record ? 3'd1 : 3'd0) +
                                   {1'b0, tagq_count} +
                                   (tag_prod_valid ? 3'd1 : 3'd0) +
                                   (detached_result_pending ? 3'd1 : 3'd0) +
                                   (enc_result_pending ? 3'd1 : 3'd0);
            zeroize_busy_r      <= 1'b1;
            zeroize_index       <= 5'd0;
            state               <= ST_IDLE;
            bank_allocated      <= 2'b00;
            rec_iv_is_96_r      <= 1'b0;
            key_ready_r         <= 1'b0;
            h_request_pending   <= 1'b0;
            h_request_sent      <= 1'b0;
            ctr_request_index_r  <= 5'd0;
            ctr_request_total_r  <= 5'd0;
            ctr_request_value_r  <= 32'd0;
            ctr_issue_pending_r  <= 1'b0;
            iv96_ctr_load_pending_r <= 1'b0;
            h_reg               <= 128'd0;
            tag_mask_reg        <= 128'd0;
            hash_reg            <= 128'd0;
            final_tag_reg       <= 128'd0;
            input_block         <= 128'd0;
            tag_mask_ready      <= 1'b0;
            final_hash_ready    <= 1'b0;
            final_tag_ready     <= 1'b0;
            tag_request_pending <= 1'b0;
            iv_length_pending   <= 1'b0;
            message_length_pending <= 1'b0;
            aes_prod_valid      <= 1'b0;
            gh_input_valid      <= 1'b0;
            gh_aes_valid        <= 1'b0;
            gh_ctrl_valid       <= 1'b0;
            ct_prod_valid       <= 1'b0;
            tag_prod_valid      <= 1'b0;
            prep_iv_bytes       <= 9'd0;
            prep_aad_bytes      <= 9'd0;
            prep_data_bytes     <= 9'd0;
            prep_header_bytes   <= 10'd0;
            prep_payload_bytes  <= 10'd0;
            prep_record_bytes   <= 10'd0;
            record_last_r       <= 1'b0;
            // ZEROIZE is an emergency public-frame termination.  The AXI
            // boundary registers are synchronously cleared with the same
            // command, so no post-zeroize synthetic data beat may reappear.
            abort_terminator_pending <= 1'b0;
            plain_release_valid <= 1'b0;
            result_valid_r      <= 1'b0;
            enc_result_pending  <= 1'b0;
            abort_queue_clear   <= 1'b1;
        end
        else if(zeroize_busy_r)
        begin
            state <= ST_IDLE;
            if(zeroize_index == 5'd15)
                zeroize_busy_r <= 1'b0;
            else
                zeroize_index <= zeroize_index + 5'd1;
        end
        else
        begin
            if(key_commit)
            begin
                key_ready_r       <= 1'b0;
                h_request_pending <= 1'b0;
                h_request_sent    <= 1'b0;
            end

            if(key_context_ready && !key_ready_r && !h_request_sent)
                h_request_pending <= 1'b1;

            if(h_request_pending && !aes_prod_valid &&
               crypto_event_enable_w)
            begin
                aes_prod_valid      <= 1'b1;
                h_request_pending   <= 1'b0;
                h_request_sent      <= 1'b1;
            end

            // The 96-bit-IV fast path registers its final-byte event before
            // loading the wide CTR scheduler state.  This one-cycle cut also
            // keeps counter requests ahead of AES_K(J0).
            if(iv96_ctr_load_pending_r && !queue_clear &&
               normal_crypto_state)
            begin
                ctr_request_index_r     <= 5'd0;
                ctr_request_value_r     <= 32'd2;
                ctr_issue_pending_r     <=
                    (ctr_request_total_r != 5'd0);
                iv96_ctr_load_pending_r <= 1'b0;
            end

            if(tag_request_pending && !aes_prod_valid &&
               crypto_event_enable_w && !ctr_issue_pending_r &&
               !iv96_ctr_load_pending_r)
            begin
                aes_prod_valid     <= 1'b1;
                tag_request_pending<= 1'b0;
            end

            // Keep the shared AES engine fed with future counter blocks.  A
            // sixteen-entry keystream FIFO covers the complete descriptor,
            // so input completion never launches an AES recurrence.
            if(ctr_issue_pending_r && !aes_prod_valid &&
               !h_request_pending && crypto_event_enable_w &&
               !iv96_ctr_load_pending_r)
            begin
                aes_prod_valid <= 1'b1;
                ctr_request_index_r <= ctr_request_index_r + 5'd1;
                ctr_request_value_r <= ctr_request_value_r + 32'd1;
                if((ctr_request_index_r + 5'd1) == ctr_request_total_r)
                    ctr_issue_pending_r <= 1'b0;
            end

            if(iv_length_pending && !gh_ctrl_valid && !queue_clear &&
               normal_crypto_state)
            begin
                gh_ctrl_valid       <= 1'b1;
                iv_length_pending   <= 1'b0;
            end

            if(message_length_pending && !message_length_enqueued &&
               !gh_ctrl_valid && !queue_clear && normal_crypto_state)
            begin
                gh_ctrl_valid           <= 1'b1;
                main_init_pending       <= 1'b0;
                message_length_enqueued <= 1'b1;
            end

            // Interpret completed GHASH blocks.
            if(ghash_done && !queue_clear && normal_crypto_state)
            begin
                if(gh_active_kind == GH_KIND_IV_LEN)
                begin
                    ctr_value           <= ghash_y[31:0] + 32'd1;
                    tag_request_pending <= 1'b1;
                    ctr_request_index_r <= 5'd0;
                    ctr_request_value_r <= ghash_y[31:0] + 32'd1;
                    ctr_issue_pending_r <=
                        (ctr_request_total_r != 5'd0);
                    main_init_pending   <= 1'b1;
                    input_block         <= 128'd0;
                    block_byte_index    <= 4'd0;
                    field_received      <= 9'd0;
                    if(rec_aad_bits != 0)
                    begin
                        field_last_r <= (prep_aad_bytes == 9'd1);
                        state       <= ST_AAD;
                    end
                    else if(ctr_request_total_r != 5'd0)
                    begin
                        field_last_r <= (prep_data_bytes == 9'd1);
                        state       <= ST_DATA;
                    end
                    else if(rec_decrypt)
                    begin
                        all_cipher_blocks_ready <= 1'b1;
                        message_length_pending  <= 1'b1;
                        field_last_r <= (prep_tag_bytes == 9'd1);
                        state       <= ST_TAG_IN;
                    end
                    else
                    begin
                        all_cipher_blocks_ready <= 1'b1;
                        message_length_pending  <= 1'b1;
                        field_last_r <= 1'b0;
                        state <= ST_FINAL_WAIT;
                    end
                end
                else if(gh_active_kind == GH_KIND_MSG_LEN)
                begin
                    hash_reg         <= ghash_y;
                    final_hash_ready <= 1'b1;
                end
            end

            if(final_tag_form_w)
            begin
                final_tag_reg   <= final_tag_value_w;
                final_tag_ready <= 1'b1;
            end

            // Non-CTR results are always pop-ready.  A stalled CTR result may
            // be observed repeatedly here, but its case has no side effects.
            if(aes_result_observe_w)
            begin
                case(aes_res_kind)
                    AES_KIND_H:
                    begin
                        h_reg                  <= aes_res_block;
                        ghash_load_h           <= 1'b1;
                        key_ready_r            <= 1'b1;
                    end
                    AES_KIND_TAG_MASK:
                    begin
                        tag_mask_reg           <= aes_res_block;
                        tag_mask_ready         <= 1'b1;
                    end
                    AES_KIND_CTR_PREFETCH:
                        ;
                    default:
                    begin
                        abort_code             <= RESULT_INTERNAL_ERROR;
                        abort_queue_clear      <= 1'b1;
                        record_last_r          <= 1'b0;
                        state                  <= ST_ABORT_WAIT;
                    end
                endcase
            end

            // Capture a descriptor, then compute its byte counts over three
            // short registered stages.  This keeps the FIFO read pointer and
            // four variable ceil(bits/8) additions out of one timing cone.
            if(take_descriptor)
            begin
                rec_decrypt             <= desc_out_data[41];
                rec_tag_bits            <= desc_out_data[40:33];
                rec_iv_bits             <= desc_out_data[32:22];
                rec_iv_is_96_r           <=
                    (desc_out_data[32:22] == 11'd96);
                rec_aad_bits            <= desc_out_data[21:11];
                rec_data_bits           <= desc_out_data[10:0];
                ctr_request_total_r     <=
                    bits_to_blocks(desc_out_data[10:0]);
                prep_iv_bytes           <= bits_to_bytes(desc_out_data[32:22]);
                prep_aad_bytes          <= bits_to_bytes(desc_out_data[21:11]);
                prep_data_bytes         <= bits_to_bytes(desc_out_data[10:0]);
                record_last_r           <= 1'b0;
                field_received          <= 9'd0;
                block_byte_index        <= 4'd0;
                input_block             <= 128'd0;
                tag_mask_ready          <= 1'b0;
                final_hash_ready        <= 1'b0;
                final_tag_ready         <= 1'b0;
                tag_request_pending     <= 1'b0;
                ctr_issue_pending_r     <= 1'b0;
                iv96_ctr_load_pending_r <= 1'b0;
                iv_length_pending       <= 1'b0;
                message_length_pending  <= 1'b0;
                message_length_enqueued <= 1'b0;
                main_init_pending       <= 1'b0;
                all_cipher_blocks_ready <= (desc_out_data[10:0] == 0);
                enc_data_sent           <= (desc_out_data[10:0] == 0);
                ctr_value               <= 32'd0;
                enc_frame_started       <= 1'b0;
                enc_frame_finished      <= (desc_out_data[10:0] == 0);
                abort_terminator_pending<= 1'b0;
                state                   <= ST_DESC_WAIT;
            end

            // The descriptor is already captured and represented by
            // active_record.  Select a plaintext bank only when the ordered
            // record can actually start; a bank may have been released while
            // this state was waiting.
            if((state == ST_DESC_WAIT) && descriptor_resource_ready_w)
            begin
                rec_bank <= free_plain_bank;
                if(rec_decrypt)
                    bank_allocated[free_plain_bank] <= 1'b1;
                state <= ST_DESC_SUM;
            end

            if(state == ST_DESC_SUM)
            begin
                prep_header_bytes  <= {1'b0, prep_iv_bytes} +
                                      {1'b0, prep_aad_bytes};
                prep_payload_bytes <= {1'b0, prep_data_bytes} +
                                      {1'b0, prep_tag_bytes};
                state <= ST_DESC_TOTAL;
            end

            if(state == ST_DESC_TOTAL)
            begin
                prep_record_bytes <= prep_header_bytes +
                                     prep_payload_bytes;
                state <= ST_DESC_START;
            end

            if(state == ST_DESC_START)
            begin
                record_bytes_remaining <= prep_record_bytes;
                record_last_r          <= (prep_record_bytes == 10'd1);
                field_last_r           <= (prep_iv_bytes == 9'd1);
                state <= ST_IV;
            end

            // Packet input and TLAST enforcement.
            else if(input_fire)
            begin
                if(state == ST_DRAIN)
                begin
                    if(s_axis_tlast)
                        state <= ST_ABORT_WAIT;
                end
                else if(early_tlast_now || late_tlast_now)
                begin
                    abort_code        <= early_tlast_now ? RESULT_EARLY_TLAST :
                                                             RESULT_LATE_TLAST;
                    abort_queue_clear <= 1'b1;
                    record_last_r     <= 1'b0;
                    if(!rec_decrypt &&
                       (enc_frame_started || ct_stream_fire) &&
                       !(enc_frame_finished ||
                         (ct_stream_fire && ct_record_last_byte)))
                        abort_terminator_pending <= 1'b1;
                    state             <= early_tlast_now ? ST_ABORT_WAIT : ST_DRAIN;
                end
                else
                begin
                    record_bytes_remaining <= record_bytes_remaining - 10'd1;
                    record_last_r          <=
                        (record_bytes_remaining == 10'd2);
                    field_last_r           <= (field_bytes_remaining == 9'd2);
                    case(state)
                        ST_IV:
                        begin
                            input_block <= put_block_byte(
                                input_block, block_byte_index,
                                completing_field_byte ?
                                mask_final_byte(s_axis_tdata, rec_iv_bits) :
                                s_axis_tdata);
                            if(completing_block_byte)
                            begin
                                if(!rec_iv_is_96_r)
                                begin
                                    gh_input_valid <= 1'b1;
                                    gh_input_data  <= {GH_KIND_IV_DATA,
                                                      (field_received < 9'd16),
                                                      put_block_byte(
                                                        input_block,
                                                        block_byte_index,
                                                        completing_field_byte ?
                                                        mask_final_byte(s_axis_tdata,
                                                                        rec_iv_bits) :
                                                        s_axis_tdata)};
                                end
                                input_block      <= 128'd0;
                                block_byte_index<= 4'd0;
                            end
                            else
                                block_byte_index <= block_byte_index + 4'd1;

                            if(completing_field_byte)
                            begin
                                field_received <= 9'd0;
                                if(rec_iv_is_96_r)
                                begin
                                    ctr_value <= 32'd2;
                                    tag_request_pending <= 1'b1;
                                    iv96_ctr_load_pending_r <= 1'b1;
                                    main_init_pending <= 1'b1;
                                    if(rec_aad_bits != 0)
                                    begin
                                        field_last_r <=
                                            (prep_aad_bytes == 9'd1);
                                        state <= ST_AAD;
                                    end
                                    else if(ctr_request_total_r != 5'd0)
                                    begin
                                        field_last_r <=
                                            (prep_data_bytes == 9'd1);
                                        state <= ST_DATA;
                                    end
                                    else if(rec_decrypt)
                                    begin
                                        message_length_pending <= 1'b1;
                                        field_last_r <=
                                            (prep_tag_bytes == 9'd1);
                                        state <= ST_TAG_IN;
                                    end
                                    else
                                    begin
                                        message_length_pending <= 1'b1;
                                        field_last_r <= 1'b0;
                                        state <= ST_FINAL_WAIT;
                                    end
                                end
                                else
                                begin
                                    iv_length_pending <= 1'b1;
                                    field_last_r <= 1'b0;
                                    state <= ST_IV_WAIT;
                                end
                            end
                            else
                                field_received <= field_received + 9'd1;
                        end

                        ST_AAD:
                        begin
                            input_block <= put_block_byte(
                                input_block, block_byte_index,
                                completing_field_byte ?
                                mask_final_byte(s_axis_tdata, rec_aad_bits) :
                                s_axis_tdata);
                            if(completing_block_byte)
                            begin
                                gh_input_valid <= 1'b1;
                                gh_input_data  <= {GH_KIND_MSG_DATA,
                                                  main_init_pending,
                                                  put_block_byte(
                                                    input_block,
                                                    block_byte_index,
                                                    completing_field_byte ?
                                                    mask_final_byte(s_axis_tdata,
                                                                    rec_aad_bits) :
                                                    s_axis_tdata)};
                                main_init_pending <= 1'b0;
                                input_block       <= 128'd0;
                                block_byte_index <= 4'd0;
                            end
                            else
                                block_byte_index <= block_byte_index + 4'd1;

                            if(completing_field_byte)
                            begin
                                field_received <= 9'd0;
                                if(ctr_request_total_r != 5'd0)
                                begin
                                    field_last_r <=
                                        (prep_data_bytes == 9'd1);
                                    state <= ST_DATA;
                                end
                                else if(rec_decrypt)
                                begin
                                    message_length_pending <= 1'b1;
                                    field_last_r <=
                                        (prep_tag_bytes == 9'd1);
                                    state <= ST_TAG_IN;
                                end
                                else
                                begin
                                    message_length_pending <= 1'b1;
                                    field_last_r <= 1'b0;
                                    state <= ST_FINAL_WAIT;
                                end
                            end
                            else
                                field_received <= field_received + 9'd1;
                        end

                        ST_DATA:
                        begin
                            input_block <= put_block_byte(
                                input_block, block_byte_index,
                                completing_field_byte ?
                                mask_final_byte(s_axis_tdata, rec_data_bits) :
                                s_axis_tdata);
                            if(completing_block_byte)
                            begin
                                if(rec_decrypt)
                                begin
                                    gh_input_valid <= 1'b1;
                                    gh_input_data  <= {GH_KIND_MSG_DATA,
                                                      main_init_pending,
                                                      completed_input_block_w};
                                end
                                else
                                begin
                                    ct_prod_valid <= 1'b1;
                                    ct_prod_data  <= {data_result_w,
                                                      completed_data_bytes_w,
                                                      completing_field_byte};
                                    gh_aes_valid <= 1'b1;
                                    gh_aes_data  <= {GH_KIND_MSG_DATA,
                                                      main_init_pending,
                                                      data_result_w};
                                end
                                main_init_pending <= 1'b0;
                                if(completing_field_byte)
                                begin
                                    all_cipher_blocks_ready <= 1'b1;
                                    message_length_pending <= 1'b1;
                                end
                                input_block       <= 128'd0;
                                block_byte_index <= 4'd0;
                            end
                            else
                                block_byte_index <= block_byte_index + 4'd1;

                            if(completing_field_byte)
                            begin
                                field_received <= 9'd0;
                                if(rec_decrypt)
                                begin
                                    message_length_pending <= 1'b1;
                                    field_last_r <=
                                        (prep_tag_bytes == 9'd1);
                                    state <= ST_TAG_IN;
                                end
                                else
                                begin
                                    field_last_r <= 1'b0;
                                    state <= ST_FINAL_WAIT;
                                end
                            end
                            else
                                field_received <= field_received + 9'd1;
                        end

                        ST_TAG_IN:
                        begin
                            if(completing_field_byte)
                            begin
                                field_received <= 9'd0;
                                field_last_r <= 1'b0;
                                state <= ST_FINAL_WAIT;
                            end
                            else
                                field_received <= field_received + 9'd1;
                        end
                        default: state <= state;
                    endcase
                end
            end

            // Decryption authentication result is generated only when both
            // tag operands are complete.  The compare is a fixed XOR/OR
            // reduction; there is no early byte exit.
            if(descriptor_crypto_active_w && final_tag_ready &&
               all_cipher_blocks_ready && !result_valid_r &&
               !enc_result_pending)
            begin
                if(rec_decrypt)
                begin
                    if(tag_compare_ready_r &&
                       !older_encryption_completion_pending &&
                       !plain_write_pending_valid_r)
                    begin
                        result_data_r  <= tag_mismatch_w ?
                                          RESULT_DEC_AUTH_FAIL :
                                          RESULT_DEC_AUTH_OK;
                        result_valid_r <= 1'b1;
                        state          <= ST_DEC_RESULT;
                    end
                end
                else if(enc_data_sent)
                begin
                    if(!tag_prod_valid)
                    begin
                        tag_prod_valid <= 1'b1;
                        tag_prod_data  <= {rec_tag_bits, final_tag_reg};
                        state <= ST_IDLE;
                    end
                end
            end

            if((state == ST_DEC_RESULT) && result_valid_r &&
               m_axis_result_tready)
            begin
                result_valid_r <= 1'b0;
                if(result_data_r == RESULT_DEC_AUTH_OK)
                begin
                    if(ctr_request_total_r != 5'd0)
                    begin
                        plain_release_valid <= 1'b1;
                        plain_release_data  <= {rec_bank, rec_data_bits};
                    end
                    else
                        bank_allocated[rec_bank] <= 1'b0;
                end
                else
                    bank_allocated[rec_bank] <= 1'b0;
                state <= ST_IDLE;
            end

            if(result_valid_r && m_axis_result_tready &&
               (result_data_r == RESULT_ENC_OK))
                result_valid_r <= 1'b0;

            if(enc_result_pending && !result_valid_r)
            begin
                result_data_r      <= RESULT_ENC_OK;
                result_valid_r     <= 1'b1;
                enc_result_pending <= 1'b0;
            end

            if(active_abort_result_load_w)
            begin
                result_data_r  <= abort_code;
                result_valid_r <= 1'b1;
            end

            // An older ENC_OK may occupy the shared result register while
            // this descriptor waits in ST_ABORT_WAIT.  Only the active
            // descriptor's own abort code retires the abort state.
            if((state == ST_ABORT_WAIT) && result_valid_r &&
               active_abort_result_r && m_axis_result_tready)
            begin
                result_valid_r <= 1'b0;
                if(rec_decrypt)
                    bank_allocated[rec_bank] <= 1'b0;
                state <= ST_IDLE;
            end

            // Explicit zeroize abort responses are emitted after memory
            // scrubbing.  Reset is the only operation allowed to suppress an
            // already accepted descriptor's result beat.
            if(zeroize_abort_result_fire_w)
                result_valid_r <= 1'b0;
            else if((zeroize_abort_count != 0) && !result_valid_r &&
                    (state == ST_IDLE) && !abort_terminator_pending)
            begin
                result_data_r       <= RESULT_ZEROIZE_ABORT;
                result_valid_r      <= 1'b1;
                zeroize_abort_count <= zeroize_abort_count - 3'd1;
            end
        end
    end
end

endmodule
