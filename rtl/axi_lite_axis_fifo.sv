`timescale 1ns/1ps
// AXI4-Lite control/status wrapper around the AXI4-Stream beat FIFO.
// Register writes and stream transfers use the same clock and active-low reset.
module axi_lite_axis_fifo #(
    parameter integer DATA_WIDTH = 32,
    parameter integer DEPTH = 16,
    parameter integer KEEP_WIDTH = DATA_WIDTH/8,
    parameter integer COUNT_W = $clog2(DEPTH+1)
) (
    input wire aclk,
    input wire aresetn,

    // AXI4-Lite write address channel
    input wire [31:0] s_axi_awaddr,
    input wire s_axi_awvalid,
    output wire s_axi_awready,
    // AXI4-Lite write data channel
    input wire [31:0] s_axi_wdata,
    input wire [3:0] s_axi_wstrb,
    input wire s_axi_wvalid,
    output wire s_axi_wready,
    // AXI4-Lite write response channel
    output reg [1:0] s_axi_bresp,
    output reg s_axi_bvalid,
    input wire s_axi_bready,

    // AXI4-Lite read address channel
    input wire [31:0] s_axi_araddr,
    input wire s_axi_arvalid,
    output wire s_axi_arready,
    // AXI4-Lite read data/response channel
    output reg [31:0] s_axi_rdata,
    output reg [1:0] s_axi_rresp,
    output reg s_axi_rvalid,
    input wire s_axi_rready,

    // AXI4-Stream source
    input wire [DATA_WIDTH-1:0] s_axis_tdata,
    input wire [KEEP_WIDTH-1:0] s_axis_tkeep,
    input wire s_axis_tlast,
    input wire s_axis_tvalid,
    output wire s_axis_tready,

    // AXI4-Stream sink
    output wire [DATA_WIDTH-1:0] m_axis_tdata,
    output wire [KEEP_WIDTH-1:0] m_axis_tkeep,
    output wire m_axis_tlast,
    output wire m_axis_tvalid,
    input wire m_axis_tready,

    output wire [COUNT_W-1:0] level,
    output wire irq
);
    localparam [31:0] ADDR_CONTROL   = 32'h0000_0000;
    localparam [31:0] ADDR_STATUS    = 32'h0000_0004;
    localparam [31:0] ADDR_LEVEL     = 32'h0000_0008;
    localparam [31:0] ADDR_THRESHOLD = 32'h0000_000c;
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    reg [31:0] awaddr_q;
    reg [31:0] wdata_q;
    reg [3:0] wstrb_q;
    reg aw_pending, w_pending;
    reg irq_enable;
    reg [31:0] irq_threshold;
    wire [COUNT_W-1:0] fifo_level;

    reg [31:0] threshold_merged;
    reg write_error;

    function [31:0] merge_bytes;
        input [31:0] old_value;
        input [31:0] write_value;
        input [3:0] strobe;
        integer byte_index;
        begin
            merge_bytes = old_value;
            for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                if (strobe[byte_index])
                    merge_bytes[byte_index*8 +: 8] = write_value[byte_index*8 +: 8];
        end
    endfunction

    wire write_commit = aw_pending && w_pending && !s_axi_bvalid;
    wire [31:0] status_word = {29'b0, irq, (fifo_level == DEPTH), (fifo_level == 0)};
    wire [31:0] level_word = fifo_level;

    assign irq = irq_enable && (irq_threshold != 0) &&
                 (fifo_level >= irq_threshold[COUNT_W-1:0]);
    assign level = fifo_level;

    // Each write channel has an independent one-entry holding slot.
    // Neither channel is accepted while a previous B response is pending.
    assign s_axi_awready = aresetn && !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = aresetn && !w_pending  && !s_axi_bvalid;
    assign s_axi_arready = aresetn && !s_axi_rvalid;

    always @* begin
        threshold_merged = merge_bytes(irq_threshold, wdata_q, wstrb_q);
        write_error = 1'b0;
        if (awaddr_q[1:0] != 2'b00) begin
            write_error = 1'b1;
        end else begin
            case (awaddr_q)
                ADDR_CONTROL: begin
                    write_error = 1'b0;
                end
                ADDR_THRESHOLD: begin
                    if (threshold_merged == 0 || threshold_merged > DEPTH)
                        write_error = 1'b1;
                end
                ADDR_STATUS, ADDR_LEVEL: write_error = 1'b1;
                default: write_error = 1'b1;
            endcase
        end
    end

    axis_packet_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .COUNT_W(COUNT_W)
    ) stream_fifo (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_axis_tdata), .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tlast(s_axis_tlast), .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata), .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tlast(m_axis_tlast), .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready), .level(fifo_level)
    );

    always @(posedge aclk) begin
        if (!aresetn) begin
            awaddr_q <= 0;
            wdata_q <= 0;
            wstrb_q <= 0;
            aw_pending <= 1'b0;
            w_pending <= 1'b0;
            irq_enable <= 1'b0;
            irq_threshold <= DEPTH;
            s_axi_bresp <= RESP_OKAY;
            s_axi_bvalid <= 1'b0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_q <= s_axi_awaddr;
                aw_pending <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_q <= s_axi_wdata;
                wstrb_q <= s_axi_wstrb;
                w_pending <= 1'b1;
            end

            if (write_commit) begin
                if (!write_error) begin
                    case (awaddr_q)
                        ADDR_CONTROL: begin
                            if (wstrb_q[0]) irq_enable <= wdata_q[0];
                        end
                        ADDR_THRESHOLD: irq_threshold <= threshold_merged;
                        default: begin end
                    endcase
                end
                s_axi_bresp <= write_error ? RESP_SLVERR : RESP_OKAY;
                s_axi_bvalid <= 1'b1;
                aw_pending <= 1'b0;
                w_pending <= 1'b0;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_rdata <= 0;
            s_axi_rresp <= RESP_OKAY;
            s_axi_rvalid <= 1'b0;
        end else begin
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid <= 1'b1;
                if (s_axi_araddr[1:0] != 2'b00) begin
                    s_axi_rdata <= 0;
                    s_axi_rresp <= RESP_SLVERR;
                end else begin
                    case (s_axi_araddr)
                        ADDR_CONTROL: begin
                            s_axi_rdata <= {31'b0, irq_enable};
                            s_axi_rresp <= RESP_OKAY;
                        end
                        ADDR_STATUS: begin
                            s_axi_rdata <= status_word;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        ADDR_LEVEL: begin
                            s_axi_rdata <= level_word;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        ADDR_THRESHOLD: begin
                            s_axi_rdata <= irq_threshold;
                            s_axi_rresp <= RESP_OKAY;
                        end
                        default: begin
                            s_axi_rdata <= 0;
                            s_axi_rresp <= RESP_SLVERR;
                        end
                    endcase
                end
            end
        end
    end

`ifdef AXI_LITE_FORMAL
    // Formal-only local properties. The formal harness replaces the stream
    // FIFO with a bounded occupancy abstraction; the stream FIFO itself is
    // covered by formal/fifo_formal.sv and its existing runner.
    reg axi_f_past_valid = 1'b0;
    always @(posedge aclk) begin
        axi_f_past_valid <= 1'b1;

        if (axi_f_past_valid && aresetn &&
            $past(aresetn && s_axi_bvalid && !s_axi_bready)) begin
            assert(s_axi_bvalid);
            assert(s_axi_bresp == $past(s_axi_bresp));
        end
        if (axi_f_past_valid && aresetn &&
            $past(aresetn && s_axi_rvalid && !s_axi_rready)) begin
            assert(s_axi_rvalid);
            assert(s_axi_rdata == $past(s_axi_rdata));
            assert(s_axi_rresp == $past(s_axi_rresp));
        end
        if (axi_f_past_valid && $past(!aresetn)) begin
            assert(!s_axi_bvalid);
            assert(!s_axi_rvalid);
            assert(!irq_enable);
            assert(irq_threshold == DEPTH);
        end

        if (axi_f_past_valid && aresetn) begin
            assert(irq_threshold >= 1 && irq_threshold <= DEPTH);
            assert(irq == (irq_enable && (irq_threshold != 0) &&
                           (fifo_level >= irq_threshold[COUNT_W-1:0])));
            if (s_axi_bvalid)
                assert(s_axi_bresp == RESP_OKAY || s_axi_bresp == RESP_SLVERR);
            if (s_axi_rvalid)
                assert(s_axi_rresp == RESP_OKAY || s_axi_rresp == RESP_SLVERR);
        end

        // A completed register write changes only its documented register.
        if (axi_f_past_valid && aresetn && $past(aresetn && write_commit)) begin
            if ($past(write_error)) begin
                assert(irq_enable == $past(irq_enable));
                assert(irq_threshold == $past(irq_threshold));
            end else begin
                case ($past(awaddr_q))
                    ADDR_CONTROL: begin
                        if ($past(wstrb_q[0]))
                            assert(irq_enable == $past(wdata_q[0]));
                        else
                            assert(irq_enable == $past(irq_enable));
                        assert(irq_threshold == $past(irq_threshold));
                    end
                    ADDR_THRESHOLD: begin
                        assert(irq_threshold == $past(threshold_merged));
                        assert(irq_enable == $past(irq_enable));
                    end
                    default: begin
                        assert(irq_enable == $past(irq_enable));
                        assert(irq_threshold == $past(irq_threshold));
                    end
                endcase
            end
        end

        // The read response must snapshot the mapped register at AR handshake.
        if (axi_f_past_valid && aresetn &&
            $past(aresetn && s_axi_arvalid && s_axi_arready)) begin
            assert(s_axi_rvalid);
            if ($past(s_axi_araddr[1:0] != 0)) begin
                assert(s_axi_rdata == 0 && s_axi_rresp == RESP_SLVERR);
            end else begin
                case ($past(s_axi_araddr))
                    ADDR_CONTROL: begin
                        assert(s_axi_rdata == {31'b0, $past(irq_enable)});
                        assert(s_axi_rresp == RESP_OKAY);
                    end
                    ADDR_STATUS: begin
                        assert(s_axi_rdata == $past(status_word));
                        assert(s_axi_rresp == RESP_OKAY);
                    end
                    ADDR_LEVEL: begin
                        assert(s_axi_rdata == $past(level_word));
                        assert(s_axi_rresp == RESP_OKAY);
                    end
                    ADDR_THRESHOLD: begin
                        assert(s_axi_rdata == $past(irq_threshold));
                        assert(s_axi_rresp == RESP_OKAY);
                    end
                    default: begin
                        assert(s_axi_rdata == 0 && s_axi_rresp == RESP_SLVERR);
                    end
                endcase
            end
        end

        cover(aw_pending && !w_pending);
        cover(w_pending && !aw_pending);
        cover(s_axi_bvalid && !s_axi_bready);
        cover(s_axi_rvalid && !s_axi_rready);
        cover(irq);
    end
`endif
endmodule
