`timescale 1ns / 1ps

module AES_e
(
input          clk,
input          rst_n,
input          start,
input  [1:0]   key_size,
input  [255:0] Key,
input  [127:0] word,
output         busy,
output         finish,
output [127:0] wordout
);

localparam KEY_SIZE_128 = 2'd0;
localparam KEY_SIZE_192 = 2'd1;
localparam KEY_SIZE_256 = 2'd2;

reg          busy_r;
reg          finish_r;
reg  [1:0]   key_size_r;
reg  [3:0]   round_r;
reg  [127:0] state_r;
reg  [127:0] wordout_r;
reg  [127:0] round_key_q;
reg          schedule_phase_r;
reg  [2:0]   generate_count_r;
reg          rcon_event0_r;
reg          rcon_event1_r;
reg          rcon_event2_r;
reg          rcon_event3_r;
reg          sub_event0_r;
reg          sub_event1_r;
reg          sub_event2_r;
reg          sub_event3_r;

reg  [31:0] sched_w0_r;
reg  [31:0] sched_w1_r;
reg  [31:0] sched_w2_r;
reg  [31:0] sched_w3_r;
reg  [31:0] sched_w4_r;
reg  [31:0] sched_w5_r;
reg  [31:0] sched_w6_r;
reg  [31:0] sched_w7_r;
reg  [6:0]  next_word_index_r;
reg  [7:0]  rcon_r;

wire [127:0] sub_bytes_w;
wire [127:0] shift_rows_w;
wire [127:0] mix_columns_w;
wire [3:0]   last_round_w;

wire [2:0] generate_count_w;
wire [6:0] index0_w;
wire [6:0] index1_w;
wire [6:0] index2_w;
wire [6:0] index3_w;
wire rcon_event0_w;
wire rcon_event1_w;
wire rcon_event2_w;
wire rcon_event3_w;
wire sub_event0_w;
wire sub_event1_w;
wire sub_event2_w;
wire sub_event3_w;
wire active_event0_w;
wire active_event1_w;
wire active_event2_w;
wire active_event3_w;

wire [31:0] newest_schedule_word_w;
wire [31:0] schedule_prev0_w;
wire [31:0] schedule_base_new0_w;
wire [31:0] schedule_base_new1_w;
wire [31:0] schedule_base_new2_w;
wire [31:0] schedule_base_new3_w;
wire [31:0] schedule_sbox_source_w;
wire [31:0] schedule_sbox_input_w;
wire [7:0]  schedule_sbox_b0_w;
wire [7:0]  schedule_sbox_b1_w;
wire [7:0]  schedule_sbox_b2_w;
wire [7:0]  schedule_sbox_b3_w;
wire [31:0] schedule_subword_w;
wire [31:0] schedule_event_delta_w;
wire        schedule_rcon_event_w;
wire [31:0] schedule_new0_w;
wire [31:0] schedule_new1_w;
wire [31:0] schedule_new2_w;
wire [31:0] schedule_new3_w;

reg  [31:0] sched_w0_next;
reg  [31:0] sched_w1_next;
reg  [31:0] sched_w2_next;
reg  [31:0] sched_w3_next;
reg  [31:0] sched_w4_next;
reg  [31:0] sched_w5_next;
reg  [31:0] sched_w6_next;
reg  [31:0] sched_w7_next;
reg  [127:0] round_key_r;

wire [6:0] next_word_index_w;
wire [7:0] next_rcon_w;
wire [127:0] round_result_w;

genvar byte_index;
generate
    for(byte_index = 0; byte_index < 16; byte_index = byte_index + 1)
    begin : GEN_STATE_SBOX
        sbox #(.REGISTERED(1)) u_sbox (
            .clk  (clk),
            .rst_n(rst_n),
            .a    (state_r[127 - byte_index*8 -: 8]),
            .co   (sub_bytes_w[127 - byte_index*8 -: 8])
        );
    end
endgenerate

assign shift_rows_w = {
    sub_bytes_w[127:120], sub_bytes_w[87:80],    sub_bytes_w[47:40],   sub_bytes_w[7:0],
    sub_bytes_w[95:88],   sub_bytes_w[55:48],    sub_bytes_w[15:8],    sub_bytes_w[103:96],
    sub_bytes_w[63:56],   sub_bytes_w[23:16],    sub_bytes_w[111:104], sub_bytes_w[71:64],
    sub_bytes_w[31:24],   sub_bytes_w[119:112],  sub_bytes_w[79:72],   sub_bytes_w[39:32]
};

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

function is_rcon_index;
input [6:0] index;
input [1:0] size;
begin
    case(size)
        KEY_SIZE_128: is_rcon_index = (index[1:0] == 2'd0);
        KEY_SIZE_192: is_rcon_index = ((index % 7'd6) == 7'd0);
        default:      is_rcon_index = (index[2:0] == 3'd0);
    endcase
end
endfunction

assign mix_columns_w = {
    mix_column(shift_rows_w[127:96]),
    mix_column(shift_rows_w[95:64]),
    mix_column(shift_rows_w[63:32]),
    mix_column(shift_rows_w[31:0])
};

assign last_round_w = (key_size_r == KEY_SIZE_128) ? 4'd10 :
                      (key_size_r == KEY_SIZE_192) ? 4'd12 : 4'd14;

assign generate_count_w = generate_count_r;

assign index0_w = next_word_index_r;
assign index1_w = next_word_index_r + 7'd1;
assign index2_w = next_word_index_r + 7'd2;
assign index3_w = next_word_index_r + 7'd3;

assign rcon_event0_w = rcon_event0_r;
assign rcon_event1_w = rcon_event1_r;
assign rcon_event2_w = rcon_event2_r;
assign rcon_event3_w = rcon_event3_r;

assign sub_event0_w = sub_event0_r;
assign sub_event1_w = sub_event1_r;
assign sub_event2_w = sub_event2_r;
assign sub_event3_w = sub_event3_r;

assign active_event0_w = (generate_count_w > 3'd0) && (rcon_event0_w || sub_event0_w);
assign active_event1_w = (generate_count_w > 3'd1) && (rcon_event1_w || sub_event1_w);
assign active_event2_w = (generate_count_w > 3'd2) && (rcon_event2_w || sub_event2_w);
assign active_event3_w = (generate_count_w > 3'd3) && (rcon_event3_w || sub_event3_w);

assign newest_schedule_word_w = (key_size_r == KEY_SIZE_128) ? sched_w3_r :
                                (key_size_r == KEY_SIZE_192) ? sched_w5_r : sched_w7_r;

assign schedule_prev0_w = newest_schedule_word_w;

// Only one special key-schedule event can occur in a four-word batch.  Build
// the no-event words as a parallel XOR prefix.  At the special word, the
// S-box transformation differs from the no-event prefix by one delta; that
// same delta propagates to every following word in the batch.
assign schedule_base_new0_w = sched_w0_r ^ schedule_prev0_w;
assign schedule_base_new1_w = sched_w1_r ^ sched_w0_r ^ schedule_prev0_w;
assign schedule_base_new2_w = sched_w2_r ^ sched_w1_r ^ sched_w0_r ^ schedule_prev0_w;
assign schedule_base_new3_w = sched_w3_r ^ sched_w2_r ^ sched_w1_r ^
                              sched_w0_r ^ schedule_prev0_w;

assign schedule_sbox_source_w = active_event0_w ? schedule_prev0_w :
                                active_event1_w ? schedule_base_new0_w :
                                active_event2_w ? schedule_base_new1_w : schedule_base_new2_w;

assign schedule_sbox_input_w =
    ((active_event0_w && rcon_event0_w) ||
     (active_event1_w && rcon_event1_w) ||
     (active_event2_w && rcon_event2_w) ||
     (active_event3_w && rcon_event3_w)) ?
        {schedule_sbox_source_w[23:0], schedule_sbox_source_w[31:24]} :
        schedule_sbox_source_w;

sbox #(.REGISTERED(1)) u_schedule_sbox0 (.clk(clk), .rst_n(rst_n), .a(schedule_sbox_input_w[31:24]), .co(schedule_sbox_b0_w));
sbox #(.REGISTERED(1)) u_schedule_sbox1 (.clk(clk), .rst_n(rst_n), .a(schedule_sbox_input_w[23:16]), .co(schedule_sbox_b1_w));
sbox #(.REGISTERED(1)) u_schedule_sbox2 (.clk(clk), .rst_n(rst_n), .a(schedule_sbox_input_w[15:8]),  .co(schedule_sbox_b2_w));
sbox #(.REGISTERED(1)) u_schedule_sbox3 (.clk(clk), .rst_n(rst_n), .a(schedule_sbox_input_w[7:0]),   .co(schedule_sbox_b3_w));

assign schedule_subword_w = {schedule_sbox_b0_w, schedule_sbox_b1_w,
                             schedule_sbox_b2_w, schedule_sbox_b3_w};

assign schedule_rcon_event_w = (active_event0_w && rcon_event0_w) ||
                               (active_event1_w && rcon_event1_w) ||
                               (active_event2_w && rcon_event2_w) ||
                               (active_event3_w && rcon_event3_w);

assign schedule_event_delta_w = schedule_subword_w ^ schedule_sbox_source_w ^
                                (schedule_rcon_event_w ? {rcon_r, 24'd0} : 32'd0);

assign schedule_new0_w = schedule_base_new0_w ^
                         ({32{active_event0_w}} & schedule_event_delta_w);
assign schedule_new1_w = schedule_base_new1_w ^
                         ({32{active_event0_w || active_event1_w}} & schedule_event_delta_w);
assign schedule_new2_w = schedule_base_new2_w ^
                         ({32{active_event0_w || active_event1_w || active_event2_w}} & schedule_event_delta_w);
assign schedule_new3_w = schedule_base_new3_w ^
                         ({32{active_event0_w || active_event1_w || active_event2_w || active_event3_w}} & schedule_event_delta_w);

always @(*)
begin
    sched_w0_next = sched_w0_r;
    sched_w1_next = sched_w1_r;
    sched_w2_next = sched_w2_r;
    sched_w3_next = sched_w3_r;
    sched_w4_next = sched_w4_r;
    sched_w5_next = sched_w5_r;
    sched_w6_next = sched_w6_r;
    sched_w7_next = sched_w7_r;

    if(generate_count_w == 3'd2)
    begin
        sched_w0_next = sched_w2_r;
        sched_w1_next = sched_w3_r;
        sched_w2_next = sched_w4_r;
        sched_w3_next = sched_w5_r;
        sched_w4_next = schedule_new0_w;
        sched_w5_next = schedule_new1_w;
    end
    else if(generate_count_w == 3'd4)
    begin
        case(key_size_r)
            KEY_SIZE_128:
            begin
                sched_w0_next = schedule_new0_w;
                sched_w1_next = schedule_new1_w;
                sched_w2_next = schedule_new2_w;
                sched_w3_next = schedule_new3_w;
            end

            KEY_SIZE_192:
            begin
                sched_w0_next = sched_w4_r;
                sched_w1_next = sched_w5_r;
                sched_w2_next = schedule_new0_w;
                sched_w3_next = schedule_new1_w;
                sched_w4_next = schedule_new2_w;
                sched_w5_next = schedule_new3_w;
            end

            default:
            begin
                sched_w0_next = sched_w4_r;
                sched_w1_next = sched_w5_r;
                sched_w2_next = sched_w6_r;
                sched_w3_next = sched_w7_r;
                sched_w4_next = schedule_new0_w;
                sched_w5_next = schedule_new1_w;
                sched_w6_next = schedule_new2_w;
                sched_w7_next = schedule_new3_w;
            end
        endcase
    end

    if((round_r == 4'd0) && (key_size_r == KEY_SIZE_192))
        round_key_r = {sched_w4_r, sched_w5_r, schedule_new0_w, schedule_new1_w};
    else if((round_r == 4'd0) && (key_size_r == KEY_SIZE_256))
        round_key_r = {sched_w4_r, sched_w5_r, sched_w6_r, sched_w7_r};
    else
        round_key_r = {schedule_new0_w, schedule_new1_w,
                       schedule_new2_w, schedule_new3_w};
end

assign next_word_index_w = next_word_index_r + generate_count_w;
assign next_rcon_w = ((active_event0_w && rcon_event0_w) ||
                      (active_event1_w && rcon_event1_w) ||
                      (active_event2_w && rcon_event2_w) ||
                      (active_event3_w && rcon_event3_w)) ? xtime(rcon_r) : rcon_r;

assign round_result_w = ((round_r == last_round_w) ? shift_rows_w : mix_columns_w) ^ round_key_q;

always @(posedge clk)
begin
    if(!rst_n)
    begin
        busy_r           <= 1'b0;
        finish_r         <= 1'b0;
        key_size_r       <= KEY_SIZE_256;
        round_r          <= 4'd0;
        state_r          <= 128'd0;
        wordout_r        <= 128'd0;
        round_key_q      <= 128'd0;
        schedule_phase_r <= 1'b0;
        generate_count_r <= 3'd0;
        rcon_event0_r    <= 1'b0;
        rcon_event1_r    <= 1'b0;
        rcon_event2_r    <= 1'b0;
        rcon_event3_r    <= 1'b0;
        sub_event0_r     <= 1'b0;
        sub_event1_r     <= 1'b0;
        sub_event2_r     <= 1'b0;
        sub_event3_r     <= 1'b0;
        sched_w0_r       <= 32'd0;
        sched_w1_r       <= 32'd0;
        sched_w2_r       <= 32'd0;
        sched_w3_r       <= 32'd0;
        sched_w4_r       <= 32'd0;
        sched_w5_r       <= 32'd0;
        sched_w6_r       <= 32'd0;
        sched_w7_r       <= 32'd0;
        next_word_index_r<= 7'd0;
        rcon_r           <= 8'h01;
    end
    else
    begin
        finish_r <= 1'b0;

        if(start && !busy_r)
        begin
            busy_r     <= 1'b1;
            key_size_r <= key_size;
            round_r    <= 4'd0;
            state_r    <= word ^ Key[255:128];
            round_key_q<= 128'd0;
            schedule_phase_r <= 1'b0;
            sched_w0_r <= Key[255:224];
            sched_w1_r <= Key[223:192];
            sched_w2_r <= Key[191:160];
            sched_w3_r <= Key[159:128];
            sched_w4_r <= Key[127:96];
            sched_w5_r <= Key[95:64];
            sched_w6_r <= Key[63:32];
            sched_w7_r <= Key[31:0];
            next_word_index_r <= (key_size == KEY_SIZE_128) ? 7'd4 :
                                 (key_size == KEY_SIZE_192) ? 7'd6 : 7'd8;
            rcon_r <= 8'h01;

            case(key_size)
                KEY_SIZE_128:
                begin
                    generate_count_r <= 3'd4;
                    rcon_event0_r    <= 1'b1;
                end

                KEY_SIZE_192:
                begin
                    generate_count_r <= 3'd2;
                    rcon_event0_r    <= 1'b1;
                end

                default:
                begin
                    generate_count_r <= 3'd0;
                    rcon_event0_r    <= 1'b0;
                end
            endcase
            rcon_event1_r <= 1'b0;
            rcon_event2_r <= 1'b0;
            rcon_event3_r <= 1'b0;
            sub_event0_r  <= 1'b0;
            sub_event1_r  <= 1'b0;
            sub_event2_r  <= 1'b0;
            sub_event3_r  <= 1'b0;
        end
        else if(busy_r)
        begin
            if(!schedule_phase_r)
            begin
                schedule_phase_r <= 1'b1;
            end
            else
            begin
                schedule_phase_r <= 1'b0;
                sched_w0_r        <= sched_w0_next;
                sched_w1_r        <= sched_w1_next;
                sched_w2_r        <= sched_w2_next;
                sched_w3_r        <= sched_w3_next;
                sched_w4_r        <= sched_w4_next;
                sched_w5_r        <= sched_w5_next;
                sched_w6_r        <= sched_w6_next;
                sched_w7_r        <= sched_w7_next;
                next_word_index_r <= next_word_index_w;
                rcon_r             <= next_rcon_w;
                round_key_q        <= round_key_r;
                generate_count_r   <= 3'd4;
                rcon_event0_r      <= is_rcon_index(next_word_index_w,      key_size_r);
                rcon_event1_r      <= is_rcon_index(next_word_index_w + 1,  key_size_r);
                rcon_event2_r      <= is_rcon_index(next_word_index_w + 2,  key_size_r);
                rcon_event3_r      <= is_rcon_index(next_word_index_w + 3,  key_size_r);
                sub_event0_r       <= (key_size_r == KEY_SIZE_256) &&
                                      (next_word_index_w[2:0] == 3'd4);
                sub_event1_r       <= (key_size_r == KEY_SIZE_256) &&
                                      (next_word_index_w[2:0] == 3'd3);
                sub_event2_r       <= (key_size_r == KEY_SIZE_256) &&
                                      (next_word_index_w[2:0] == 3'd2);
                sub_event3_r       <= (key_size_r == KEY_SIZE_256) &&
                                      (next_word_index_w[2:0] == 3'd1);

                if(round_r == 4'd0)
                begin
                    round_r <= 4'd1;
                end
                else if(round_r == last_round_w)
                begin
                    wordout_r <= round_result_w;
                    busy_r    <= 1'b0;
                    finish_r  <= 1'b1;
                    round_r   <= 4'd0;
                end
                else
                begin
                    state_r <= round_result_w;
                    round_r <= round_r + 4'd1;
                end
            end
        end
    end
end

assign busy    = busy_r;
assign finish  = finish_r;
assign wordout = wordout_r;

endmodule
