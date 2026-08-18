`timescale 1ns / 1ps

// One-outstanding-transaction AXI4-Lite register bank.
//
// 0x00 CONTROL (write pulse): bit 0 CMD_PUSH, bit 1 KEY_COMMIT,
//                            bit 2 ZEROIZE
// 0x04 STATUS  (read only):   bit 0 KEY_READY, bit 1 KEY_BUSY,
//                            bit 2 CMD_FULL, bit 3 RECORD_ACTIVE,
//                            bit 4 OUTPUT_PENDING, bit 5 ZEROIZE_BUSY
// 0x08 CFG     (read/write):  bit 0 DECRYPT, bits 15:8 TAG_BITS
// 0x0c IV_LEN, 0x10 AAD_LEN, 0x14 DATA_LEN: bits 10:0, in bits
// 0x20..0x3c KEY_WORD0..7 (write only)
// 0x40 CAPABILITY (read only)
//
// KEY_WORD0 fills key_staging_o[255:224], through KEY_WORD7 filling
// key_staging_o[31:0].  Within each word WDATA[31:24] is the earliest AES
// byte.  key_mode is deliberately not stored here; integration samples the
// external key_mode together with key_commit_pulse_o.
module axi_lite_regs #(
    parameter integer C_S_AXI_ADDR_WIDTH = 7,
    parameter         ALLOW_NIST_TAG_LENGTHS = 1'b1
)
(
    input                                  s_axi_aclk,
    input                                  s_axi_aresetn,

    input      [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input      [2:0]                       s_axi_awprot,
    input                                  s_axi_awvalid,
    output                                 s_axi_awready,

    input      [31:0]                      s_axi_wdata,
    input      [3:0]                       s_axi_wstrb,
    input                                  s_axi_wvalid,
    output                                 s_axi_wready,

    output reg [1:0]                       s_axi_bresp,
    output reg                             s_axi_bvalid,
    input                                  s_axi_bready,

    input      [C_S_AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input      [2:0]                       s_axi_arprot,
    input                                  s_axi_arvalid,
    output                                 s_axi_arready,

    output reg [31:0]                      s_axi_rdata,
    output reg [1:0]                       s_axi_rresp,
    output reg                             s_axi_rvalid,
    input                                  s_axi_rready,

    input                                  key_ready_i,
    input                                  key_busy_i,
    input                                  cmd_full_i,
    input                                  record_active_i,
    input                                  output_pending_i,
    input                                  zeroize_busy_i,

    input                                  reject_cmd_push_i,
    input                                  reject_key_commit_i,
    input                                  reject_zeroize_i,

    output reg                             cmd_push_pulse_o,
    output reg                             key_commit_pulse_o,
    output reg                             zeroize_pulse_o,

    output reg                             cfg_decrypt_o,
    output reg [7:0]                       cfg_tag_bits_o,
    output reg [10:0]                      iv_len_bits_o,
    output reg [10:0]                      aad_len_bits_o,
    output reg [10:0]                      data_len_bits_o,
    output reg [255:0]                     key_staging_o
);

localparam [1:0] AXI_RESP_OKAY   = 2'b00;
localparam [1:0] AXI_RESP_SLVERR = 2'b10;

localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONTROL    = 7'h00;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS     = 7'h04;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CFG        = 7'h08;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IV_LEN     = 7'h0c;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_AAD_LEN    = 7'h10;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_DATA_LEN   = 7'h14;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD0  = 7'h20;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD1  = 7'h24;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD2  = 7'h28;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD3  = 7'h2c;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD4  = 7'h30;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD5  = 7'h34;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD6  = 7'h38;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_KEY_WORD7  = 7'h3c;
localparam [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CAPABILITY = 7'h40;

localparam [31:0] CAPABILITY_VALUE = {
    8'h01,
    8'h07,
    4'd11,
    ALLOW_NIST_TAG_LENGTHS,
    11'd2047
};

reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_q;
reg                          awaddr_valid_q;
reg [31:0]                   wdata_q;
reg [3:0]                    wstrb_q;
reg                          wdata_valid_q;
reg [5:0]                    status_snapshot_q;
reg                          status_read_pending_q;

wire [31:0] status_value;
wire [31:0] cfg_value;
wire [2:0]  requested_control;
wire        multiple_control_bits;
wire        rejected_control;

assign status_value = {
    26'd0,
    zeroize_busy_i,
    output_pending_i,
    record_active_i,
    cmd_full_i,
    key_busy_i,
    key_ready_i
};

assign cfg_value = {16'd0, cfg_tag_bits_o, 7'd0, cfg_decrypt_o};

assign requested_control = wstrb_q[0] ? wdata_q[2:0] : 3'b000;
assign multiple_control_bits =
       (requested_control[0] && requested_control[1])
    || (requested_control[0] && requested_control[2])
    || (requested_control[1] && requested_control[2]);

assign rejected_control = multiple_control_bits
                       || (requested_control[0] && reject_cmd_push_i)
                       || (requested_control[1] && reject_key_commit_i)
                       || (requested_control[2] && reject_zeroize_i);

assign s_axi_awready = !awaddr_valid_q && !s_axi_bvalid;
assign s_axi_wready  = !wdata_valid_q && !s_axi_bvalid;
assign s_axi_arready = !s_axi_rvalid && !status_read_pending_q;

function [31:0] apply_wstrb;
input [31:0] old_value;
input [31:0] new_value;
input [3:0]  byte_strobe;
integer byte_index;
begin
    apply_wstrb = old_value;
    for(byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
    begin
        if(byte_strobe[byte_index])
            apply_wstrb[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
    end
end
endfunction

always @(posedge s_axi_aclk)
begin
    if(!s_axi_aresetn)
    begin
        awaddr_q           <= {C_S_AXI_ADDR_WIDTH{1'b0}};
        awaddr_valid_q     <= 1'b0;
        wdata_q            <= 32'd0;
        wstrb_q            <= 4'd0;
        wdata_valid_q      <= 1'b0;
        s_axi_bresp        <= AXI_RESP_OKAY;
        s_axi_bvalid       <= 1'b0;
        cmd_push_pulse_o   <= 1'b0;
        key_commit_pulse_o <= 1'b0;
        zeroize_pulse_o    <= 1'b0;
        cfg_decrypt_o      <= 1'b0;
        cfg_tag_bits_o     <= 8'd128;
        iv_len_bits_o      <= 11'd0;
        aad_len_bits_o     <= 11'd0;
        data_len_bits_o    <= 11'd0;
        key_staging_o      <= 256'd0;
    end
    else
    begin
        cmd_push_pulse_o   <= 1'b0;
        key_commit_pulse_o <= 1'b0;
        zeroize_pulse_o    <= 1'b0;

        if(s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;

        if(s_axi_awready && s_axi_awvalid)
        begin
            awaddr_q       <= s_axi_awaddr;
            awaddr_valid_q <= 1'b1;
        end

        if(s_axi_wready && s_axi_wvalid)
        begin
            wdata_q       <= s_axi_wdata;
            wstrb_q       <= s_axi_wstrb;
            wdata_valid_q <= 1'b1;
        end

        if(awaddr_valid_q && wdata_valid_q && !s_axi_bvalid)
        begin
            awaddr_valid_q <= 1'b0;
            wdata_valid_q  <= 1'b0;
            s_axi_bresp    <= AXI_RESP_OKAY;
            s_axi_bvalid   <= 1'b1;

            if(awaddr_q[1:0] != 2'b00)
            begin
                s_axi_bresp <= AXI_RESP_SLVERR;
            end
            else
            begin
                case(awaddr_q)
                    ADDR_CONTROL:
                    begin
                        if(rejected_control)
                        begin
                            s_axi_bresp <= AXI_RESP_SLVERR;
                        end
                        else
                        begin
                            cmd_push_pulse_o   <= requested_control[0];
                            key_commit_pulse_o <= requested_control[1];
                            zeroize_pulse_o    <= requested_control[2];

                            if(requested_control[2])
                                key_staging_o <= 256'd0;
                        end
                    end

                    ADDR_CFG:
                    begin
                        if(wstrb_q[0])
                            cfg_decrypt_o <= wdata_q[0];
                        if(wstrb_q[1])
                            cfg_tag_bits_o <= wdata_q[15:8];
                    end

                    ADDR_IV_LEN:
                    begin
                        if(wstrb_q[0])
                            iv_len_bits_o[7:0] <= wdata_q[7:0];
                        if(wstrb_q[1])
                            iv_len_bits_o[10:8] <= wdata_q[10:8];
                    end

                    ADDR_AAD_LEN:
                    begin
                        if(wstrb_q[0])
                            aad_len_bits_o[7:0] <= wdata_q[7:0];
                        if(wstrb_q[1])
                            aad_len_bits_o[10:8] <= wdata_q[10:8];
                    end

                    ADDR_DATA_LEN:
                    begin
                        if(wstrb_q[0])
                            data_len_bits_o[7:0] <= wdata_q[7:0];
                        if(wstrb_q[1])
                            data_len_bits_o[10:8] <= wdata_q[10:8];
                    end

                    ADDR_KEY_WORD0:
                        key_staging_o[255:224] <= apply_wstrb(
                            key_staging_o[255:224], wdata_q, wstrb_q);
                    ADDR_KEY_WORD1:
                        key_staging_o[223:192] <= apply_wstrb(
                            key_staging_o[223:192], wdata_q, wstrb_q);
                    ADDR_KEY_WORD2:
                        key_staging_o[191:160] <= apply_wstrb(
                            key_staging_o[191:160], wdata_q, wstrb_q);
                    ADDR_KEY_WORD3:
                        key_staging_o[159:128] <= apply_wstrb(
                            key_staging_o[159:128], wdata_q, wstrb_q);
                    ADDR_KEY_WORD4:
                        key_staging_o[127:96] <= apply_wstrb(
                            key_staging_o[127:96], wdata_q, wstrb_q);
                    ADDR_KEY_WORD5:
                        key_staging_o[95:64] <= apply_wstrb(
                            key_staging_o[95:64], wdata_q, wstrb_q);
                    ADDR_KEY_WORD6:
                        key_staging_o[63:32] <= apply_wstrb(
                            key_staging_o[63:32], wdata_q, wstrb_q);
                    ADDR_KEY_WORD7:
                        key_staging_o[31:0] <= apply_wstrb(
                            key_staging_o[31:0], wdata_q, wstrb_q);

                    default:
                        s_axi_bresp <= AXI_RESP_SLVERR;
                endcase
            end
        end
    end
end

always @(posedge s_axi_aclk)
begin
    if(!s_axi_aresetn)
    begin
        s_axi_rdata          <= 32'd0;
        s_axi_rresp          <= AXI_RESP_OKAY;
        s_axi_rvalid         <= 1'b0;
        status_snapshot_q    <= 6'd0;
        status_read_pending_q<= 1'b0;
    end
    else
    begin
        if(s_axi_rvalid && s_axi_rready)
            s_axi_rvalid <= 1'b0;

        if(status_read_pending_q)
        begin
            s_axi_rdata           <= {26'd0, status_snapshot_q};
            s_axi_rresp           <= AXI_RESP_OKAY;
            s_axi_rvalid          <= 1'b1;
            status_read_pending_q <= 1'b0;
        end

        if(s_axi_arready && s_axi_arvalid)
        begin
            if(s_axi_araddr[1:0] != 2'b00)
            begin
                s_axi_rdata  <= 32'd0;
                s_axi_rresp  <= AXI_RESP_SLVERR;
                s_axi_rvalid <= 1'b1;
            end
            else if(s_axi_araddr == ADDR_STATUS)
            begin
                status_snapshot_q     <= status_value[5:0];
                status_read_pending_q <= 1'b1;
            end
            else
            begin
                s_axi_rdata  <= 32'd0;
                s_axi_rresp  <= AXI_RESP_OKAY;
                s_axi_rvalid <= 1'b1;

                case(s_axi_araddr)
                    ADDR_CONTROL:
                        s_axi_rdata <= 32'd0;
                    ADDR_CFG:
                        s_axi_rdata <= cfg_value;
                    ADDR_IV_LEN:
                        s_axi_rdata <= {21'd0, iv_len_bits_o};
                    ADDR_AAD_LEN:
                        s_axi_rdata <= {21'd0, aad_len_bits_o};
                    ADDR_DATA_LEN:
                        s_axi_rdata <= {21'd0, data_len_bits_o};
                    ADDR_KEY_WORD0,
                    ADDR_KEY_WORD1,
                    ADDR_KEY_WORD2,
                    ADDR_KEY_WORD3,
                    ADDR_KEY_WORD4,
                    ADDR_KEY_WORD5,
                    ADDR_KEY_WORD6,
                    ADDR_KEY_WORD7:
                        s_axi_rdata <= 32'd0;
                    ADDR_CAPABILITY:
                        s_axi_rdata <= CAPABILITY_VALUE;
                    default:
                    begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= AXI_RESP_SLVERR;
                    end
                endcase
            end
        end
    end
end

// Protection attributes are accepted as part of the AXI4-Lite boundary.  This
// register bank does not implement privilege- or security-based filtering.
wire unused_prot;
assign unused_prot = ^s_axi_awprot ^ ^s_axi_arprot;

endmodule
