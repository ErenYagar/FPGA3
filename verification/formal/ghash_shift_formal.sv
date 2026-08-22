`timescale 1ns/1ps

// Tool-neutral combinational harness. A version-specific formal adapter may
// select this module as top after the tool has been detected and queried.
module ghash_shift_formal;
    (* anyconst *) logic [127:0] value;
    wire [127:0] direct [0:16];

    function automatic logic [127:0] shift_one(input logic [127:0] v);
        shift_one = {1'b0, v[127:1]} ^
                    (v[0] ? 128'he1000000000000000000000000000000 : 128'd0);
    endfunction

    function automatic logic [127:0] repeated_shift(
        input logic [127:0] v,
        input integer count
    );
        logic [127:0] work;
        integer i;
        begin
            work = v;
            for (i = 0; i < count; i = i + 1)
                work = shift_one(work);
            repeated_shift = work;
        end
    endfunction

    genvar k;
    generate
        for (k = 0; k <= 16; k = k + 1) begin : g_power
            ghash16_gf_shift_power #(.POWER(k)) dut (
                .value(value), .transformed(direct[k])
            );
            always_comb assert (direct[k] == repeated_shift(value, k));
        end
    endgenerate
endmodule
