`timescale 1ns/1ps
// AXI4-Stream beat FIFO: TLAST and TKEEP travel with TDATA.
// This is not a store-and-forward packet admission engine.
module axis_packet_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = 16,
    parameter integer KEEP_WIDTH = DATA_WIDTH/8,
    parameter integer COUNT_W = $clog2(DEPTH+1)
) (
    input wire aclk, input wire aresetn,
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s_axis_tkeep,
    input wire s_axis_tlast, input wire s_axis_tvalid,
    output wire s_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire m_axis_tlast, output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire [COUNT_W-1:0] level
);
    sync_fifo #(.WIDTH(DATA_WIDTH+KEEP_WIDTH+1), .DEPTH(DEPTH)) fifo (
        .clk(aclk), .rst_n(aresetn),
        .s_data({s_axis_tlast,s_axis_tkeep,s_axis_tdata}),
        .s_valid(s_axis_tvalid), .s_ready(s_axis_tready),
        .m_data({m_axis_tlast,m_axis_tkeep,m_axis_tdata}),
        .m_valid(m_axis_tvalid), .m_ready(m_axis_tready), .level(level)
    );
endmodule
