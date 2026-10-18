`timescale 1ns/1ps
// One clock, synchronous active-low reset, no empty bypass.
module sync_fifo #(
    parameter integer WIDTH = 37,
    parameter integer DEPTH = 16,
    parameter integer PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
    parameter integer COUNT_W = $clog2(DEPTH + 1)
) (
    input wire clk, input wire rst_n,
    input wire [WIDTH-1:0] s_data,
    input wire s_valid, output wire s_ready,
    output wire [WIDTH-1:0] m_data,
    output wire m_valid, input wire m_ready,
    output reg [COUNT_W-1:0] level
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wr_ptr, rd_ptr;
    wire push = s_valid && s_ready;
    wire pop = m_valid && m_ready;

    assign s_ready = rst_n && (level < DEPTH);
    assign m_valid = rst_n && (level != 0);
    assign m_data = mem[rd_ptr]; // Meaningful only while m_valid is high.

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            level <= 0;
        end else begin
            if (push) begin
                mem[wr_ptr] <= s_data;
                wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
            end
            if (pop)
                rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
            case ({push, pop})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase
        end
    end

`ifdef FORMAL
    // Independent shift-register reference model. Inductive invariants connect
    // the circular implementation to the logical queue, including every entry.
    reg f_past_valid = 0;
    reg [WIDTH-1:0] f_queue [0:DEPTH-1];
    reg [COUNT_W-1:0] f_count;
    integer i;
    always @(posedge clk) begin
        f_past_valid <= 1;
        if (!f_past_valid) assume (!rst_n);
        if (!rst_n) begin
            f_count <= 0;
        end else begin
            if (pop)
                for (i=0; i<DEPTH-1; i=i+1)
                    f_queue[i] <= f_queue[i+1];
            if (push) f_queue[f_count - (pop ? 1 : 0)] <= s_data;
            case ({push,pop})
                2'b10: f_count <= f_count + 1'b1;
                2'b01: f_count <= f_count - 1'b1;
                default: f_count <= f_count;
            endcase
        end
        if (f_past_valid) begin
            assert (level <= DEPTH);
            assert (wr_ptr < DEPTH);
            assert (rd_ptr < DEPTH);
            assert (level == f_count);
            assert (wr_ptr == ((rd_ptr + level) % DEPTH));
            for (i=0; i<DEPTH; i=i+1)
                if (i < f_count)
                    assert (mem[(rd_ptr+i)%DEPTH] == f_queue[i]);
            if (m_valid) assert (m_data == f_queue[0]);
            if ($past(rst_n) && rst_n && $past(m_valid && !m_ready)) begin
                assert (m_valid);
                assert (m_data == $past(m_data));
            end
            if (!$past(rst_n)) assert (level == 0);
            cover (rst_n && level == DEPTH);
            cover (rst_n && push && pop);
            cover (rst_n && push && wr_ptr == DEPTH-1);
        end
    end
`endif
endmodule
