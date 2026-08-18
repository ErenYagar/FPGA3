`timescale 1ns / 1ps

module tb_throughput;

localparam integer PACKETS = 100;
localparam integer DATA_BYTES = 128;
localparam integer TAG_BYTES = 16;
localparam [1:0] OKAY = 2'b00;

reg aclk = 0;
always #2.5 aclk = ~aclk;
reg aresetn = 0;
reg [2:0] key_mode = 0;

reg [6:0] awaddr;
reg [2:0] awprot = 0;
reg awvalid;
wire awready;
reg [31:0] wdata;
reg [3:0] wstrb;
reg wvalid;
wire wready;
wire [1:0] bresp;
wire bvalid;
reg bready;
reg [6:0] araddr;
reg [2:0] arprot = 0;
reg arvalid;
wire arready;
wire [31:0] rdata;
wire [1:0] rresp;
wire rvalid;
reg rready;

reg [7:0] s_data;
reg s_valid;
wire s_ready;
reg s_last;
wire [7:0] data_out;
wire data_valid;
reg data_ready = 1;
wire data_last;
wire [3:0] data_user;
wire [7:0] tag_out;
wire tag_valid;
reg tag_ready = 1;
wire tag_last;
wire [7:0] result_out;
wire result_valid;
reg result_ready = 1;
wire result_last;

aes_gcm_axi_top dut (
    .aclk(aclk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arprot(arprot),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp),
    .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid),
    .s_axis_tready(s_ready), .s_axis_tlast(s_last),
    .m_axis_data_tdata(data_out), .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last), .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid),
    .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

reg [7:0] ciphertext [0:PACKETS*DATA_BYTES-1];
reg [7:0] tags [0:PACKETS*TAG_BYTES-1];
integer cycle_count;
integer data_count;
integer tag_count;
integer result_count;
integer measure_start;
integer measure_end;
integer run_phase;
integer error_count;

always @(posedge aclk)
begin
    cycle_count <= cycle_count + 1;
    if(data_valid && data_ready)
    begin
        if(run_phase == 1)
            ciphertext[data_count] <= data_out;
        else if((run_phase == 2) && (data_out !== 8'h00))
        begin
            $display("DECRYPT_DATA_ERROR index=%0d value=%02x", data_count,
                     data_out);
            error_count <= error_count + 1;
        end
        data_count <= data_count + 1;
        if((run_phase == 2) && (data_count + 1 == PACKETS*DATA_BYTES))
            measure_end <= cycle_count;
    end
    if(tag_valid && tag_ready)
    begin
        if(run_phase == 1)
            tags[tag_count] <= tag_out;
        tag_count <= tag_count + 1;
    end
    if(result_valid && result_ready)
    begin
        if(((run_phase == 1) && (result_out != 8'h00)) ||
           ((run_phase == 2) && (result_out != 8'h01)))
        begin
            $display("RESULT_ERROR phase=%0d packet=%0d code=%02x",
                     run_phase, result_count, result_out);
            error_count <= error_count + 1;
        end
        result_count <= result_count + 1;
        if((run_phase == 1) && (result_count + 1 == PACKETS))
            measure_end <= cycle_count;
    end
end

task axi_write;
input [6:0] address;
input [31:0] value;
reg aw_done;
reg w_done;
begin
    @(negedge aclk);
    awaddr = address;
    awvalid = 1;
    wdata = value;
    wstrb = 4'hf;
    wvalid = 1;
    bready = 1;
    aw_done = 0;
    w_done = 0;
    while(!(aw_done && w_done))
    begin
        @(posedge aclk);
        if(awvalid && awready) aw_done = 1;
        if(wvalid && wready) w_done = 1;
        @(negedge aclk);
        if(aw_done) awvalid = 0;
        if(w_done) wvalid = 0;
    end
    while(!bvalid) @(posedge aclk);
    if(bresp !== OKAY)
        $fatal(1, "AXI_WRITE_FAILED addr=%02x response=%b", address, bresp);
    @(negedge aclk);
    bready = 0;
end
endtask

task axi_read;
input [6:0] address;
output [31:0] value;
begin
    @(negedge aclk);
    araddr = address;
    arvalid = 1;
    rready = 1;
    while(!(arvalid && arready)) @(posedge aclk);
    @(negedge aclk);
    arvalid = 0;
    while(!rvalid) @(posedge aclk);
    if(rresp !== OKAY)
        $fatal(1, "AXI_READ_FAILED addr=%02x response=%b", address, rresp);
    value = rdata;
    @(negedge aclk);
    rready = 0;
end
endtask

task send_byte;
input [7:0] value;
input is_last;
begin
    s_data = value;
    s_last = is_last;
    s_valid = 1;
    while(!(s_valid && s_ready)) @(posedge aclk);
    if(measure_start < 0)
        measure_start = cycle_count;
    @(negedge aclk);
    s_valid = 0;
    s_last = 0;
end
endtask

task send_iv;
input integer packet_number;
integer byte_number;
begin
    for(byte_number = 0; byte_number < 8; byte_number = byte_number + 1)
        send_byte(8'h00, 1'b0);
    send_byte(packet_number[31:24], 1'b0);
    send_byte(packet_number[23:16], 1'b0);
    send_byte(packet_number[15:8], 1'b0);
    send_byte(packet_number[7:0], 1'b0);
end
endtask

task wait_key_ready;
reg [31:0] status;
begin
    status = 0;
    while(!status[0]) axi_read(7'h04, status);
end
endtask

task load_zero_key;
input [2:0] selected_mode;
integer word_number;
begin
    key_mode = selected_mode;
    for(word_number = 0; word_number < 8; word_number = word_number + 1)
        axi_write(7'h20 + word_number*4, 32'd0);
    axi_write(7'h00, 32'h00000002);
    wait_key_ready();
end
endtask

task configure_record;
input decrypt;
begin
    axi_write(7'h08, {16'd0, 8'd128, 7'd0, decrypt});
    axi_write(7'h0c, 32'd96);
    axi_write(7'h10, 32'd0);
    axi_write(7'h14, 32'd1024);
end
endtask

task clear_measurement;
input integer phase_value;
begin
    @(negedge aclk);
    run_phase = phase_value;
    data_count = 0;
    tag_count = 0;
    result_count = 0;
    measure_start = -1;
    measure_end = -1;
end
endtask

task run_encrypt;
integer packet_number;
integer byte_number;
integer elapsed;
real throughput;
begin
    configure_record(1'b0);
    clear_measurement(1);
    for(packet_number = 0; packet_number < PACKETS; packet_number = packet_number + 1)
    begin
        axi_write(7'h00, 32'h00000001);
        send_iv(packet_number + 1);
        for(byte_number = 0; byte_number < DATA_BYTES; byte_number = byte_number + 1)
            send_byte(8'h00, byte_number == DATA_BYTES-1);
    end
    while(result_count != PACKETS) @(posedge aclk);
    elapsed = measure_end - measure_start + 1;
    throughput = (PACKETS * 1024.0 * 0.2) / elapsed;
    $display("THROUGHPUT mode=AES-%0d direction=encrypt cycles=%0d gbps=%0.6f",
             (key_mode == 0) ? 128 : ((key_mode == 1) ? 192 : 256),
             elapsed, throughput);
    if(throughput < 1.0)
        $fatal(1, "ENCRYPT_THROUGHPUT_BELOW_1GBPS");
    if(data_count != PACKETS*DATA_BYTES || tag_count != PACKETS*TAG_BYTES)
        $fatal(1, "ENCRYPT_OUTPUT_COUNT_ERROR data=%0d tag=%0d",
               data_count, tag_count);
end
endtask

task run_decrypt;
integer packet_number;
integer byte_number;
integer elapsed;
real throughput;
begin
    configure_record(1'b1);
    clear_measurement(2);
    for(packet_number = 0; packet_number < PACKETS; packet_number = packet_number + 1)
    begin
        axi_write(7'h00, 32'h00000001);
        send_iv(packet_number + 1);
        for(byte_number = 0; byte_number < DATA_BYTES; byte_number = byte_number + 1)
            send_byte(ciphertext[packet_number*DATA_BYTES + byte_number], 1'b0);
        for(byte_number = 0; byte_number < TAG_BYTES; byte_number = byte_number + 1)
            send_byte(tags[packet_number*TAG_BYTES + byte_number],
                      byte_number == TAG_BYTES-1);
    end
    while(data_count != PACKETS*DATA_BYTES) @(posedge aclk);
    elapsed = measure_end - measure_start + 1;
    throughput = (PACKETS * 1024.0 * 0.2) / elapsed;
    $display("THROUGHPUT mode=AES-%0d direction=decrypt cycles=%0d gbps=%0.6f",
             (key_mode == 0) ? 128 : ((key_mode == 1) ? 192 : 256),
             elapsed, throughput);
    if(throughput < 1.0)
        $fatal(1, "DECRYPT_THROUGHPUT_BELOW_1GBPS");
    if(result_count != PACKETS || tag_count != 0)
        $fatal(1, "DECRYPT_OUTPUT_COUNT_ERROR result=%0d tag=%0d",
               result_count, tag_count);
end
endtask

task zeroize_key;
reg [31:0] status;
begin
    axi_write(7'h00, 32'h00000004);
    status = 32'h20;
    while(status[5]) axi_read(7'h04, status);
end
endtask

integer mode_number;
initial
begin
    cycle_count = 0;
    data_count = 0;
    tag_count = 0;
    result_count = 0;
    measure_start = -1;
    measure_end = -1;
    run_phase = 0;
    error_count = 0;
    awaddr = 0; awvalid = 0; wdata = 0; wstrb = 0; wvalid = 0;
    bready = 0; araddr = 0; arvalid = 0; rready = 0;
    s_data = 0; s_valid = 0; s_last = 0;
    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1;

    for(mode_number = 0; mode_number < 3; mode_number = mode_number + 1)
    begin
        load_zero_key(mode_number[2:0]);
        run_encrypt();
        run_decrypt();
        zeroize_key();
    end

    if(error_count != 0)
        $fatal(1, "THROUGHPUT_DATA_ERRORS count=%0d", error_count);
    $display("THROUGHPUT_PASS all key modes >= 1.0 Gbps");
    $finish;
end

endmodule
