`timescale 1ns / 1ps

// One-entry AXI4-Stream elastic output register.  It holds every payload
// sideband stable while the downstream applies back-pressure and can replace
// a consumed beat in the same cycle, so a ready downstream sees no bubbles.
module axis_output_skid_8 #(
    parameter integer USER_WIDTH = 1
)
(
    input                       aclk,
    input                       aresetn,
    input                       clear,

    input      [7:0]            s_axis_tdata,
    input                       s_axis_tkeep,
    input                       s_axis_tlast,
    input      [USER_WIDTH-1:0] s_axis_tuser,
    input                       s_axis_tvalid,
    output                      s_axis_tready,

    output     [7:0]            m_axis_tdata,
    output                      m_axis_tkeep,
    output                      m_axis_tlast,
    output     [USER_WIDTH-1:0] m_axis_tuser,
    output                      m_axis_tvalid,
    input                       m_axis_tready
);

reg [7:0]            data_q;
reg                  keep_q;
reg                  last_q;
reg [USER_WIDTH-1:0] user_q;
reg                  valid_q;

assign s_axis_tready = !valid_q || m_axis_tready;

assign m_axis_tdata  = data_q;
assign m_axis_tkeep  = keep_q;
assign m_axis_tlast  = last_q;
assign m_axis_tuser  = user_q;
assign m_axis_tvalid = valid_q;

always @(posedge aclk)
begin
    if(!aresetn || clear)
    begin
        data_q  <= 8'd0;
        keep_q  <= 1'b0;
        last_q  <= 1'b0;
        user_q  <= {USER_WIDTH{1'b0}};
        valid_q <= 1'b0;
    end
    else if(s_axis_tready)
    begin
        valid_q <= s_axis_tvalid;

        if(s_axis_tvalid)
        begin
            data_q <= s_axis_tdata;
            keep_q <= s_axis_tkeep;
            last_q <= s_axis_tlast;
            user_q <= s_axis_tuser;
        end
    end
end

endmodule
