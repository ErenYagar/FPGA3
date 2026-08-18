`timescale 1ns / 1ps

// Compatibility bridge for the original byte/type/last interface.
//
// One complete legacy record is buffered before it is submitted to the
// streaming core.  The upstream contract has no ready output, so inputs are
// accepted only while this adapter is collecting an idle record.
module legacy_stream_adapter
(
    input          clk,
    input          rst,
    input  [2:0]   key_mode,
    input          mode,
    input  [7:0]   in,
    input          in_valid,
    input  [2:0]   in_type,
    input  [10:0]  in_valid_bit,
    input          last,
    output reg     pc_ct_valid,
    output reg     tag_valid,
    output reg [10:0] pc_ct_len_bit,
    output reg [3:0] pc_ct_valid_bit,
    output reg [7:0] out
);

localparam [2:0] TYPE_IV  = 3'd0;
localparam [2:0] TYPE_KEY = 3'd1;
localparam [2:0] TYPE_AAD = 3'd2;
localparam [2:0] TYPE_PT  = 3'd3;
localparam [2:0] TYPE_CT  = 3'd4;
localparam [2:0] TYPE_TAG = 3'd5;

localparam [3:0] ST_COLLECT       = 4'd0;
localparam [3:0] ST_KEY_COMMIT    = 4'd1;
localparam [3:0] ST_KEY_WAIT      = 4'd2;
localparam [3:0] ST_CMD_PUSH      = 4'd3;
localparam [3:0] ST_SEND_IV       = 4'd4;
localparam [3:0] ST_SEND_AAD      = 4'd5;
localparam [3:0] ST_SEND_DATA     = 4'd6;
localparam [3:0] ST_SEND_TAG      = 4'd7;
localparam [3:0] ST_WAIT_COMPLETE = 4'd8;
localparam [3:0] ST_DEC_STATUS    = 4'd9;
localparam [3:0] ST_CLEAR         = 4'd10;

localparam [7:0] RESULT_DEC_AUTH_OK   = 8'h01;

function [7:0] mask_last_byte;
input [7:0] byte_in;
input [10:0] total_bits;
begin
    case(total_bits[2:0])
        3'd0: mask_last_byte = byte_in;
        3'd1: mask_last_byte = {byte_in[7],   7'd0};
        3'd2: mask_last_byte = {byte_in[7:6], 6'd0};
        3'd3: mask_last_byte = {byte_in[7:5], 5'd0};
        3'd4: mask_last_byte = {byte_in[7:4], 4'd0};
        3'd5: mask_last_byte = {byte_in[7:3], 3'd0};
        3'd6: mask_last_byte = {byte_in[7:2], 2'd0};
        default: mask_last_byte = {byte_in[7:1], 1'b0};
    endcase
end
endfunction

function [8:0] bits_to_bytes;
input [10:0] bit_count;
reg [11:0] rounded;
begin
    rounded = {1'b0, bit_count} + 12'd7;
    bits_to_bytes = rounded[11:3];
end
endfunction

function key_length_matches;
input [2:0] selected_mode;
input [10:0] bit_count;
begin
    case(selected_mode)
        3'd0: key_length_matches = (bit_count == 11'd128);
        3'd1: key_length_matches = (bit_count == 11'd192);
        3'd2: key_length_matches = (bit_count == 11'd256);
        default: key_length_matches = 1'b0;
    endcase
end
endfunction

function tag_length_allowed;
input [7:0] bit_count;
begin
    case(bit_count)
        8'd32, 8'd64, 8'd96, 8'd104,
        8'd112, 8'd120, 8'd128:
            tag_length_allowed = 1'b1;
        default:
            tag_length_allowed = 1'b0;
    endcase
end
endfunction

reg [3:0] state_r;
reg       mode_r;
reg [2:0] key_mode_r;

reg [255:0] key_shift_r;
reg [5:0]   key_byte_index_r;
reg         key_collected_r;

reg [7:0] iv_mem  [0:127];
reg [7:0] aad_mem [0:127];
reg [7:0] pt_mem  [0:127];
reg [7:0] ct_mem  [0:127];
reg [7:0] tag_mem [0:15];

reg [7:0] iv_byte_index_r;
reg [7:0] aad_byte_index_r;
reg [7:0] pt_byte_index_r;
reg [7:0] ct_byte_index_r;
reg [4:0] tag_byte_index_r;

reg [10:0] iv_bits_r;
reg [10:0] aad_bits_r;
reg [10:0] pt_bits_r;
reg [10:0] ct_bits_r;
reg [10:0] tag_bits_r;

reg iv_collected_r;
reg aad_collected_r;
reg pt_collected_r;
reg ct_collected_r;
reg tag_collected_r;

reg [7:0] send_index_r;

wire [255:0] normalized_key_w =
    (key_mode_r == 3'd0) ? {key_shift_r[127:0], 128'd0} :
    (key_mode_r == 3'd1) ? {key_shift_r[191:0],  64'd0} :
                           key_shift_r;

wire [10:0] selected_data_bits_w = mode_r ? ct_bits_r : pt_bits_r;
wire [8:0] iv_bytes_w   = bits_to_bytes(iv_bits_r);
wire [8:0] aad_bytes_w  = bits_to_bytes(aad_bits_r);
wire [8:0] data_bytes_w = bits_to_bytes(selected_data_bits_w);
wire [8:0] tag_bytes_w  = bits_to_bytes(tag_bits_r);

wire selected_input_collected_w = mode ? ct_collected_r : pt_collected_r;
wire record_collected_w = key_collected_r && iv_collected_r &&
                          aad_collected_r && selected_input_collected_w &&
                          tag_collected_r && (iv_bits_r != 11'd0) &&
                          tag_length_allowed(tag_bits_r[7:0]);

wire core_key_ready;
wire core_key_busy;
wire core_cmd_full;
wire core_cmd_pending;
wire core_record_active;
wire core_output_pending;
wire core_zeroize_busy;
wire core_zeroize_defer_unused;

wire core_key_commit_w = (state_r == ST_KEY_COMMIT) &&
                         !core_key_busy && !core_record_active &&
                         !core_output_pending && !core_cmd_pending &&
                         !core_zeroize_busy;
wire core_cmd_push_w = (state_r == ST_CMD_PUSH) &&
                       core_key_ready && !core_cmd_full;

reg  [7:0] core_s_tdata_r;
reg        core_s_tvalid_r;
reg        core_s_tlast_r;
wire       core_s_tready;
wire       core_input_fire_w = core_s_tvalid_r && core_s_tready;

wire [7:0] core_data_tdata;
wire       core_data_tvalid;
wire       core_data_tlast;
wire [3:0] core_data_tuser;
wire [7:0] core_tag_tdata;
wire       core_tag_tvalid;
wire       core_tag_tlast;
wire [7:0] core_result_tdata;
wire       core_result_tvalid;
wire       core_result_tlast;

// The legacy interface cannot apply backpressure to an output.  The adapter
// therefore consumes every core output beat immediately and registers it on
// the corresponding legacy valid signal.
wire core_data_tready   = 1'b1;
wire core_tag_tready    = 1'b1;
wire core_result_tready = 1'b1;

always @(*)
begin
    core_s_tdata_r  = 8'd0;
    core_s_tvalid_r = 1'b0;
    core_s_tlast_r  = 1'b0;

    case(state_r)
        ST_SEND_IV:
        begin
            core_s_tdata_r  = iv_mem[send_index_r];
            core_s_tvalid_r = 1'b1;
            core_s_tlast_r  = (({1'b0, send_index_r} + 9'd1) == iv_bytes_w) &&
                              (aad_bytes_w == 9'd0) &&
                              (data_bytes_w == 9'd0) && !mode_r;
        end
        ST_SEND_AAD:
        begin
            core_s_tdata_r  = aad_mem[send_index_r];
            core_s_tvalid_r = 1'b1;
            core_s_tlast_r  = (({1'b0, send_index_r} + 9'd1) == aad_bytes_w) &&
                              (data_bytes_w == 9'd0) && !mode_r;
        end
        ST_SEND_DATA:
        begin
            core_s_tdata_r  = mode_r ? ct_mem[send_index_r] :
                                       pt_mem[send_index_r];
            core_s_tvalid_r = 1'b1;
            core_s_tlast_r  = (({1'b0, send_index_r} + 9'd1) == data_bytes_w) &&
                              !mode_r;
        end
        ST_SEND_TAG:
        begin
            core_s_tdata_r  = tag_mem[send_index_r[3:0]];
            core_s_tvalid_r = 1'b1;
            core_s_tlast_r  = (({1'b0, send_index_r} + 9'd1) == tag_bytes_w);
        end
        default:
        begin
            core_s_tdata_r  = 8'd0;
            core_s_tvalid_r = 1'b0;
            core_s_tlast_r  = 1'b0;
        end
    endcase
end

aes_gcm_stream_core #(
    .ALLOW_NIST_TAG_LENGTHS(1'b1)
) u_stream_core (
    .clk                    (clk),
    .rst_n                  (~rst),
    .key_commit             (core_key_commit_w),
    .zeroize                (1'b0),
    .key_mode               (key_mode_r),
    .key_data               (normalized_key_w),
    .key_ready              (core_key_ready),
    .key_busy               (core_key_busy),
    .cmd_push               (core_cmd_push_w),
    .cmd_decrypt            (mode_r),
    .cmd_tag_bits           (tag_bits_r[7:0]),
    .cmd_iv_bits            (iv_bits_r),
    .cmd_aad_bits           (aad_bits_r),
    .cmd_data_bits          (selected_data_bits_w),
    .cmd_full               (core_cmd_full),
    .cmd_pending            (core_cmd_pending),
    .record_active          (core_record_active),
    .output_pending         (core_output_pending),
    .zeroize_busy           (core_zeroize_busy),
    .zeroize_defer          (core_zeroize_defer_unused),
    .s_axis_tdata           (core_s_tdata_r),
    .s_axis_tvalid          (core_s_tvalid_r),
    .s_axis_tready          (core_s_tready),
    .s_axis_tlast           (core_s_tlast_r),
    .m_axis_data_tdata      (core_data_tdata),
    .m_axis_data_tvalid     (core_data_tvalid),
    .m_axis_data_tready     (core_data_tready),
    .m_axis_data_tlast      (core_data_tlast),
    .m_axis_data_tuser      (core_data_tuser),
    .m_axis_tag_tdata       (core_tag_tdata),
    .m_axis_tag_tvalid      (core_tag_tvalid),
    .m_axis_tag_tready      (core_tag_tready),
    .m_axis_tag_tlast       (core_tag_tlast),
    .m_axis_result_tdata    (core_result_tdata),
    .m_axis_result_tvalid   (core_result_tvalid),
    .m_axis_result_tready   (core_result_tready),
    .m_axis_result_tlast    (core_result_tlast)
);

always @(posedge clk)
begin
    if(rst)
    begin
        state_r             <= ST_COLLECT;
        mode_r              <= 1'b0;
        key_mode_r          <= 3'd0;
        key_shift_r         <= 256'd0;
        key_byte_index_r    <= 6'd0;
        key_collected_r     <= 1'b0;
        iv_byte_index_r     <= 8'd0;
        aad_byte_index_r    <= 8'd0;
        pt_byte_index_r     <= 8'd0;
        ct_byte_index_r     <= 8'd0;
        tag_byte_index_r    <= 5'd0;
        iv_bits_r           <= 11'd0;
        aad_bits_r          <= 11'd0;
        pt_bits_r           <= 11'd0;
        ct_bits_r           <= 11'd0;
        tag_bits_r          <= 11'd0;
        iv_collected_r      <= 1'b0;
        aad_collected_r     <= 1'b0;
        pt_collected_r      <= 1'b0;
        ct_collected_r      <= 1'b0;
        tag_collected_r     <= 1'b0;
        send_index_r        <= 8'd0;
        pc_ct_valid         <= 1'b0;
        tag_valid           <= 1'b0;
        pc_ct_len_bit       <= 11'd0;
        pc_ct_valid_bit     <= 4'd0;
        out                 <= 8'd0;
    end
    else
    begin
        pc_ct_valid     <= 1'b0;
        tag_valid       <= 1'b0;
        pc_ct_valid_bit <= 4'd0;

        if(core_data_tvalid)
        begin
            out             <= core_data_tdata;
            pc_ct_valid     <= 1'b1;
            pc_ct_valid_bit <= core_data_tlast ? core_data_tuser : 4'd8;
        end

        if(!mode_r && core_tag_tvalid)
        begin
            out       <= core_tag_tdata;
            tag_valid <= 1'b1;
        end

        if((state_r == ST_COLLECT) && in_valid)
        begin
            case(in_type)
                TYPE_KEY:
                begin
                    if(last && (in_valid_bit == 11'd0) &&
                       (key_byte_index_r == 6'd0))
                    begin
                        key_shift_r      <= 256'd0;
                        key_byte_index_r <= 6'd0;
                        key_collected_r  <= 1'b0;
                    end
                    else
                    begin
                        if(key_byte_index_r < 6'd32)
                            key_shift_r <= {key_shift_r[247:0],
                                            last ? mask_last_byte(in,
                                                                  in_valid_bit) :
                                                   in};
                        if(last)
                        begin
                            key_mode_r       <= key_mode;
                            key_collected_r  <= key_length_matches(key_mode,
                                                                   in_valid_bit);
                            key_byte_index_r <= 6'd0;
                        end
                        else if(key_byte_index_r < 6'd32)
                            key_byte_index_r <= key_byte_index_r + 6'd1;
                    end
                end

                TYPE_IV:
                begin
                    if(last && (in_valid_bit == 11'd0))
                    begin
                        iv_bits_r       <= 11'd0;
                        iv_collected_r  <= 1'b1;
                        iv_byte_index_r <= 8'd0;
                    end
                    else
                    begin
                        if(iv_byte_index_r < 8'd128)
                            iv_mem[iv_byte_index_r] <=
                                last ? mask_last_byte(in, in_valid_bit) : in;
                        if(last)
                        begin
                            iv_bits_r       <= in_valid_bit;
                            iv_collected_r  <= (in_valid_bit <= 11'd1024);
                            iv_byte_index_r <= 8'd0;
                        end
                        else if(iv_byte_index_r < 8'd128)
                            iv_byte_index_r <= iv_byte_index_r + 8'd1;
                    end
                end

                TYPE_AAD:
                begin
                    if(last && (in_valid_bit == 11'd0))
                    begin
                        aad_bits_r       <= 11'd0;
                        aad_collected_r  <= 1'b1;
                        aad_byte_index_r <= 8'd0;
                    end
                    else
                    begin
                        if(aad_byte_index_r < 8'd128)
                            aad_mem[aad_byte_index_r] <=
                                last ? mask_last_byte(in, in_valid_bit) : in;
                        if(last)
                        begin
                            aad_bits_r       <= in_valid_bit;
                            aad_collected_r  <= (in_valid_bit <= 11'd1024);
                            aad_byte_index_r <= 8'd0;
                        end
                        else if(aad_byte_index_r < 8'd128)
                            aad_byte_index_r <= aad_byte_index_r + 8'd1;
                    end
                end

                TYPE_PT:
                begin
                    if(last && (in_valid_bit == 11'd0))
                    begin
                        pt_bits_r       <= 11'd0;
                        pt_collected_r  <= 1'b1;
                        pt_byte_index_r <= 8'd0;
                    end
                    else
                    begin
                        if(pt_byte_index_r < 8'd128)
                            pt_mem[pt_byte_index_r] <=
                                last ? mask_last_byte(in, in_valid_bit) : in;
                        if(last)
                        begin
                            pt_bits_r       <= in_valid_bit;
                            pt_collected_r  <= (in_valid_bit <= 11'd1024);
                            pt_byte_index_r <= 8'd0;
                        end
                        else if(pt_byte_index_r < 8'd128)
                            pt_byte_index_r <= pt_byte_index_r + 8'd1;
                    end
                end

                TYPE_CT:
                begin
                    if(last && (in_valid_bit == 11'd0))
                    begin
                        ct_bits_r       <= 11'd0;
                        ct_collected_r  <= 1'b1;
                        ct_byte_index_r <= 8'd0;
                    end
                    else
                    begin
                        if(ct_byte_index_r < 8'd128)
                            ct_mem[ct_byte_index_r] <=
                                last ? mask_last_byte(in, in_valid_bit) : in;
                        if(last)
                        begin
                            ct_bits_r       <= in_valid_bit;
                            ct_collected_r  <= (in_valid_bit <= 11'd1024);
                            ct_byte_index_r <= 8'd0;
                        end
                        else if(ct_byte_index_r < 8'd128)
                            ct_byte_index_r <= ct_byte_index_r + 8'd1;
                    end
                end

                TYPE_TAG:
                begin
                    if(last && (in_valid_bit == 11'd0))
                    begin
                        tag_bits_r       <= 11'd0;
                        tag_collected_r  <= 1'b1;
                        tag_byte_index_r <= 5'd0;
                    end
                    else
                    begin
                        if(tag_byte_index_r < 5'd16)
                            tag_mem[tag_byte_index_r] <=
                                last ? mask_last_byte(in, in_valid_bit) : in;
                        if(last)
                        begin
                            tag_bits_r       <= in_valid_bit;
                            tag_collected_r  <= (in_valid_bit <= 11'd128);
                            tag_byte_index_r <= 5'd0;
                        end
                        else if(tag_byte_index_r < 5'd16)
                            tag_byte_index_r <= tag_byte_index_r + 5'd1;
                    end
                end
                default:
                begin
                end
            endcase
        end

        case(state_r)
            ST_COLLECT:
            begin
                if(record_collected_w)
                begin
                    mode_r          <= mode;
                    pc_ct_len_bit   <= mode ? ct_bits_r : pt_bits_r;
                    send_index_r    <= 8'd0;
                    state_r         <= ST_KEY_COMMIT;
                end
            end

            ST_KEY_COMMIT:
            begin
                if(core_key_commit_w)
                    state_r <= ST_KEY_WAIT;
            end

            ST_KEY_WAIT:
            begin
                if(core_key_ready)
                    state_r <= ST_CMD_PUSH;
            end

            ST_CMD_PUSH:
            begin
                if(core_cmd_push_w)
                begin
                    send_index_r <= 8'd0;
                    state_r      <= ST_SEND_IV;
                end
            end

            ST_SEND_IV:
            begin
                if(core_input_fire_w)
                begin
                    if(({1'b0, send_index_r} + 9'd1) == iv_bytes_w)
                    begin
                        send_index_r <= 8'd0;
                        if(aad_bytes_w != 9'd0)
                            state_r <= ST_SEND_AAD;
                        else if(data_bytes_w != 9'd0)
                            state_r <= ST_SEND_DATA;
                        else if(mode_r)
                            state_r <= ST_SEND_TAG;
                        else
                            state_r <= ST_WAIT_COMPLETE;
                    end
                    else
                        send_index_r <= send_index_r + 8'd1;
                end
            end

            ST_SEND_AAD:
            begin
                if(core_input_fire_w)
                begin
                    if(({1'b0, send_index_r} + 9'd1) == aad_bytes_w)
                    begin
                        send_index_r <= 8'd0;
                        if(data_bytes_w != 9'd0)
                            state_r <= ST_SEND_DATA;
                        else if(mode_r)
                            state_r <= ST_SEND_TAG;
                        else
                            state_r <= ST_WAIT_COMPLETE;
                    end
                    else
                        send_index_r <= send_index_r + 8'd1;
                end
            end

            ST_SEND_DATA:
            begin
                if(core_input_fire_w)
                begin
                    if(({1'b0, send_index_r} + 9'd1) == data_bytes_w)
                    begin
                        send_index_r <= 8'd0;
                        state_r <= mode_r ? ST_SEND_TAG : ST_WAIT_COMPLETE;
                    end
                    else
                        send_index_r <= send_index_r + 8'd1;
                end
            end

            ST_SEND_TAG:
            begin
                if(core_input_fire_w)
                begin
                    if(({1'b0, send_index_r} + 9'd1) == tag_bytes_w)
                    begin
                        send_index_r <= 8'd0;
                        state_r      <= ST_WAIT_COMPLETE;
                    end
                    else
                        send_index_r <= send_index_r + 8'd1;
                end
            end

            ST_DEC_STATUS:
            begin
                tag_valid <= 1'b1;
                state_r   <= ST_CLEAR;
            end

            ST_CLEAR:
            begin
                mode_r              <= 1'b0;
                key_shift_r         <= 256'd0;
                key_byte_index_r    <= 6'd0;
                key_collected_r     <= 1'b0;
                iv_byte_index_r     <= 8'd0;
                aad_byte_index_r    <= 8'd0;
                pt_byte_index_r     <= 8'd0;
                ct_byte_index_r     <= 8'd0;
                tag_byte_index_r    <= 5'd0;
                iv_bits_r           <= 11'd0;
                aad_bits_r          <= 11'd0;
                pt_bits_r           <= 11'd0;
                ct_bits_r           <= 11'd0;
                tag_bits_r          <= 11'd0;
                iv_collected_r      <= 1'b0;
                aad_collected_r     <= 1'b0;
                pt_collected_r      <= 1'b0;
                ct_collected_r      <= 1'b0;
                tag_collected_r     <= 1'b0;
                send_index_r        <= 8'd0;
                pc_ct_len_bit       <= 11'd0;
                state_r             <= ST_COLLECT;
            end

            default:
            begin
            end
        endcase

        // Decryption result is deliberately consumed before plaintext.  The
        // core releases plaintext only for RESULT_DEC_AUTH_OK.  The legacy
        // one-cycle tag_valid authentication status remains after the final
        // plaintext byte, matching the original lane behavior.
        if(core_result_tvalid)
        begin
            if(mode_r)
            begin
                if(core_result_tdata == RESULT_DEC_AUTH_OK)
                begin
                    if(selected_data_bits_w == 11'd0)
                        state_r <= ST_DEC_STATUS;
                end
                else
                    state_r <= ST_CLEAR;
            end
            else
            begin
                // Normal and abort/error result codes all terminate an
                // encryption record because the old interface has no
                // separate result channel.
                state_r <= ST_CLEAR;
            end
        end

        if(mode_r && core_data_tvalid && core_data_tlast)
            state_r <= ST_DEC_STATUS;
    end
end

endmodule
