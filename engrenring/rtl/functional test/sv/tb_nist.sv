`timescale 1ns / 1ps

// Pure-SystemVerilog NIST CAVP regression for aes_gcm_axi_top.
//
// The six .rsp files are parsed at run time.  Every vector is driven only
// through the public AXI-Lite register interface and byte-wide AXI streams.
// No generated include files, DPI code, Python, or DUT hierarchy accesses are
// used, so this is also intended to be a readable executable protocol example.
module tb_nist;

localparam [1:0] AXI_OKAY = 2'b00;
localparam integer EXPECTED_PER_FILE = 7875;
localparam integer EXPECTED_TOTAL = 47250;
localparam integer OUTPUT_TIMEOUT_CYCLES = 25000;
localparam integer KEY_TIMEOUT_POLLS = 1000;
localparam integer MAX_PRINTED_FAILURES = 20;

localparam [6:0] REG_CONTROL = 7'h00;
localparam [6:0] REG_STATUS  = 7'h04;
localparam [6:0] REG_CFG     = 7'h08;
localparam [6:0] REG_IV_BITS = 7'h0c;
localparam [6:0] REG_AAD_BITS = 7'h10;
localparam [6:0] REG_DATA_BITS = 7'h14;
localparam [6:0] REG_KEY0 = 7'h20;

localparam [7:0] RESULT_ENC_OK = 8'h00;
localparam [7:0] RESULT_DEC_AUTH_OK = 8'h01;
localparam [7:0] RESULT_DEC_AUTH_FAIL = 8'h02;

reg aclk = 1'b0;
always #2.857 aclk = ~aclk;

reg aresetn = 1'b0;
reg [2:0] key_mode = 3'd0;

reg [6:0] awaddr;
reg [2:0] awprot = 3'd0;
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
reg [2:0] arprot = 3'd0;
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
reg data_ready = 1'b1;
wire data_last;
wire [3:0] data_user;

wire [7:0] tag_out;
wire tag_valid;
reg tag_ready = 1'b1;
wire tag_last;

wire [7:0] result_out;
wire result_valid;
reg result_ready = 1'b1;
wire result_last;

aes_gcm_axi_top #(
    .ALLOW_NIST_TAG_LENGTHS(1'b1)
) dut (
    .aclk(aclk), .aresetn(aresetn), .key_mode(key_mode),
    .s_axi_awaddr(awaddr), .s_axi_awprot(awprot),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready), .s_axi_araddr(araddr),
    .s_axi_arprot(arprot), .s_axi_arvalid(arvalid),
    .s_axi_arready(arready), .s_axi_rdata(rdata),
    .s_axi_rresp(rresp), .s_axi_rvalid(rvalid),
    .s_axi_rready(rready), .s_axis_tdata(s_data),
    .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tlast(s_last), .m_axis_data_tdata(data_out),
    .m_axis_data_tvalid(data_valid),
    .m_axis_data_tready(data_ready), .m_axis_data_tlast(data_last),
    .m_axis_data_tuser(data_user), .m_axis_tag_tdata(tag_out),
    .m_axis_tag_tvalid(tag_valid), .m_axis_tag_tready(tag_ready),
    .m_axis_tag_tlast(tag_last),
    .m_axis_result_tdata(result_out),
    .m_axis_result_tvalid(result_valid),
    .m_axis_result_tready(result_ready),
    .m_axis_result_tlast(result_last)
);

// A CAVP field in these files never exceeds 2047 bits, the public length
// register width.  Parsed hexadecimal values are right-aligned in these regs.
reg [2047:0] vector_key;
reg [2047:0] vector_iv;
reg [2047:0] vector_aad;
reg [2047:0] vector_input_data;
reg [2047:0] vector_expected_data;
reg [2047:0] vector_tag;
integer vector_key_bits;
integer vector_iv_bits;
integer vector_aad_bits;
integer vector_data_bits;
integer vector_tag_bits;
integer vector_rsp_count;
integer vector_expected_fail;

integer total_vectors;
integer total_passed;
integer total_failed;
integer cycle_count;
integer max_vectors;
integer limited_run;

integer capture_active;
integer expected_decrypt;
integer expected_data_bytes;
integer expected_tag_bytes;
integer data_count;
integer tag_count;
integer result_count;
integer data_last_count;
integer tag_last_count;
integer result_last_count;
integer framing_error;
integer first_data_cycle;
integer result_cycle;
reg [2047:0] captured_data;
reg [2047:0] captured_tag;
reg [7:0] captured_result;
reg [3:0] captured_last_user;
string rsp_directory;

always @(posedge aclk)
begin
    cycle_count = cycle_count + 1;

    if(capture_active && data_valid && data_ready)
    begin
        data_count = data_count + 1;
        captured_data = {captured_data[2039:0], data_out};
        if(first_data_cycle < 0)
            first_data_cycle = cycle_count;
        if(data_last)
        begin
            data_last_count = data_last_count + 1;
            captured_last_user = data_user;
            if(data_count != expected_data_bytes)
                framing_error = 1;
        end
    end

    if(capture_active && tag_valid && tag_ready)
    begin
        tag_count = tag_count + 1;
        captured_tag = {captured_tag[2039:0], tag_out};
        if(tag_last)
        begin
            tag_last_count = tag_last_count + 1;
            if(tag_count != expected_tag_bytes)
                framing_error = 1;
        end
    end

    if(capture_active && result_valid && result_ready)
    begin
        result_count = result_count + 1;
        captured_result = result_out;
        result_cycle = cycle_count;
        if(result_last)
            result_last_count = result_last_count + 1;
    end
end

task automatic clear_capture;
input integer decrypt_mode;
input integer data_bytes;
input integer tag_bytes;
begin
    @(negedge aclk);
    capture_active = 0;
    expected_decrypt = decrypt_mode;
    expected_data_bytes = data_bytes;
    expected_tag_bytes = tag_bytes;
    data_count = 0;
    tag_count = 0;
    result_count = 0;
    data_last_count = 0;
    tag_last_count = 0;
    result_last_count = 0;
    framing_error = 0;
    first_data_cycle = -1;
    result_cycle = -1;
    captured_data = 2048'd0;
    captured_tag = 2048'd0;
    captured_result = 8'hff;
    captured_last_user = 4'd0;
    capture_active = 1;
end
endtask

// AXI-Lite AW and W are deliberately treated as independent channels.
task automatic axi_write;
input [6:0] address;
input [31:0] value;
reg aw_done;
reg w_done;
begin
    @(negedge aclk);
    awaddr = address;
    awvalid = 1'b1;
    wdata = value;
    wstrb = 4'hf;
    wvalid = 1'b1;
    bready = 1'b1;
    aw_done = 1'b0;
    w_done = 1'b0;

    while(!(aw_done && w_done))
    begin
        @(posedge aclk);
        if(awvalid && awready)
            aw_done = 1'b1;
        if(wvalid && wready)
            w_done = 1'b1;
        @(negedge aclk);
        if(aw_done)
            awvalid = 1'b0;
        if(w_done)
            wvalid = 1'b0;
    end

    while(!bvalid)
        @(posedge aclk);
    if(bresp !== AXI_OKAY)
        $fatal(1, "AXI write rejected: address=0x%02x response=%b",
               address, bresp);
    @(negedge aclk);
    bready = 1'b0;
end
endtask

task automatic axi_read;
input [6:0] address;
output [31:0] value;
begin
    @(negedge aclk);
    araddr = address;
    arvalid = 1'b1;
    rready = 1'b1;
    while(!(arvalid && arready))
        @(posedge aclk);
    @(negedge aclk);
    arvalid = 1'b0;
    while(!rvalid)
        @(posedge aclk);
    if(rresp !== AXI_OKAY)
        $fatal(1, "AXI read failed: address=0x%02x response=%b",
               address, rresp);
    value = rdata;
    @(negedge aclk);
    rready = 1'b0;
end
endtask

task automatic send_byte;
input [7:0] value;
input integer is_last;
begin
    s_data = value;
    s_last = (is_last != 0);
    s_valid = 1'b1;
    while(!(s_valid && s_ready))
        @(posedge aclk);
    @(negedge aclk);
    s_valid = 1'b0;
    s_last = 1'b0;
end
endtask

// CAVP strings represent a partial final byte with the valid bits at its MSB.
// Index from ceil(bits/8)*8, rather than directly from bits, so this remains
// correct for partial-byte vectors as well as the byte-aligned supplied files.
task automatic send_field;
input [2047:0] value;
input integer length_bits;
input integer last_field;
integer byte_count;
integer byte_index;
integer bit_index;
begin
    byte_count = (length_bits + 7) / 8;
    for(byte_index = 0; byte_index < byte_count;
        byte_index = byte_index + 1)
    begin
        bit_index = byte_count * 8 - 1 - byte_index * 8;
        send_byte(value[bit_index -: 8],
                  last_field && (byte_index == byte_count - 1));
    end
end
endtask

task automatic program_key;
input [2047:0] key_value;
input integer key_bits;
reg [255:0] staged_key;
reg [31:0] status_word;
integer word_count;
integer word_index;
integer poll_count;
begin
    case(key_bits)
        128: key_mode = 3'd0;
        192: key_mode = 3'd1;
        256: key_mode = 3'd2;
        default: $fatal(1, "Unsupported Keylen=%0d", key_bits);
    endcase

    staged_key = key_value[255:0] << (256 - key_bits);
    word_count = key_bits / 32;
    for(word_index = 0; word_index < word_count;
        word_index = word_index + 1)
        axi_write(REG_KEY0 + word_index * 4,
                  staged_key[255-word_index*32 -: 32]);

    axi_write(REG_CONTROL, 32'h00000002);

    status_word = 32'd0;
    poll_count = 0;
    while(!status_word[0] && poll_count < KEY_TIMEOUT_POLLS)
    begin
        axi_read(REG_STATUS, status_word);
        poll_count = poll_count + 1;
    end
    if(!status_word[0])
        $fatal(1, "Key setup timeout for Keylen=%0d", key_bits);
end
endtask

task automatic program_record;
input integer decrypt_mode;
input integer tag_bits;
input integer iv_bits;
input integer aad_bits;
input integer data_bits;
reg [31:0] cfg_word;
begin
    cfg_word = 32'd0;
    cfg_word[0] = (decrypt_mode != 0);
    cfg_word[15:8] = tag_bits[7:0];
    axi_write(REG_CFG, cfg_word);
    axi_write(REG_IV_BITS, iv_bits[10:0]);
    axi_write(REG_AAD_BITS, aad_bits[10:0]);
    axi_write(REG_DATA_BITS, data_bits[10:0]);
    axi_write(REG_CONTROL, 32'h00000001);
end
endtask

task automatic send_record;
input integer decrypt_mode;
begin
    if(decrypt_mode)
    begin
        send_field(vector_iv, vector_iv_bits, 0);
        send_field(vector_aad, vector_aad_bits, 0);
        send_field(vector_input_data, vector_data_bits, 0);
        send_field(vector_tag, vector_tag_bits, 1);
    end
    else
    begin
        send_field(vector_iv, vector_iv_bits,
                   (vector_aad_bits == 0) && (vector_data_bits == 0));
        send_field(vector_aad, vector_aad_bits,
                   vector_data_bits == 0);
        send_field(vector_input_data, vector_data_bits, 1);
    end
end
endtask

task automatic wait_for_outputs;
input integer wanted_data_bytes;
input integer wanted_tag_bytes;
integer timeout;
begin
    timeout = 0;
    while((result_count == 0) && (timeout < OUTPUT_TIMEOUT_CYCLES))
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if(result_count == 0)
        $fatal(1, "Result timeout at global vector %0d", total_vectors + 1);

    while(((data_count < wanted_data_bytes) ||
           (tag_count < wanted_tag_bytes)) &&
          (timeout < OUTPUT_TIMEOUT_CYCLES))
    begin
        @(posedge aclk);
        timeout = timeout + 1;
    end
    if((data_count < wanted_data_bytes) || (tag_count < wanted_tag_bytes))
        $fatal(1, "Output timeout at global vector %0d: data=%0d/%0d tag=%0d/%0d",
               total_vectors + 1, data_count, wanted_data_bytes,
               tag_count, wanted_tag_bytes);

    // Move off the final handshake edge and catch accidental extra beats.
    repeat(2) @(posedge aclk);
    @(negedge aclk);
end
endtask

task automatic execute_vector;
input integer decrypt_mode;
output integer passed;
integer wanted_data_bytes;
integer wanted_tag_bytes;
integer wanted_last_bits;
reg [7:0] wanted_result;
integer ok;
begin
    wanted_data_bytes = vector_expected_fail ? 0 :
                        (vector_data_bits + 7) / 8;
    wanted_tag_bytes = decrypt_mode ? 0 : (vector_tag_bits + 7) / 8;
    wanted_last_bits = (vector_data_bits % 8 == 0) ? 8 :
                       vector_data_bits % 8;
    if(!decrypt_mode)
        wanted_result = RESULT_ENC_OK;
    else if(vector_expected_fail)
        wanted_result = RESULT_DEC_AUTH_FAIL;
    else
        wanted_result = RESULT_DEC_AUTH_OK;

    // Key commitment is intentionally repeated for every CAVP Count.  The
    // files supply a new independent key for each vector.
    program_key(vector_key, vector_key_bits);
    clear_capture(decrypt_mode, wanted_data_bytes, wanted_tag_bytes);
    program_record(decrypt_mode, vector_tag_bits, vector_iv_bits,
                   vector_aad_bits, vector_data_bits);
    send_record(decrypt_mode);
    wait_for_outputs(wanted_data_bytes, wanted_tag_bytes);

    ok = 1;
    if(result_count != 1 || captured_result !== wanted_result ||
       result_last_count != 1)
        ok = 0;
    if(data_count != wanted_data_bytes ||
       captured_data !== vector_expected_data)
        ok = 0;
    if(tag_count != wanted_tag_bytes)
        ok = 0;
    if(!decrypt_mode && captured_tag !== vector_tag)
        ok = 0;
    if(decrypt_mode && captured_tag !== 2048'd0)
        ok = 0;
    if(wanted_data_bytes == 0)
    begin
        if(data_last_count != 0)
            ok = 0;
    end
    else if(data_last_count != 1 ||
            captured_last_user != wanted_last_bits[3:0])
        ok = 0;
    if(wanted_tag_bytes == 0)
    begin
        if(tag_last_count != 0)
            ok = 0;
    end
    else if(tag_last_count != 1)
        ok = 0;
    if(framing_error)
        ok = 0;

    // Successful decryption must not release plaintext until the public
    // authentication-result beat has actually handshaken.
    if(decrypt_mode && !vector_expected_fail && wanted_data_bytes != 0 &&
       first_data_cycle <= result_cycle)
        ok = 0;

    passed = ok;
    if(!ok && total_failed < MAX_PRINTED_FAILURES)
    begin
        $display("NIST_VECTOR_FAIL global=%0d Count=%0d decrypt=%0d Keylen=%0d IVlen=%0d PTlen=%0d AADlen=%0d Taglen=%0d expected_fail=%0d",
                 total_vectors + 1, vector_rsp_count, decrypt_mode,
                 vector_key_bits, vector_iv_bits, vector_data_bits,
                 vector_aad_bits, vector_tag_bits, vector_expected_fail);
        $display("  result got=%02x expected=%02x beats=%0d last=%0d",
                 captured_result, wanted_result, result_count,
                 result_last_count);
        $display("  data bytes=%0d/%0d last=%0d user=%0d got=%0h expected=%0h",
                 data_count, wanted_data_bytes, data_last_count,
                 captured_last_user, captured_data, vector_expected_data);
        $display("  tag  bytes=%0d/%0d last=%0d got=%0h expected=%0h framing_error=%0d",
                 tag_count, wanted_tag_bytes, tag_last_count,
                 captured_tag, vector_tag, framing_error);
    end
    capture_active = 0;
end
endtask

task automatic read_hex_field;
input integer file_handle;
input string expected_name;
input integer expected_bits;
output reg [2047:0] value;
string line;
string parsed_name;
integer scan_count;
begin
    value = 2048'd0;
    line = "";
    if($fgets(line, file_handle) == 0)
        $fatal(1, "Unexpected EOF while reading %s", expected_name);
    parsed_name = "";
    scan_count = $sscanf(line, "%s = %h", parsed_name, value);
    if(parsed_name != expected_name)
        $fatal(1, "RSP parse error: expected %s, line was: %s",
               expected_name, line);
    if(expected_bits == 0)
    begin
        if(scan_count != 1)
            $fatal(1, "RSP parse error: %s should be empty", expected_name);
        value = 2048'd0;
    end
    else if(scan_count != 2)
        $fatal(1, "RSP parse error: missing %s value", expected_name);
end
endtask

task automatic read_decrypt_outcome;
input integer file_handle;
input integer pt_bits;
output integer expected_fail;
output reg [2047:0] plaintext;
string line;
string first_word;
string parsed_name;
integer scan_count;
begin
    plaintext = 2048'd0;
    line = "";
    if($fgets(line, file_handle) == 0)
        $fatal(1, "Unexpected EOF while reading decrypt outcome");
    first_word = "";
    scan_count = $sscanf(line, "%s", first_word);
    if(first_word == "FAIL")
    begin
        expected_fail = 1;
        plaintext = 2048'd0;
    end
    else
    begin
        expected_fail = 0;
        parsed_name = "";
        scan_count = $sscanf(line, "%s = %h", parsed_name, plaintext);
        if(parsed_name != "PT")
            $fatal(1, "RSP parse error: expected PT or FAIL, line was: %s",
                   line);
        if(pt_bits == 0)
        begin
            if(scan_count != 1)
                $fatal(1, "RSP parse error: zero-length PT was not empty");
            plaintext = 2048'd0;
        end
        else if(scan_count != 2)
            $fatal(1, "RSP parse error: missing PT value");
    end
end
endtask

// Resolve the response-vector directory from the simulator working directory.
// RSP_DIR may include or omit a trailing slash.  The underscore spelling is
// retained for the same Vivado/Windows command-line use case as MAX_VECTORS.
task automatic probe_rsp_directory;
input string candidate;
output integer usable;
string probe_name;
integer probe_handle;
integer added_separator;
begin
    usable = 0;
    added_separator = 0;
    probe_name = {candidate, "gcmEncryptExtIV128.rsp"};
    probe_handle = $fopen(probe_name, "r");
    if(probe_handle == 0)
    begin
        probe_name = {candidate, "/gcmEncryptExtIV128.rsp"};
        probe_handle = $fopen(probe_name, "r");
        added_separator = 1;
    end
    if(probe_handle != 0)
    begin
        $fclose(probe_handle);
        if(added_separator)
            rsp_directory = {candidate, "/"};
        else
            rsp_directory = candidate;
        usable = 1;
    end
end
endtask

task automatic select_rsp_directory;
string requested_directory;
integer usable;
begin
    usable = 0;
    if($value$plusargs("RSP_DIR=%s", requested_directory) ||
       $value$plusargs("RSP_DIR_%s", requested_directory))
    begin
        probe_rsp_directory(requested_directory, usable);
        if(!usable)
            $fatal(1, "RSP_DIR does not contain NIST response files: %s",
                   requested_directory);
    end
    else
    begin
        probe_rsp_directory("rtl/functional test/rsp/", usable);
        if(!usable)
            probe_rsp_directory("../rtl/functional test/rsp/", usable);
        if(!usable)
            probe_rsp_directory("engrenring/rtl/functional test/rsp/",
                                usable);
        if(!usable)
            probe_rsp_directory("../engrenring/rtl/functional test/rsp/",
                                usable);
        if(!usable)
            probe_rsp_directory("rsp/", usable);
        if(!usable)
            probe_rsp_directory("../rsp/", usable);
        if(!usable)
            $fatal(1, "Cannot locate NIST rsp directory; use +RSP_DIR=<path>");
    end
    $display("NIST_RSP_DIRECTORY %s", rsp_directory);
end
endtask

task automatic process_rsp_file;
input string base_name;
input integer decrypt_file;
input integer expected_key_bits;
string full_name;
string line;
integer file_handle;
integer scan_value;
integer section_key_bits;
integer section_iv_bits;
integer section_pt_bits;
integer section_aad_bits;
integer section_tag_bits;
integer file_vectors;
integer file_parsed;
integer file_passed;
integer file_failed;
integer one_passed;
begin
    full_name = {rsp_directory, base_name};
    file_handle = $fopen(full_name, "r");
    if(file_handle == 0)
    begin
        full_name = {rsp_directory, "/", base_name};
        file_handle = $fopen(full_name, "r");
    end
    if(file_handle == 0)
        $fatal(1, "Cannot open NIST response file: %s", full_name);

    section_key_bits = -1;
    section_iv_bits = -1;
    section_pt_bits = -1;
    section_aad_bits = -1;
    section_tag_bits = -1;
    file_vectors = 0;
    file_parsed = 0;
    file_passed = 0;
    file_failed = 0;

    while($fgets(line, file_handle) != 0)
    begin
        if($sscanf(line, "[Keylen = %d]", scan_value) == 1)
            section_key_bits = scan_value;
        else if($sscanf(line, "[IVlen = %d]", scan_value) == 1)
            section_iv_bits = scan_value;
        else if($sscanf(line, "[PTlen = %d]", scan_value) == 1)
            section_pt_bits = scan_value;
        else if($sscanf(line, "[AADlen = %d]", scan_value) == 1)
            section_aad_bits = scan_value;
        else if($sscanf(line, "[Taglen = %d]", scan_value) == 1)
            section_tag_bits = scan_value;
        else if($sscanf(line, "Count = %d", vector_rsp_count) == 1)
        begin
            if(section_key_bits != expected_key_bits ||
               section_iv_bits <= 0 || section_pt_bits < 0 ||
               section_aad_bits < 0 || section_tag_bits <= 0)
                $fatal(1, "Invalid section before Count=%0d in %s",
                       vector_rsp_count, base_name);

            vector_key_bits = section_key_bits;
            vector_iv_bits = section_iv_bits;
            vector_data_bits = section_pt_bits;
            vector_aad_bits = section_aad_bits;
            vector_tag_bits = section_tag_bits;
            vector_expected_fail = 0;
            vector_key = 2048'd0;
            vector_iv = 2048'd0;
            vector_aad = 2048'd0;
            vector_input_data = 2048'd0;
            vector_expected_data = 2048'd0;
            vector_tag = 2048'd0;

            read_hex_field(file_handle, "Key", section_key_bits,
                           vector_key);
            read_hex_field(file_handle, "IV", section_iv_bits, vector_iv);
            if(decrypt_file)
            begin
                read_hex_field(file_handle, "CT", section_pt_bits,
                               vector_input_data);
                read_hex_field(file_handle, "AAD", section_aad_bits,
                               vector_aad);
                read_hex_field(file_handle, "Tag", section_tag_bits,
                               vector_tag);
                read_decrypt_outcome(file_handle, section_pt_bits,
                                     vector_expected_fail,
                                     vector_expected_data);
            end
            else
            begin
                read_hex_field(file_handle, "PT", section_pt_bits,
                               vector_input_data);
                read_hex_field(file_handle, "AAD", section_aad_bits,
                               vector_aad);
                read_hex_field(file_handle, "CT", section_pt_bits,
                               vector_expected_data);
                read_hex_field(file_handle, "Tag", section_tag_bits,
                               vector_tag);
            end

            file_parsed = file_parsed + 1;
            if(total_vectors < max_vectors)
            begin
                execute_vector(decrypt_file, one_passed);
                file_vectors = file_vectors + 1;
                total_vectors = total_vectors + 1;
                if(one_passed)
                begin
                    file_passed = file_passed + 1;
                    total_passed = total_passed + 1;
                end
                else
                begin
                    file_failed = file_failed + 1;
                    total_failed = total_failed + 1;
                end
            end
        end
    end

    $fclose(file_handle);
    $display("NIST_FILE_SUMMARY file=%s pass=%0d fail=%0d total=%0d",
             base_name, file_passed, file_failed, file_vectors);
    if(file_parsed != EXPECTED_PER_FILE)
        $fatal(1, "Wrong vector count in %s: got %0d expected %0d",
               base_name, file_parsed, EXPECTED_PER_FILE);
end
endtask

initial
begin
    awaddr = 0;
    awvalid = 0;
    wdata = 0;
    wstrb = 0;
    wvalid = 0;
    bready = 0;
    araddr = 0;
    arvalid = 0;
    rready = 0;
    s_data = 0;
    s_valid = 0;
    s_last = 0;
    capture_active = 0;
    cycle_count = 0;
    total_vectors = 0;
    total_passed = 0;
    total_failed = 0;
    select_rsp_directory();
    // The underscore spelling is a Vivado 2021.1/Windows command-line
    // workaround; normal simulators can use the conventional +MAX_VECTORS=N.
    if($value$plusargs("MAX_VECTORS=%d", max_vectors) ||
       $value$plusargs("MAX_VECTORS_%d", max_vectors))
    begin
        if(max_vectors < 1)
            $fatal(1, "MAX_VECTORS must be positive");
        limited_run = 1;
        $display("NIST_LIMITED_RUN max_vectors=%0d", max_vectors);
    end
    else
    begin
        max_vectors = EXPECTED_TOTAL;
        limited_run = 0;
    end

    repeat(8) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;

    process_rsp_file("gcmEncryptExtIV128.rsp", 0, 128);
    process_rsp_file("gcmEncryptExtIV192.rsp", 0, 192);
    process_rsp_file("gcmEncryptExtIV256.rsp", 0, 256);
    process_rsp_file("gcmDecrypt128.rsp", 1, 128);
    process_rsp_file("gcmDecrypt192.rsp", 1, 192);
    process_rsp_file("gcmDecrypt256.rsp", 1, 256);

    $display("NIST_TOTAL_SUMMARY pass=%0d fail=%0d total=%0d cycles=%0d",
             total_passed, total_failed, total_vectors, cycle_count);
    if(!limited_run &&
       (total_vectors != EXPECTED_TOTAL || total_passed != EXPECTED_TOTAL ||
        total_failed != 0))
        $fatal(1, "NIST regression failed: required %0d/%0d",
               EXPECTED_TOTAL, EXPECTED_TOTAL);

    if(limited_run)
        $display("NIST_LIMITED_DONE pass=%0d fail=%0d total=%0d",
                 total_passed, total_failed, total_vectors);
    else
        $display("NIST_ALL_PASS 47250/47250");
    $finish;
end

endmodule
