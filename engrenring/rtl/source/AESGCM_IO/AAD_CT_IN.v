`timescale 1ns / 1ps

module AAD_CT_IN
(
input           clk,
input           rst_n,
input           clear,
input  [7:0]    in,
input           in_valid,
input  [2:0]    in_type,
input  [10:0]   in_valid_bit,
input           last,
output [1023:0] aad_data,
output [10:0]   aad_len_bits,
output          aad_ready,
output [1023:0] pt_data,
output [10:0]   pt_len_bits,
output          pt_ready,
output [1023:0] ct_data,
output [10:0]   ct_len_bits,
output          ct_ready,
output [127:0]  tag_data,
output [10:0]   tag_len_bits,
output          tag_ready
);

localparam TYPE_AAD = 3'd2;
localparam TYPE_PT  = 3'd3;
localparam TYPE_CT  = 3'd4;
localparam TYPE_TAG = 3'd5;

reg [1023:0] aad_data_r;
reg [10:0]   aad_len_bits_r;
reg          aad_ready_r;
reg [6:0]    aad_byte_count_r;

reg [1023:0] pt_data_r;
reg [10:0]   pt_len_bits_r;
reg          pt_ready_r;
reg [6:0]    pt_byte_count_r;

reg [1023:0] ct_data_r;
reg [10:0]   ct_len_bits_r;
reg          ct_ready_r;
reg [6:0]    ct_byte_count_r;

reg [127:0]  tag_data_r;
reg [10:0]   tag_len_bits_r;
reg          tag_ready_r;

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

function [1023:0] append_byte_to_block;
input [1023:0] data_in;
input [6:0]    byte_count;
input [7:0]    byte_in;
begin
    append_byte_to_block = data_in;
    case (byte_count[6:4])
        3'd0: append_byte_to_block[1023:896] = {data_in[1015:896], byte_in};
        3'd1: append_byte_to_block[895:768]  = {data_in[887:768],  byte_in};
        3'd2: append_byte_to_block[767:640]  = {data_in[759:640],  byte_in};
        3'd3: append_byte_to_block[639:512]  = {data_in[631:512],  byte_in};
        3'd4: append_byte_to_block[511:384]  = {data_in[503:384],  byte_in};
        3'd5: append_byte_to_block[383:256]  = {data_in[375:256],  byte_in};
        3'd6: append_byte_to_block[255:128]  = {data_in[247:128],  byte_in};
        default: append_byte_to_block[127:0] = {data_in[119:0],    byte_in};
    endcase
end
endfunction

always @(posedge clk)
begin
    if(!rst_n)
    begin
    aad_data_r     <= 1024'd0;
    aad_len_bits_r <= 11'd0;
    aad_ready_r    <= 1'b0;
    aad_byte_count_r <= 7'd0;
    pt_data_r      <= 1024'd0;
    pt_len_bits_r  <= 11'd0;
    pt_ready_r     <= 1'b0;
    pt_byte_count_r <= 7'd0;
    ct_data_r      <= 1024'd0;
    ct_len_bits_r  <= 11'd0;
    ct_ready_r     <= 1'b0;
    ct_byte_count_r <= 7'd0;
    tag_data_r     <= 128'd0;
    tag_len_bits_r <= 11'd0;
    tag_ready_r    <= 1'b0;
    end
    else
    begin
        if(clear)
        begin
        aad_data_r     <= 1024'd0;
        aad_len_bits_r <= 11'd0;
        aad_ready_r    <= 1'b0;
        aad_byte_count_r <= 7'd0;
        pt_data_r      <= 1024'd0;
        pt_len_bits_r  <= 11'd0;
        pt_ready_r     <= 1'b0;
        pt_byte_count_r <= 7'd0;
        ct_data_r      <= 1024'd0;
        ct_len_bits_r  <= 11'd0;
        ct_ready_r     <= 1'b0;
        ct_byte_count_r <= 7'd0;
        tag_data_r     <= 128'd0;
        tag_len_bits_r <= 11'd0;
        tag_ready_r    <= 1'b0;
        end
        else
        begin
            if(in_valid)
            begin
                case (in_type)
                    TYPE_AAD:
                    begin
                        if(last && (in_valid_bit == 11'd0))
                        begin
                        aad_len_bits_r <= 11'd0;
                        aad_ready_r    <= 1'b1;
                        end
                        else
                        begin
                            if(last)
                            begin
                            aad_data_r     <= append_byte_to_block(aad_data_r, aad_byte_count_r,
                                                                  mask_last_byte(in, in_valid_bit));
                            aad_len_bits_r <= in_valid_bit;
                            aad_ready_r    <= 1'b1;
                            end
                            else
                            begin
                            aad_data_r <= append_byte_to_block(aad_data_r, aad_byte_count_r, in);
                            end
                            aad_byte_count_r <= aad_byte_count_r + 7'd1;
                        end
                    end

                    TYPE_PT:
                    begin
                        if(last && (in_valid_bit == 11'd0))
                        begin
                        pt_len_bits_r <= 11'd0;
                        pt_ready_r    <= 1'b1;
                        end
                        else
                        begin
                            if(last)
                            begin
                            pt_data_r     <= append_byte_to_block(pt_data_r, pt_byte_count_r,
                                                                 mask_last_byte(in, in_valid_bit));
                            pt_len_bits_r <= in_valid_bit;
                            pt_ready_r    <= 1'b1;
                            end
                            else
                            begin
                            pt_data_r <= append_byte_to_block(pt_data_r, pt_byte_count_r, in);
                            end
                            pt_byte_count_r <= pt_byte_count_r + 7'd1;
                        end
                    end

                    TYPE_CT:
                    begin
                        if(last && (in_valid_bit == 11'd0))
                        begin
                        ct_len_bits_r <= 11'd0;
                        ct_ready_r    <= 1'b1;
                        end
                        else
                        begin
                            if(last)
                            begin
                            ct_data_r     <= append_byte_to_block(ct_data_r, ct_byte_count_r,
                                                                 mask_last_byte(in, in_valid_bit));
                            ct_len_bits_r <= in_valid_bit;
                            ct_ready_r    <= 1'b1;
                            end
                            else
                            begin
                            ct_data_r <= append_byte_to_block(ct_data_r, ct_byte_count_r, in);
                            end
                            ct_byte_count_r <= ct_byte_count_r + 7'd1;
                        end
                    end

                    TYPE_TAG:
                    begin
                        if(last && (in_valid_bit == 11'd0))
                        begin
                        tag_len_bits_r <= 11'd0;
                        tag_ready_r    <= 1'b1;
                        end
                        else
                        begin
                            if(last)
                            begin
                            tag_data_r     <= {tag_data_r[119:0], mask_last_byte(in, in_valid_bit)};
                            tag_len_bits_r <= in_valid_bit;
                            tag_ready_r    <= 1'b1;
                            end
                            else
                            begin
                            tag_data_r <= {tag_data_r[119:0], in};
                            end
                        end
                    end

                    default:
                    begin
                    end
                endcase
            end
        end
    end
end

assign aad_data     = aad_data_r;
assign aad_len_bits = aad_len_bits_r;
assign aad_ready    = aad_ready_r;
assign pt_data      = pt_data_r;
assign pt_len_bits  = pt_len_bits_r;
assign pt_ready     = pt_ready_r;
assign ct_data      = ct_data_r;
assign ct_len_bits  = ct_len_bits_r;
assign ct_ready     = ct_ready_r;
assign tag_data     = tag_data_r;
assign tag_len_bits = tag_len_bits_r;
assign tag_ready    = tag_ready_r;

endmodule
