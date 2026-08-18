`timescale 1ns / 1ps

module tb_top;

localparam TYPE_IV  = 3'd0;
localparam TYPE_KEY = 3'd1;
localparam TYPE_AAD = 3'd2;
localparam TYPE_PT  = 3'd3;
localparam TYPE_CT  = 3'd4;
localparam TYPE_TAG = 3'd5;
localparam MAX_CASE_CYCLES = 50000;

reg         clk;
reg         rst;
reg  [2:0]  key_mode;
reg         mode;
reg  [7:0]  in;
reg         in_valid;
reg  [2:0]  in_type;
reg  [10:0] in_valid_bit;
reg         last;
wire        pc_ct_valid;
wire        tag_valid;
wire [10:0] pc_ct_len_bit;
wire [3:0]  pc_ct_valid_bit;
wire [7:0]  out;

integer vector_fd;
integer scan_result;
integer max_cases;
integer start_case;
integer scanned_cases;
integer total_cases;
integer passed_cases;
integer failed_cases;
integer timeout_cases;
integer detail_count;

integer mode_i;
integer count_i;
integer key_len_i;
integer iv_len_i;
integer aad_len_i;
integer data_len_i;
integer tag_len_i;
integer accept_i;
integer expected_data_bytes;
integer expected_tag_bytes;
integer got_data_bytes;
integer got_tag_bytes;
integer got_status_pulses;
integer cycles;

reg [255:0]  key_v;
reg [1023:0] iv_v;
reg [1023:0] aad_v;
reg [1023:0] data_in_v;
reg [127:0]  tag_v;
reg [1023:0] data_exp_v;
reg [1023:0] got_data_v;
reg [127:0]  got_tag_v;
reg          started;
reg          completed;
reg          case_failed;

top #(
    .LANES(1)
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
    forever #5 clk = ~clk;
end

task automatic send_field;
    input [2:0] field_type;
    input integer field_bits;
    input [1023:0] field_value;
    integer byte_count;
    integer byte_index;
    integer shift_amount;
begin
    byte_count = (field_bits + 7) / 8;
    if (byte_count == 0) begin
        @(negedge clk);
        in           = 8'd0;
        in_valid     = 1'b1;
        in_type      = field_type;
        in_valid_bit = 11'd0;
        last         = 1'b1;
    end
    else begin
        for (byte_index = 0; byte_index < byte_count; byte_index = byte_index + 1) begin
            shift_amount = (byte_count - 1 - byte_index) * 8;
            @(negedge clk);
            in           = (field_value >> shift_amount) & 8'hff;
            in_valid     = 1'b1;
            in_type      = field_type;
            in_valid_bit = (byte_index == byte_count - 1) ? field_bits : 0;
            last         = (byte_index == byte_count - 1);
        end
    end

    @(negedge clk);
    in           = 8'd0;
    in_valid     = 1'b0;
    in_type      = 3'd0;
    in_valid_bit = 11'd0;
    last         = 1'b0;
end
endtask

task automatic report_failure;
begin
    failed_cases = failed_cases + 1;
    if (detail_count < 20) begin
        $display(
            "FAIL case=%0d mode=%0d KEY=%0d IV=%0d AAD=%0d DATA=%0d TAG=%0d accept=%0d got_data_bytes=%0d got_tag_bytes=%0d status=%0d",
            count_i, mode_i, key_len_i, iv_len_i, aad_len_i, data_len_i, tag_len_i,
            accept_i, got_data_bytes, got_tag_bytes, got_status_pulses
        );
        if (got_data_v !== data_exp_v)
            $display("  DATA expected=%h got=%h", data_exp_v, got_data_v);
        if ((mode_i == 0) && (got_tag_v !== tag_v))
            $display("  TAG  expected=%h got=%h", tag_v, got_tag_v);
        detail_count = detail_count + 1;
    end
end
endtask

initial begin
    rst              = 1'b1;
    key_mode         = 3'd2;
    mode             = 1'b0;
    in               = 8'd0;
    in_valid         = 1'b0;
    in_type          = 3'd0;
    in_valid_bit     = 11'd0;
    last             = 1'b0;
    total_cases      = 0;
    passed_cases     = 0;
    failed_cases     = 0;
    timeout_cases    = 0;
    detail_count     = 0;
    max_cases        = 0;
    start_case       = 0;
    scanned_cases    = 0;

    if (!$value$plusargs("MAX_CASES=%d", max_cases))
        max_cases = 0;
    if (!$value$plusargs("START_CASE=%d", start_case))
        start_case = 0;

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    vector_fd = $fopen("vectors_all.txt", "r");
    if (vector_fd == 0) begin
        $display("FATAL unable to open vectors_all.txt");
        $finish;
    end

    while (!$feof(vector_fd) && ((max_cases == 0) || (total_cases < max_cases))) begin
        scan_result = $fscanf(
            vector_fd,
            "%d %d %h %d %d %h %d %h %d %h %d %h %h %d\n",
            mode_i, count_i, key_v, key_len_i, iv_len_i, iv_v, aad_len_i, aad_v,
            data_len_i, data_in_v, tag_len_i, tag_v, data_exp_v, accept_i
        );

        if (scan_result == 14) begin
          if (scanned_cases >= start_case) begin
            mode = mode_i;
            case (key_len_i)
                128: key_mode = 3'd0;
                192: key_mode = 3'd1;
                default: key_mode = 3'd2;
            endcase
            send_field(TYPE_KEY, key_len_i, {768'd0, key_v});
            send_field(TYPE_IV, iv_len_i, iv_v);
            send_field(TYPE_AAD, aad_len_i, aad_v);
            if (mode_i == 0)
                send_field(TYPE_PT, data_len_i, data_in_v);
            else
                send_field(TYPE_CT, data_len_i, data_in_v);
            send_field(TYPE_TAG, tag_len_i, {896'd0, tag_v});

            expected_data_bytes = (data_len_i + 7) / 8;
            expected_tag_bytes  = (tag_len_i + 7) / 8;
            got_data_bytes      = 0;
            got_tag_bytes       = 0;
            got_status_pulses   = 0;
            got_data_v          = 1024'd0;
            got_tag_v           = 128'd0;
            cycles              = 0;
            started             = 1'b0;
            completed           = 1'b0;

            while (!completed && (cycles < MAX_CASE_CYCLES)) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (dut.GEN_LANES[0].u_lane.state != 5'd0)
                    started = 1'b1;
                if (pc_ct_valid) begin
                    got_data_v     = (got_data_v << 8) | out;
                    got_data_bytes = got_data_bytes + 1;
                end
                if (tag_valid) begin
                    if (mode_i == 0) begin
                        got_tag_v     = (got_tag_v << 8) | out;
                        got_tag_bytes = got_tag_bytes + 1;
                    end
                    else begin
                        got_status_pulses = got_status_pulses + 1;
                    end
                end
                if (started && (dut.GEN_LANES[0].u_lane.state == 5'd0) &&
                    (dut.GEN_LANES[0].u_lane.key_ready == 1'b0))
                    completed = 1'b1;
            end

            total_cases = total_cases + 1;
            case_failed = 1'b0;

            if (!completed) begin
                timeout_cases = timeout_cases + 1;
                case_failed = 1'b1;
                if (detail_count < 20) begin
                    $display("TIMEOUT case=%0d mode=%0d state=%0d", count_i, mode_i,
                             dut.GEN_LANES[0].u_lane.state);
                    detail_count = detail_count + 1;
                end
            end
            else if (mode_i == 0) begin
                if (got_data_bytes != expected_data_bytes)
                    case_failed = 1'b1;
                if (got_data_v !== data_exp_v)
                    case_failed = 1'b1;
                if (got_tag_bytes != expected_tag_bytes)
                    case_failed = 1'b1;
                if (got_tag_v !== tag_v)
                    case_failed = 1'b1;
                if (got_status_pulses != 0)
                    case_failed = 1'b1;
            end
            else if (accept_i != 0) begin
                if (got_data_bytes != expected_data_bytes)
                    case_failed = 1'b1;
                if (got_data_v !== data_exp_v)
                    case_failed = 1'b1;
                if (got_tag_bytes != 0)
                    case_failed = 1'b1;
                if (got_status_pulses != 1)
                    case_failed = 1'b1;
            end
            else begin
                if (got_data_bytes != 0)
                    case_failed = 1'b1;
                if (got_tag_bytes != 0)
                    case_failed = 1'b1;
                if (got_status_pulses != 0)
                    case_failed = 1'b1;
            end

            if (case_failed)
                report_failure();
            else
                passed_cases = passed_cases + 1;

            if ((total_cases % 500) == 0)
                $display("PROGRESS total=%0d pass=%0d fail=%0d timeout=%0d", total_cases, passed_cases, failed_cases, timeout_cases);

            repeat (2) @(posedge clk);
          end
            scanned_cases = scanned_cases + 1;
        end
    end

    $fclose(vector_fd);
    $display("RESULT total=%0d pass=%0d fail=%0d timeout=%0d", total_cases, passed_cases, failed_cases, timeout_cases);
    $finish;
end

endmodule
