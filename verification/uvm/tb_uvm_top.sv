`timescale 1ns/1ps

module tb_uvm_top;
    import uvm_pkg::*;
    import aesgcm_uvm_pkg::*;

    logic clk=0;
    always #2.857 clk=~clk;

    axi_lite_if control_if(clk);
    axis_input_if input_if(clk);
    axis_output_if #(4) data_if(clk);
    axis_output_if #(4) tag_if(clk);
    axis_output_if #(4) result_if(clk);

    assign input_if.aresetn=control_if.aresetn;
    assign data_if.aresetn=control_if.aresetn;
    assign tag_if.aresetn=control_if.aresetn;
    assign result_if.aresetn=control_if.aresetn;

    aes_gcm_axi_top dut (
        .aclk(clk),.aresetn(control_if.aresetn),.key_mode(control_if.key_mode),
        .s_axi_awaddr(control_if.awaddr),.s_axi_awprot(control_if.awprot),
        .s_axi_awvalid(control_if.awvalid),.s_axi_awready(control_if.awready),
        .s_axi_wdata(control_if.wdata),.s_axi_wstrb(control_if.wstrb),
        .s_axi_wvalid(control_if.wvalid),.s_axi_wready(control_if.wready),
        .s_axi_bresp(control_if.bresp),.s_axi_bvalid(control_if.bvalid),
        .s_axi_bready(control_if.bready),.s_axi_araddr(control_if.araddr),
        .s_axi_arprot(control_if.arprot),.s_axi_arvalid(control_if.arvalid),
        .s_axi_arready(control_if.arready),.s_axi_rdata(control_if.rdata),
        .s_axi_rresp(control_if.rresp),.s_axi_rvalid(control_if.rvalid),
        .s_axi_rready(control_if.rready),
        .s_axis_tdata(input_if.tdata),.s_axis_tvalid(input_if.tvalid),
        .s_axis_tready(input_if.tready),.s_axis_tlast(input_if.tlast),
        .m_axis_data_tdata(data_if.tdata),.m_axis_data_tvalid(data_if.tvalid),
        .m_axis_data_tready(data_if.tready),.m_axis_data_tlast(data_if.tlast),
        .m_axis_data_tuser(data_if.tuser),
        .m_axis_tag_tdata(tag_if.tdata),.m_axis_tag_tvalid(tag_if.tvalid),
        .m_axis_tag_tready(tag_if.tready),.m_axis_tag_tlast(tag_if.tlast),
        .m_axis_result_tdata(result_if.tdata),
        .m_axis_result_tvalid(result_if.tvalid),
        .m_axis_result_tready(result_if.tready),
        .m_axis_result_tlast(result_if.tlast)
    );
    assign tag_if.tuser=4'd0;
    assign result_if.tuser=4'd0;

    initial begin
        control_if.aresetn=0;
        control_if.key_mode=0;
        repeat(8) @(posedge clk);
        control_if.aresetn=1;
    end

    initial begin
        string selected_test;
        uvm_config_db#(virtual axi_lite_if)::set(null,"uvm_test_top.env.axi_lite*","vif",control_if);
        uvm_config_db#(virtual axis_input_if)::set(null,"uvm_test_top.env.input_axis*","vif",input_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.data_output*","vif",data_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.tag_output*","vif",tag_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.result_output*","vif",result_if);
        uvm_config_db#(virtual axi_lite_if)::set(null,"uvm_test_top.env.reconstruction","control_vif",control_if);
        uvm_config_db#(virtual axis_input_if)::set(null,"uvm_test_top.env.reconstruction","input_vif",input_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.reconstruction","data_vif",data_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.reconstruction","tag_vif",tag_if);
        uvm_config_db#(virtual axis_output_if #(4))::set(null,"uvm_test_top.env.reconstruction","result_vif",result_if);
        if(!$value$plusargs("UVM_TESTNAME_%s",selected_test))
            selected_test="aesgcm_uvm_test";
        run_test(selected_test);
    end
endmodule
