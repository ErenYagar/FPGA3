`timescale 1ns / 1ps

module GHASH (
    input          clk,
    input          rst_n,
    input          init,
    input  [127:0] GHASH_block,
    input          GHASH_en,
    input  [127:0] H,
    input          H_done,
    output         busy,
    output         done,
    output [127:0] Y
);

localparam ST_IDLE = 1'b0;
localparam ST_MUL  = 1'b1;
localparam [127:0] GF_R = 128'he1000000000000000000000000000000;

reg          state;
reg  [1:0]   step_count;
reg          busy_r;
reg          done_r;
reg          h_valid;
reg  [127:0] h_reg;
reg  [127:0] y_reg;
reg  [127:0] x_work;
reg  [127:0] v_work;
reg  [127:0] z_work;

reg  [127:0] x_next;
reg  [127:0] v_next;
reg  [127:0] z_next;
integer bit_index;

always @(*)
begin
    x_next = x_work;
    v_next = v_work;
    z_next = z_work;

    for(bit_index = 0; bit_index < 32; bit_index = bit_index + 1)
    begin
        if(x_next[127])
            z_next = z_next ^ v_next;

        if(v_next[0])
            v_next = (v_next >> 1) ^ GF_R;
        else
            v_next = v_next >> 1;

        x_next = {x_next[126:0], 1'b0};
    end
end

always @(posedge clk)
begin
    if(!rst_n)
    begin
        state      <= ST_IDLE;
        step_count <= 2'd0;
        busy_r     <= 1'b0;
        done_r     <= 1'b0;
        h_valid    <= 1'b0;
        h_reg      <= 128'd0;
        y_reg      <= 128'd0;
        x_work     <= 128'd0;
        v_work     <= 128'd0;
        z_work     <= 128'd0;
    end
    else
    begin
        done_r <= 1'b0;

        if(H_done)
        begin
            h_reg   <= H;
            h_valid <= 1'b1;
        end

        if(init)
            y_reg <= 128'd0;

        case(state)
            ST_IDLE:
            begin
                busy_r <= 1'b0;

                if(GHASH_en && (h_valid || H_done))
                begin
                    busy_r     <= 1'b1;
                    step_count <= 2'd0;
                    x_work     <= (init ? 128'd0 : y_reg) ^ GHASH_block;
                    v_work     <= H_done ? H : h_reg;
                    z_work     <= 128'd0;
                    state      <= ST_MUL;
                end
            end

            ST_MUL:
            begin
                busy_r <= 1'b1;

                if(step_count == 2'd3)
                begin
                    y_reg      <= z_next;
                    busy_r     <= 1'b0;
                    done_r     <= 1'b1;
                    step_count <= 2'd0;
                    state      <= ST_IDLE;
                end
                else
                begin
                    x_work     <= x_next;
                    v_work     <= v_next;
                    z_work     <= z_next;
                    step_count <= step_count + 2'd1;
                end
            end

            default:
            begin
                state  <= ST_IDLE;
                busy_r <= 1'b0;
            end
        endcase
    end
end

assign busy = busy_r;
assign done = done_r;
assign Y    = y_reg;

endmodule
