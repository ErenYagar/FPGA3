`timescale 1ns/1ps

module ghash16_sva (
    input logic         clk,
    input logic         rst_n,
    input logic         load_h,
    input logic [127:0] H,
    input logic         init,
    input logic         start,
    input logic [127:0] block_in,
    input logic         busy,
    input logic         done,
    input logic [127:0] Y,
    input logic [2:0]   digit_count_r,
    input logic [127:0] h_r,
    input logic [127:0] x_work_r,
    input logic [127:0] v_work_r,
    input logic [127:0] z_work_r,
    input logic [127:0] v_power_16,
    input logic [127:0] digit_product_w,
    input logic [127:0] z_after_digit_w
);

    logic past_valid;
    logic h_loaded;
    logic [127:0] accepted_y;
    logic [127:0] accepted_block;
    logic [127:0] accepted_h;
    integer clocks_since_start;

    function automatic logic [127:0] gf_shift_one(input logic [127:0] v);
        gf_shift_one = {1'b0, v[127:1]} ^
                       (v[0] ? 128'he1000000000000000000000000000000 : 128'd0);
    endfunction

    function automatic logic [127:0] gf_shift_n(
        input logic [127:0] v,
        input integer count
    );
        logic [127:0] work;
        integer i;
        begin
            work = v;
            for (i = 0; i < count; i = i + 1)
                work = gf_shift_one(work);
            gf_shift_n = work;
        end
    endfunction

    function automatic logic [127:0] digit_reference(
        input logic [15:0] x_digit,
        input logic [127:0] v
    );
        logic [127:0] work_v;
        logic [127:0] product;
        integer i;
        begin
            work_v = v;
            product = 128'd0;
            for (i = 15; i >= 0; i = i - 1) begin
                if (x_digit[i])
                    product = product ^ work_v;
                work_v = gf_shift_one(work_v);
            end
            digit_reference = product;
        end
    endfunction

    function automatic logic [127:0] multiply_reference(
        input logic [127:0] x,
        input logic [127:0] h
    );
        logic [127:0] work_v;
        logic [127:0] product;
        integer i;
        begin
            work_v = h;
            product = 128'd0;
            for (i = 127; i >= 0; i = i - 1) begin
                if (x[i])
                    product = product ^ work_v;
                work_v = gf_shift_one(work_v);
            end
            multiply_reference = product;
        end
    endfunction

    always_ff @(posedge clk) begin
        past_valid <= 1'b1;
        if (!rst_n) begin
            h_loaded <= 1'b0;
            accepted_y <= 128'd0;
            accepted_block <= 128'd0;
            accepted_h <= 128'd0;
            clocks_since_start <= 32'h3fffffff;
        end else begin
            if (load_h)
                h_loaded <= 1'b1;
            if (start && !busy) begin
                accepted_y <= init ? 128'd0 : Y;
                accepted_block <= block_in;
                accepted_h <= load_h ? H : h_r;
                clocks_since_start <= 0;
            end else if (clocks_since_start < 32'h3fffffff) begin
                clocks_since_start <= clocks_since_start + 1;
            end
        end
    end

    default clocking cb @(posedge clk); endclocking

    ap_sync_reset: assert property (!rst_n |=>
        !busy && !done && digit_count_r == 3'd0 && Y == 128'd0 &&
        x_work_r == 128'd0 && v_work_r == 128'd0 && z_work_r == 128'd0);

    ap_h_before_start: assert property (disable iff (!rst_n)
        (start && !busy) |-> (h_loaded || load_h));

    ap_no_start_while_busy: assert property (disable iff (!rst_n)
        busy |-> !start);

    ap_same_cycle_h: assert property (disable iff (!rst_n)
        (start && !busy && load_h) |=> v_work_r == $past(H));

    ap_t16_reference: assert property (disable iff (!rst_n)
        v_power_16 == gf_shift_n(v_work_r, 16));

    ap_digit_product_reference: assert property (disable iff (!rst_n)
        digit_product_w == digit_reference(x_work_r[127:112], v_work_r));

    ap_done_one_cycle: assert property (disable iff (!rst_n)
        done |=> !done);

    ap_start_sets_digit_zero: assert property (disable iff (!rst_n)
        (start && !busy) |=> busy && digit_count_r == 3'd0);

    ap_digit_sequence: assert property (disable iff (!rst_n)
        (past_valid && $past(rst_n) && $past(busy) &&
         $past(digit_count_r) < 3'd7) |->
        (busy && digit_count_r == ($past(digit_count_r) + 3'd1)));

    ap_x_advance: assert property (disable iff (!rst_n)
        (past_valid && $past(rst_n) && $past(busy) &&
         $past(digit_count_r) < 3'd7) |->
        x_work_r == {$past(x_work_r[111:0]), 16'd0});

    ap_v_advance: assert property (disable iff (!rst_n)
        (past_valid && $past(rst_n) && $past(busy) &&
         $past(digit_count_r) < 3'd7) |->
        v_work_r == gf_shift_n($past(v_work_r), 16));

    ap_z_accumulate: assert property (disable iff (!rst_n)
        (past_valid && $past(rst_n) && $past(busy) &&
         $past(digit_count_r) < 3'd7) |->
        z_work_r == ($past(z_work_r) ^
                     digit_reference($past(x_work_r[127:112]),
                                     $past(v_work_r))));

    ap_final_y: assert property (disable iff (!rst_n)
        (past_valid && $past(rst_n) && $past(busy) &&
         $past(digit_count_r) == 3'd7) |->
        (!busy && done &&
         Y == ($past(z_work_r) ^
               digit_reference($past(x_work_r[127:112]),
                               $past(v_work_r)))));

    ap_full_recurrence: assert property (disable iff (!rst_n)
        done |-> Y == multiply_reference(accepted_y ^ accepted_block,
                                         accepted_h));

    ap_min_request_interval: assert property (disable iff (!rst_n)
        (start && !busy) |-> clocks_since_start >= 8);

endmodule
