`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLKS_PER_BIT = 1519
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        data_valid,
    output reg        busy
);

localparam [1:0] ST_IDLE  = 2'd0;
localparam [1:0] ST_START = 2'd1;
localparam [1:0] ST_DATA  = 2'd2;
localparam [1:0] ST_STOP  = 2'd3;

reg [1:0]  state;
reg [15:0] clk_cnt;
reg [3:0]  bit_idx;
reg [7:0]  shreg;
reg        rx_meta;
reg        rx_sync;

always @(posedge clk)
begin
    if(rst)
    begin
        state      <= ST_IDLE;
        clk_cnt    <= 16'd0;
        bit_idx    <= 4'd0;
        shreg      <= 8'd0;
        data       <= 8'd0;
        data_valid <= 1'b0;
        busy       <= 1'b0;
        rx_meta    <= 1'b1;
        rx_sync    <= 1'b1;
    end
    else
    begin
        data_valid <= 1'b0;
        rx_meta    <= rx;
        rx_sync    <= rx_meta;

        case(state)
            ST_IDLE:
            begin
                clk_cnt <= 16'd0;
                bit_idx <= 4'd0;
                busy    <= 1'b0;
                if(!rx_sync)
                begin
                    state   <= ST_START;
                    busy    <= 1'b1;
                    clk_cnt <= 16'd0;
                end
            end

            ST_START:
            begin
                if(clk_cnt == ((CLKS_PER_BIT - 1) / 2))
                begin
                    if(!rx_sync)
                    begin
                        clk_cnt <= 16'd0;
                        state   <= ST_DATA;
                        bit_idx <= 4'd0;
                    end
                    else
                    begin
                        state <= ST_IDLE;
                        busy  <= 1'b0;
                    end
                end
                else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            ST_DATA:
            begin
                if(clk_cnt == (CLKS_PER_BIT - 1))
                begin
                    clk_cnt       <= 16'd0;
                    shreg[bit_idx] <= rx_sync;
                    if(bit_idx == 4'd7)
                    begin
                        bit_idx <= 4'd0;
                        state   <= ST_STOP;
                    end
                    else
                        bit_idx <= bit_idx + 4'd1;
                end
                else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            ST_STOP:
            begin
                if(clk_cnt == (CLKS_PER_BIT - 1))
                begin
                    state      <= ST_IDLE;
                    clk_cnt    <= 16'd0;
                    data       <= shreg;
                    data_valid <= 1'b1;
                    busy       <= 1'b0;
                end
                else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            default:
            begin
                state <= ST_IDLE;
                busy  <= 1'b0;
            end
        endcase
    end
end

endmodule
