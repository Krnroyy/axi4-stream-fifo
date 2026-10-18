module fifo_formal(input wire clk);
    (* anyseq *) reg rst_n;
    (* anyseq *) reg [7:0] data;
    (* anyseq *) reg keep, last, valid, ready;
    wire in_ready, out_valid, out_last, out_keep;
    wire [7:0] out_data;
    wire [2:0] level;
    reg past_valid=0;
    axis_packet_fifo #(.DATA_WIDTH(8), .DEPTH(4)) dut (
        .aclk(clk),.aresetn(rst_n),
        .s_axis_tdata(data),.s_axis_tkeep(keep),.s_axis_tlast(last),
        .s_axis_tvalid(valid),.s_axis_tready(in_ready),
        .m_axis_tdata(out_data),.m_axis_tkeep(out_keep),.m_axis_tlast(out_last),
        .m_axis_tvalid(out_valid),.m_axis_tready(ready),.level(level)
    );
    always @(posedge clk) begin
        past_valid<=1;
        if (!past_valid) assume(!rst_n);
        // AXI source contract, not a restriction on the DUT's output.
        if (past_valid && rst_n && $past(rst_n && valid && !in_ready)) begin
            assume(valid);
            assume({data,keep,last}==$past({data,keep,last}));
        end
        if (!rst_n) begin
            assert(!out_valid);
            assert(!in_ready);
        end
    end
endmodule
