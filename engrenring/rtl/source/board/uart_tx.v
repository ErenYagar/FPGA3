`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLKS_PER_BIT = 1519
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done
);

localparam [2:0] ST_IDLE  = 3'd0;
localparam [2:0] ST_START = 3'd1;
localparam [2:0] ST_DATA  = 3'd2;
localparam [2:0] ST_STOP  = 3'd3;

reg [2:0]  state;
reg [7:0]  shreg;
reg [3:0]  bit_idx;
reg [15:0] clk_cnt;

always @(posedge clk)
begin
    if(rst)
    begin
        state   <= ST_IDLE;
        shreg   <= 8'd0;
        bit_idx <= 4'd0;
        clk_cnt <= 16'd0;
        tx      <= 1'b1;
        busy    <= 1'b0;
        done    <= 1'b0;
    end
    else
    begin
        done <= 1'b0;
        case(state)
            ST_IDLE:
            begin
                tx      <= 1'b1;
                busy    <= 1'b0;
                clk_cnt <= 16'd0;
                bit_idx <= 4'd0;
                if(start)
                begin
                    shreg <= data;
                    busy  <= 1'b1;
                    state <= ST_START;
                end
            end

            ST_START:
            begin
                tx <= 1'b0;
                if(clk_cnt == (CLKS_PER_BIT - 1))
                begin
                    clk_cnt <= 16'd0;
                    state   <= ST_DATA;
                end
                else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            ST_DATA:
            begin
                tx <= shreg[bit_idx];
                if(clk_cnt == (CLKS_PER_BIT - 1))
                begin
                    clk_cnt <= 16'd0;
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
                tx <= 1'b1;
                if(clk_cnt == (CLKS_PER_BIT - 1))
                begin
                    clk_cnt <= 16'd0;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    state   <= ST_IDLE;
                end
                else
                    clk_cnt <= clk_cnt + 16'd1;
            end

            default:
                state <= ST_IDLE;
        endcase
    end
end

endmodule
