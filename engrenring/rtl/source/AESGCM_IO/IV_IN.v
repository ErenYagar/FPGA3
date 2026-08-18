`timescale 1ns / 1ps

module IV_IN
(
input         clk,
input         rst_n,
input         clear,
input  [7:0]  in,
input         in_valid,
input  [2:0]  in_type,
input  [10:0] in_valid_bit,
input         last,
output [1023:0] iv_data,
output [10:0] iv_len_bits,
output        iv_ready
);

localparam TYPE_IV = 3'd0;

reg [1023:0] iv_data_r;
reg [10:0]   iv_len_bits_r;
reg          iv_ready_r;
reg [6:0]    iv_byte_count_r;

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
    iv_data_r     <= 1024'd0;
    iv_len_bits_r <= 11'd0;
    iv_ready_r    <= 1'b0;
    iv_byte_count_r <= 7'd0;
    end
    else
    begin
        if(clear)
        begin
        iv_data_r     <= 1024'd0;
        iv_len_bits_r <= 11'd0;
        iv_ready_r    <= 1'b0;
        iv_byte_count_r <= 7'd0;
        end
        else
        begin
            if(in_valid && (in_type == TYPE_IV))
            begin
                if(last && (in_valid_bit == 11'd0))
                begin
                iv_len_bits_r <= 11'd0;
                iv_ready_r    <= 1'b1;
                end
                else
                begin
                    if(last)
                    begin
                    iv_data_r     <= append_byte_to_block(iv_data_r, iv_byte_count_r,
                                                         mask_last_byte(in, in_valid_bit));
                    iv_len_bits_r <= in_valid_bit;
                    iv_ready_r    <= 1'b1;
                    end
                    else
                    begin
                    iv_data_r <= append_byte_to_block(iv_data_r, iv_byte_count_r, in);
                    end
                    iv_byte_count_r <= iv_byte_count_r + 7'd1;
                end
            end
        end
    end
end

assign iv_data     = iv_data_r;
assign iv_len_bits = iv_len_bits_r;
assign iv_ready    = iv_ready_r;

endmodule
