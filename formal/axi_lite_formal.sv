// Bounded occupancy abstraction for compositional AXI-Lite control proof.
// The production stream FIFO is separately checked by fifo_formal.sv.
module axis_packet_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = 16,
    parameter integer KEEP_WIDTH = DATA_WIDTH/8,
    parameter integer COUNT_W = $clog2(DEPTH+1)
) (
    input wire aclk,
    input wire aresetn,
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s_axis_tkeep,
    input wire s_axis_tlast,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire m_axis_tlast,
    output wire m_axis_tvalid,
    input wire m_axis_tready,
    output wire [COUNT_W-1:0] level
);
    (* anyseq *) reg [COUNT_W-1:0] any_level;
    assign level = !aresetn ? {COUNT_W{1'b0}} :
                   ((any_level <= DEPTH) ? any_level : {COUNT_W{1'b0}});
    assign s_axis_tready = 1'b0;
    assign m_axis_tdata = {DATA_WIDTH{1'b0}};
    assign m_axis_tkeep = {KEEP_WIDTH{1'b0}};
    assign m_axis_tlast = 1'b0;
    assign m_axis_tvalid = 1'b0;
endmodule

module axi_lite_formal(input wire clk);
    localparam integer DEPTH = 2;

    (* anyseq *) reg aresetn;
    (* anyseq *) reg [31:0] awaddr;
    (* anyseq *) reg awvalid;
    wire awready;
    (* anyseq *) reg [31:0] wdata;
    (* anyseq *) reg [3:0] wstrb;
    (* anyseq *) reg wvalid;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    (* anyseq *) reg bready;

    (* anyseq *) reg [31:0] araddr;
    (* anyseq *) reg arvalid;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    (* anyseq *) reg rready;

    wire [7:0] s_data;
    wire [0:0] s_keep;
    (* anyseq *) reg s_last;
    (* anyseq *) reg s_valid;
    wire s_ready;
    wire [7:0] m_data;
    wire [0:0] m_keep;
    wire m_last, m_valid;
    (* anyseq *) reg m_ready;
    wire [1:0] level;
    wire irq;

    (* anyseq *) reg [7:0] arbitrary_data;
    (* anyseq *) reg arbitrary_keep;
    assign s_data = arbitrary_data;
    assign s_keep = arbitrary_keep;

    axi_lite_axis_fifo #(
        .DATA_WIDTH(8), .DEPTH(DEPTH), .KEEP_WIDTH(1)
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s_axis_tdata(s_data), .s_axis_tkeep(s_keep), .s_axis_tlast(s_last),
        .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
        .m_axis_tdata(m_data), .m_axis_tkeep(m_keep), .m_axis_tlast(m_last),
        .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
        .level(level), .irq(irq)
    );

    reg past_valid = 1'b0;
    always @(posedge clk) begin
        past_valid <= 1'b1;
        if (!past_valid) assume(!aresetn);

        // AXI manager obligations: hold each request and payload while stalled.
        if (past_valid && $past(aresetn && awvalid && !awready)) begin
            assume(awvalid);
            assume(awaddr == $past(awaddr));
        end
        if (past_valid && $past(aresetn && wvalid && !wready)) begin
            assume(wvalid);
            assume({wdata,wstrb} == $past({wdata,wstrb}));
        end
        if (past_valid && $past(aresetn && arvalid && !arready)) begin
            assume(arvalid);
            assume(araddr == $past(araddr));
        end
    end
endmodule
