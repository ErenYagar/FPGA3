`timescale 1ns / 1ps

module tb_ghash16;

reg          clk;
reg          rst_n;
reg          load_h;
reg  [127:0] H;
reg          init;
reg          start;
reg  [127:0] block_in;
wire         busy;
wire         done;
wire [127:0] Y;

reg  [127:0] reference_h;
reg  [127:0] reference_y;
reg  [127:0] expected_y;
reg  [127:0] random_block;
integer      test_count;
integer      error_count;
integer      sim_cycle;
integer      previous_accept_cycle;
integer      random_index;

ghash16 dut
(
    .clk     (clk),
    .rst_n   (rst_n),
    .load_h  (load_h),
    .H       (H),
    .init    (init),
    .start   (start),
    .block_in(block_in),
    .busy    (busy),
    .done    (done),
    .Y       (Y)
);

always #5 clk = ~clk;

always @(posedge clk)
    sim_cycle = sim_cycle + 1;

function [127:0] gf_multiply_reference;
input [127:0] x_value;
input [127:0] h_value;
reg   [127:0] z_value;
reg   [127:0] v_value;
integer bit_index;
begin
    z_value = 128'd0;
    v_value = h_value;

    for(bit_index = 0; bit_index < 128; bit_index = bit_index + 1)
    begin
        if(x_value[127 - bit_index])
            z_value = z_value ^ v_value;

        if(v_value[0])
            v_value = (v_value >> 1) ^
                      128'he1000000000000000000000000000000;
        else
            v_value = v_value >> 1;
    end

    gf_multiply_reference = z_value;
end
endfunction

task load_hash_key;
input [127:0] hash_key;
begin
    @(negedge clk);
    H      = hash_key;
    load_h = 1'b1;
    @(posedge clk);
    #1;
    load_h     = 1'b0;
    reference_h = hash_key;
    previous_accept_cycle = -1;
end
endtask

task run_block;
input [127:0] block_value;
input         initialize;
input         check_known_first_product;
integer       accepted_cycle;
integer       digit_cycles;
begin
    expected_y = gf_multiply_reference(
        (initialize ? 128'd0 : reference_y) ^ block_value,
        reference_h
    );

    @(negedge clk);
    block_in = block_value;
    init     = initialize;
    start    = 1'b1;

    @(posedge clk);
    #1;
    accepted_cycle = sim_cycle;
    if(!busy)
    begin
        $display("GHASH16_ERROR request was not accepted");
        error_count = error_count + 1;
    end

    if((previous_accept_cycle >= 0) &&
       ((accepted_cycle - previous_accept_cycle) != 9))
    begin
        $display("GHASH16_ERROR external II=%0d expected=9",
                 accepted_cycle - previous_accept_cycle);
        error_count = error_count + 1;
    end
    previous_accept_cycle = accepted_cycle;

    @(negedge clk);
    start = 1'b0;
    init  = 1'b0;

    digit_cycles = 0;
    while(!done && (digit_cycles < 12))
    begin
        @(posedge clk);
        #1;
        digit_cycles = digit_cycles + 1;
    end

    if(digit_cycles != 8)
    begin
        $display("GHASH16_ERROR digit cycles=%0d expected=8", digit_cycles);
        error_count = error_count + 1;
    end

    if(Y !== expected_y)
    begin
        $display("GHASH16_ERROR block=%032h expected=%032h actual=%032h",
                 block_value, expected_y, Y);
        error_count = error_count + 1;
    end

    if(check_known_first_product &&
       (Y !== 128'h5e2ec746917062882c85b0685353deb7))
    begin
        $display("GHASH16_ERROR known GCM product mismatch actual=%032h", Y);
        error_count = error_count + 1;
    end

    reference_y = expected_y;
    test_count  = test_count + 1;
end
endtask

initial
begin
    clk                   = 1'b0;
    rst_n                 = 1'b0;
    load_h                = 1'b0;
    H                     = 128'd0;
    init                  = 1'b0;
    start                 = 1'b0;
    block_in              = 128'd0;
    reference_h           = 128'd0;
    reference_y           = 128'd0;
    expected_y            = 128'd0;
    test_count            = 0;
    error_count           = 0;
    sim_cycle             = 0;
    previous_accept_cycle = -1;

    repeat(4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    load_hash_key(128'h66e94bd4ef8a2c3b884cfa59ca342b2e);
    run_block(128'h0388dace60b6a392f328c2b971b2fe78, 1'b1, 1'b1);
    run_block(128'h00000000000000000000000000000080, 1'b0, 1'b0);

    load_hash_key(128'hb83b533708bf535d0aa6e52980d53b78);
    reference_y = 128'd0;

    for(random_index = 0; random_index < 64; random_index = random_index + 1)
    begin
        random_block = {$urandom, $urandom, $urandom, $urandom};
        run_block(random_block, (random_index == 0), 1'b0);
    end

    @(posedge clk);
    #1;
    if(done)
    begin
        $display("GHASH16_ERROR done did not clear after one clock");
        error_count = error_count + 1;
    end

    if(error_count == 0)
        $display("GHASH16_PASS tests=%0d digit_cycles=8 external_ii=9", test_count);
    else
        $display("GHASH16_FAIL tests=%0d errors=%0d", test_count, error_count);

    $finish;
end

endmodule
