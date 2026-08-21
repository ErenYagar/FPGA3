`timescale 1ns / 1ps

// UART transport for running NIST GCM .rsp records against aes_gcm_axi_top.
// Host frames are: command, bit_length[15:8], bit_length[7:0], payload.
// Payload bytes use the same MSB-first representation as the CAVP files.
module aes_gcm_uart_rsp_bridge #(
    parameter integer UART_CLKS_PER_BIT = 1519
) (
    input              clk,
    input              aresetn,
    input              uart_rx_i,
    output             uart_tx_o,

    output reg  [2:0]  key_mode,
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

    output      [6:0]  s_axi_araddr,
    output             s_axi_arvalid,
    input              s_axi_arready,
    input       [31:0] s_axi_rdata,
    input       [1:0]  s_axi_rresp,
    input              s_axi_rvalid,
    output             s_axi_rready,

    output      [7:0]  s_axis_tdata,
    output             s_axis_tvalid,
    input              s_axis_tready,
    output             s_axis_tlast,

    input       [7:0]  m_axis_data_tdata,
    input              m_axis_data_tvalid,
    output             m_axis_data_tready,
    input              m_axis_data_tlast,
    input       [3:0]  m_axis_data_tuser,
    input       [7:0]  m_axis_tag_tdata,
    input              m_axis_tag_tvalid,
    output             m_axis_tag_tready,
    input              m_axis_tag_tlast,
    input       [7:0]  m_axis_result_tdata,
    input              m_axis_result_tvalid,
    output             m_axis_result_tready,
    input              m_axis_result_tlast,

    output             busy,
    output reg         last_pass,
    output reg         last_fail
);

localparam [7:0] CMD_MODE = 8'h01;
localparam [7:0] CMD_KEY  = 8'h02;
localparam [7:0] CMD_IV   = 8'h03;
localparam [7:0] CMD_AAD  = 8'h04;
localparam [7:0] CMD_PT   = 8'h05;
localparam [7:0] CMD_CT   = 8'h06;
localparam [7:0] CMD_TAG  = 8'h07;
localparam [7:0] CMD_RUN  = 8'h08;

localparam [7:0] RSP_STATUS = 8'h80;
localparam [7:0] RSP_DATA   = 8'h81;
localparam [7:0] RSP_TAG    = 8'h82;

localparam [7:0] STAT_ENC_OK    = 8'h00;
localparam [7:0] STAT_DEC_OK    = 8'h01;
localparam [7:0] STAT_AUTH_FAIL = 8'hff;
localparam [7:0] STAT_BAD_CFG   = 8'hfe;
localparam [7:0] STAT_BUSY      = 8'hfd;

localparam [1:0] RX_CMD     = 2'd0;
localparam [1:0] RX_LEN_HI  = 2'd1;
localparam [1:0] RX_LEN_LO  = 2'd2;
localparam [1:0] RX_PAYLOAD = 2'd3;

localparam [5:0] ENG_IDLE            = 6'd0;
localparam [5:0] ENG_KEY_WORD        = 6'd1;
localparam [5:0] ENG_KEY_WORD_WAIT   = 6'd2;
localparam [5:0] ENG_KEY_COMMIT      = 6'd3;
localparam [5:0] ENG_KEY_COMMIT_WAIT = 6'd4;
localparam [5:0] ENG_KEY_DELAY       = 6'd5;
localparam [5:0] ENG_CFG             = 6'd6;
localparam [5:0] ENG_CFG_WAIT        = 6'd7;
localparam [5:0] ENG_IV_LEN          = 6'd8;
localparam [5:0] ENG_IV_LEN_WAIT     = 6'd9;
localparam [5:0] ENG_AAD_LEN         = 6'd10;
localparam [5:0] ENG_AAD_LEN_WAIT    = 6'd11;
localparam [5:0] ENG_DATA_LEN        = 6'd12;
localparam [5:0] ENG_DATA_LEN_WAIT   = 6'd13;
localparam [5:0] ENG_CMD_PUSH        = 6'd14;
localparam [5:0] ENG_CMD_PUSH_WAIT   = 6'd15;
localparam [5:0] ENG_STREAM          = 6'd16;
localparam [5:0] ENG_WAIT_RESULT     = 6'd17;
localparam [5:0] ENG_RESPOND         = 6'd18;
localparam [5:0] ENG_COOLDOWN        = 6'd19;

localparam [1:0] FIELD_IV   = 2'd0;
localparam [1:0] FIELD_AAD  = 2'd1;
localparam [1:0] FIELD_DATA = 2'd2;
localparam [1:0] FIELD_TAG  = 2'd3;

localparam [8:0] MEM_IV_BASE   = 9'd0;
localparam [8:0] MEM_AAD_BASE  = 9'd128;
localparam [8:0] MEM_DATA_BASE = 9'd256;
localparam [8:0] MEM_TAG_BASE  = 9'd384;

wire [7:0] rx_data;
wire       rx_valid;
wire       rx_busy;
reg        tx_start_r;
reg [7:0]  tx_data_r;
wire       tx_busy;
wire       tx_done;

uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_rx (
    .clk(clk), .rst(!aresetn), .rx(uart_rx_i), .data(rx_data),
    .data_valid(rx_valid), .busy(rx_busy)
);

uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart_tx (
    .clk(clk), .rst(!aresetn), .start(tx_start_r), .data(tx_data_r),
    .tx(uart_tx_o), .busy(tx_busy), .done(tx_done)
);

reg        mode_cfg_r;
reg        mode_loaded_r;
reg [255:0] key_cfg_r;
reg [8:0]  key_len_r;
reg        key_loaded_r;
reg [10:0] iv_len_r;
reg        iv_loaded_r;
reg [10:0] aad_len_r;
reg        aad_loaded_r;
reg [10:0] pt_len_r;
reg        pt_loaded_r;
reg [10:0] ct_len_r;
reg        ct_loaded_r;
reg [7:0] tag_len_r;
reg        tag_loaded_r;

(* ram_style = "distributed" *) reg [7:0] input_mem [0:399];

reg [1:0]  rx_state_r;
reg [7:0]  rx_cmd_r;
reg [15:0] rx_len_r;
reg [7:0]  rx_payload_bytes_r;
reg [7:0]  rx_byte_index_r;
reg        run_request_r;
reg        status_only_pending_r;
reg [7:0]  status_only_code_r;

reg [5:0] eng_state_r;
reg [3:0] key_word_index_r;
reg [8:0] stream_total_bytes_r;
reg [8:0] stream_field_bytes_r;
reg [1:0] stream_field_r;
reg [8:0] stream_addr_r;
reg [8:0] key_delay_r;
reg [23:0] result_watchdog_r;
reg [3:0] cooldown_r;
reg       capture_active_r;

reg        wr_request_r;
reg [6:0]  wr_address_r;
reg [31:0] wr_value_r;
reg        wr_busy_r;
reg        wr_done_r;
reg        wr_error_r;

(* ram_style = "distributed" *) reg [7:0] data_capture_mem [0:127];
reg [7:0]    data_count_r;
reg          data_done_r;
(* ram_style = "distributed" *) reg [7:0] tag_capture_mem [0:15];
reg [4:0]    tag_count_r;
reg          tag_done_r;
reg [7:0]    expected_data_bytes_r;
reg [4:0]    expected_tag_bytes_r;
reg [3:0]    expected_last_user_r;
reg [7:0]    result_code_r;
reg          result_done_r;
reg          capture_error_r;

reg       frame_active_r;
reg [1:0] frame_phase_r;
reg [7:0] frame_type_r;
reg [15:0] frame_len_r;
reg [7:0] frame_payload_bytes_r;
reg [7:0] frame_byte_index_r;
reg       send_status_pending_r;
reg       send_data_pending_r;
reg       send_tag_pending_r;
reg [7:0] response_status_r;

function integer byte_count_from_bits;
input [15:0] bits;
begin
    if(bits == 16'd0)
        byte_count_from_bits = 0;
    else
        byte_count_from_bits = (bits + 16'd7) / 16'd8;
end
endfunction

function tag_length_allowed;
input [7:0] bits;
begin
    case(bits)
        8'd32, 8'd64, 8'd96, 8'd104, 8'd112, 8'd120, 8'd128:
            tag_length_allowed = 1'b1;
        default:
            tag_length_allowed = 1'b0;
    endcase
end
endfunction

wire run_fields_ready = mode_loaded_r && key_loaded_r && iv_loaded_r &&
                        aad_loaded_r && tag_loaded_r &&
                        (mode_cfg_r ? ct_loaded_r : pt_loaded_r) &&
                        ((key_len_r == 9'd128) || (key_len_r == 9'd192) ||
                         (key_len_r == 9'd256)) &&
                        (iv_len_r != 11'd0) && (iv_len_r <= 11'd1024) &&
                        (aad_len_r <= 11'd1024) &&
                        (mode_cfg_r ? (ct_len_r <= 11'd1024) :
                                      (pt_len_r <= 11'd1024)) &&
                        tag_length_allowed(tag_len_r);

assign s_axi_araddr  = 7'd0;
assign s_axi_arvalid = 1'b0;
assign s_axi_rready  = 1'b0;
assign s_axis_tdata  = input_mem[stream_addr_r];
assign s_axis_tvalid = (eng_state_r == ENG_STREAM);
assign s_axis_tlast  = (eng_state_r == ENG_STREAM) &&
                       (stream_total_bytes_r == 9'd1);
assign m_axis_data_tready   = 1'b1;
assign m_axis_tag_tready    = 1'b1;
assign m_axis_result_tready = 1'b1;
assign busy = (eng_state_r != ENG_IDLE) || frame_active_r || tx_busy || rx_busy;

always @(posedge clk)
begin
    if(!aresetn)
    begin
        key_mode             <= 3'd0;
        s_axi_awaddr         <= 7'd0;
        s_axi_awvalid        <= 1'b0;
        s_axi_wdata          <= 32'd0;
        s_axi_wstrb          <= 4'hf;
        s_axi_wvalid         <= 1'b0;
        s_axi_bready         <= 1'b0;
        mode_cfg_r           <= 1'b0;
        mode_loaded_r        <= 1'b0;
        key_cfg_r            <= 256'd0;
        key_len_r            <= 9'd0;
        key_loaded_r         <= 1'b0;
        iv_len_r             <= 11'd0;
        iv_loaded_r          <= 1'b0;
        aad_len_r            <= 11'd0;
        aad_loaded_r         <= 1'b0;
        pt_len_r             <= 11'd0;
        pt_loaded_r          <= 1'b0;
        ct_len_r             <= 11'd0;
        ct_loaded_r          <= 1'b0;
        tag_len_r            <= 8'd0;
        tag_loaded_r         <= 1'b0;
        rx_state_r           <= RX_CMD;
        rx_cmd_r             <= 8'd0;
        rx_len_r             <= 16'd0;
        rx_payload_bytes_r   <= 8'd0;
        rx_byte_index_r      <= 8'd0;
        run_request_r        <= 1'b0;
        status_only_pending_r<= 1'b0;
        status_only_code_r   <= STAT_BAD_CFG;
        eng_state_r          <= ENG_IDLE;
        key_word_index_r     <= 4'd0;
        stream_total_bytes_r <= 9'd0;
        stream_field_bytes_r <= 9'd0;
        stream_field_r       <= FIELD_IV;
        stream_addr_r        <= MEM_IV_BASE;
        key_delay_r          <= 9'd0;
        result_watchdog_r    <= 24'd0;
        cooldown_r           <= 4'd0;
        capture_active_r     <= 1'b0;
        wr_request_r         <= 1'b0;
        wr_address_r         <= 7'd0;
        wr_value_r           <= 32'd0;
        wr_busy_r            <= 1'b0;
        wr_done_r            <= 1'b0;
        wr_error_r           <= 1'b0;
        data_count_r         <= 8'd0;
        data_done_r          <= 1'b0;
        tag_count_r          <= 5'd0;
        tag_done_r           <= 1'b0;
        expected_data_bytes_r<= 8'd0;
        expected_tag_bytes_r <= 5'd0;
        expected_last_user_r <= 4'd0;
        result_code_r        <= 8'hff;
        result_done_r        <= 1'b0;
        capture_error_r      <= 1'b0;
        tx_start_r           <= 1'b0;
        tx_data_r            <= 8'd0;
        frame_active_r       <= 1'b0;
        frame_phase_r        <= 2'd0;
        frame_type_r         <= 8'd0;
        frame_len_r          <= 16'd0;
        frame_payload_bytes_r<= 8'd0;
        frame_byte_index_r   <= 8'd0;
        send_status_pending_r<= 1'b0;
        send_data_pending_r  <= 1'b0;
        send_tag_pending_r   <= 1'b0;
        response_status_r    <= STAT_BAD_CFG;
        last_pass            <= 1'b0;
        last_fail            <= 1'b0;
    end
    else
    begin
        tx_start_r   <= 1'b0;
        wr_request_r <= 1'b0;
        wr_done_r    <= 1'b0;

        // One-outstanding AXI-Lite write agent. AW and W handshake
        // independently, matching the production register-bank contract.
        if(!wr_busy_r && wr_request_r)
        begin
            s_axi_awaddr  <= wr_address_r;
            s_axi_wdata   <= wr_value_r;
            s_axi_wstrb   <= 4'hf;
            s_axi_awvalid <= 1'b1;
            s_axi_wvalid  <= 1'b1;
            s_axi_bready  <= 1'b1;
            wr_busy_r     <= 1'b1;
            wr_error_r    <= 1'b0;
        end
        if(wr_busy_r)
        begin
            if(s_axi_awvalid && s_axi_awready)
                s_axi_awvalid <= 1'b0;
            if(s_axi_wvalid && s_axi_wready)
                s_axi_wvalid <= 1'b0;
            if(s_axi_bvalid && s_axi_bready)
            begin
                s_axi_bready <= 1'b0;
                wr_busy_r    <= 1'b0;
                wr_done_r    <= 1'b1;
                wr_error_r   <= (s_axi_bresp != 2'b00);
            end
        end

        // UART response-frame serializer.
        if(frame_active_r && !tx_busy && !tx_start_r)
        begin
            case(frame_phase_r)
                2'd0:
                begin
                    tx_data_r     <= frame_type_r;
                    tx_start_r    <= 1'b1;
                    frame_phase_r <= 2'd1;
                end
                2'd1:
                begin
                    tx_data_r     <= frame_len_r[15:8];
                    tx_start_r    <= 1'b1;
                    frame_phase_r <= 2'd2;
                end
                2'd2:
                begin
                    tx_data_r  <= frame_len_r[7:0];
                    tx_start_r <= 1'b1;
                    if(frame_payload_bytes_r == 8'd0)
                    begin
                        frame_active_r <= 1'b0;
                        frame_phase_r  <= 2'd0;
                    end
                    else
                        frame_phase_r <= 2'd3;
                end
                default:
                begin
                    case(frame_type_r)
                        RSP_STATUS: tx_data_r <= response_status_r;
                        RSP_DATA:   tx_data_r <= data_capture_mem[frame_byte_index_r];
                        RSP_TAG:    tx_data_r <= tag_capture_mem[frame_byte_index_r[3:0]];
                        default:    tx_data_r <= 8'd0;
                    endcase
                    tx_start_r <= 1'b1;
                    if(frame_byte_index_r == (frame_payload_bytes_r - 8'd1))
                    begin
                        frame_active_r     <= 1'b0;
                        frame_phase_r      <= 2'd0;
                        frame_byte_index_r <= 8'd0;
                    end
                    else
                        frame_byte_index_r <= frame_byte_index_r + 8'd1;
                end
            endcase
        end

        // Receive and retain one complete CAVP transaction.
        if(rx_valid)
        begin
            case(rx_state_r)
                RX_CMD:
                begin
                    rx_cmd_r   <= rx_data;
                    rx_state_r <= RX_LEN_HI;
                end
                RX_LEN_HI:
                begin
                    rx_len_r[15:8] <= rx_data;
                    rx_state_r     <= RX_LEN_LO;
                end
                RX_LEN_LO:
                begin
                    rx_len_r[7:0]       <= rx_data;
                    rx_payload_bytes_r  <= byte_count_from_bits({rx_len_r[15:8], rx_data});
                    rx_byte_index_r     <= 8'd0;
                    if(byte_count_from_bits({rx_len_r[15:8], rx_data}) == 0)
                    begin
                        rx_state_r <= RX_CMD;
                        case(rx_cmd_r)
                            CMD_AAD:
                            begin
                                aad_len_r    <= 11'd0;
                                aad_loaded_r <= 1'b1;
                            end
                            CMD_PT:
                            begin
                                pt_len_r    <= 11'd0;
                                pt_loaded_r <= 1'b1;
                            end
                            CMD_CT:
                            begin
                                ct_len_r    <= 11'd0;
                                ct_loaded_r <= 1'b1;
                            end
                            CMD_RUN:
                            begin
                                if(eng_state_r != ENG_IDLE)
                                begin
                                    status_only_pending_r <= 1'b1;
                                    status_only_code_r    <= STAT_BUSY;
                                end
                                else if(run_fields_ready)
                                    run_request_r <= 1'b1;
                                else
                                begin
                                    status_only_pending_r <= 1'b1;
                                    status_only_code_r    <= STAT_BAD_CFG;
                                end
                            end
                            default:
                            begin
                            end
                        endcase
                    end
                    else
                    begin
                        rx_state_r <= RX_PAYLOAD;
                        case(rx_cmd_r)
                            CMD_KEY: key_cfg_r <= 256'd0;
                            default:
                            begin
                            end
                        endcase
                    end
                end
                default:
                begin
                    case(rx_cmd_r)
                        CMD_MODE: mode_cfg_r <= rx_data[0];
                        CMD_KEY: key_cfg_r <= {key_cfg_r[247:0], rx_data};
                        CMD_IV:  input_mem[MEM_IV_BASE + rx_byte_index_r] <= rx_data;
                        CMD_AAD: input_mem[MEM_AAD_BASE + rx_byte_index_r] <= rx_data;
                        CMD_PT:  input_mem[MEM_DATA_BASE + rx_byte_index_r] <= rx_data;
                        CMD_CT:  input_mem[MEM_DATA_BASE + rx_byte_index_r] <= rx_data;
                        CMD_TAG: input_mem[MEM_TAG_BASE + rx_byte_index_r] <= rx_data;
                        default:
                        begin
                        end
                    endcase
                    if(rx_byte_index_r == (rx_payload_bytes_r - 8'd1))
                    begin
                        rx_state_r <= RX_CMD;
                        case(rx_cmd_r)
                            CMD_MODE:
                                mode_loaded_r <= (rx_len_r == 16'd8);
                            CMD_KEY:
                            begin
                                key_len_r    <= rx_len_r[8:0];
                                key_loaded_r <= (rx_len_r == 16'd128) ||
                                                (rx_len_r == 16'd192) ||
                                                (rx_len_r == 16'd256);
                                case(rx_len_r)
                                    16'd128:
                                        key_cfg_r <= {key_cfg_r[119:0], rx_data, 128'd0};
                                    16'd192:
                                        key_cfg_r <= {key_cfg_r[183:0], rx_data, 64'd0};
                                    default:
                                        key_cfg_r <= {key_cfg_r[247:0], rx_data};
                                endcase
                            end
                            CMD_IV:
                            begin
                                iv_len_r    <= rx_len_r[10:0];
                                iv_loaded_r <= (rx_len_r <= 16'd1024) &&
                                               (rx_len_r != 16'd0);
                            end
                            CMD_AAD:
                            begin
                                aad_len_r    <= rx_len_r[10:0];
                                aad_loaded_r <= (rx_len_r <= 16'd1024);
                            end
                            CMD_PT:
                            begin
                                pt_len_r    <= rx_len_r[10:0];
                                pt_loaded_r <= (rx_len_r <= 16'd1024);
                            end
                            CMD_CT:
                            begin
                                ct_len_r    <= rx_len_r[10:0];
                                ct_loaded_r <= (rx_len_r <= 16'd1024);
                            end
                            CMD_TAG:
                            begin
                                tag_len_r    <= rx_len_r[7:0];
                                tag_loaded_r <= (rx_len_r <= 16'd128) &&
                                                tag_length_allowed(rx_len_r[7:0]);
                            end
                            default:
                            begin
                            end
                        endcase
                    end
                    else
                        rx_byte_index_r <= rx_byte_index_r + 8'd1;
                end
            endcase
        end

        if(capture_active_r && m_axis_data_tvalid)
        begin
            data_capture_mem[data_count_r] <= m_axis_data_tdata;
            data_count_r   <= data_count_r + 8'd1;
            if(m_axis_data_tlast)
            begin
                data_done_r <= 1'b1;
                if((data_count_r + 8'd1) != expected_data_bytes_r)
                    capture_error_r <= 1'b1;
                if(m_axis_data_tuser != expected_last_user_r)
                    capture_error_r <= 1'b1;
            end
        end
        if(capture_active_r && m_axis_tag_tvalid)
        begin
            tag_capture_mem[tag_count_r[3:0]] <= m_axis_tag_tdata;
            tag_count_r   <= tag_count_r + 5'd1;
            if(m_axis_tag_tlast)
            begin
                tag_done_r <= 1'b1;
                if((tag_count_r + 5'd1) != expected_tag_bytes_r)
                    capture_error_r <= 1'b1;
            end
        end
        if(capture_active_r && m_axis_result_tvalid)
        begin
            if(result_done_r || !m_axis_result_tlast)
                capture_error_r <= 1'b1;
            result_code_r <= m_axis_result_tdata;
            result_done_r <= 1'b1;
        end

        case(eng_state_r)
            ENG_IDLE:
            begin
                cooldown_r <= 4'd0;
                if(status_only_pending_r && !frame_active_r && !tx_busy)
                begin
                    status_only_pending_r <= 1'b0;
                    response_status_r     <= status_only_code_r;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r   <= 1'b0;
                    send_tag_pending_r    <= 1'b0;
                    last_pass             <= 1'b0;
                    last_fail             <= 1'b1;
                    eng_state_r           <= ENG_RESPOND;
                end
                else if(run_request_r && !frame_active_r && !tx_busy)
                begin
                    run_request_r        <= 1'b0;
                    key_mode            <= (key_len_r == 9'd128) ? 3'd0 :
                                           (key_len_r == 9'd192) ? 3'd1 : 3'd2;
                    key_word_index_r     <= 4'd0;
                    stream_total_bytes_r <= byte_count_from_bits({5'd0, iv_len_r}) +
                                            byte_count_from_bits({5'd0, aad_len_r}) +
                                            byte_count_from_bits({5'd0, mode_cfg_r ? ct_len_r : pt_len_r}) +
                                            (mode_cfg_r ? byte_count_from_bits({8'd0, tag_len_r}) : 0);
                    stream_field_r       <= FIELD_IV;
                    stream_field_bytes_r <= byte_count_from_bits({5'd0, iv_len_r});
                    stream_addr_r        <= MEM_IV_BASE;
                    data_count_r         <= 8'd0;
                    data_done_r          <= 1'b0;
                    tag_count_r          <= 5'd0;
                    tag_done_r           <= 1'b0;
                    expected_data_bytes_r<= byte_count_from_bits({5'd0, mode_cfg_r ? ct_len_r : pt_len_r});
                    expected_tag_bytes_r <= byte_count_from_bits({8'd0, tag_len_r});
                    expected_last_user_r <= ((mode_cfg_r ? ct_len_r : pt_len_r) & 11'd7) == 0 ?
                                            4'd8 : (mode_cfg_r ? ct_len_r[3:0] : pt_len_r[3:0]);
                    result_code_r        <= 8'hff;
                    result_done_r        <= 1'b0;
                    capture_error_r      <= 1'b0;
                    capture_active_r     <= 1'b1;
                    result_watchdog_r    <= 24'd0;
                    last_pass            <= 1'b0;
                    last_fail            <= 1'b0;
                    eng_state_r          <= ENG_KEY_WORD;
                end
            end

            ENG_KEY_WORD:
            begin
                wr_address_r <= 7'h20 + {key_word_index_r, 2'b00};
                wr_value_r   <= key_cfg_r[255:224];
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_KEY_WORD_WAIT;
            end
            ENG_KEY_WORD_WAIT:
            begin
                if(wr_done_r)
                begin
                    if(wr_error_r)
                    begin
                        response_status_r <= STAT_BAD_CFG;
                        send_status_pending_r <= 1'b1;
                        capture_active_r <= 1'b0;
                        eng_state_r <= ENG_RESPOND;
                    end
                    else if(key_word_index_r == ((key_len_r >> 5) - 1))
                        eng_state_r <= ENG_KEY_COMMIT;
                    else
                    begin
                        key_word_index_r <= key_word_index_r + 4'd1;
                        key_cfg_r <= {key_cfg_r[223:0], 32'd0};
                        eng_state_r <= ENG_KEY_WORD;
                    end
                end
            end
            ENG_KEY_COMMIT:
            begin
                wr_address_r <= 7'h00;
                wr_value_r   <= 32'h00000002;
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_KEY_COMMIT_WAIT;
            end
            ENG_KEY_COMMIT_WAIT:
            begin
                if(wr_done_r)
                begin
                    if(wr_error_r)
                    begin
                        response_status_r <= STAT_BAD_CFG;
                        send_status_pending_r <= 1'b1;
                        capture_active_r <= 1'b0;
                        eng_state_r <= ENG_RESPOND;
                    end
                    else
                    begin
                        key_delay_r <= 9'd0;
                        eng_state_r <= ENG_KEY_DELAY;
                    end
                end
            end
            ENG_KEY_DELAY:
            begin
                if(key_delay_r == 9'd255)
                    eng_state_r <= ENG_CFG;
                else
                    key_delay_r <= key_delay_r + 9'd1;
            end
            ENG_CFG:
            begin
                wr_address_r <= 7'h08;
                wr_value_r   <= {16'd0, tag_len_r, 7'd0, mode_cfg_r};
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_CFG_WAIT;
            end
            ENG_CFG_WAIT:
            begin
                if(wr_done_r)
                    eng_state_r <= wr_error_r ? ENG_RESPOND : ENG_IV_LEN;
                if(wr_done_r && wr_error_r)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    capture_active_r <= 1'b0;
                end
            end
            ENG_IV_LEN:
            begin
                wr_address_r <= 7'h0c;
                wr_value_r   <= {21'd0, iv_len_r};
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_IV_LEN_WAIT;
            end
            ENG_IV_LEN_WAIT:
            begin
                if(wr_done_r)
                    eng_state_r <= wr_error_r ? ENG_RESPOND : ENG_AAD_LEN;
                if(wr_done_r && wr_error_r)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    capture_active_r <= 1'b0;
                end
            end
            ENG_AAD_LEN:
            begin
                wr_address_r <= 7'h10;
                wr_value_r   <= {21'd0, aad_len_r};
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_AAD_LEN_WAIT;
            end
            ENG_AAD_LEN_WAIT:
            begin
                if(wr_done_r)
                    eng_state_r <= wr_error_r ? ENG_RESPOND : ENG_DATA_LEN;
                if(wr_done_r && wr_error_r)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    capture_active_r <= 1'b0;
                end
            end
            ENG_DATA_LEN:
            begin
                wr_address_r <= 7'h14;
                wr_value_r   <= {21'd0, mode_cfg_r ? ct_len_r : pt_len_r};
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_DATA_LEN_WAIT;
            end
            ENG_DATA_LEN_WAIT:
            begin
                if(wr_done_r)
                    eng_state_r <= wr_error_r ? ENG_RESPOND : ENG_CMD_PUSH;
                if(wr_done_r && wr_error_r)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    capture_active_r <= 1'b0;
                end
            end
            ENG_CMD_PUSH:
            begin
                wr_address_r <= 7'h00;
                wr_value_r   <= 32'h00000001;
                wr_request_r <= 1'b1;
                eng_state_r  <= ENG_CMD_PUSH_WAIT;
            end
            ENG_CMD_PUSH_WAIT:
            begin
                if(wr_done_r)
                begin
                    if(wr_error_r)
                    begin
                        response_status_r <= STAT_BAD_CFG;
                        send_status_pending_r <= 1'b1;
                        capture_active_r <= 1'b0;
                        eng_state_r <= ENG_RESPOND;
                    end
                    else
                    begin
                        stream_field_r <= FIELD_IV;
                        stream_field_bytes_r <= byte_count_from_bits({5'd0, iv_len_r});
                        stream_addr_r <= MEM_IV_BASE;
                        eng_state_r <= ENG_STREAM;
                    end
                end
            end
            ENG_STREAM:
            begin
                if(s_axis_tvalid && s_axis_tready)
                begin
                    if(s_axis_tlast)
                    begin
                        result_watchdog_r <= 24'd0;
                        eng_state_r <= ENG_WAIT_RESULT;
                    end
                    else
                    begin
                        stream_total_bytes_r <= stream_total_bytes_r - 9'd1;
                        if(stream_field_bytes_r != 9'd1)
                        begin
                            stream_field_bytes_r <= stream_field_bytes_r - 9'd1;
                            stream_addr_r <= stream_addr_r + 9'd1;
                        end
                        else
                        begin
                            case(stream_field_r)
                                FIELD_IV:
                                begin
                                    if(aad_len_r != 11'd0)
                                    begin
                                        stream_field_r <= FIELD_AAD;
                                        stream_field_bytes_r <= byte_count_from_bits({5'd0, aad_len_r});
                                        stream_addr_r <= MEM_AAD_BASE;
                                    end
                                    else if((mode_cfg_r ? ct_len_r : pt_len_r) != 11'd0)
                                    begin
                                        stream_field_r <= FIELD_DATA;
                                        stream_field_bytes_r <= byte_count_from_bits({5'd0, mode_cfg_r ? ct_len_r : pt_len_r});
                                        stream_addr_r <= MEM_DATA_BASE;
                                    end
                                    else
                                    begin
                                        stream_field_r <= FIELD_TAG;
                                        stream_field_bytes_r <= byte_count_from_bits({8'd0, tag_len_r});
                                        stream_addr_r <= MEM_TAG_BASE;
                                    end
                                end
                                FIELD_AAD:
                                begin
                                    if((mode_cfg_r ? ct_len_r : pt_len_r) != 11'd0)
                                    begin
                                        stream_field_r <= FIELD_DATA;
                                        stream_field_bytes_r <= byte_count_from_bits({5'd0, mode_cfg_r ? ct_len_r : pt_len_r});
                                        stream_addr_r <= MEM_DATA_BASE;
                                    end
                                    else
                                    begin
                                        stream_field_r <= FIELD_TAG;
                                        stream_field_bytes_r <= byte_count_from_bits({8'd0, tag_len_r});
                                        stream_addr_r <= MEM_TAG_BASE;
                                    end
                                end
                                FIELD_DATA:
                                begin
                                    stream_field_r <= FIELD_TAG;
                                    stream_field_bytes_r <= byte_count_from_bits({8'd0, tag_len_r});
                                    stream_addr_r <= MEM_TAG_BASE;
                                end
                                default:
                                    stream_field_bytes_r <= 9'd0;
                            endcase
                        end
                    end
                end
            end
            ENG_WAIT_RESULT:
            begin
                result_watchdog_r <= result_watchdog_r + 24'd1;
                if(capture_error_r)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= 1'b0;
                    send_tag_pending_r <= 1'b0;
                    capture_active_r <= 1'b0;
                    eng_state_r <= ENG_RESPOND;
                end
                else if(mode_cfg_r && result_done_r && (result_code_r == 8'h02))
                begin
                    response_status_r <= STAT_AUTH_FAIL;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= 1'b0;
                    send_tag_pending_r <= 1'b0;
                    capture_active_r <= 1'b0;
                    last_pass <= 1'b1;
                    last_fail <= 1'b0;
                    eng_state_r <= ENG_RESPOND;
                end
                else if(mode_cfg_r && result_done_r && (result_code_r == 8'h01) &&
                        ((ct_len_r == 11'd0) || data_done_r))
                begin
                    response_status_r <= STAT_DEC_OK;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= (ct_len_r != 11'd0);
                    send_tag_pending_r <= 1'b0;
                    capture_active_r <= 1'b0;
                    last_pass <= 1'b1;
                    last_fail <= 1'b0;
                    eng_state_r <= ENG_RESPOND;
                end
                else if(!mode_cfg_r && result_done_r && (result_code_r == 8'h00) &&
                        ((pt_len_r == 11'd0) || data_done_r) && tag_done_r)
                begin
                    response_status_r <= STAT_ENC_OK;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= (pt_len_r != 11'd0);
                    send_tag_pending_r <= 1'b1;
                    capture_active_r <= 1'b0;
                    last_pass <= 1'b1;
                    last_fail <= 1'b0;
                    eng_state_r <= ENG_RESPOND;
                end
                else if(result_done_r &&
                        !((mode_cfg_r && ((result_code_r == 8'h01) ||
                                          (result_code_r == 8'h02))) ||
                          (!mode_cfg_r && (result_code_r == 8'h00))))
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= 1'b0;
                    send_tag_pending_r <= 1'b0;
                    capture_active_r <= 1'b0;
                    last_pass <= 1'b0;
                    last_fail <= 1'b1;
                    eng_state_r <= ENG_RESPOND;
                end
                else if(result_watchdog_r == 24'hffffff)
                begin
                    response_status_r <= STAT_BAD_CFG;
                    send_status_pending_r <= 1'b1;
                    send_data_pending_r <= 1'b0;
                    send_tag_pending_r <= 1'b0;
                    capture_active_r <= 1'b0;
                    last_pass <= 1'b0;
                    last_fail <= 1'b1;
                    eng_state_r <= ENG_RESPOND;
                end
            end
            ENG_RESPOND:
            begin
                if(!frame_active_r && !tx_busy && !tx_start_r)
                begin
                    if(send_status_pending_r)
                    begin
                        frame_active_r        <= 1'b1;
                        frame_phase_r         <= 2'd0;
                        frame_type_r          <= RSP_STATUS;
                        frame_len_r           <= 16'd8;
                        frame_payload_bytes_r <= 8'd1;
                        frame_byte_index_r    <= 8'd0;
                        send_status_pending_r <= 1'b0;
                    end
                    else if(send_data_pending_r)
                    begin
                        frame_active_r        <= 1'b1;
                        frame_phase_r         <= 2'd0;
                        frame_type_r          <= RSP_DATA;
                        frame_len_r           <= {5'd0, mode_cfg_r ? ct_len_r : pt_len_r};
                        frame_payload_bytes_r <= byte_count_from_bits({5'd0, mode_cfg_r ? ct_len_r : pt_len_r});
                        frame_byte_index_r    <= 8'd0;
                        send_data_pending_r   <= 1'b0;
                    end
                    else if(send_tag_pending_r)
                    begin
                        frame_active_r        <= 1'b1;
                        frame_phase_r         <= 2'd0;
                        frame_type_r          <= RSP_TAG;
                        frame_len_r           <= {8'd0, tag_len_r};
                        frame_payload_bytes_r <= byte_count_from_bits({8'd0, tag_len_r});
                        frame_byte_index_r    <= 8'd0;
                        send_tag_pending_r    <= 1'b0;
                    end
                    else
                    begin
                        cooldown_r  <= 4'd0;
                        eng_state_r <= ENG_COOLDOWN;
                    end
                end
            end
            ENG_COOLDOWN:
            begin
                if(!frame_active_r && !tx_busy)
                begin
                    if(cooldown_r == 4'd8)
                    begin
                        mode_loaded_r <= 1'b0;
                        key_loaded_r  <= 1'b0;
                        iv_loaded_r   <= 1'b0;
                        aad_loaded_r  <= 1'b0;
                        pt_loaded_r   <= 1'b0;
                        ct_loaded_r   <= 1'b0;
                        tag_loaded_r  <= 1'b0;
                        eng_state_r <= ENG_IDLE;
                    end
                    else
                        cooldown_r <= cooldown_r + 4'd1;
                end
                else
                    cooldown_r <= 4'd0;
            end
            default:
                eng_state_r <= ENG_IDLE;
        endcase
    end
end

endmodule
