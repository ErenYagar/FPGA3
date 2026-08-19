`timescale 1ns / 1ps

module tb_round54_fifo_clear_directed;

reg clk = 1'b0;
always #2.5 clk = ~clk;

reg rst_n = 1'b0;
reg zeroize_clear = 1'b0;
reg abort_clear = 1'b0;
reg [7:0] in_data = 8'h00;
reg in_valid = 1'b0;
reg out_ready = 1'b0;
wire clear = zeroize_clear || abort_clear;

wire in_ready_keep;
wire [7:0] out_data_keep;
wire out_valid_keep;
wire [2:0] count_keep;
wire in_ready_scrub;
wire [7:0] out_data_scrub;
wire out_valid_scrub;
wire [2:0] count_scrub;
integer visible_fire_count = 0;

stream_fifo #(.WIDTH(8), .DEPTH(4), .ADDR_W(2),
              .CLEAR_HEAD_ON_CLEAR(0)) keep_head_fifo (
    .clk(clk), .rst_n(rst_n), .clear(clear),
    .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready_keep),
    .out_data(out_data_keep), .out_valid(out_valid_keep),
    .out_ready(out_ready), .count(count_keep)
);

stream_fifo #(.WIDTH(8), .DEPTH(4), .ADDR_W(2)) scrub_head_fifo (
    .clk(clk), .rst_n(rst_n), .clear(clear),
    .in_data(in_data), .in_valid(in_valid), .in_ready(in_ready_scrub),
    .out_data(out_data_scrub), .out_valid(out_valid_scrub),
    .out_ready(out_ready), .count(count_scrub)
);

always @(posedge clk)
begin
    if(out_valid_keep && out_ready && !clear)
        visible_fire_count = visible_fire_count + 1;
end

task automatic drive_push;
input [7:0] value;
begin
    @(negedge clk);
    in_data = value;
    in_valid = 1'b1;
    out_ready = 1'b0;
    @(posedge clk);
    @(negedge clk);
    in_valid = 1'b0;
end
endtask

initial
begin
    repeat(4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    drive_push(8'ha5);
    #1;
    if(!out_valid_keep || count_keep != 1 || out_data_keep !== 8'ha5)
        $fatal(1, "FIFO_INITIAL_HEAD valid=%b count=%0d data=%02x",
               out_valid_keep, count_keep, out_data_keep);

    // A protocol abort has priority over simultaneous push/pop.  The
    // retained physical head is unobservable because logical valid/count
    // clear on the edge and visible valid is masked while clear is asserted.
    @(negedge clk);
    abort_clear = 1'b1;
    in_data = 8'h3c;
    in_valid = 1'b1;
    out_ready = 1'b1;
    @(posedge clk);
    #1;
    if(count_keep != 0 || out_valid_keep || visible_fire_count != 0)
        $fatal(1, "FIFO_ABORT_CLEAR_PRIORITY count=%0d valid=%b fires=%0d",
               count_keep, out_valid_keep, visible_fire_count);
    if(out_data_scrub !== 8'h00)
        $fatal(1, "FIFO_DEFAULT_HEAD_NOT_SCRUBBED data=%02x", out_data_scrub);

    // Keep VALID asserted while clear drops.  The very next edge must refill
    // the empty FIFO with no stale-head exposure or lost/duplicate item.
    @(negedge clk);
    abort_clear = 1'b0;
    out_ready = 1'b0;
    @(posedge clk);
    #1;
    if(!out_valid_keep || count_keep != 1 || out_data_keep !== 8'h3c)
        $fatal(1, "FIFO_IMMEDIATE_REFILL count=%0d valid=%b data=%02x",
               count_keep, out_valid_keep, out_data_keep);
    @(negedge clk);
    in_valid = 1'b0;
    out_ready = 1'b1;
    @(posedge clk);
    @(negedge clk);
    out_ready = 1'b0;
    if(count_keep != 0 || out_valid_keep || visible_fire_count != 1)
        $fatal(1, "FIFO_REFILL_RETIRE count=%0d valid=%b fires=%0d",
               count_keep, out_valid_keep, visible_fire_count);

    // The same logical contract applies to raw ZEROIZE clear.
    drive_push(8'h5a);
    @(negedge clk);
    zeroize_clear = 1'b1;
    @(posedge clk);
    #1;
    if(count_keep != 0 || out_valid_keep || visible_fire_count != 1)
        $fatal(1, "FIFO_ZEROIZE_CLEAR count=%0d valid=%b fires=%0d",
               count_keep, out_valid_keep, visible_fire_count);
    @(negedge clk);
    zeroize_clear = 1'b0;

    // Global reset always scrubs the head, including the specialized FIFO.
    drive_push(8'hc7);
    @(negedge clk);
    rst_n = 1'b0;
    @(posedge clk);
    #1;
    if(count_keep != 0 || out_valid_keep || out_data_keep !== 8'h00)
        $fatal(1, "FIFO_GLOBAL_RESET count=%0d valid=%b data=%02x",
               count_keep, out_valid_keep, out_data_keep);

    $display("ROUND54_FIFO_CLEAR_HEAD_PASS abort=1 zeroize=1 priority=clear refill=immediate stale_fire=0 global_scrub=1");
    $finish;
end

endmodule
