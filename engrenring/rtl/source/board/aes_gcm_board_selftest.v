`timescale 1ns / 1ps

// Synthesizable power-on known-answer test for the production AXI wrapper.
// The controller encrypts one all-zero block with an all-zero AES-128 key
// and 96-bit all-zero IV, then checks ciphertext, tag, and result streams.
module aes_gcm_board_selftest (
    input              clk,
    input              aresetn,

    output reg  [6:0]  s_axi_awaddr,
    output reg         s_axi_awvalid,
    input              s_axi_awready,
    output reg  [31:0] s_axi_wdata,
    output reg  [3:0]  s_axi_wstrb,
    output reg         s_axi_wvalid,
    input              s_axi_wready,
    input       [1:0]  s_axi_bresp,
    input              s_axi_bvalid,
    output reg         s_axi_bready,

    output reg  [7:0]  s_axis_tdata,
    output reg         s_axis_tvalid,
    input              s_axis_tready,
    output reg         s_axis_tlast,

    input       [7:0]  m_axis_data_tdata,
    input              m_axis_data_tvalid,
    input              m_axis_data_tlast,
    input       [3:0]  m_axis_data_tuser,
    input       [7:0]  m_axis_tag_tdata,
    input              m_axis_tag_tvalid,
    input              m_axis_tag_tlast,
    input       [7:0]  m_axis_result_tdata,
    input              m_axis_result_tvalid,
    input              m_axis_result_tlast,

    output             running,
    output             pass,
    output             fail
);

localparam [4:0] ST_BOOT       = 5'd0;
localparam [4:0] ST_KEY0       = 5'd1;
localparam [4:0] ST_KEY1       = 5'd2;
localparam [4:0] ST_KEY2       = 5'd3;
localparam [4:0] ST_KEY3       = 5'd4;
localparam [4:0] ST_KEY_COMMIT = 5'd5;
localparam [4:0] ST_KEY_WAIT   = 5'd6;
localparam [4:0] ST_CFG        = 5'd7;
localparam [4:0] ST_IV_LEN     = 5'd8;
localparam [4:0] ST_AAD_LEN    = 5'd9;
localparam [4:0] ST_DATA_LEN   = 5'd10;
localparam [4:0] ST_CMD_PUSH   = 5'd11;
localparam [4:0] ST_STREAM     = 5'd12;
localparam [4:0] ST_WAIT_OUT   = 5'd13;
localparam [4:0] ST_PASS       = 5'd14;
localparam [4:0] ST_FAIL       = 5'd15;

reg [4:0] state_r;
reg       write_started_r;
reg [8:0] key_wait_r;
reg [5:0] stream_index_r;
reg [4:0] data_count_r;
reg [4:0] tag_count_r;
reg       data_done_r;
reg       tag_done_r;
reg       result_done_r;
reg       error_r;
reg [23:0] watchdog_r;

function is_write_state;
input [4:0] state;
begin
    case(state)
        ST_KEY0, ST_KEY1, ST_KEY2, ST_KEY3, ST_KEY_COMMIT,
        ST_CFG, ST_IV_LEN, ST_AAD_LEN, ST_DATA_LEN, ST_CMD_PUSH:
            is_write_state = 1'b1;
        default:
            is_write_state = 1'b0;
    endcase
end
endfunction

function [6:0] write_address;
input [4:0] state;
begin
    case(state)
        ST_KEY0:       write_address = 7'h20;
        ST_KEY1:       write_address = 7'h24;
        ST_KEY2:       write_address = 7'h28;
        ST_KEY3:       write_address = 7'h2c;
        ST_KEY_COMMIT: write_address = 7'h00;
        ST_CFG:        write_address = 7'h08;
        ST_IV_LEN:     write_address = 7'h0c;
        ST_AAD_LEN:    write_address = 7'h10;
        ST_DATA_LEN:   write_address = 7'h14;
        ST_CMD_PUSH:   write_address = 7'h00;
        default:       write_address = 7'h00;
    endcase
end
endfunction

function [31:0] write_value;
input [4:0] state;
begin
    case(state)
        ST_KEY0, ST_KEY1, ST_KEY2, ST_KEY3:
            write_value = 32'd0;
        ST_KEY_COMMIT:
            write_value = 32'h00000002;
        ST_CFG:
            write_value = 32'h00008000;
        ST_IV_LEN:
            write_value = 32'd96;
        ST_AAD_LEN:
            write_value = 32'd0;
        ST_DATA_LEN:
            write_value = 32'd128;
        ST_CMD_PUSH:
            write_value = 32'h00000001;
        default:
            write_value = 32'd0;
    endcase
end
endfunction

function [4:0] next_write_state;
input [4:0] state;
begin
    case(state)
        ST_KEY0:       next_write_state = ST_KEY1;
        ST_KEY1:       next_write_state = ST_KEY2;
        ST_KEY2:       next_write_state = ST_KEY3;
        ST_KEY3:       next_write_state = ST_KEY_COMMIT;
        ST_KEY_COMMIT: next_write_state = ST_KEY_WAIT;
        ST_CFG:        next_write_state = ST_IV_LEN;
        ST_IV_LEN:     next_write_state = ST_AAD_LEN;
        ST_AAD_LEN:    next_write_state = ST_DATA_LEN;
        ST_DATA_LEN:   next_write_state = ST_CMD_PUSH;
        ST_CMD_PUSH:   next_write_state = ST_STREAM;
        default:       next_write_state = ST_FAIL;
    endcase
end
endfunction

function [7:0] expected_ciphertext_byte;
input [4:0] index;
begin
    case(index)
        5'd0:  expected_ciphertext_byte = 8'h03;
        5'd1:  expected_ciphertext_byte = 8'h88;
        5'd2:  expected_ciphertext_byte = 8'hda;
        5'd3:  expected_ciphertext_byte = 8'hce;
        5'd4:  expected_ciphertext_byte = 8'h60;
        5'd5:  expected_ciphertext_byte = 8'hb6;
        5'd6:  expected_ciphertext_byte = 8'ha3;
        5'd7:  expected_ciphertext_byte = 8'h92;
        5'd8:  expected_ciphertext_byte = 8'hf3;
        5'd9:  expected_ciphertext_byte = 8'h28;
        5'd10: expected_ciphertext_byte = 8'hc2;
        5'd11: expected_ciphertext_byte = 8'hb9;
        5'd12: expected_ciphertext_byte = 8'h71;
        5'd13: expected_ciphertext_byte = 8'hb2;
        5'd14: expected_ciphertext_byte = 8'hfe;
        5'd15: expected_ciphertext_byte = 8'h78;
        default: expected_ciphertext_byte = 8'h00;
    endcase
end
endfunction

function [7:0] expected_tag_byte;
input [4:0] index;
begin
    case(index)
        5'd0:  expected_tag_byte = 8'hab;
        5'd1:  expected_tag_byte = 8'h6e;
        5'd2:  expected_tag_byte = 8'h47;
        5'd3:  expected_tag_byte = 8'hd4;
        5'd4:  expected_tag_byte = 8'h2c;
        5'd5:  expected_tag_byte = 8'hec;
        5'd6:  expected_tag_byte = 8'h13;
        5'd7:  expected_tag_byte = 8'hbd;
        5'd8:  expected_tag_byte = 8'hf5;
        5'd9:  expected_tag_byte = 8'h3a;
        5'd10: expected_tag_byte = 8'h67;
        5'd11: expected_tag_byte = 8'hb2;
        5'd12: expected_tag_byte = 8'h12;
        5'd13: expected_tag_byte = 8'h57;
        5'd14: expected_tag_byte = 8'hbd;
        5'd15: expected_tag_byte = 8'hdf;
        default: expected_tag_byte = 8'h00;
    endcase
end
endfunction

assign running = (state_r != ST_PASS) && (state_r != ST_FAIL);
assign pass = (state_r == ST_PASS);
assign fail = (state_r == ST_FAIL);

always @(posedge clk)
begin
    if(!aresetn)
    begin
        state_r          <= ST_BOOT;
        write_started_r  <= 1'b0;
        s_axi_awaddr     <= 7'd0;
        s_axi_awvalid    <= 1'b0;
        s_axi_wdata      <= 32'd0;
        s_axi_wstrb      <= 4'hf;
        s_axi_wvalid     <= 1'b0;
        s_axi_bready     <= 1'b0;
        s_axis_tdata     <= 8'd0;
        s_axis_tvalid    <= 1'b0;
        s_axis_tlast     <= 1'b0;
        key_wait_r       <= 9'd0;
        stream_index_r   <= 6'd0;
        data_count_r     <= 5'd0;
        tag_count_r      <= 5'd0;
        data_done_r      <= 1'b0;
        tag_done_r       <= 1'b0;
        result_done_r    <= 1'b0;
        error_r          <= 1'b0;
        watchdog_r       <= 24'd0;
    end
    else
    begin
        if(state_r == ST_BOOT)
            state_r <= ST_KEY0;

        if(is_write_state(state_r))
        begin
            if(!write_started_r)
            begin
                s_axi_awaddr    <= write_address(state_r);
                s_axi_wdata     <= write_value(state_r);
                s_axi_wstrb     <= 4'hf;
                s_axi_awvalid   <= 1'b1;
                s_axi_wvalid    <= 1'b1;
                s_axi_bready    <= 1'b1;
                write_started_r <= 1'b1;
            end
            else
            begin
                if(s_axi_awvalid && s_axi_awready)
                    s_axi_awvalid <= 1'b0;
                if(s_axi_wvalid && s_axi_wready)
                    s_axi_wvalid <= 1'b0;
                if(s_axi_bvalid && s_axi_bready)
                begin
                    s_axi_bready    <= 1'b0;
                    write_started_r <= 1'b0;
                    if(s_axi_bresp != 2'b00)
                        error_r <= 1'b1;
                    else
                        state_r <= next_write_state(state_r);
                end
            end
        end

        if(state_r == ST_KEY_WAIT)
        begin
            if(key_wait_r == 9'd255)
            begin
                key_wait_r <= 9'd0;
                state_r <= ST_CFG;
            end
            else
                key_wait_r <= key_wait_r + 9'd1;
        end

        if(state_r == ST_STREAM)
        begin
            if(!s_axis_tvalid)
            begin
                s_axis_tdata  <= 8'd0;
                s_axis_tvalid <= 1'b1;
                s_axis_tlast  <= (stream_index_r == 6'd27);
            end
            else if(s_axis_tready)
            begin
                if(stream_index_r == 6'd27)
                begin
                    s_axis_tvalid <= 1'b0;
                    s_axis_tlast  <= 1'b0;
                    state_r       <= ST_WAIT_OUT;
                end
                else
                begin
                    stream_index_r <= stream_index_r + 6'd1;
                    s_axis_tlast <= (stream_index_r == 6'd26);
                end
            end
        end

        if(m_axis_data_tvalid)
        begin
            if((data_count_r >= 5'd16) ||
               (m_axis_data_tdata != expected_ciphertext_byte(data_count_r)) ||
               (m_axis_data_tlast != (data_count_r == 5'd15)) ||
               (m_axis_data_tuser != ((data_count_r == 5'd15) ? 4'd8 : 4'd0)))
                error_r <= 1'b1;
            if(m_axis_data_tlast)
                data_done_r <= 1'b1;
            data_count_r <= data_count_r + 5'd1;
        end

        if(m_axis_tag_tvalid)
        begin
            if((tag_count_r >= 5'd16) ||
               (m_axis_tag_tdata != expected_tag_byte(tag_count_r)) ||
               (m_axis_tag_tlast != (tag_count_r == 5'd15)))
                error_r <= 1'b1;
            if(m_axis_tag_tlast)
                tag_done_r <= 1'b1;
            tag_count_r <= tag_count_r + 5'd1;
        end

        if(m_axis_result_tvalid)
        begin
            if(result_done_r || (m_axis_result_tdata != 8'h00) ||
               !m_axis_result_tlast)
                error_r <= 1'b1;
            result_done_r <= 1'b1;
        end

        if((state_r == ST_STREAM) || (state_r == ST_WAIT_OUT))
        begin
            if(watchdog_r == 24'hffffff)
                error_r <= 1'b1;
            else
                watchdog_r <= watchdog_r + 24'd1;
        end
        else
            watchdog_r <= 24'd0;

        if((state_r == ST_WAIT_OUT) && data_done_r && tag_done_r &&
           result_done_r && !error_r)
            state_r <= ST_PASS;

        if(error_r)
        begin
            s_axis_tvalid <= 1'b0;
            state_r <= ST_FAIL;
        end
    end
end

endmodule
