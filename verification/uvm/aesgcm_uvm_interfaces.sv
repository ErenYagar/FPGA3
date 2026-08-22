`timescale 1ns/1ps

interface axi_lite_if(input logic aclk);
    logic aresetn;
    logic [2:0] key_mode;
    logic [6:0] awaddr;
    logic [2:0] awprot;
    logic awvalid, awready;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic wvalid, wready;
    logic [1:0] bresp;
    logic bvalid, bready;
    logic [6:0] araddr;
    logic [2:0] arprot;
    logic arvalid, arready;
    logic [31:0] rdata;
    logic [1:0] rresp;
    logic rvalid, rready;

    clocking driver_cb @(posedge aclk);
        output key_mode, awaddr, awprot, awvalid, wdata, wstrb, wvalid,
               bready, araddr, arprot, arvalid, rready;
        input awready, wready, bresp, bvalid, arready, rdata, rresp, rvalid;
    endclocking
    clocking monitor_cb @(posedge aclk);
        input aresetn, key_mode, awaddr, awvalid, awready, wdata, wstrb,
              wvalid, wready, bresp, bvalid, bready, araddr, arvalid,
              arready, rdata, rresp, rvalid, rready;
    endclocking
endinterface

interface axis_input_if(input logic aclk);
    logic aresetn;
    logic [7:0] tdata;
    logic tvalid, tready, tlast;
    clocking driver_cb @(posedge aclk);
        output tdata, tvalid, tlast;
        input tready;
    endclocking
    clocking monitor_cb @(posedge aclk);
        input aresetn, tdata, tvalid, tready, tlast;
    endclocking
endinterface

interface axis_output_if #(parameter integer USER_WIDTH = 1)(input logic aclk);
    logic aresetn;
    logic [7:0] tdata;
    logic tvalid, tready, tlast;
    logic [USER_WIDTH-1:0] tuser;
    clocking driver_cb @(posedge aclk);
        output tready;
        input tdata, tvalid, tlast, tuser;
    endclocking
    clocking monitor_cb @(posedge aclk);
        input aresetn, tdata, tvalid, tready, tlast, tuser;
    endclocking
endinterface
