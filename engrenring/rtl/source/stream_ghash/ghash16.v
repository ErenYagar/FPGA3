`timescale 1ns / 1ps

// Fixed linear transform T^POWER used by the GCM field multiplier.
//
// T(v) = (v >> 1) ^ (v[0] ? 128'he1...00 : 0)
//
// Every output bit below is derived directly from the original input value.
// No instance depends on the result of another shift-power instance, so the
// sixteen powers used by ghash16 do not form a runtime shift/reduce chain.
module ghash16_gf_shift_power #(
    parameter integer POWER = 0
)
(
    input  [127:0] value,
    output [127:0] transformed
);

genvar bit_index;
generate
    for(bit_index = 0; bit_index < 128; bit_index = bit_index + 1)
    begin : GEN_DIRECT_BIT
        wire base_bit;
        wire reduce_127;
        wire reduce_126;
        wire reduce_125;
        wire reduce_120;

        // The reduction polynomial constant has set bits 127, 126, 125 and
        // 120.  These four terms are the closed-form contribution of every
        // bit shifted out during POWER applications of T.
        if((bit_index + POWER) < 128)
            assign base_bit = value[bit_index + POWER];
        else
            assign base_bit = 1'b0;

        if(((bit_index + POWER - 128) >= 0) &&
           ((bit_index + POWER - 128) < POWER))
            assign reduce_127 = value[bit_index + POWER - 128];
        else
            assign reduce_127 = 1'b0;

        if(((bit_index + POWER - 127) >= 0) &&
           ((bit_index + POWER - 127) < POWER))
            assign reduce_126 = value[bit_index + POWER - 127];
        else
            assign reduce_126 = 1'b0;

        if(((bit_index + POWER - 126) >= 0) &&
           ((bit_index + POWER - 126) < POWER))
            assign reduce_125 = value[bit_index + POWER - 126];
        else
            assign reduce_125 = 1'b0;

        if(((bit_index + POWER - 121) >= 0) &&
           ((bit_index + POWER - 121) < POWER))
            assign reduce_120 = value[bit_index + POWER - 121];
        else
            assign reduce_120 = 1'b0;

        assign transformed[bit_index] = base_bit    ^ reduce_127 ^
                                        reduce_126 ^ reduce_125 ^
                                        reduce_120;
    end
endgenerate

endmodule


// 16-bit digit-serial GHASH primitive.
//
// The block recurrence is Y_next = (Y ^ block_in) * H.  Multiplication uses
// the MSB-first convention from GCM: X[127] is consumed first and V is shifted
// right with the e1 reduction polynomial.  A request takes eight digit clocks.
// Because loading is a separate clock, requests can be accepted nine clocks
// apart (external initiation interval = 9).
module ghash16
(
    input          clk,
    input          rst_n,
    input          load_h,
    input  [127:0] H,
    input          init,
    input          start,
    input  [127:0] block_in,
    output         busy,
    output         done,
    output [127:0] Y
);

reg          busy_r;
reg          done_r;
reg  [2:0]   digit_count_r;
reg  [127:0] h_r;
reg  [127:0] y_r;
reg  [127:0] x_work_r;
reg  [127:0] v_work_r;
reg  [127:0] z_work_r;

wire [127:0] v_power_0;
wire [127:0] v_power_1;
wire [127:0] v_power_2;
wire [127:0] v_power_3;
wire [127:0] v_power_4;
wire [127:0] v_power_5;
wire [127:0] v_power_6;
wire [127:0] v_power_7;
wire [127:0] v_power_8;
wire [127:0] v_power_9;
wire [127:0] v_power_10;
wire [127:0] v_power_11;
wire [127:0] v_power_12;
wire [127:0] v_power_13;
wire [127:0] v_power_14;
wire [127:0] v_power_15;
wire [127:0] v_power_16;

ghash16_gf_shift_power #(.POWER(0))  u_power_0  (.value(v_work_r), .transformed(v_power_0));
ghash16_gf_shift_power #(.POWER(1))  u_power_1  (.value(v_work_r), .transformed(v_power_1));
ghash16_gf_shift_power #(.POWER(2))  u_power_2  (.value(v_work_r), .transformed(v_power_2));
ghash16_gf_shift_power #(.POWER(3))  u_power_3  (.value(v_work_r), .transformed(v_power_3));
ghash16_gf_shift_power #(.POWER(4))  u_power_4  (.value(v_work_r), .transformed(v_power_4));
ghash16_gf_shift_power #(.POWER(5))  u_power_5  (.value(v_work_r), .transformed(v_power_5));
ghash16_gf_shift_power #(.POWER(6))  u_power_6  (.value(v_work_r), .transformed(v_power_6));
ghash16_gf_shift_power #(.POWER(7))  u_power_7  (.value(v_work_r), .transformed(v_power_7));
ghash16_gf_shift_power #(.POWER(8))  u_power_8  (.value(v_work_r), .transformed(v_power_8));
ghash16_gf_shift_power #(.POWER(9))  u_power_9  (.value(v_work_r), .transformed(v_power_9));
ghash16_gf_shift_power #(.POWER(10)) u_power_10 (.value(v_work_r), .transformed(v_power_10));
ghash16_gf_shift_power #(.POWER(11)) u_power_11 (.value(v_work_r), .transformed(v_power_11));
ghash16_gf_shift_power #(.POWER(12)) u_power_12 (.value(v_work_r), .transformed(v_power_12));
ghash16_gf_shift_power #(.POWER(13)) u_power_13 (.value(v_work_r), .transformed(v_power_13));
ghash16_gf_shift_power #(.POWER(14)) u_power_14 (.value(v_work_r), .transformed(v_power_14));
ghash16_gf_shift_power #(.POWER(15)) u_power_15 (.value(v_work_r), .transformed(v_power_15));
ghash16_gf_shift_power #(.POWER(16)) u_power_16 (.value(v_work_r), .transformed(v_power_16));

wire [127:0] selected_0  = v_power_0  & {128{x_work_r[127]}};
wire [127:0] selected_1  = v_power_1  & {128{x_work_r[126]}};
wire [127:0] selected_2  = v_power_2  & {128{x_work_r[125]}};
wire [127:0] selected_3  = v_power_3  & {128{x_work_r[124]}};
wire [127:0] selected_4  = v_power_4  & {128{x_work_r[123]}};
wire [127:0] selected_5  = v_power_5  & {128{x_work_r[122]}};
wire [127:0] selected_6  = v_power_6  & {128{x_work_r[121]}};
wire [127:0] selected_7  = v_power_7  & {128{x_work_r[120]}};
wire [127:0] selected_8  = v_power_8  & {128{x_work_r[119]}};
wire [127:0] selected_9  = v_power_9  & {128{x_work_r[118]}};
wire [127:0] selected_10 = v_power_10 & {128{x_work_r[117]}};
wire [127:0] selected_11 = v_power_11 & {128{x_work_r[116]}};
wire [127:0] selected_12 = v_power_12 & {128{x_work_r[115]}};
wire [127:0] selected_13 = v_power_13 & {128{x_work_r[114]}};
wire [127:0] selected_14 = v_power_14 & {128{x_work_r[113]}};
wire [127:0] selected_15 = v_power_15 & {128{x_work_r[112]}};

// Explicit balanced reduction: 16 selected field terms become 8, 4, 2, 1.
wire [127:0] xor_level1_0 = selected_0  ^ selected_1;
wire [127:0] xor_level1_1 = selected_2  ^ selected_3;
wire [127:0] xor_level1_2 = selected_4  ^ selected_5;
wire [127:0] xor_level1_3 = selected_6  ^ selected_7;
wire [127:0] xor_level1_4 = selected_8  ^ selected_9;
wire [127:0] xor_level1_5 = selected_10 ^ selected_11;
wire [127:0] xor_level1_6 = selected_12 ^ selected_13;
wire [127:0] xor_level1_7 = selected_14 ^ selected_15;

wire [127:0] xor_level2_0 = xor_level1_0 ^ xor_level1_1;
wire [127:0] xor_level2_1 = xor_level1_2 ^ xor_level1_3;
wire [127:0] xor_level2_2 = xor_level1_4 ^ xor_level1_5;
wire [127:0] xor_level2_3 = xor_level1_6 ^ xor_level1_7;

wire [127:0] xor_level3_0 = xor_level2_0 ^ xor_level2_1;
wire [127:0] xor_level3_1 = xor_level2_2 ^ xor_level2_3;
wire [127:0] digit_product_w = xor_level3_0 ^ xor_level3_1;

wire [127:0] z_after_digit_w = z_work_r ^ digit_product_w;
wire [127:0] x_after_digit_w = {x_work_r[111:0], 16'd0};

always @(posedge clk)
begin
    if(!rst_n)
    begin
        busy_r       <= 1'b0;
        done_r       <= 1'b0;
        digit_count_r<= 3'd0;
        h_r          <= 128'd0;
        y_r          <= 128'd0;
        x_work_r     <= 128'd0;
        v_work_r     <= 128'd0;
        z_work_r     <= 128'd0;
    end
    else
    begin
        done_r <= 1'b0;

        if(load_h)
            h_r <= H;

        if(!busy_r)
        begin
            if(start)
            begin
                if(init)
                    y_r <= 128'd0;
                busy_r        <= 1'b1;
                digit_count_r <= 3'd0;
                x_work_r      <= (init ? 128'd0 : y_r) ^ block_in;
                v_work_r      <= load_h ? H : h_r;
                z_work_r      <= 128'd0;
            end
        end
        else
        begin
            if(digit_count_r == 3'd7)
            begin
                y_r           <= z_after_digit_w;
                busy_r        <= 1'b0;
                done_r        <= 1'b1;
                digit_count_r <= 3'd0;
            end
            else
            begin
                x_work_r      <= x_after_digit_w;
                v_work_r      <= v_power_16;
                z_work_r      <= z_after_digit_w;
                digit_count_r <= digit_count_r + 3'd1;
            end
        end
    end
end

assign busy = busy_r;
assign done = done_r;
assign Y    = y_r;

endmodule
