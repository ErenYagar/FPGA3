`timescale 1ns / 1ps

module tb_top_1g_parallel #(
    parameter integer LANES = 4,
    parameter integer KEY_BITS = 256,
    parameter integer PAYLOAD_BITS = 1024,
    parameter integer PACKET_COUNT = 100,
    parameter integer CLK_FREQ_HZ = 200000000
);

localparam TYPE_IV  = 3'd0;
localparam TYPE_KEY = 3'd1;
localparam TYPE_AAD = 3'd2;
localparam TYPE_PT  = 3'd3;
localparam TYPE_TAG = 3'd5;

localparam real    CLK_PERIOD_NS = 1.0e9 / CLK_FREQ_HZ;
localparam integer TAG_BITS      = 128;

localparam [255:0] KEY_VALUE =
    256'h603deb1015ca71be2b73aef0857d7781_1f352c073b6108d72d9810a30914dff4;
localparam [95:0] IV_VALUE = 96'hcafebabefacedbaddecaf888;
localparam [1023:0] PT_VALUE = {
    8{128'h6bc1bee22e409f96e93d7e117393172a}
};

reg                       clk;
reg                       rst;
reg  [2:0]                key_mode;
reg  [LANES-1:0]          mode;
reg  [LANES*8-1:0]        in;
reg  [LANES-1:0]          in_valid;
reg  [LANES*3-1:0]        in_type;
reg  [LANES*11-1:0]       in_valid_bit;
reg  [LANES-1:0]          last;
wire [LANES-1:0]          pc_ct_valid;
wire [LANES-1:0]          tag_valid;
wire [LANES*11-1:0]       pc_ct_len_bit;
wire [LANES*4-1:0]        pc_ct_valid_bit;
wire [LANES*8-1:0]        out;

integer cycle_count;
integer aggregate_start_cycle;
integer aggregate_end_cycle;
integer packet_index;
integer lane_index;
integer pc_byte_count [0:LANES-1];
integer tag_byte_count [0:LANES-1];
integer timeout_cycles;
reg     packet_complete;
real    aggregate_gbps;

top #(
    .LANES(LANES)
) dut (
    .clk             (clk),
    .rst             (rst),
    .key_mode        (key_mode),
    .mode            (mode),
    .in              (in),
    .in_valid        (in_valid),
    .in_type         (in_type),
    .in_valid_bit    (in_valid_bit),
    .last            (last),
    .pc_ct_valid     (pc_ct_valid),
    .tag_valid       (tag_valid),
    .pc_ct_len_bit   (pc_ct_len_bit),
    .pc_ct_valid_bit (pc_ct_valid_bit),
    .out             (out)
);

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS / 2.0) clk = ~clk;
end

always @(posedge clk)
    cycle_count <= cycle_count + 1;

task automatic drive_all_lanes;
    input [7:0] byte_value;
    input [2:0] type_value;
    input [10:0] valid_bit_value;
    input last_value;
    integer drive_lane;
begin
    for(drive_lane = 0; drive_lane < LANES; drive_lane = drive_lane + 1)
    begin
        in[drive_lane*8 +: 8] = byte_value;
        in_type[drive_lane*3 +: 3] = type_value;
        in_valid_bit[drive_lane*11 +: 11] = valid_bit_value;
        in_valid[drive_lane] = 1'b1;
        last[drive_lane] = last_value;
    end
end
endtask

task automatic send_field_all;
    input [2:0] field_type;
    input integer field_bits;
    input [1023:0] field_value;
    integer byte_count;
    integer byte_index;
    integer shift_amount;
    reg [7:0] field_byte;
begin
    byte_count = (field_bits + 7) / 8;

    if(byte_count == 0)
    begin
        @(negedge clk);
        drive_all_lanes(8'd0, field_type, 11'd0, 1'b1);
    end
    else
    begin
        for(byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1)
        begin
            shift_amount = (byte_count - 1 - byte_index) * 8;
            field_byte = (field_value >> shift_amount) & 8'hff;
            @(negedge clk);
            drive_all_lanes(
                field_byte,
                field_type,
                (byte_index == byte_count - 1) ? field_bits : 0,
                (byte_index == byte_count - 1)
            );
        end
    end

    @(negedge clk);
    in           = {LANES*8{1'b0}};
    in_valid     = {LANES{1'b0}};
    in_type      = {LANES*3{1'b0}};
    in_valid_bit = {LANES*11{1'b0}};
    last         = {LANES{1'b0}};
end
endtask

initial begin
    cycle_count           = 0;
    aggregate_start_cycle = 0;
    aggregate_end_cycle   = 0;
    rst                   = 1'b1;
    mode                  = {LANES{1'b0}};
    in                    = {LANES*8{1'b0}};
    in_valid              = {LANES{1'b0}};
    in_type               = {LANES*3{1'b0}};
    in_valid_bit          = {LANES*11{1'b0}};
    last                  = {LANES{1'b0}};

    case(KEY_BITS)
        128: key_mode = 3'd0;
        192: key_mode = 3'd1;
        256: key_mode = 3'd2;
        default: begin
            $display("THROUGHPUT_1G_ERROR unsupported KEY_BITS=%0d", KEY_BITS);
            $finish;
        end
    endcase

    repeat(5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat(2) @(posedge clk);

    for(packet_index = 0; packet_index < PACKET_COUNT; packet_index = packet_index + 1)
    begin
        while(!((dut.GEN_LANES[0].u_lane.state == 5'd0) &&
                (dut.GEN_LANES[0].u_lane.key_ready == 1'b0)))
            @(posedge clk);

        if(packet_index == 0)
            aggregate_start_cycle = cycle_count;

        send_field_all(TYPE_KEY, KEY_BITS, {768'd0, KEY_VALUE});
        send_field_all(TYPE_IV, 96, {928'd0, IV_VALUE});
        send_field_all(TYPE_AAD, 0, 1024'd0);
        send_field_all(TYPE_PT, PAYLOAD_BITS, PT_VALUE);
        send_field_all(TYPE_TAG, TAG_BITS, 1024'd0);

        for(lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
        begin
            pc_byte_count[lane_index] = 0;
            tag_byte_count[lane_index] = 0;
        end

        timeout_cycles = 0;
        packet_complete = 1'b0;
        while(!packet_complete && (timeout_cycles < 100000))
        begin
            @(posedge clk);
            #1;
            timeout_cycles = timeout_cycles + 1;

            for(lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
            begin
                if(pc_ct_valid[lane_index])
                begin
                    pc_byte_count[lane_index] = pc_byte_count[lane_index] + 1;
                    if(out[lane_index*8 +: 8] !== out[7:0])
                    begin
                        $display("THROUGHPUT_1G_ERROR lane=%0d ciphertext mismatch", lane_index);
                        $finish;
                    end
                end

                if(tag_valid[lane_index])
                begin
                    tag_byte_count[lane_index] = tag_byte_count[lane_index] + 1;
                    if(out[lane_index*8 +: 8] !== out[7:0])
                    begin
                        $display("THROUGHPUT_1G_ERROR lane=%0d tag mismatch", lane_index);
                        $finish;
                    end
                end
            end

            packet_complete = 1'b1;
            for(lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
            begin
                if(tag_byte_count[lane_index] != (TAG_BITS / 8))
                    packet_complete = 1'b0;
            end
        end

        if(!packet_complete)
        begin
            $display("THROUGHPUT_1G_ERROR packet=%0d timeout", packet_index);
            $finish;
        end

        for(lane_index = 0; lane_index < LANES; lane_index = lane_index + 1)
        begin
            if((pc_byte_count[lane_index] != (PAYLOAD_BITS / 8)) ||
               (tag_byte_count[lane_index] != (TAG_BITS / 8)))
            begin
                $display(
                    "THROUGHPUT_1G_ERROR lane=%0d pc_bytes=%0d tag_bytes=%0d",
                    lane_index, pc_byte_count[lane_index], tag_byte_count[lane_index]
                );
                $finish;
            end
        end

        while(!((dut.GEN_LANES[0].u_lane.state == 5'd0) &&
                (dut.GEN_LANES[0].u_lane.key_ready == 1'b0)))
            @(posedge clk);

        if(packet_index == PACKET_COUNT - 1)
            aggregate_end_cycle = cycle_count;
    end

    aggregate_gbps = (LANES * PACKET_COUNT * PAYLOAD_BITS * 1.0 * CLK_FREQ_HZ) /
                     ((aggregate_end_cycle - aggregate_start_cycle) * 1.0e9);

    $display(
        "THROUGHPUT_1G_RESULT lanes=%0d clock_hz=%0d key_bits=%0d payload_bits=%0d packets_per_lane=%0d cycles=%0d gbps=%0.6f",
        LANES, CLK_FREQ_HZ, KEY_BITS, PAYLOAD_BITS, PACKET_COUNT,
        aggregate_end_cycle - aggregate_start_cycle, aggregate_gbps
    );

    if(aggregate_gbps < 1.0)
        $display("THROUGHPUT_1G_FAIL target=1.0 measured=%0.6f", aggregate_gbps);
    else
        $display("THROUGHPUT_1G_PASS target=1.0 measured=%0.6f", aggregate_gbps);

    $finish;
end

endmodule
