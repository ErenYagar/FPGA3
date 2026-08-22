`timescale 1ns/1ps

module board_sdp_bram #(
    parameter integer WIDTH=8,
    parameter integer ADDR_WIDTH=8,
    parameter integer DEPTH=256
)(
    input logic clk,
    input logic write_enable,
    input logic [ADDR_WIDTH-1:0] write_address,
    input logic [WIDTH-1:0] write_data,
    input logic read_enable,
    input logic [ADDR_WIDTH-1:0] read_address,
    output logic [WIDTH-1:0] read_data
);
    (* ram_style="block" *) logic [WIDTH-1:0] memory[0:DEPTH-1];
    always_ff @(posedge clk)
        if(write_enable)memory[write_address]<=write_data;
    always_ff @(posedge clk)
        if(read_enable)read_data<=memory[read_address];
endmodule

module board_test_shell #(
    parameter integer AXI_ADDR_WIDTH = 12,
    parameter integer INPUT_DEPTH = 256,
    parameter integer OUTPUT_DEPTH = 512
) (
    input logic aclk,input logic aresetn,input logic [2:0] key_mode,
    input logic [AXI_ADDR_WIDTH-1:0] s_ctrl_awaddr,input logic s_ctrl_awvalid,output logic s_ctrl_awready,
    input logic [31:0] s_ctrl_wdata,input logic [3:0] s_ctrl_wstrb,input logic s_ctrl_wvalid,output logic s_ctrl_wready,
    output logic [1:0] s_ctrl_bresp,output logic s_ctrl_bvalid,input logic s_ctrl_bready,
    input logic [AXI_ADDR_WIDTH-1:0] s_ctrl_araddr,input logic s_ctrl_arvalid,output logic s_ctrl_arready,
    output logic [31:0] s_ctrl_rdata,output logic [1:0] s_ctrl_rresp,output logic s_ctrl_rvalid,input logic s_ctrl_rready,
    input logic [6:0] s_dut_awaddr,input logic [2:0] s_dut_awprot,input logic s_dut_awvalid,output logic s_dut_awready,
    input logic [31:0] s_dut_wdata,input logic [3:0] s_dut_wstrb,input logic s_dut_wvalid,output logic s_dut_wready,
    output logic [1:0] s_dut_bresp,output logic s_dut_bvalid,input logic s_dut_bready,
    input logic [6:0] s_dut_araddr,input logic [2:0] s_dut_arprot,input logic s_dut_arvalid,output logic s_dut_arready,
    output logic [31:0] s_dut_rdata,output logic [1:0] s_dut_rresp,output logic s_dut_rvalid,input logic s_dut_rready,
    output logic irq
);
    localparam logic [11:0] ADDR_CONTROL=12'h000,ADDR_STATUS=12'h004,
        ADDR_INPUT_LEN=12'h008,ADDR_STALL_CFG=12'h00c,
        ADDR_CYCLES=12'h010,ADDR_INPUT_COUNT=12'h014,
        ADDR_OUTPUT_COUNT=12'h018,ADDR_STALL_COUNT=12'h01c,
        INPUT_BASE=12'h100,OUTPUT_BASE=12'h800;
    logic [AXI_ADDR_WIDTH-1:0] awaddr_q;logic aw_seen;
    logic [31:0] wdata_q;logic [3:0] wstrb_q;logic w_seen;
    logic running,done,overflow;logic [8:0] input_length,input_index;
    logic [9:0] output_count;
    logic [31:0] cycle_count,input_count,stall_count;
    logic stall_enable;logic [6:0] stall_threshold;logic [2:0] stall_mask;
    logic [15:0] lfsr;logic feed_valid;logic feed_last,prefetch_pending;
    logic [7:0] input_read_data;
    logic [14:0] output_read_data;logic output_read_pending;
    wire random_ready=(lfsr[6:0]>=stall_threshold)||!stall_enable;

    wire [7:0] data_tdata,tag_tdata,result_tdata;wire data_tvalid,tag_tvalid,result_tvalid;
    wire data_tlast,tag_tlast,result_tlast;wire [3:0] data_tuser;
    wire data_tready=random_ready||!stall_mask[0];
    wire tag_tready=random_ready||!stall_mask[1];
    wire result_tready=random_ready||!stall_mask[2];
    wire dut_input_ready;
    (* mark_debug="true" *) wire data_fire=data_tvalid&&data_tready;
    (* mark_debug="true" *) wire tag_fire=tag_tvalid&&tag_tready;
    (* mark_debug="true" *) wire result_fire=result_tvalid&&result_tready;
    (* mark_debug="true" *) wire feed_fire=feed_valid&&dut_input_ready;
    wire any_stall=(feed_valid&&!dut_input_ready)||(data_tvalid&&!data_tready)||
                   (tag_tvalid&&!tag_tready)||(result_tvalid&&!result_tready);
    wire input_write_enable=aw_seen&&w_seen&&!s_ctrl_bvalid&&
        awaddr_q>=INPUT_BASE&&awaddr_q<(INPUT_BASE+INPUT_DEPTH*4);
    wire [7:0] input_write_address=(awaddr_q-INPUT_BASE)>>2;
    wire output_write_enable=(data_fire||tag_fire||result_fire)&&
        output_count<OUTPUT_DEPTH;
    wire [14:0] output_write_data=data_fire?{2'd0,data_tlast,data_tuser,data_tdata}:
        tag_fire?{2'd1,tag_tlast,4'd0,tag_tdata}:
        {2'd2,result_tlast,4'd0,result_tdata};
    wire output_read_enable=s_ctrl_arready&&s_ctrl_arvalid&&
        s_ctrl_araddr>=OUTPUT_BASE&&s_ctrl_araddr<(OUTPUT_BASE+OUTPUT_DEPTH*4);
    wire [8:0] output_read_address=(s_ctrl_araddr-OUTPUT_BASE)>>2;
    wire [7:0] feed_data=input_read_data;
    wire [7:0] input_bram_read_address=(feed_fire&&!feed_last)?
        (input_index[7:0]+8'd1):input_index[7:0];

    board_sdp_bram #(.WIDTH(8),.ADDR_WIDTH(8),.DEPTH(INPUT_DEPTH)) input_bram(
        .clk(aclk),.write_enable(input_write_enable),
        .write_address(input_write_address),.write_data(wdata_q[7:0]),
        .read_enable(1'b1),.read_address(input_bram_read_address),.read_data(input_read_data));
    board_sdp_bram #(.WIDTH(15),.ADDR_WIDTH(9),.DEPTH(OUTPUT_DEPTH)) output_bram(
        .clk(aclk),.write_enable(output_write_enable),.write_address(output_count[8:0]),
        .write_data(output_write_data),.read_enable(output_read_enable),
        .read_address(output_read_address),.read_data(output_read_data));

    assign s_ctrl_awready=!aw_seen&&!s_ctrl_bvalid;
    assign s_ctrl_wready=!w_seen&&!s_ctrl_bvalid;
    assign s_ctrl_arready=!s_ctrl_rvalid&&!output_read_pending;
    assign s_ctrl_bresp=2'b00;assign s_ctrl_rresp=2'b00;
    assign irq=done;

    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            aw_seen<=0;w_seen<=0;s_ctrl_bvalid<=0;s_ctrl_rvalid<=0;
            running<=0;done<=0;overflow<=0;input_length<=0;input_index<=0;
            output_count<=0;cycle_count<=0;input_count<=0;stall_count<=0;
            stall_enable<=0;stall_threshold<=0;stall_mask<=3'b111;lfsr<=16'h1;
            feed_valid<=0;feed_last<=0;prefetch_pending<=0;
            output_read_pending<=0;s_ctrl_rdata<=0;
        end else begin
            lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            if(s_ctrl_awready&&s_ctrl_awvalid)begin awaddr_q<=s_ctrl_awaddr;aw_seen<=1;end
            if(s_ctrl_wready&&s_ctrl_wvalid)begin wdata_q<=s_ctrl_wdata;wstrb_q<=s_ctrl_wstrb;w_seen<=1;end
            if(s_ctrl_bvalid&&s_ctrl_bready)s_ctrl_bvalid<=0;
            if(aw_seen&&w_seen&&!s_ctrl_bvalid)begin
                aw_seen<=0;w_seen<=0;s_ctrl_bvalid<=1;
                if(awaddr_q==ADDR_CONTROL&&wstrb_q[0])begin
                    if(wdata_q[1])begin running<=0;done<=0;feed_valid<=0;output_count<=0;end
                    if(wdata_q[0])begin
                        running<=1;done<=0;overflow<=0;cycle_count<=0;input_count<=0;
                        output_count<=0;stall_count<=0;input_index<=0;
                        feed_valid<=0;prefetch_pending<=(input_length!=0);
                        feed_last<=(input_length==1);
                    end
                end else if(awaddr_q==ADDR_INPUT_LEN) input_length<=wdata_q[8:0];
                else if(awaddr_q==ADDR_STALL_CFG)begin
                    stall_enable<=wdata_q[31];stall_mask<=wdata_q[18:16];
                    stall_threshold<=wdata_q[6:0];if(wdata_q[15:0]!=0)lfsr<=wdata_q[15:0];
                end
            end
            if(s_ctrl_rvalid&&s_ctrl_rready)s_ctrl_rvalid<=0;
            if(output_read_pending)begin
                s_ctrl_rvalid<=1;output_read_pending<=0;
                s_ctrl_rdata<={17'd0,output_read_data};
            end
            if(s_ctrl_arready&&s_ctrl_arvalid)begin
                if(output_read_enable)output_read_pending<=1;
                else begin
                  s_ctrl_rvalid<=1;
                  case(s_ctrl_araddr)
                    ADDR_STATUS:s_ctrl_rdata<={28'd0,overflow,feed_valid,done,running};
                    ADDR_INPUT_LEN:s_ctrl_rdata<={23'd0,input_length};
                    ADDR_STALL_CFG:s_ctrl_rdata<={stall_enable,12'd0,stall_mask,9'd0,stall_threshold};
                    ADDR_CYCLES:s_ctrl_rdata<=cycle_count;
                    ADDR_INPUT_COUNT:s_ctrl_rdata<=input_count;
                    ADDR_OUTPUT_COUNT:s_ctrl_rdata<=output_count;
                    ADDR_STALL_COUNT:s_ctrl_rdata<=stall_count;
                    default:s_ctrl_rdata<=32'd0;
                  endcase
                end
            end
            if(running)cycle_count<=cycle_count+1;
            if(any_stall)stall_count<=stall_count+1;
            if(prefetch_pending)begin feed_valid<=1;prefetch_pending<=0;end
            if(feed_fire)begin
                input_count<=input_count+1;
                if(feed_last)feed_valid<=0;
                else begin input_index<=input_index+1;
                    feed_last<=((input_index+2)==input_length);end
            end
            if(data_fire||tag_fire||result_fire)begin
                if(output_count<OUTPUT_DEPTH)begin
                    output_count<=output_count+1;
                end else overflow<=1;
            end
            if(result_fire)begin running<=0;done<=1;end
        end
    end

    aes_gcm_axi_top dut(
        .aclk(aclk),.aresetn(aresetn),.key_mode(key_mode),
        .s_axi_awaddr(s_dut_awaddr),.s_axi_awprot(s_dut_awprot),.s_axi_awvalid(s_dut_awvalid),.s_axi_awready(s_dut_awready),
        .s_axi_wdata(s_dut_wdata),.s_axi_wstrb(s_dut_wstrb),.s_axi_wvalid(s_dut_wvalid),.s_axi_wready(s_dut_wready),
        .s_axi_bresp(s_dut_bresp),.s_axi_bvalid(s_dut_bvalid),.s_axi_bready(s_dut_bready),
        .s_axi_araddr(s_dut_araddr),.s_axi_arprot(s_dut_arprot),.s_axi_arvalid(s_dut_arvalid),.s_axi_arready(s_dut_arready),
        .s_axi_rdata(s_dut_rdata),.s_axi_rresp(s_dut_rresp),.s_axi_rvalid(s_dut_rvalid),.s_axi_rready(s_dut_rready),
        .s_axis_tdata(feed_data),.s_axis_tvalid(feed_valid),.s_axis_tready(dut_input_ready),.s_axis_tlast(feed_last),
        .m_axis_data_tdata(data_tdata),.m_axis_data_tvalid(data_tvalid),.m_axis_data_tready(data_tready),.m_axis_data_tlast(data_tlast),.m_axis_data_tuser(data_tuser),
        .m_axis_tag_tdata(tag_tdata),.m_axis_tag_tvalid(tag_tvalid),.m_axis_tag_tready(tag_tready),.m_axis_tag_tlast(tag_tlast),
        .m_axis_result_tdata(result_tdata),.m_axis_result_tvalid(result_tvalid),.m_axis_result_tready(result_tready),.m_axis_result_tlast(result_tlast));
endmodule
