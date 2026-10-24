`timescale 1ns/1ps
module tb_axi_lite_axis_fifo;
    localparam integer DEPTH = 4;
    localparam integer CW = $clog2(DEPTH+1);
    localparam [1:0] OKAY = 2'b00;
    localparam [1:0] SLVERR = 2'b10;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg [31:0] awaddr = 0;
    reg awvalid = 0;
    wire awready;
    reg [31:0] wdata = 0;
    reg [3:0] wstrb = 0;
    reg wvalid = 0;
    wire wready;
    wire [1:0] bresp;
    wire bvalid;
    reg bready = 0;

    reg [31:0] araddr = 0;
    reg arvalid = 0;
    wire arready;
    wire [31:0] rdata;
    wire [1:0] rresp;
    wire rvalid;
    reg rready = 0;

    reg [31:0] s_data = 0;
    reg [3:0] s_keep = 0;
    reg s_last = 0;
    reg s_valid = 0;
    wire s_ready;
    wire [31:0] m_data;
    wire [3:0] m_keep;
    wire m_last, m_valid;
    reg m_ready = 0;
    wire [CW-1:0] level;
    wire irq;
    integer checks = 0;

    axi_lite_axis_fifo #(.DATA_WIDTH(32), .DEPTH(DEPTH)) dut (
        .aclk(clk), .aresetn(rst_n),
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

    task automatic axi_write;
        input [31:0] address;
        input [31:0] value;
        input [3:0] strobes;
        input integer aw_delay;
        input integer w_delay;
        input [1:0] expected_response;
        integer k;
        reg [1:0] held_response;
        begin
            fork
                begin
                    repeat (aw_delay) @(negedge clk);
                    awaddr = address;
                    awvalid = 1;
                    do @(posedge clk); while (!awready);
                    @(negedge clk); awvalid = 0;
                end
                begin
                    repeat (w_delay) @(negedge clk);
                    wdata = value;
                    wstrb = strobes;
                    wvalid = 1;
                    do @(posedge clk); while (!wready);
                    @(negedge clk); wvalid = 0;
                end
            join

            do @(posedge clk); while (!bvalid);
            if (bresp !== expected_response)
                $fatal(1, "B response for addr=%08h: got %b expected %b", address, bresp, expected_response);
            held_response = bresp;
            checks = checks + 1;
            repeat (2) begin
                @(posedge clk);
                if (!bvalid || bresp !== held_response)
                    $fatal(1, "B response changed while stalled at addr=%08h", address);
                checks = checks + 1;
            end
            @(negedge clk); bready = 1;
            @(posedge clk);
            @(negedge clk); bready = 0;
        end
    endtask

    task automatic axi_read;
        input [31:0] address;
        input [31:0] expected_data;
        input [1:0] expected_response;
        integer k;
        reg [31:0] held_data;
        reg [1:0] held_response;
        begin
            @(negedge clk); araddr = address; arvalid = 1;
            do @(posedge clk); while (!arready);
            @(negedge clk); arvalid = 0;
            do @(posedge clk); while (!rvalid);
            if (rdata !== expected_data || rresp !== expected_response)
                $fatal(1, "R response addr=%08h data=%08h resp=%b expected data=%08h resp=%b",
                       address, rdata, rresp, expected_data, expected_response);
            held_data = rdata;
            held_response = rresp;
            checks = checks + 1;
            repeat (2) begin
                @(posedge clk);
                if (!rvalid || rdata !== held_data || rresp !== held_response)
                    $fatal(1, "R response changed while stalled at addr=%08h", address);
                checks = checks + 1;
            end
            @(negedge clk); rready = 1;
            @(posedge clk);
            @(negedge clk); rready = 0;
        end
    endtask

    task automatic push_beat;
        input [31:0] data_value;
        input [3:0] keep_value;
        input last_value;
        begin
            @(negedge clk);
            s_data = data_value; s_keep = keep_value;
            s_last = last_value; s_valid = 1;
            do @(posedge clk); while (!s_ready);
            checks = checks + 1;
            @(negedge clk); s_valid = 0;
        end
    endtask

    task automatic pop_beat;
        input [31:0] expected_data;
        input [3:0] expected_keep;
        input expected_last;
        begin
            @(negedge clk); m_ready = 1;
            do @(posedge clk); while (!m_valid);
            if (m_data !== expected_data || m_keep !== expected_keep || m_last !== expected_last)
                $fatal(1, "Stream mismatch: data=%08h keep=%h last=%b", m_data, m_keep, m_last);
            checks = checks + 1;
            @(negedge clk); m_ready = 0;
        end
    endtask

    task automatic expect_irq;
        input expected;
        begin
            #1;
            if (irq !== expected) $fatal(1, "IRQ got %b expected %b at level %0d", irq, expected, level);
            checks = checks + 1;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;

        // Reset map: CONTROL=0, STATUS.EMPTY=1, LEVEL=0, THRESHOLD=DEPTH.
        axi_read(32'h00, 0, OKAY);
        axi_read(32'h04, 1, OKAY);
        axi_read(32'h08, 0, OKAY);
        axi_read(32'h0c, DEPTH, OKAY);

        // Program threshold with AW first, then enable its level interrupt.
        axi_write(32'h0c, 2, 4'b1111, 0, 3, OKAY);
        axi_write(32'h00, 1, 4'b0001, 2, 0, OKAY);
        axi_read(32'h00, 1, OKAY);
        expect_irq(0);

        // Two accepted stream beats reach threshold; status bit 2 reflects IRQ.
        push_beat(32'h1111_0001, 4'hf, 0);
        expect_irq(0);
        push_beat(32'h2222_0002, 4'hf, 1);
        expect_irq(1);
        axi_read(32'h04, 32'h4, OKAY);
        axi_read(32'h08, 2, OKAY);

        // Pop one, then fill the FIFO. Backpressure and all stream sidebands persist.
        pop_beat(32'h1111_0001, 4'hf, 0);
        expect_irq(0);
        push_beat(32'h3333_0003, 4'h3, 0);
        push_beat(32'h4444_0004, 4'hf, 0);
        push_beat(32'h5555_0005, 4'h1, 1);
        expect_irq(1);
        axi_read(32'h04, 32'h6, OKAY); // FULL=1, IRQ=1
        axi_read(32'h08, DEPTH, OKAY);
        pop_beat(32'h2222_0002, 4'hf, 1);
        pop_beat(32'h3333_0003, 4'h3, 0);
        pop_beat(32'h4444_0004, 4'hf, 0);
        pop_beat(32'h5555_0005, 4'h1, 1);
        expect_irq(0);
        axi_read(32'h04, 1, OKAY); // EMPTY=1

        // Byte strobes preserve untouched bytes; invalid threshold writes do not commit.
        axi_write(32'h0c, 3, 4'b0001, 0, 0, OKAY);
        axi_write(32'h0c, 32'h0000_aa00, 4'b0010, 0, 0, SLVERR);
        axi_write(32'h0c, 32'hffff_ffff, 4'b0000, 0, 0, OKAY);
        axi_read(32'h0c, 3, OKAY);
        axi_write(32'h00, 32'h0000_ff00, 4'b0010, 0, 0, OKAY);
        axi_read(32'h00, 1, OKAY);

        // RO, unmapped and unaligned accesses return SLVERR and leave state intact.
        axi_write(32'h04, 0, 4'hf, 0, 0, SLVERR);
        axi_write(32'h20, 1, 4'hf, 0, 0, SLVERR);
        axi_write(32'h05, 1, 4'hf, 0, 0, SLVERR);
        axi_read(32'h20, 0, SLVERR);
        axi_read(32'h01, 0, SLVERR);
        axi_read(32'h0c, 3, OKAY);

        // Shared reset empties the stream FIFO and restores control registers.
        push_beat(32'hdead_beef, 4'hf, 1);
        @(negedge clk); rst_n = 0;
        repeat (2) @(negedge clk);
        rst_n = 1;
        expect_irq(0);
        if (level !== 0 || m_valid !== 0) $fatal(1, "Reset did not empty stream FIFO");
        checks = checks + 1;
        axi_read(32'h00, 0, OKAY);
        axi_read(32'h04, 1, OKAY);
        axi_read(32'h08, 0, OKAY);
        axi_read(32'h0c, DEPTH, OKAY);

        $display("AXI-LITE CONTROL PASS: %0d checks", checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "AXI-Lite control test timeout");
    end
endmodule
