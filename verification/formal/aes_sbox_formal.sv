`timescale 1ns/1ps

// Combinational proof harness for the production AES S-box.  The reference
// is algebraic rather than a second lookup table: inversion in GF(2^8) with
// the AES polynomial x^8+x^4+x^3+x+1, followed by the AES affine transform.
module aes_sbox_formal;
    (* anyconst *) logic [7:0] input_a;
    (* anyconst *) logic [7:0] input_b;
    wire [7:0] output_a;
    wire [7:0] output_b;

    sbox #(.REGISTERED(0)) dut_a (
        .clk(1'b0), .rst_n(1'b1), .a(input_a), .co(output_a)
    );

    sbox #(.REGISTERED(0)) dut_b (
        .clk(1'b0), .rst_n(1'b1), .a(input_b), .co(output_b)
    );

    function automatic logic [7:0] gf_multiply(
        input logic [7:0] multiplicand,
        input logic [7:0] multiplier
    );
        logic [7:0] a_work;
        logic [7:0] b_work;
        logic [7:0] product;
        integer i;
        begin
            a_work = multiplicand;
            b_work = multiplier;
            product = 8'd0;
            for (i = 0; i < 8; i = i + 1) begin
                if (b_work[0])
                    product = product ^ a_work;
                a_work = {a_work[6:0], 1'b0} ^
                         (a_work[7] ? 8'h1b : 8'h00);
                b_work = {1'b0, b_work[7:1]};
            end
            gf_multiply = product;
        end
    endfunction

    function automatic logic [7:0] gf_inverse(input logic [7:0] value);
        logic [7:0] base;
        logic [7:0] result;
        integer exponent;
        integer i;
        begin
            // For nonzero x in GF(2^8), x^-1 = x^254.  The same expression
            // naturally maps zero to zero, as required by the AES S-box.
            base = value;
            result = 8'h01;
            exponent = 254;
            for (i = 0; i < 8; i = i + 1) begin
                if (exponent & (1 << i))
                    result = gf_multiply(result, base);
                base = gf_multiply(base, base);
            end
            gf_inverse = (value == 8'h00) ? 8'h00 : result;
        end
    endfunction

    function automatic logic [7:0] aes_affine(input logic [7:0] value);
        begin
            aes_affine = value ^
                         {value[6:0], value[7]} ^
                         {value[5:0], value[7:6]} ^
                         {value[4:0], value[7:5]} ^
                         {value[3:0], value[7:4]} ^
                         8'h63;
        end
    endfunction

    always_comb begin
        assert (output_a == aes_affine(gf_inverse(input_a)));
        assert ((input_a == input_b) || (output_a != output_b));
    end
endmodule
