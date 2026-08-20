`timescale 1ns / 1ps

// AES key expansion context.
//
// The input key is MSB aligned:
//   AES-128 uses key[255:128]
//   AES-192 uses key[255:64]
//   AES-256 uses key[255:0]
//
// Round-key layout:
//   round_keys[round_index*128 +: 128]
// Round zero is therefore round_keys[127:0], and round fourteen is
// round_keys[1919:1792].
module aes_key_context
(
    input             clk,
    input             rst_n,
    input             commit,
    input      [2:0]  key_mode,
    input      [255:0] key,
    input             zeroize,
    output            busy,
    output            ready,
    output     [1:0]  key_size,
    output     [1919:0] round_keys,
    output     [3:0]  round_count
);

localparam KEY_SIZE_128 = 2'd0;
localparam KEY_SIZE_192 = 2'd1;
localparam KEY_SIZE_256 = 2'd2;

localparam ST_IDLE         = 3'd0;
localparam ST_GENERATE     = 3'd1;
localparam ST_SBOX_WAIT    = 3'd2;
localparam ST_SBOX_CAPTURE = 3'd3;
localparam ST_STORE_WORD   = 3'd4;

reg         busy_r;
reg         ready_r;
reg [1:0]   key_size_r;
reg [3:0]   round_count_r;
reg [1919:0] round_keys_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg [59:0]  round_key_word_we_r;

reg [2:0]  state_r;
reg [3:0]  nk_r;
reg [6:0]  total_words_r;
reg [6:0]  word_index_r;
reg [2:0]  word_position_r;
reg [7:0]  rcon_r;
reg        sbox_uses_rcon_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg        next_word_uses_rcon_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg        next_word_uses_sbox_r;
(* keep = "true", equivalent_register_removal = "no" *)
reg [31:0] sbox_input_r;
reg [31:0] generated_word_r;
reg [31:0] window_w0_r;
reg [31:0] window_w1_r;
reg [31:0] window_w2_r;
reg [31:0] window_w3_r;
reg [31:0] window_w4_r;
reg [31:0] window_w5_r;
reg [31:0] window_w6_r;
reg [31:0] window_w7_r;
integer round_key_round_iter;
integer round_key_word_iter;

wire [31:0] previous_word_w;
wire [31:0] nk_back_word_w;
wire [7:0]  sbox_b0_w;
wire [7:0]  sbox_b1_w;
wire [7:0]  sbox_b2_w;
wire [7:0]  sbox_b3_w;
wire [31:0] sbox_word_w;
wire [31:0] normal_new_word_w;
wire [31:0] sbox_new_word_w;
wire        sbox_rst_n_w;

function [7:0] xtime;
input [7:0] value;
begin
    xtime = {value[6:0], 1'b0} ^ (value[7] ? 8'h1b : 8'h00);
end
endfunction

assign previous_word_w = (nk_r == 4'd4) ? window_w3_r :
                         (nk_r == 4'd6) ? window_w5_r : window_w7_r;
assign nk_back_word_w  = window_w0_r;
assign normal_new_word_w = nk_back_word_w ^ previous_word_w;
assign sbox_word_w = {sbox_b0_w, sbox_b1_w, sbox_b2_w, sbox_b3_w};
assign sbox_new_word_w = nk_back_word_w ^ sbox_word_w ^
                         (sbox_uses_rcon_r ? {rcon_r, 24'd0} : 32'd0);

assign sbox_rst_n_w = rst_n && !zeroize;

// A registered S-box makes the key-expansion lookup an explicit pipeline
// stage.  sbox_input_r is the only address source, so the key-word XOR chain
// is not placed on the synchronous ROM address path.
sbox #(.REGISTERED(1)) u_key_sbox0
(
    .clk   (clk),
    .rst_n (sbox_rst_n_w),
    .a     (sbox_input_r[31:24]),
    .co    (sbox_b0_w)
);

sbox #(.REGISTERED(1)) u_key_sbox1
(
    .clk   (clk),
    .rst_n (sbox_rst_n_w),
    .a     (sbox_input_r[23:16]),
    .co    (sbox_b1_w)
);

sbox #(.REGISTERED(1)) u_key_sbox2
(
    .clk   (clk),
    .rst_n (sbox_rst_n_w),
    .a     (sbox_input_r[15:8]),
    .co    (sbox_b2_w)
);

sbox #(.REGISTERED(1)) u_key_sbox3
(
    .clk   (clk),
    .rst_n (sbox_rst_n_w),
    .a     (sbox_input_r[7:0]),
    .co    (sbox_b3_w)
);

always @(posedge clk)
begin
    if(!rst_n)
    begin
        busy_r            <= 1'b0;
        ready_r           <= 1'b0;
        key_size_r        <= KEY_SIZE_256;
        round_count_r     <= 4'd0;
        round_key_word_we_r <= 60'd0;
        // Round-key payload is invalid while ready_r=0; omit ordinary reset
        // to avoid a 1920-bit synchronous-reset fanout.  Explicit ZEROIZE
        // below still scrubs every key bit.
        state_r           <= ST_IDLE;
        nk_r              <= 4'd0;
        total_words_r     <= 7'd0;
        word_index_r      <= 7'd0;
        word_position_r   <= 3'd0;
        rcon_r            <= 8'h01;
        sbox_uses_rcon_r  <= 1'b0;
        next_word_uses_rcon_r <= 1'b0;
        next_word_uses_sbox_r <= 1'b0;
        sbox_input_r      <= 32'd0;
        generated_word_r  <= 32'd0;
        window_w0_r       <= 32'd0;
        window_w1_r       <= 32'd0;
        window_w2_r       <= 32'd0;
        window_w3_r       <= 32'd0;
        window_w4_r       <= 32'd0;
        window_w5_r       <= 32'd0;
        window_w6_r       <= 32'd0;
        window_w7_r       <= 32'd0;
    end
    else if(zeroize)
    begin
        busy_r            <= 1'b0;
        ready_r           <= 1'b0;
        key_size_r        <= KEY_SIZE_256;
        round_count_r     <= 4'd0;
        round_keys_r      <= 1920'd0;
        round_key_word_we_r <= 60'd0;
        state_r           <= ST_IDLE;
        nk_r              <= 4'd0;
        total_words_r     <= 7'd0;
        word_index_r      <= 7'd0;
        word_position_r   <= 3'd0;
        rcon_r            <= 8'h01;
        sbox_uses_rcon_r  <= 1'b0;
        next_word_uses_rcon_r <= 1'b0;
        next_word_uses_sbox_r <= 1'b0;
        sbox_input_r      <= 32'd0;
        generated_word_r  <= 32'd0;
        window_w0_r       <= 32'd0;
        window_w1_r       <= 32'd0;
        window_w2_r       <= 32'd0;
        window_w3_r       <= 32'd0;
        window_w4_r       <= 32'd0;
        window_w5_r       <= 32'd0;
        window_w6_r       <= 32'd0;
        window_w7_r       <= 32'd0;
    end
    else
    begin
        // The key-expansion FSM registers a one-hot write pulse one cycle
        // before ST_STORE_WORD.  Each pulse drives only one 32-bit round-key
        // word, keeping the FSM state bits out of the 1920 payload CEs while
        // preserving the existing key-expansion latency.
        round_key_word_we_r <= 60'd0;
        for(round_key_round_iter = 0;
            round_key_round_iter < 15;
            round_key_round_iter = round_key_round_iter + 1)
        begin
            for(round_key_word_iter = 0;
                round_key_word_iter < 4;
                round_key_word_iter = round_key_word_iter + 1)
            begin
                if(round_key_word_we_r[round_key_round_iter*4 +
                                       round_key_word_iter])
                    round_keys_r[round_key_round_iter*128 +
                                 (3-round_key_word_iter)*32 +: 32]
                        <= generated_word_r;
            end
        end

        case(state_r)
            ST_IDLE:
            begin
                busy_r <= 1'b0;

                if(commit)
                begin
                    ready_r          <= 1'b0;
                    rcon_r           <= 8'h01;
                    word_position_r  <= 3'd0;
                    sbox_input_r     <= 32'd0;
                    sbox_uses_rcon_r <= 1'b0;
                    next_word_uses_rcon_r <= 1'b0;
                    next_word_uses_sbox_r <= 1'b0;

                    case(key_mode)
                        3'd0:
                        begin
                            busy_r        <= 1'b1;
                            key_size_r    <= KEY_SIZE_128;
                            round_count_r <= 4'd10;
                            nk_r          <= 4'd4;
                            total_words_r <= 7'd44;
                            word_index_r  <= 7'd4;
                            state_r       <= ST_GENERATE;
                            next_word_uses_rcon_r <= 1'b1;
                            next_word_uses_sbox_r <= 1'b1;

                            window_w0_r <= key[255:224];
                            window_w1_r <= key[223:192];
                            window_w2_r <= key[191:160];
                            window_w3_r <= key[159:128];
                            window_w4_r <= 32'd0;
                            window_w5_r <= 32'd0;
                            window_w6_r <= 32'd0;
                            window_w7_r <= 32'd0;
                            round_keys_r[127:0] <= key[255:128];
                        end

                        3'd1:
                        begin
                            busy_r        <= 1'b1;
                            key_size_r    <= KEY_SIZE_192;
                            round_count_r <= 4'd12;
                            nk_r          <= 4'd6;
                            total_words_r <= 7'd52;
                            word_index_r  <= 7'd6;
                            state_r       <= ST_GENERATE;
                            next_word_uses_rcon_r <= 1'b1;
                            next_word_uses_sbox_r <= 1'b1;

                            window_w0_r <= key[255:224];
                            window_w1_r <= key[223:192];
                            window_w2_r <= key[191:160];
                            window_w3_r <= key[159:128];
                            window_w4_r <= key[127:96];
                            window_w5_r <= key[95:64];
                            window_w6_r <= 32'd0;
                            window_w7_r <= 32'd0;
                            round_keys_r[127:0]   <= key[255:128];
                            round_keys_r[255:128] <= {key[127:64], 64'd0};
                        end

                        3'd2:
                        begin
                            busy_r        <= 1'b1;
                            key_size_r    <= KEY_SIZE_256;
                            round_count_r <= 4'd14;
                            nk_r          <= 4'd8;
                            total_words_r <= 7'd60;
                            word_index_r  <= 7'd8;
                            state_r       <= ST_GENERATE;
                            next_word_uses_rcon_r <= 1'b1;
                            next_word_uses_sbox_r <= 1'b1;

                            window_w0_r <= key[255:224];
                            window_w1_r <= key[223:192];
                            window_w2_r <= key[191:160];
                            window_w3_r <= key[159:128];
                            window_w4_r <= key[127:96];
                            window_w5_r <= key[95:64];
                            window_w6_r <= key[63:32];
                            window_w7_r <= key[31:0];
                            round_keys_r[127:0]   <= key[255:128];
                            round_keys_r[255:128] <= key[127:0];
                        end

                        default:
                        begin
                            busy_r        <= 1'b0;
                            ready_r       <= 1'b0;
                            round_count_r <= 4'd0;
                            state_r       <= ST_IDLE;
                        end
                    endcase
                end
            end

            ST_GENERATE:
            begin
                if(next_word_uses_sbox_r)
                begin
                    sbox_uses_rcon_r <= next_word_uses_rcon_r;
                    sbox_input_r <= next_word_uses_rcon_r ?
                                    {previous_word_w[23:0],
                                     previous_word_w[31:24]} :
                                    previous_word_w;
                    state_r <= ST_SBOX_WAIT;
                end
                else
                begin
                    generated_word_r <= normal_new_word_w;
                    round_key_word_we_r <= 60'd1 << word_index_r;
                    state_r <= ST_STORE_WORD;
                end
            end

            ST_SBOX_WAIT:
            begin
                // The registered S-box samples sbox_input_r on this edge.
                state_r <= ST_SBOX_CAPTURE;
            end

            ST_SBOX_CAPTURE:
            begin
                generated_word_r <= sbox_new_word_w;
                round_key_word_we_r <= 60'd1 << word_index_r;

                if(sbox_uses_rcon_r)
                    rcon_r <= xtime(rcon_r);

                state_r <= ST_STORE_WORD;
            end

            ST_STORE_WORD:
            begin
                case(nk_r)
                    4'd4:
                    begin
                        window_w0_r <= window_w1_r;
                        window_w1_r <= window_w2_r;
                        window_w2_r <= window_w3_r;
                        window_w3_r <= generated_word_r;
                    end

                    4'd6:
                    begin
                        window_w0_r <= window_w1_r;
                        window_w1_r <= window_w2_r;
                        window_w2_r <= window_w3_r;
                        window_w3_r <= window_w4_r;
                        window_w4_r <= window_w5_r;
                        window_w5_r <= generated_word_r;
                    end

                    default:
                    begin
                        window_w0_r <= window_w1_r;
                        window_w1_r <= window_w2_r;
                        window_w2_r <= window_w3_r;
                        window_w3_r <= window_w4_r;
                        window_w4_r <= window_w5_r;
                        window_w5_r <= window_w6_r;
                        window_w6_r <= window_w7_r;
                        window_w7_r <= generated_word_r;
                    end
                endcase

                if(word_index_r == (total_words_r - 7'd1))
                begin
                    busy_r  <= 1'b0;
                    ready_r <= 1'b1;
                    state_r <= ST_IDLE;
                end
                else
                begin
                    word_index_r <= word_index_r + 7'd1;
                    if(word_position_r == (nk_r - 4'd1))
                    begin
                        word_position_r <= 3'd0;
                        next_word_uses_rcon_r <= 1'b1;
                        next_word_uses_sbox_r <= 1'b1;
                    end
                    else
                    begin
                        word_position_r <= word_position_r + 3'd1;
                        next_word_uses_rcon_r <= 1'b0;
                        next_word_uses_sbox_r <= (nk_r == 4'd8) &&
                                                (word_position_r == 3'd3);
                    end
                    state_r <= ST_GENERATE;
                end
            end

            default:
            begin
                busy_r  <= 1'b0;
                ready_r <= 1'b0;
                state_r <= ST_IDLE;
            end
        endcase
    end
end

assign busy        = busy_r;
assign ready       = ready_r;
assign key_size    = key_size_r;
assign round_keys  = round_keys_r;
assign round_count = round_count_r;

endmodule
