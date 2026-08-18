`timescale 1ns / 1ps

module aes_ctr_wrapper
(
input clk,
input rst_n,
input start,
input [127:0] nonce,
input [127:0] plaintext,
input [7:0] valid_bits,
input [1:0] key_size,
input [255:0] key,
output [127:0] ciphertext,
output done
);

wire [127:0] keystream;
wire busy;
wire fin;
reg [127:0] plaintext_r;
reg [7:0] valid_bits_r;
reg [127:0] ciphertext_r;
reg fin_d1;

function [127:0] keep_msb_bits;
input [127:0] data_in;
input [7:0] bit_count;
integer bit_idx;
begin
    keep_msb_bits = 128'd0;

    for (bit_idx = 0; bit_idx < 128; bit_idx = bit_idx + 1)
    begin
        if (bit_idx < bit_count)
        begin
        keep_msb_bits[127 - bit_idx] = data_in[127 - bit_idx];
        end
        else
        begin
        keep_msb_bits[127 - bit_idx] = 1'b0;
        end
    end
end
endfunction

always @(posedge clk)
begin
    if(!rst_n)
    begin
    plaintext_r <= 128'd0;
    valid_bits_r <= 8'd128;
    end
    else
    begin
        if(start)
        begin
        plaintext_r <= plaintext;
        if((valid_bits == 8'd0) || (valid_bits > 8'd128))
        begin
        valid_bits_r <= 8'd128;
        end
        else
        begin
        valid_bits_r <= valid_bits;
        end
        end
    end
end

AES_e g0
(
.clk(clk),
.rst_n(rst_n),
.start(start),
.key_size(key_size),
.busy(busy),
.word(nonce),
.Key(key),
.finish(fin),
.wordout(keystream)
);

always @(posedge clk)
begin
    if(!rst_n)
    begin
    ciphertext_r <= 128'd0;
    end
    else
    begin
        if(fin)
        begin
        ciphertext_r <= keep_msb_bits(plaintext_r ^ keystream, valid_bits_r);
        end
    end
end

always @(posedge clk)
begin
    if(!rst_n)
    begin
    fin_d1 <= 1'b0;
    end
    else
    begin
    fin_d1 <= fin;
    end
end

assign ciphertext = ciphertext_r;
assign done = fin_d1;

endmodule
