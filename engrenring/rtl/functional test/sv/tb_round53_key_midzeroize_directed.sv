`timescale 1ns / 1ps

// Promoted Round47 key-context security regression.  The stimulus, checks,
// and PASS signature are preserved for the Round53 tracked regression set.
module tb_round53_key_midzeroize_directed;

reg clk = 1'b0;
always #2.5 clk = ~clk;

reg rst_n = 1'b0;
reg commit = 1'b0;
reg [2:0] key_mode = 3'd2;
reg [255:0] key =
    256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f;
reg zeroize = 1'b0;
wire busy;
wire ready;
wire [1:0] key_size;
wire [1919:0] round_keys;
wire [3:0] round_count;

integer recovery_cycles;

aes_key_context dut (
    .clk(clk), .rst_n(rst_n), .commit(commit), .key_mode(key_mode),
    .key(key), .zeroize(zeroize), .busy(busy), .ready(ready),
    .key_size(key_size), .round_keys(round_keys),
    .round_count(round_count)
);

task automatic pulse_commit;
begin
    @(negedge clk);
    commit = 1'b1;
    @(posedge clk);
    @(negedge clk);
    commit = 1'b0;
end
endtask

initial
begin
    repeat(6) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    pulse_commit();
    repeat(24) @(posedge clk);
    #1;
    if(!busy || ready)
        $fatal(1, "MID_ZEROIZE_NOT_EXPANDING busy=%b ready=%b", busy, ready);
    if(round_keys === 1920'd0)
        $fatal(1, "MID_ZEROIZE_KEY_STATE_NOT_LIVE");

    @(negedge clk);
    zeroize = 1'b1;
    @(posedge clk);
    #1;
    if(busy || ready || (round_keys !== 1920'd0) ||
       (round_count != 4'd0))
        $fatal(1,
               "MID_ZEROIZE_SCRUB_FAIL busy=%b ready=%b rounds=%0d keys_zero=%b",
               busy, ready, round_count, round_keys === 1920'd0);
    @(negedge clk);
    zeroize = 1'b0;
    repeat(4) @(posedge clk);
    if(busy || ready)
        $fatal(1, "MID_ZEROIZE_STALE_READY busy=%b ready=%b", busy, ready);

    key_mode = 3'd0;
    key = {128'h000102030405060708090a0b0c0d0e0f, 128'd0};
    pulse_commit();
    recovery_cycles = 0;
    while(!ready && (recovery_cycles < 500))
    begin
        @(posedge clk);
        recovery_cycles = recovery_cycles + 1;
    end
    #1;
    if(!ready || busy || (key_size != 2'd0) || (round_count != 4'd10))
        $fatal(1,
               "MID_ZEROIZE_RECOVERY_FAIL cycles=%0d busy=%b ready=%b size=%0d rounds=%0d",
               recovery_cycles, busy, ready, key_size, round_count);

    $display("KEY_MID_EXPANSION_ZEROIZE_PASS recovery_cycles=%0d scrubbed_round_keys=1",
             recovery_cycles);
    $finish;
end

endmodule
