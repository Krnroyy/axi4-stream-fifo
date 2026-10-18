`timescale 1ns/1ps
module tb_axis_packet_fifo;
    parameter integer DEPTH = 16;
    localparam integer CW = $clog2(DEPTH+1);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg [31:0] sd=0;
    reg [3:0] sk=0;
    reg sl=0, sv=0, mr=0;
    wire sr, mv, ml;
    wire [31:0] md;
    wire [3:0] mk;
    wire [CW-1:0] level;
    axis_packet_fifo #(.DEPTH(DEPTH)) dut (
        .aclk(clk),.aresetn(rst_n),
        .s_axis_tdata(sd),.s_axis_tkeep(sk),.s_axis_tlast(sl),
        .s_axis_tvalid(sv),.s_axis_tready(sr),
        .m_axis_tdata(md),.m_axis_tkeep(mk),.m_axis_tlast(ml),
        .m_axis_tvalid(mv),.m_axis_tready(mr),.level(level)
    );
    reg [36:0] expected [0:65535];
    integer head=0,tail=0,n=0,tx=0,rx=0;
    integer full_cycles=0,empty_cycles=0,stalls=0,both=0;
    integer packets=0,partial=0,resets_nonempty=0,wraps=0;
    integer writes_epoch=0,reads_epoch=0;
    reg stalled=0;
    reg [36:0] held;
    reg sampled_push=0;
    reg [31:0] rng;
    integer seed=1, k, packet_left=0;
    function [31:0] next_random;
        input [31:0] value;
        reg [31:0] v;
        begin
            v=value ^ (value<<13);
            v=v ^ (v>>17);
            next_random=v ^ (v<<5);
        end
    endfunction

    // Observe handshakes at rising edges; drive only on falling edges.
    always @(posedge clk) begin
        sampled_push=sv && sr;
        if (!rst_n) begin
            if (n>0) resets_nonempty=resets_nonempty+1;
            head=0; tail=0; n=0; stalled=0;
            writes_epoch=0; reads_epoch=0;
            if (mv || sr) $fatal(1,"Handshake enabled during reset");
        end else begin
            if (level !== n) $fatal(1,"Occupancy mismatch level=%0d model=%0d",level,n);
            if (mv !== (n!=0)) $fatal(1,"VALID mismatch");
            if (sr !== (n<DEPTH)) $fatal(1,"READY mismatch");
            if (stalled && (!mv || {ml,mk,md} !== held))
                $fatal(1,"Output changed during stall");
            stalled=mv && !mr;
            held={ml,mk,md};
            if (n==0) empty_cycles=empty_cycles+1;
            if (n==DEPTH) full_cycles=full_cycles+1;
            if (mv && !mr) stalls=stalls+1;
            if (sv && sr && mv && mr) both=both+1;
            if (mv && mr) begin
                if (n==0) $fatal(1,"Unexpected output");
                if ({ml,mk,md} !== expected[head])
                    $fatal(1,"Scoreboard mismatch at receive %0d",rx);
                head=(head+1)%65536; n=n-1; rx=rx+1;
                reads_epoch=reads_epoch+1;
                if ((reads_epoch%DEPTH)==0) wraps=wraps+1;
                if (ml) packets=packets+1;
                if (mk!=4'hf) partial=partial+1;
            end
            if (sv && sr) begin
                expected[tail]={sl,sk,sd}; tail=(tail+1)%65536;
                n=n+1; tx=tx+1; writes_epoch=writes_epoch+1;
            end
        end
    end

    task reset_fifo;
        begin
            @(negedge clk); rst_n=0; sv=0; mr=0;
            repeat(3) @(negedge clk);
            rst_n=1;
        end
    endtask
    task send_beat;
        input [31:0] data;
        input [3:0] keep;
        input last;
        begin
            @(negedge clk); sv=1; sd=data; sk=keep; sl=last;
            @(posedge clk);
            while (!sr) @(posedge clk);
            @(negedge clk); sv=0;
        end
    endtask
    task drain;
        begin
            @(negedge clk); sv=0; mr=1;
            while (n!=0) @(negedge clk);
            repeat(3) @(negedge clk);
        end
    endtask
    initial begin
        if (!$value$plusargs("SEED=%d",seed)) seed=1;
        rng=seed; if (rng==0) rng=1;
        if ($test$plusargs("WAVES")) begin
            $dumpfile("build/fifo.vcd"); $dumpvars(0,tb_axis_packet_fifo);
        end
        reset_fifo();
        // Fill, hold full, then drain. Two packets, including a partial beat.
        for(k=0;k<DEPTH;k=k+1)
            send_beat(k, (k==DEPTH-1)?4'h3:4'hf, (k==DEPTH/2 || k==DEPTH-1));
        repeat(8) @(negedge clk);
        drain();


// Eight single-beat packets; receiver is ready.
begin : single_beat_test
    integer packets_before;
    packets_before = packets;

    for (k = 0; k < 8; k = k + 1)
        send_beat(32'hA5000000 + k, 4'hF, 1'b1);

    drain();

    if (packets != packets_before + 8)
        $fatal(1, "Single-beat packet count mismatch");

    $display("PASS: eight single-beat packets");
end

     // Reset while an output beat is stalled.
@(negedge clk);
mr = 0;

send_beat(32'hDEADBEEF, 4'hF, 1'b0);

// Receiver is not ready: the pending beat must stay available.
repeat (4) begin
    @(negedge clk);
    if (mv !== 1'b1 ||
        {ml, mk, md} !== {1'b0, 4'hF, 32'hDEADBEEF})
        $fatal(1, "Pending output changed before reset");
end

reset_fifo();
packet_left = 0;

// After reset, the old beat must no longer be valid.
@(negedge clk);
if (mv !== 1'b0 || level !== 0)
    $fatal(1, "Reset did not flush the stalled beat");

$display("PASS: reset flushes stalled output");

// Random traffic: hold the input beat stable until accepted.
for (k = 0; k < 5000; k = k + 1) begin
    @(negedge clk);

    rng = next_random(rng);
    mr = (rng % 100) < 60;

    if (!sv || sampled_push) begin
        rng = next_random(rng);
        sv = (rng % 100) < 75;

        if (sv) begin
            if (packet_left == 0) begin
                rng = next_random(rng);
                packet_left = 1 + (rng % 8);
            end

            rng = next_random(rng);
            sd = rng;
            sl = (packet_left == 1);

            rng = next_random(rng);
            sk = sl ? (4'hF >> (rng % 4)) : 4'hF;

            packet_left = packet_left - 1;
        end
    end
end



        // Complete any currently stalled input before ending the stimulus.
        @(negedge clk); mr=1;
        if (sampled_push) sv=0;
        if (sv && !sampled_push) begin
            @(posedge clk); while(!sr) @(posedge clk);
        end
        drain();
        if (full_cycles==0 || empty_cycles==0 || stalls==0 ||
            (DEPTH>1 && both==0) || packets==0 || partial==0 ||
            resets_nonempty==0 || wraps==0)
            $fatal(1,"Required coverage event missing");
        $display("PASS depth=%0d seed=%0d tx=%0d rx=%0d discarded=%0d",DEPTH,seed,tx,rx,tx-rx);
        $display("COVER full=%0d empty=%0d stalls=%0d simultaneous=%0d packets=%0d partial=%0d reset_nonempty=%0d wraps=%0d",
                 full_cycles,empty_cycles,stalls,both,packets,partial,resets_nonempty,wraps);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Simulation timeout"); end
endmodule
