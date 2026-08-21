`timescale 1ns / 1ps

module tb_aes_gcm_uart_rsp;

localparam integer CLKS_PER_BIT = 8;

reg clk = 1'b0;
reg aresetn = 1'b0;
reg uart_rx = 1'b1;
wire uart_tx;
always #2.857 clk = ~clk;

wire [2:0] key_mode;
wire [6:0] awaddr;
wire awvalid;
wire awready;
wire [31:0] wdata;
wire [3:0] wstrb;
wire wvalid;
wire wready;
wire [1:0] bresp;
wire bvalid;
wire bready;
wire [6:0] araddr;
wire arvalid;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
wire rready;
wire [7:0] s_data;
wire s_valid;
wire s_ready;
wire s_last;
wire [7:0] data_out;
wire data_valid;
wire data_ready;
wire data_last;
wire [3:0] data_user;
wire [7:0] tag_out;
wire tag_valid;
wire tag_ready;
wire tag_last;
wire [7:0] result_out;
wire result_valid;
wire result_ready;
wire result_last;
wire bridge_busy;
wire last_pass;
wire last_fail;

aes_gcm_uart_rsp_bridge #(
    .UART_CLKS_PER_BIT(CLKS_PER_BIT)
) u_bridge (
    .clk(clk), .aresetn(aresetn), .uart_rx_i(uart_rx), .uart_tx_o(uart_tx),
    .key_mode(key_mode), .s_axi_awaddr(awaddr),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
    .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready), .s_axi_araddr(araddr),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .s_axis_tdata(s_data),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid), .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last), .busy(bridge_busy),
    .last_pass(last_pass), .last_fail(last_fail)
);

aes_gcm_axi_top #(.ALLOW_NIST_TAG_LENGTHS(1'b1)) u_dut (
    .aclk(clk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
    .s_axi_wready(wready), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready), .s_axi_araddr(araddr), .s_axi_arprot(3'd0),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .s_axis_tdata(s_data),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid), .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

task automatic uart_send_byte;
input [7:0] value;
integer bit_index;
begin
    @(negedge clk);
    uart_rx = 1'b0;
    repeat(CLKS_PER_BIT) @(posedge clk);
    for(bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
    begin
        @(negedge clk);
        uart_rx = value[bit_index];
        repeat(CLKS_PER_BIT) @(posedge clk);
    end
    @(negedge clk);
    uart_rx = 1'b1;
    repeat(CLKS_PER_BIT) @(posedge clk);
end
endtask

task automatic uart_recv_byte;
output [7:0] value;
integer bit_index;
reg [7:0] captured;
begin
    @(negedge uart_tx);
    repeat(CLKS_PER_BIT / 2) @(posedge clk);
    if(uart_tx !== 1'b0)
        $fatal(1, "UART false start");
    for(bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
    begin
        repeat(CLKS_PER_BIT) @(posedge clk);
        captured[bit_index] = uart_tx;
    end
    repeat(CLKS_PER_BIT) @(posedge clk);
    if(uart_tx !== 1'b1)
        $fatal(1, "UART bad stop bit");
    value = captured;
end
endtask

task automatic send_packet;
input [7:0] command;
input integer bit_length;
input [2047:0] payload;
integer byte_count;
integer byte_index;
integer bit_index;
begin
    uart_send_byte(command);
    uart_send_byte(bit_length[15:8]);
    uart_send_byte(bit_length[7:0]);
    byte_count = (bit_length + 7) / 8;
    for(byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
    begin
        bit_index = byte_count * 8 - 1 - byte_index * 8;
        uart_send_byte(payload[bit_index -: 8]);
    end
end
endtask

task automatic recv_frame;
output [7:0] frame_type;
output integer bit_length;
output [2047:0] payload;
reg [7:0] byte_value;
reg [7:0] length_hi;
reg [7:0] length_lo;
reg [2047:0] captured;
integer byte_count;
integer byte_index;
begin
    captured = 2048'd0;
    uart_recv_byte(frame_type);
    uart_recv_byte(length_hi);
    uart_recv_byte(length_lo);
    bit_length = {length_hi, length_lo};
    byte_count = (bit_length + 7) / 8;
    for(byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
    begin
        uart_recv_byte(byte_value);
        captured = {captured[2039:0], byte_value};
    end
    payload = captured;
end
endtask

task automatic run_case;
input integer decrypt_mode;
input integer key_bits;
input [2047:0] key_value;
input integer iv_bits;
input [2047:0] iv_value;
input integer aad_bits;
input [2047:0] aad_value;
input integer data_bits;
input [2047:0] input_data;
input integer tag_bits;
input [2047:0] input_tag;
input [7:0] expected_status;
input [2047:0] expected_data;
input [2047:0] expected_tag;
reg [7:0] frame_type;
integer frame_bits;
reg [2047:0] frame_payload;
integer iv_byte_count;
integer iv_byte_index;
begin
    send_packet(8'h01, 8, decrypt_mode);
    send_packet(8'h02, key_bits, key_value);
    send_packet(8'h03, iv_bits, iv_value);
    send_packet(8'h04, aad_bits, aad_value);
    send_packet(decrypt_mode ? 8'h06 : 8'h05, data_bits, input_data);
    send_packet(8'h07, tag_bits, decrypt_mode ? input_tag : 2048'd0);
    if(u_bridge.key_cfg_r !==
       (key_value[255:0] << (256 - key_bits)))
        $fatal(1, "UART key buffer mismatch bits=%0d got=%064x expected=%064x",
               key_bits, u_bridge.key_cfg_r,
               (key_value[255:0] << (256 - key_bits)));
    iv_byte_count = (iv_bits + 7) / 8;
    for(iv_byte_index = 0; iv_byte_index < iv_byte_count;
        iv_byte_index = iv_byte_index + 1)
        if(u_bridge.input_mem[iv_byte_index] !==
           iv_value[iv_byte_count*8-1-iv_byte_index*8 -: 8])
            $fatal(1, "UART IV buffer mismatch bits=%0d byte=%0d",
                   iv_bits, iv_byte_index);
    send_packet(8'h08, 0, 2048'd0);

    recv_frame(frame_type, frame_bits, frame_payload);
    if(frame_type !== 8'h80 || frame_bits != 8 ||
       frame_payload[7:0] !== expected_status)
        $fatal(1, "STATUS mismatch type=%02x bits=%0d got=%02x expected=%02x",
               frame_type, frame_bits, frame_payload[7:0], expected_status);

    if((expected_status == 8'h00) && (data_bits != 0))
    begin
        recv_frame(frame_type, frame_bits, frame_payload);
        if(frame_type !== 8'h81 || frame_bits != data_bits ||
           frame_payload !== expected_data)
            $fatal(1, "encrypt DATA mismatch type=%02x bits=%0d got=%h expected=%h",
                   frame_type, frame_bits, frame_payload, expected_data);
    end
    else if((expected_status == 8'h01) && (data_bits != 0))
    begin
        recv_frame(frame_type, frame_bits, frame_payload);
        if(frame_type !== 8'h81 || frame_bits != data_bits ||
           frame_payload !== expected_data)
            $fatal(1, "decrypt DATA mismatch type=%02x bits=%0d got=%h expected=%h",
                   frame_type, frame_bits, frame_payload, expected_data);
    end

    if(expected_status == 8'h00)
    begin
        recv_frame(frame_type, frame_bits, frame_payload);
        if(frame_type !== 8'h82 || frame_bits != tag_bits ||
           frame_payload !== expected_tag)
            $fatal(1, "TAG mismatch type=%02x bits=%0d got=%h expected=%h",
                   frame_type, frame_bits, frame_payload, expected_tag);
    end
    repeat(100) @(posedge clk);
end
endtask

initial
begin
    repeat(20) @(posedge clk);
    aresetn = 1'b1;
    repeat(20) @(posedge clk);

    run_case(0, 128, 128'h00000000000000000000000000000000,
             96, 96'h000000000000000000000000,
             0, 0, 128, 128'h00000000000000000000000000000000,
             128, 0, 8'h00,
             128'h0388dace60b6a392f328c2b971b2fe78,
             128'hab6e47d42cec13bdf53a67b21257bddf);

    run_case(0, 192, 192'haa740abfadcda779220d3b406c5d7ec09a77fe9d94104539,
             96, 96'hab2265b4c168955561f04315,
             0, 0, 0, 0, 128, 0, 8'h00, 0,
             128'hf149e2b5f0adaa9842ca5f45b768a8fc);

    run_case(0, 256, 256'hb52c505a37d78eda5dd34f20c22540ea1b58963cf8e5bf8ffa85f9f2492505b4,
             96, 96'h516c33929df5a3284ff463d7,
             0, 0, 0, 0, 128, 0, 8'h00, 0,
             128'hbdc1ac884d332457a1d2664f168c76f0);

    run_case(1, 128, 128'hcf063a34d4a9a76c2c86787d3f96db71,
             96, 96'h113b9785971864c83b01c787,
             0, 0, 0, 0, 128,
             128'h72ac8493e3a5228b5d130a69d2510e42,
             8'h01, 0, 0);

    run_case(1, 128, 128'ha49a5e26a2f8cb63d05546c2a62f5343,
             96, 96'h907763b19b9b4ab6bd4f0281,
             0, 0, 0, 0, 128,
             128'ha2be08210d8c470a8df6e8fbd79ec5cf,
             8'hff, 0, 0);

    run_case(1, 128, 128'h00000000000000000000000000000000,
             96, 96'h000000000000000000000000,
             0, 0, 128, 128'h0388dace60b6a392f328c2b971b2fe78,
             128, 128'hab6e47d42cec13bdf53a67b21257bddf,
             8'h01, 128'h00000000000000000000000000000000, 0);

    $display("UART_RSP_PROTOCOL_PASS cases=6");
    $finish;
end

initial
begin
    repeat(2000000) @(posedge clk);
    $fatal(1, "UART RSP protocol timeout");
end

endmodule
