`timescale 1ns / 1ps

module aes_gcm_lane
(
input         clk,
input         rst,
input  [2:0]  key_mode,
input         mode,
input  [7:0]  in,
input         in_valid,
input  [2:0]  in_type,
input  [10:0] in_valid_bit,
input         last,
output reg    pc_ct_valid,
output reg    tag_valid,
output reg [10:0] pc_ct_len_bit,
output reg [3:0] pc_ct_valid_bit,
output reg [7:0] out
);

localparam TYPE_IV  = 3'd0;
localparam TYPE_KEY = 3'd1;
localparam TYPE_AAD = 3'd2;
localparam TYPE_PT  = 3'd3;
localparam TYPE_CT  = 3'd4;
localparam TYPE_TAG = 3'd5;

localparam KEY_SIZE_128 = 2'd0;
localparam KEY_SIZE_192 = 2'd1;
localparam KEY_SIZE_256 = 2'd2;

localparam ST_COLLECT        = 5'd0;
localparam ST_H_START        = 5'd1;
localparam ST_H_WAIT         = 5'd2;
localparam ST_H_LOAD         = 5'd3;
localparam ST_J0_INIT        = 5'd4;
localparam ST_J0_PUSH        = 5'd5;
localparam ST_J0_WAIT        = 5'd6;
localparam ST_J0_LEN_PUSH    = 5'd7;
localparam ST_J0_LEN_WAIT    = 5'd8;
localparam ST_DATA_PREP      = 5'd9;
localparam ST_DATA_START     = 5'd10;
localparam ST_DATA_WAIT      = 5'd11;
localparam ST_GHASH_INIT     = 5'd12;
localparam ST_GHASH_AAD_PUSH = 5'd13;
localparam ST_GHASH_AAD_WAIT = 5'd14;
localparam ST_GHASH_CT_PUSH  = 5'd15;
localparam ST_GHASH_CT_WAIT  = 5'd16;
localparam ST_GHASH_LEN_PUSH = 5'd17;
localparam ST_GHASH_LEN_WAIT = 5'd18;
localparam ST_TAG_START      = 5'd19;
localparam ST_TAG_WAIT       = 5'd20;
localparam ST_OUT_PC         = 5'd21;
localparam ST_OUT_TAG        = 5'd22;
localparam ST_OUT_DEC_STATUS = 5'd23;
localparam ST_CLEAR          = 5'd24;
localparam ST_J0_PREP        = 5'd25;
localparam ST_GHASH_AAD_PREP = 5'd26;
localparam ST_GHASH_CT_PREP  = 5'd27;
localparam ST_TAG_COMPARE    = 5'd28;
localparam ST_TAG_DECIDE     = 5'd29;
localparam ST_BLOCK_ALIGN    = 5'd30;
localparam ST_DATA_ALIGN     = 5'd31;

wire rst_n;
assign rst_n = ~rst;

wire [1023:0] iv_data;
wire [10:0]   iv_len_bits;
wire          iv_ready;

wire [1023:0] aad_data;
wire [10:0]   aad_len_bits;
wire          aad_ready;
wire [1023:0] pt_data;
wire [10:0]   pt_len_bits;
wire          pt_ready;
wire [1023:0] ct_data;
wire [10:0]   ct_len_bits;
wire          ct_ready;
wire [127:0]  tag_data;
wire [10:0]   tag_len_bits;
wire          tag_ready;

reg          clear_collectors;

reg  [255:0] key_reg;
reg  [5:0]   key_byte_count;
reg          key_ready;
reg  [1:0]   key_size_reg;
wire [255:0] key_normalized;

assign key_normalized = (key_size_reg == KEY_SIZE_128) ? {key_reg[127:0], 128'd0} :
                        (key_size_reg == KEY_SIZE_192) ? {key_reg[191:0], 64'd0} :
                                                                  key_reg;

reg          mode_reg;
reg  [4:0]   state;
reg  [127:0] h_reg;
reg  [127:0] j0_reg;
reg  [127:0] ctr_nonce_reg;
reg  [1023:0] pc_out_buf;
reg  [10:0]  pc_out_len_bits;
reg  [7:0]   pc_out_byte_count;
reg  [3:0]   pc_out_last_valid_bits;
reg  [127:0]  tag_out_buf;
reg  [7:0]   tag_out_byte_count;
reg  [7:0]   out_bytes_remaining;
reg  [127:0]  tag_compare_value;
reg  [4:0]    tag_compare_align_bytes;
reg          auth_ok;

reg  [3:0]   data_block_idx;
reg  [3:0]   aad_block_idx;
reg  [3:0]   ct_block_idx;
reg  [3:0]   iv_block_count_reg;
reg  [3:0]   aad_block_count_reg;
reg  [3:0]   data_block_count_reg;

reg          hcalc_start;
reg  [255:0] hcalc_key;
reg  [127:0] hcalc_word;
wire         hcalc_busy;
wire         hcalc_done;
wire [127:0] hcalc_wordout;

reg          data_start;
reg  [127:0] data_nonce;
reg  [127:0] data_plaintext;
reg  [4:0]   data_align_bytes;
reg  [7:0]   data_valid_bits;
reg  [255:0] data_key;
wire [127:0] data_ciphertext;
wire         data_done;

reg          tag_start;
reg  [127:0] tag_nonce;
reg  [127:0] tag_plaintext;
reg  [7:0]   tag_valid_bits_cfg;
reg  [255:0] tag_key;
wire [127:0] tag_ciphertext;
wire         tag_done;

reg          ghash_init;
reg  [127:0] ghash_block;
reg          ghash_en;
reg  [127:0] ghash_h;
reg          ghash_h_done;
reg  [4:0]    ghash_align_bytes;
reg  [4:0]    ghash_align_return;
wire         ghash_busy;
wire         ghash_done;
wire [127:0] ghash_y;

wire collect_en;
assign collect_en = (state == ST_COLLECT) ? in_valid : 1'b0;

IV_IN u_iv_in (
    .clk        (clk),
    .rst_n      (rst_n),
    .clear      (clear_collectors),
    .in         (in),
    .in_valid   (collect_en),
    .in_type    (in_type),
    .in_valid_bit(in_valid_bit),
    .last       (last),
    .iv_data    (iv_data),
    .iv_len_bits(iv_len_bits),
    .iv_ready   (iv_ready)
);

AAD_CT_IN u_aad_ct_in (
    .clk        (clk),
    .rst_n      (rst_n),
    .clear      (clear_collectors),
    .in         (in),
    .in_valid   (collect_en),
    .in_type    (in_type),
    .in_valid_bit(in_valid_bit),
    .last       (last),
    .aad_data   (aad_data),
    .aad_len_bits(aad_len_bits),
    .aad_ready  (aad_ready),
    .pt_data    (pt_data),
    .pt_len_bits(pt_len_bits),
    .pt_ready   (pt_ready),
    .ct_data    (ct_data),
    .ct_len_bits(ct_len_bits),
    .ct_ready   (ct_ready),
    .tag_data   (tag_data),
    .tag_len_bits(tag_len_bits),
    .tag_ready  (tag_ready)
);

AES_e u_hcalc (
    .clk    (clk),
    .rst_n  (rst_n),
    .start  (hcalc_start),
    .key_size(key_size_reg),
    .Key    (hcalc_key),
    .word   (hcalc_word),
    .busy   (hcalc_busy),
    .finish (hcalc_done),
    .wordout(hcalc_wordout)
);

aes_ctr_wrapper u_data_ctr (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (data_start),
    .nonce     (data_nonce),
    .plaintext (data_plaintext),
    .valid_bits(data_valid_bits),
    .key_size  (key_size_reg),
    .key       (data_key),
    .ciphertext(data_ciphertext),
    .done      (data_done)
);

aes_ctr_wrapper u_tag_ctr (
    .clk       (clk),
    .rst_n     (rst_n),
    .start     (tag_start),
    .nonce     (tag_nonce),
    .plaintext (tag_plaintext),
    .valid_bits(tag_valid_bits_cfg),
    .key_size  (key_size_reg),
    .key       (tag_key),
    .ciphertext(tag_ciphertext),
    .done      (tag_done)
);

GHASH u_ghash (
    .clk        (clk),
    .rst_n      (rst_n),
    .init       (ghash_init),
    .GHASH_block(ghash_block),
    .GHASH_en   (ghash_en),
    .H          (ghash_h),
    .H_done     (ghash_h_done),
    .busy       (ghash_busy),
    .done       (ghash_done),
    .Y          (ghash_y)
);

function [7:0] mask_last_byte;
input [7:0] byte_in;
input [10:0] total_bits;
begin
    case (total_bits[2:0])
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

function [127:0] inc32;
input [127:0] counter_in;
begin
    inc32 = {counter_in[127:32], counter_in[31:0] + 32'd1};
end
endfunction

function integer block_count;
input [10:0] total_bits;
begin
    block_count = total_bits[10:7] + ((total_bits[6:0] != 7'd0) ? 1 : 0);
end
endfunction

function [7:0] block_valid_count;
input [10:0] total_bits;
input integer blk_idx;
begin
    if (blk_idx < total_bits[10:7])
        block_valid_count = 8'd128;
    else if ((blk_idx == total_bits[10:7]) && (total_bits[6:0] != 7'd0))
        block_valid_count = {1'b0, total_bits[6:0]};
    else
        block_valid_count = 8'd0;
end
endfunction

// pc_out_buf is stored MSB-aligned block by block.  Unlike the input
// collectors, its final partial block therefore needs no re-alignment.
function [127:0] select_aligned_block_1024;
input [1023:0] data_bits;
input integer blk_idx;
begin
    case (blk_idx)
        0: select_aligned_block_1024 = data_bits[1023:896];
        1: select_aligned_block_1024 = data_bits[895:768];
        2: select_aligned_block_1024 = data_bits[767:640];
        3: select_aligned_block_1024 = data_bits[639:512];
        4: select_aligned_block_1024 = data_bits[511:384];
        5: select_aligned_block_1024 = data_bits[383:256];
        6: select_aligned_block_1024 = data_bits[255:128];
        7: select_aligned_block_1024 = data_bits[127:0];
        default: select_aligned_block_1024 = 128'd0;
    endcase
end
endfunction

function [4:0] block_align_bytes;
input [10:0] total_bits;
input [3:0]  blk_idx;
begin
    if ((total_bits[6:0] != 7'd0) && (blk_idx == total_bits[10:7]))
    begin
        // Lookup form avoids putting an adder and subtractor in the load path
        // of both alignment counters.  The input is floor(bits/8), while the
        // low three bits select exact-byte versus partial-byte length.
        case (total_bits[6:3])
            4'd0:  block_align_bytes = 5'd15;
            4'd1:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd15 : 5'd14;
            4'd2:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd14 : 5'd13;
            4'd3:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd13 : 5'd12;
            4'd4:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd12 : 5'd11;
            4'd5:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd11 : 5'd10;
            4'd6:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd10 : 5'd9;
            4'd7:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd9  : 5'd8;
            4'd8:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd8  : 5'd7;
            4'd9:  block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd7  : 5'd6;
            4'd10: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd6  : 5'd5;
            4'd11: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd5  : 5'd4;
            4'd12: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd4  : 5'd3;
            4'd13: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd3  : 5'd2;
            4'd14: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd2  : 5'd1;
            default: block_align_bytes = (total_bits[2:0] == 3'd0) ? 5'd1 : 5'd0;
        endcase
    end
    else
    begin
        block_align_bytes = 5'd0;
    end
end
endfunction

function [7:0] byte_count_from_bits;
input [10:0] total_bits;
begin
    byte_count_from_bits = total_bits[10:3] +
                           ((total_bits[2:0] != 3'd0) ? 8'd1 : 8'd0);
end
endfunction

function [3:0] last_byte_valid_bits;
input [10:0] total_bits;
begin
    last_byte_valid_bits = (total_bits[2:0] == 3'd0)
                         ? 4'd8 : {1'b0, total_bits[2:0]};
end
endfunction

task store_block_to_buffer;
input      [127:0] block_in;
input      [10:0] total_bits;
input      integer blk_idx;
inout reg [1023:0] data_bits;
begin
    case (blk_idx)
        0: data_bits[1023:896] = block_in;
        1: data_bits[895:768]  = block_in;
        2: data_bits[767:640]  = block_in;
        3: data_bits[639:512]  = block_in;
        4: data_bits[511:384]  = block_in;
        5: data_bits[383:256]  = block_in;
        6: data_bits[255:128]  = block_in;
        7: data_bits[127:0]    = block_in;
        default: data_bits = data_bits;
    endcase
end
endtask

always @(posedge clk)
begin
    if(!rst_n)
    begin
    key_reg           <= 256'd0;
    key_byte_count    <= 6'd0;
    key_ready         <= 1'b0;
    key_size_reg      <= KEY_SIZE_256;
    mode_reg          <= 1'b0;
    state             <= ST_COLLECT;
    h_reg             <= 128'd0;
    j0_reg            <= 128'd0;
    ctr_nonce_reg     <= 128'd0;
    pc_out_buf        <= 1024'd0;
    pc_out_len_bits   <= 11'd0;
    pc_out_byte_count <= 8'd0;
    pc_out_last_valid_bits <= 4'd0;
    tag_out_buf       <= 128'd0;
    tag_out_byte_count<= 8'd0;
    out_bytes_remaining <= 8'd0;
    tag_compare_value <= 128'd0;
    tag_compare_align_bytes <= 5'd0;
    auth_ok           <= 1'b0;
    data_block_idx    <= 4'd0;
    aad_block_idx     <= 4'd0;
    ct_block_idx      <= 4'd0;
    iv_block_count_reg<= 4'd0;
    aad_block_count_reg<= 4'd0;
    data_block_count_reg<= 4'd0;
    hcalc_start       <= 1'b0;
    hcalc_key         <= 256'd0;
    hcalc_word        <= 128'd0;
    data_start        <= 1'b0;
    data_nonce        <= 128'd0;
    data_plaintext    <= 128'd0;
    data_align_bytes  <= 5'd0;
    data_valid_bits   <= 8'd128;
    data_key          <= 256'd0;
    tag_start         <= 1'b0;
    tag_nonce         <= 128'd0;
    tag_plaintext     <= 128'd0;
    tag_valid_bits_cfg<= 8'd128;
    tag_key           <= 256'd0;
    ghash_init        <= 1'b0;
    ghash_block       <= 128'd0;
    ghash_en          <= 1'b0;
    ghash_h           <= 128'd0;
    ghash_h_done      <= 1'b0;
    ghash_align_bytes <= 5'd0;
    ghash_align_return<= ST_COLLECT;
    clear_collectors  <= 1'b0;
    pc_ct_valid       <= 1'b0;
    tag_valid         <= 1'b0;
    pc_ct_len_bit     <= 11'd0;
    pc_ct_valid_bit   <= 4'd0;
    out               <= 8'd0;
    end
    else
    begin
        hcalc_start      <= 1'b0;
        data_start       <= 1'b0;
        tag_start        <= 1'b0;
        ghash_init       <= 1'b0;
        ghash_en         <= 1'b0;
        ghash_h_done     <= 1'b0;
        clear_collectors <= 1'b0;
        pc_ct_valid      <= 1'b0;
        tag_valid        <= 1'b0;
        pc_ct_len_bit    <= pc_ct_len_bit;
        pc_ct_valid_bit  <= 4'd0;

        if((state == ST_COLLECT) && in_valid && (in_type == TYPE_KEY))
        begin
            if(last && (in_valid_bit == 11'd0) && (key_byte_count == 6'd0))
            begin
            key_reg        <= 256'd0;
            key_byte_count <= 6'd0;
            key_ready      <= 1'b0;
            end
            else
            begin
            key_reg <= {key_reg[247:0], last ? mask_last_byte(in, in_valid_bit) : in};

                if(last)
                begin
                key_byte_count <= 6'd0;
                    case(key_mode)
                        3'd0:
                        begin
                            key_size_reg <= KEY_SIZE_128;
                            key_ready    <= (in_valid_bit == 11'd128);
                        end
                        3'd1:
                        begin
                            key_size_reg <= KEY_SIZE_192;
                            key_ready    <= (in_valid_bit == 11'd192);
                        end
                        3'd2:
                        begin
                            key_size_reg <= KEY_SIZE_256;
                            key_ready    <= (in_valid_bit == 11'd256);
                        end
                        default:
                        begin
                            key_ready <= 1'b0;
                        end
                    endcase
                end
                else
                begin
                key_byte_count <= key_byte_count + 6'd1;
                end
            end
        end

        case (state)
            ST_COLLECT:
            begin
                if(mode)
                begin
                    if(key_ready && iv_ready && aad_ready && ct_ready && tag_ready)
                    begin
                    mode_reg            <= 1'b1;
                    iv_block_count_reg  <= block_count(iv_len_bits);
                    aad_block_count_reg <= block_count(aad_len_bits);
                    data_block_count_reg<= block_count(ct_len_bits);
                    state               <= ST_H_START;
                    end
                end
                else
                begin
                    if(key_ready && iv_ready && aad_ready && pt_ready && tag_ready)
                    begin
                    mode_reg            <= 1'b0;
                    iv_block_count_reg  <= block_count(iv_len_bits);
                    aad_block_count_reg <= block_count(aad_len_bits);
                    data_block_count_reg<= block_count(pt_len_bits);
                    state               <= ST_H_START;
                    end
                end
            end

            ST_H_START:
            begin
                hcalc_key   <= key_normalized;
                hcalc_word  <= 128'd0;
                hcalc_start <= 1'b1;
                state       <= ST_H_WAIT;
            end

            ST_H_WAIT:
            begin
                if(hcalc_done)
                begin
                h_reg <= hcalc_wordout;
                ghash_h <= hcalc_wordout;
                state <= ST_H_LOAD;
                end
            end

            ST_H_LOAD:
            begin
                ghash_h_done <= 1'b1;
                if(iv_len_bits == 11'd96)
                begin
                j0_reg <= {iv_data[991:896], 32'h00000001};
                state  <= ST_DATA_PREP;
                end
                else
                begin
                state <= ST_J0_INIT;
                end
            end

            ST_J0_INIT:
            begin
                ghash_init     <= 1'b1;
                data_block_idx <= 4'd0;
                state          <= ST_J0_PREP;
            end

            ST_J0_PREP:
            begin
                if(data_block_idx < iv_block_count_reg)
                begin
                ghash_block        <= select_aligned_block_1024(iv_data, data_block_idx);
                ghash_align_bytes  <= block_align_bytes(iv_len_bits, data_block_idx);
                ghash_align_return <= ST_J0_PUSH;
                state              <= ST_BLOCK_ALIGN;
                end
                else
                begin
                state <= ST_J0_LEN_PUSH;
                end
            end

            ST_J0_PUSH:
            begin
                ghash_en    <= 1'b1;
                state       <= ST_J0_WAIT;
            end

            ST_J0_WAIT:
            begin
                if(ghash_done)
                begin
                data_block_idx <= data_block_idx + 4'd1;
                state          <= ST_J0_PREP;
                end
            end

            ST_J0_LEN_PUSH:
            begin
                ghash_block <= {{53'd0, 11'd0}, {53'd0, iv_len_bits}};
                ghash_en    <= 1'b1;
                state       <= ST_J0_LEN_WAIT;
            end

            ST_J0_LEN_WAIT:
            begin
                if(ghash_done)
                begin
                j0_reg <= ghash_y;
                state  <= ST_DATA_PREP;
                end
            end

            ST_DATA_PREP:
            begin
                pc_out_buf      <= 1024'd0;
                pc_out_len_bits <= mode_reg ? ct_len_bits : pt_len_bits;
                pc_out_byte_count <= byte_count_from_bits(mode_reg ? ct_len_bits : pt_len_bits);
                pc_out_last_valid_bits <= last_byte_valid_bits(mode_reg ? ct_len_bits : pt_len_bits);
                pc_ct_len_bit   <= mode_reg ? ct_len_bits : pt_len_bits;
                tag_out_buf     <= 128'd0;
                tag_out_byte_count <= byte_count_from_bits(tag_len_bits);
                ctr_nonce_reg   <= inc32(j0_reg);
                data_block_idx  <= 4'd0;

                if(data_block_count_reg == 4'd0)
                    state <= ST_GHASH_INIT;
                else
                    state <= ST_DATA_START;
            end

            ST_DATA_START:
            begin
                data_nonce      <= ctr_nonce_reg;
                data_plaintext  <= select_aligned_block_1024(mode_reg ? ct_data : pt_data,
                                                             data_block_idx);
                data_align_bytes<= block_align_bytes(mode_reg ? ct_len_bits : pt_len_bits,
                                                      data_block_idx);
                data_valid_bits <= block_valid_count(mode_reg ? ct_len_bits : pt_len_bits, data_block_idx);
                data_key        <= key_normalized;
                state           <= ST_DATA_ALIGN;
            end

            ST_DATA_ALIGN:
            begin
                if(data_align_bytes == 5'd0)
                begin
                data_start <= 1'b1;
                state      <= ST_DATA_WAIT;
                end
                else
                begin
                data_plaintext   <= {data_plaintext[119:0], 8'd0};
                data_align_bytes <= data_align_bytes - 5'd1;
                end
            end

            ST_DATA_WAIT:
            begin
                if(data_done)
                begin
                store_block_to_buffer(data_ciphertext, pc_out_len_bits, data_block_idx, pc_out_buf);
                ctr_nonce_reg <= inc32(ctr_nonce_reg);

                    if((data_block_idx + 4'd1) < data_block_count_reg)
                    begin
                    data_block_idx <= data_block_idx + 4'd1;
                    state          <= ST_DATA_START;
                    end
                    else
                    begin
                    state <= ST_GHASH_INIT;
                    end
                end
            end

            ST_GHASH_INIT:
            begin
                ghash_init    <= 1'b1;
                aad_block_idx <= 4'd0;
                ct_block_idx  <= 4'd0;
                state         <= ST_GHASH_AAD_PREP;
            end

            ST_GHASH_AAD_PREP:
            begin
                if(aad_block_idx < aad_block_count_reg)
                begin
                ghash_block        <= select_aligned_block_1024(aad_data, aad_block_idx);
                ghash_align_bytes  <= block_align_bytes(aad_len_bits, aad_block_idx);
                ghash_align_return <= ST_GHASH_AAD_PUSH;
                state              <= ST_BLOCK_ALIGN;
                end
                else
                begin
                state <= ST_GHASH_CT_PREP;
                end
            end

            ST_GHASH_AAD_PUSH:
            begin
                ghash_en    <= 1'b1;
                state       <= ST_GHASH_AAD_WAIT;
            end

            ST_GHASH_AAD_WAIT:
            begin
                if(ghash_done)
                begin
                aad_block_idx <= aad_block_idx + 4'd1;
                state         <= ST_GHASH_AAD_PREP;
                end
            end

            ST_GHASH_CT_PREP:
            begin
                if(ct_block_idx < data_block_count_reg)
                begin
                ghash_block        <= select_aligned_block_1024(mode_reg ? ct_data : pc_out_buf,
                                                                ct_block_idx);
                ghash_align_bytes  <= mode_reg ? block_align_bytes(ct_len_bits, ct_block_idx)
                                                : 5'd0;
                ghash_align_return <= ST_GHASH_CT_PUSH;
                state              <= ST_BLOCK_ALIGN;
                end
                else
                begin
                state <= ST_GHASH_LEN_PUSH;
                end
            end

            ST_GHASH_CT_PUSH:
            begin
                ghash_en    <= 1'b1;
                state       <= ST_GHASH_CT_WAIT;
            end

            ST_GHASH_CT_WAIT:
            begin
                if(ghash_done)
                begin
                ct_block_idx <= ct_block_idx + 4'd1;
                state        <= ST_GHASH_CT_PREP;
                end
            end

            ST_GHASH_LEN_PUSH:
            begin
                ghash_block <= {{53'd0, aad_len_bits}, {53'd0, (mode_reg ? ct_len_bits : pt_len_bits)}};
                ghash_en    <= 1'b1;
                state       <= ST_GHASH_LEN_WAIT;
            end

            ST_GHASH_LEN_WAIT:
            begin
                if(ghash_done)
                begin
                state <= ST_TAG_START;
                end
            end

            ST_TAG_START:
            begin
                tag_nonce          <= j0_reg;
                tag_plaintext      <= ghash_y;
                tag_valid_bits_cfg <= 8'd128;
                tag_key            <= key_normalized;
                tag_start          <= 1'b1;
                state              <= ST_TAG_WAIT;
            end

            ST_TAG_WAIT:
            begin
                if(tag_done)
                begin
                tag_out_buf       <= tag_ciphertext;
                tag_compare_value <= (tag_len_bits == 11'd0) ? 128'd0 : tag_ciphertext;
                tag_compare_align_bytes <= (tag_len_bits == 11'd0)
                                         ? 5'd0 : block_align_bytes(tag_len_bits, 4'd0);
                state             <= ST_TAG_COMPARE;
                end
            end

            ST_TAG_COMPARE:
            begin
                if(tag_compare_align_bytes == 5'd0)
                begin
                auth_ok <= (tag_compare_value == tag_data);
                state   <= ST_TAG_DECIDE;
                end
                else
                begin
                tag_compare_value       <= {8'd0, tag_compare_value[127:8]};
                tag_compare_align_bytes <= tag_compare_align_bytes - 5'd1;
                end
            end

            ST_TAG_DECIDE:
            begin
                if(mode_reg)
                begin
                    if(auth_ok)
                    begin
                        if(pc_out_byte_count != 8'd0)
                        begin
                        out_bytes_remaining <= pc_out_byte_count;
                        state               <= ST_OUT_PC;
                        end
                        else
                        begin
                        state <= ST_OUT_DEC_STATUS;
                        end
                    end
                    else
                    begin
                    state <= ST_CLEAR;
                    end
                end
                else if(pc_out_byte_count != 8'd0)
                begin
                out_bytes_remaining <= pc_out_byte_count;
                state               <= ST_OUT_PC;
                end
                else if(tag_out_byte_count != 8'd0)
                begin
                out_bytes_remaining <= tag_out_byte_count;
                state               <= ST_OUT_TAG;
                end
                else
                begin
                state <= ST_CLEAR;
                end
            end

            ST_BLOCK_ALIGN:
            begin
                if(ghash_align_bytes == 5'd0)
                begin
                state <= ghash_align_return;
                end
                else
                begin
                ghash_block       <= {ghash_block[119:0], 8'd0};
                ghash_align_bytes <= ghash_align_bytes - 5'd1;

                    if(ghash_align_bytes == 5'd1)
                    begin
                    state <= ghash_align_return;
                    end
                end
            end

            ST_OUT_PC:
            begin
                out             <= pc_out_buf[1023:1016];
                pc_out_buf      <= {pc_out_buf[1015:0], 8'd0};
                pc_ct_valid     <= 1'b1;
                pc_ct_valid_bit <= (out_bytes_remaining == 8'd1)
                                 ? pc_out_last_valid_bits : 4'd8;

                if(out_bytes_remaining == 8'd1)
                begin
                out_bytes_remaining <= 8'd0;
                    if(mode_reg)
                    begin
                    state <= ST_OUT_DEC_STATUS;
                    end
                    else if(tag_out_byte_count != 8'd0)
                    begin
                    out_bytes_remaining <= tag_out_byte_count;
                    state               <= ST_OUT_TAG;
                    end
                    else
                    begin
                    state <= ST_CLEAR;
                    end
                end
                else
                begin
                out_bytes_remaining <= out_bytes_remaining - 8'd1;
                end
            end

            ST_OUT_TAG:
            begin
                out         <= tag_out_buf[127:120];
                tag_out_buf <= {tag_out_buf[119:0], 8'd0};
                tag_valid <= 1'b1;

                if(out_bytes_remaining == 8'd1)
                begin
                out_bytes_remaining <= 8'd0;
                state               <= ST_CLEAR;
                end
                else
                begin
                out_bytes_remaining <= out_bytes_remaining - 8'd1;
                end
            end

            ST_OUT_DEC_STATUS:
            begin
                tag_valid <= auth_ok;
                state     <= ST_CLEAR;
            end

            ST_CLEAR:
            begin
                clear_collectors <= 1'b1;
                key_reg          <= 256'd0;
                key_byte_count   <= 6'd0;
                key_ready        <= 1'b0;
                key_size_reg     <= KEY_SIZE_256;
                pc_out_buf       <= 1024'd0;
                pc_out_len_bits  <= 11'd0;
                pc_out_byte_count<= 8'd0;
                pc_out_last_valid_bits <= 4'd0;
                pc_ct_len_bit    <= 11'd0;
                tag_out_buf      <= 128'd0;
                tag_out_byte_count <= 8'd0;
                out_bytes_remaining<= 8'd0;
                tag_compare_value<= 128'd0;
                auth_ok          <= 1'b0;
                state            <= ST_COLLECT;
            end

            default:
            begin
                state <= ST_COLLECT;
            end
        endcase
    end
end

endmodule
