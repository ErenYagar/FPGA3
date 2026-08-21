`timescale 1ns / 1ps

// Low-latency service for the first counter block of a record.
//
// The shared AES engine is optimized for steady-state initiation interval and
// interleaves three contexts around a registered S-box pipeline.  That is the
// right tradeoff for blocks 1..N, but its first-result latency delays the start
// of an 8-bit ciphertext stream.  This single-context engine performs one AES
// round per clock and is used only for block 0; all later counter blocks remain
// on the shared engine.  ZEROIZE synchronously invalidates and clears its state.
module aes_first_block_engine
(
    input               clk,
    input               rst_n,
    input               start,
    input      [1:0]    key_size,
    input      [1919:0] round_keys,
    input      [127:0]  block_in,
    output              ready,
    output              busy,
    output              done,
    output     [127:0]  block_out
);

localparam KEY_SIZE_128 = 2'd0;
localparam KEY_SIZE_192 = 2'd1;
localparam KEY_SIZE_256 = 2'd2;

reg          busy_r;
reg          done_r;
reg [127:0]  state_r;
reg [127:0]  block_out_r;
reg [3:0]    round_r;
reg [3:0]    last_round_r;

wire [127:0] sbox_output_w;
wire [127:0] shifted_state_w;
wire [127:0] mixed_state_w;
wire [127:0] selected_round_key_w;
wire [127:0] round_result_w;
wire         final_round_w = (round_r == last_round_r);
wire         key_size_valid_w = (key_size == KEY_SIZE_128) ||
                                 (key_size == KEY_SIZE_192) ||
                                 (key_size == KEY_SIZE_256);

function [3:0] last_round_for_size;
input [1:0] size;
begin
    case(size)
        KEY_SIZE_128: last_round_for_size = 4'd10;
        KEY_SIZE_192: last_round_for_size = 4'd12;
        default:      last_round_for_size = 4'd14;
    endcase
end
endfunction

function [127:0] select_round_key;
input [1919:0] keys;
input [3:0]    round_index;
begin
    case(round_index)
        4'd0:  select_round_key = keys[127:0];
        4'd1:  select_round_key = keys[255:128];
        4'd2:  select_round_key = keys[383:256];
        4'd3:  select_round_key = keys[511:384];
        4'd4:  select_round_key = keys[639:512];
        4'd5:  select_round_key = keys[767:640];
        4'd6:  select_round_key = keys[895:768];
        4'd7:  select_round_key = keys[1023:896];
        4'd8:  select_round_key = keys[1151:1024];
        4'd9:  select_round_key = keys[1279:1152];
        4'd10: select_round_key = keys[1407:1280];
        4'd11: select_round_key = keys[1535:1408];
        4'd12: select_round_key = keys[1663:1536];
        4'd13: select_round_key = keys[1791:1664];
        default: select_round_key = keys[1919:1792];
    endcase
end
endfunction

function [7:0] xtime;
input [7:0] value;
begin
    xtime = {value[6:0], 1'b0} ^ (value[7] ? 8'h1b : 8'h00);
end
endfunction

function [31:0] mix_column;
input [31:0] column;
reg [7:0] b0;
reg [7:0] b1;
reg [7:0] b2;
reg [7:0] b3;
begin
    b0 = column[31:24];
    b1 = column[23:16];
    b2 = column[15:8];
    b3 = column[7:0];
    mix_column[31:24] = xtime(b0) ^ (xtime(b1) ^ b1) ^ b2 ^ b3;
    mix_column[23:16] = b0 ^ xtime(b1) ^ (xtime(b2) ^ b2) ^ b3;
    mix_column[15:8]  = b0 ^ b1 ^ xtime(b2) ^ (xtime(b3) ^ b3);
    mix_column[7:0]   = (xtime(b0) ^ b0) ^ b1 ^ b2 ^ xtime(b3);
end
endfunction

function [127:0] shift_rows;
input [127:0] state;
begin
    shift_rows = {
        state[127:120], state[87:80],    state[47:40],   state[7:0],
        state[95:88],   state[55:48],    state[15:8],    state[103:96],
        state[63:56],   state[23:16],    state[111:104], state[71:64],
        state[31:24],   state[119:112],  state[79:72],   state[39:32]
    };
end
endfunction

function [127:0] mix_columns;
input [127:0] state;
begin
    mix_columns = {
        mix_column(state[127:96]),
        mix_column(state[95:64]),
        mix_column(state[63:32]),
        mix_column(state[31:0])
    };
end
endfunction

genvar byte_index;
generate
    for(byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
    begin : GEN_FIRST_BLOCK_SBOX
        sbox #(.REGISTERED(0)) u_sbox
        (
            .clk(clk), .rst_n(rst_n),
            .a(state_r[127 - byte_index*8 -: 8]),
            .co(sbox_output_w[127 - byte_index*8 -: 8])
        );
    end
endgenerate

assign shifted_state_w = shift_rows(sbox_output_w);
assign mixed_state_w = mix_columns(shifted_state_w);
assign selected_round_key_w = select_round_key(round_keys, round_r);
assign round_result_w = (final_round_w ? shifted_state_w : mixed_state_w) ^
                        selected_round_key_w;

always @(posedge clk)
begin
    if(!rst_n)
    begin
        busy_r       <= 1'b0;
        done_r       <= 1'b0;
        state_r      <= 128'd0;
        block_out_r  <= 128'd0;
        round_r      <= 4'd0;
        last_round_r <= 4'd0;
    end
    else
    begin
        done_r <= 1'b0;
        if(start && ready)
        begin
            busy_r       <= 1'b1;
            state_r      <= block_in ^ round_keys[127:0];
            round_r      <= 4'd1;
            last_round_r <= last_round_for_size(key_size);
        end
        else if(busy_r)
        begin
            if(final_round_w)
            begin
                busy_r      <= 1'b0;
                done_r      <= 1'b1;
                block_out_r <= round_result_w;
            end
            else
            begin
                state_r <= round_result_w;
                round_r <= round_r + 4'd1;
            end
        end
    end
end

assign ready = !busy_r && key_size_valid_w;
assign busy = busy_r;
assign done = done_r;
assign block_out = block_out_r;

endmodule
