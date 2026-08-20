`timescale 1ns / 1ps

// Small synchronous ready/valid FIFO. DEPTH must be a power of two.
module stream_fifo #(
    parameter integer WIDTH = 8,
    parameter integer DEPTH = 4,
    parameter integer ADDR_W = 2
)(
    input                  clk,
    input                  rst_n,
    input                  clear,
    input      [WIDTH-1:0] in_data,
    input                  in_valid,
    output                 in_ready,
    output     [WIDTH-1:0] out_data,
    output                 out_valid,
    input                  out_ready,
    output     [ADDR_W:0]  count
);

reg [WIDTH-1:0] mem [0:DEPTH-1];
reg [ADDR_W-1:0] wr_ptr;
reg [ADDR_W-1:0] rd_ptr;
reg [ADDR_W:0] count_r;
reg [WIDTH-1:0] out_data_q;

wire push = in_valid && in_ready;
wire pop  = out_valid && out_ready;

// DEPTH is 2**ADDR_W, so only the count MSB is set at the full value.
// Keeping the lower count bits out of push localizes every RAM write enable.
assign in_ready = !count_r[ADDR_W];
assign out_valid = (count_r != 0);
// Register the head so the RAM/pointer selection never feeds the consumer's
// wide control/data mux in the same cycle.  Consecutive pops remain bubble
// free because the next head is prefetched at the pop edge.
assign out_data = out_data_q;
assign count = count_r;

always @(posedge clk)
begin
    if(!rst_n)
    begin
        wr_ptr  <= {ADDR_W{1'b0}};
        rd_ptr  <= {ADDR_W{1'b0}};
        count_r <= {(ADDR_W+1){1'b0}};
        out_data_q <= {WIDTH{1'b0}};
    end
    else if(clear)
    begin
        wr_ptr  <= {ADDR_W{1'b0}};
        rd_ptr  <= {ADDR_W{1'b0}};
        count_r <= {(ADDR_W+1){1'b0}};
        out_data_q <= {WIDTH{1'b0}};
    end
    else
    begin
        if(push)
        begin
            mem[wr_ptr] <= in_data;
            wr_ptr <= wr_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};
        end

        if(pop)
            rd_ptr <= rd_ptr + {{(ADDR_W-1){1'b0}}, 1'b1};

        if(push && (count_r == 0))
            out_data_q <= in_data;
        else if(pop && (count_r > 1))
            out_data_q <= mem[rd_ptr +
                              {{(ADDR_W-1){1'b0}}, 1'b1}];
        else if(pop && push && (count_r == 1))
            out_data_q <= in_data;

        case({push, pop})
            2'b10: count_r <= count_r + {{ADDR_W{1'b0}}, 1'b1};
            2'b01: count_r <= count_r - {{ADDR_W{1'b0}}, 1'b1};
            default: count_r <= count_r;
        endcase
    end
end

endmodule
