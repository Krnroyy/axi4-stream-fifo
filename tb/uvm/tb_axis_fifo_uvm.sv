
`timescale 1ns/1ps
interface axis_fifo_if;
 logic aclk=0, aresetn;
 logic [31:0] s_axis_tdata, m_axis_tdata;
 logic [3:0] s_axis_tkeep, m_axis_tkeep;
 logic s_axis_tlast,s_axis_tvalid,s_axis_tready;
 logic m_axis_tlast,m_axis_tvalid,m_axis_tready;
 logic [2:0] level;
 always #5 aclk=~aclk;
endinterface

package axis_fifo_uvm_pkg;
 import uvm_pkg::*;
 `include "uvm_macros.svh"

 class axis_fifo_item extends uvm_sequence_item;
  rand bit [31:0] data;
  rand bit [3:0] keep;
  rand bit last;
  rand int unsigned gap_cycles;
  bit is_output, is_stall, is_full, is_cycle_sample;
  bit input_fire, output_fire, source_stall, sink_stall;
  bit [2:0] sampled_level;
  constraint c_gap { gap_cycles inside {[0:1]}; }
  `uvm_object_utils_begin(axis_fifo_item)
   `uvm_field_int(data,UVM_ALL_ON)
   `uvm_field_int(keep,UVM_ALL_ON)
   `uvm_field_int(last,UVM_ALL_ON)
   `uvm_field_int(gap_cycles,UVM_ALL_ON)
  `uvm_object_utils_end
  function new(string name="axis_fifo_item"); super.new(name); endfunction
 endclass

 class axis_fifo_sequence extends uvm_sequence #(axis_fifo_item);
  `uvm_object_utils(axis_fifo_sequence)
  function new(string name="axis_fifo_sequence"); super.new(name); endfunction
  task body();
   axis_fifo_item item;
   for (int i=0;i<64;i++) begin
    item=axis_fifo_item::type_id::create($sformatf("item_%0d",i));
    start_item(item);
    if (!item.randomize()) `uvm_fatal("RAND","Could not randomize stream item")
    case(i%4)
     0:item.keep=4'b1111;
     1:item.keep=4'b0101;
     2:item.keep=4'b0000;
     3:item.keep=4'b1010;
    endcase
    item.last=((i%8)==7);
    finish_item(item);
   end
  endtask
 endclass

 class axis_fifo_driver extends uvm_driver #(axis_fifo_item);
  `uvm_component_utils(axis_fifo_driver)
  virtual axis_fifo_if vif;
  int unsigned ready_cycle;
  function new(string name="axis_fifo_driver",uvm_component parent=null); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   if(!uvm_config_db#(virtual axis_fifo_if)::get(this,"","vif",vif))
    `uvm_fatal("NOVIF","Driver did not receive axis_fifo_if")
  endfunction
  task run_phase(uvm_phase phase);
   fork drive_source(); drive_sink_ready(); join
  endtask
  task drive_source();
   axis_fifo_item req;
   @(negedge vif.aclk);
   vif.s_axis_tvalid=0; vif.s_axis_tdata='0; vif.s_axis_tkeep='0; vif.s_axis_tlast=0;
   forever begin
    seq_item_port.get_next_item(req);
    repeat(req.gap_cycles) @(negedge vif.aclk);
    vif.s_axis_tdata=req.data; vif.s_axis_tkeep=req.keep;
    vif.s_axis_tlast=req.last; vif.s_axis_tvalid=1;
    do @(posedge vif.aclk); while(!vif.s_axis_tready);
    @(negedge vif.aclk);
    vif.s_axis_tvalid=0; vif.s_axis_tdata='0; vif.s_axis_tkeep='0; vif.s_axis_tlast=0;
    seq_item_port.item_done();
   end
  endtask
  task drive_sink_ready();
   ready_cycle=0; vif.m_axis_tready=0;
   forever begin
    @(negedge vif.aclk);
    if(!vif.aresetn) vif.m_axis_tready=0;
    else begin
     ready_cycle++;
     if((ready_cycle%13)<8) vif.m_axis_tready=0;
     else vif.m_axis_tready=($urandom_range(0,3)!=0);
    end
   end
  endtask
 endclass

 class axis_fifo_monitor extends uvm_monitor;
  `uvm_component_utils(axis_fifo_monitor)
  virtual axis_fifo_if vif;
  bit is_output;
  uvm_analysis_port #(axis_fifo_item) observed_ap;
  function new(string name="axis_fifo_monitor",uvm_component parent=null);
   super.new(name,parent); observed_ap=new("observed_ap",this);
  endfunction
  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   if(!uvm_config_db#(virtual axis_fifo_if)::get(this,"","vif",vif))
    `uvm_fatal("NOVIF","Monitor did not receive axis_fifo_if")
   if(!uvm_config_db#(bit)::get(this,"","is_output",is_output))
    `uvm_fatal("NOCHANNEL","Monitor channel configuration missing")
  endfunction
  task run_phase(uvm_phase phase);
   axis_fifo_item tr;
   forever begin
    @(posedge vif.aclk);
    if(vif.aresetn) begin
     // One sample per active cycle, avoiding double-counting when both
     // source and sink handshakes occur on the same clock.
     if(!is_output) begin
      tr=axis_fifo_item::type_id::create("cycle_sample");
      tr.is_cycle_sample=1;
      tr.sampled_level=vif.level;
      tr.input_fire=vif.s_axis_tvalid && vif.s_axis_tready;
      tr.output_fire=vif.m_axis_tvalid && vif.m_axis_tready;
      tr.source_stall=vif.s_axis_tvalid && !vif.s_axis_tready;
      tr.sink_stall=vif.m_axis_tvalid && !vif.m_axis_tready;
      tr.keep=vif.s_axis_tkeep;
      tr.last=vif.s_axis_tlast;
      observed_ap.write(tr);
     end
     if(!is_output && vif.level==4) begin
      tr=axis_fifo_item::type_id::create("full_level");
      tr.is_full=1; observed_ap.write(tr);
     end
     if(is_output && vif.m_axis_tvalid && !vif.m_axis_tready) begin
      tr=axis_fifo_item::type_id::create("output_stall");
      tr.is_output=1; tr.is_stall=1; observed_ap.write(tr);
     end
     if(!is_output && vif.s_axis_tvalid && !vif.s_axis_tready) begin
      tr=axis_fifo_item::type_id::create("source_stall");
      tr.is_stall=1; observed_ap.write(tr);
     end
     if(!is_output && vif.s_axis_tvalid && vif.s_axis_tready) begin
      tr=axis_fifo_item::type_id::create("input");
      tr.data=vif.s_axis_tdata; tr.keep=vif.s_axis_tkeep; tr.last=vif.s_axis_tlast;
      observed_ap.write(tr);
     end
     if(is_output && vif.m_axis_tvalid && vif.m_axis_tready) begin
      tr=axis_fifo_item::type_id::create("output");
      tr.is_output=1; tr.data=vif.m_axis_tdata; tr.keep=vif.m_axis_tkeep; tr.last=vif.m_axis_tlast;
      observed_ap.write(tr);
     end
    end
   end
  endtask
 endclass

 class axis_fifo_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axis_fifo_scoreboard)
  uvm_analysis_imp #(axis_fifo_item,axis_fifo_scoreboard) observed_imp;
  axis_fifo_item expected[$];
  int unsigned input_count,output_count,input_stall_count,output_stall_count,full_count;
  bit saw_full_keep,saw_partial_keep,saw_zero_keep,saw_tlast;

  // Samples every clock from the passive source monitor. This is functional
  // coverage (scenario bins), separate from the scoreboard's pass/fail checks.
  covergroup fifo_cg with function sample(
   bit [2:0] level_sample, bit in_fire, bit out_fire,
   bit src_stall, bit dst_stall, bit [3:0] keep_sample, bit last_sample);
   occupancy: coverpoint level_sample {
    bins empty = {0};
    bins partially_full = {[1:3]};
    bins full = {4};
   }
   activity: coverpoint {in_fire,out_fire} {
    bins idle = {2'b00};
    bins input_only = {2'b10};
    bins output_only = {2'b01};
    bins simultaneous = {2'b11};
   }
   source_backpressure: coverpoint src_stall { bins no={0}; bins yes={1}; }
   sink_backpressure: coverpoint dst_stall { bins no={0}; bins yes={1}; }
   keep_pattern: coverpoint keep_sample {
    bins no_bytes = {4'h0};
    bins all_bytes = {4'hf};
    bins partial = {4'h5,4'ha};
    bins other = default;
   }
   packet_end: coverpoint last_sample { bins body={0}; bins packet_end={1}; }
  endgroup

  function new(string name="axis_fifo_scoreboard",uvm_component parent=null);
   super.new(name,parent); observed_imp=new("observed_imp",this);
   fifo_cg = new();
  endfunction
  function void write(axis_fifo_item tr);
   axis_fifo_item saved,exp;
   if(tr.is_cycle_sample) begin
    fifo_cg.sample(tr.sampled_level,tr.input_fire,tr.output_fire,
                   tr.source_stall,tr.sink_stall,tr.keep,tr.last);
    return;
   end
   if(tr.is_full) begin full_count++; return; end
   if(tr.is_stall) begin
    if(tr.is_output) output_stall_count++;
    else input_stall_count++;
    return;
   end
   if(!tr.is_output) begin
    saved=axis_fifo_item::type_id::create("expected");
    saved.data=tr.data; saved.keep=tr.keep; saved.last=tr.last;
    expected.push_back(saved); input_count++;
    if(tr.keep==4'hf) saw_full_keep=1;
    else if(tr.keep==0) saw_zero_keep=1;
    else saw_partial_keep=1;
    if(tr.last) saw_tlast=1;
   end else begin
    if(expected.size()==0) `uvm_fatal("SCOREBOARD","Output with no expected input")
    exp=expected.pop_front();
    if(tr.data!==exp.data || tr.keep!==exp.keep || tr.last!==exp.last)
     `uvm_fatal("MISMATCH",$sformatf("Expected %h/%b/%b got %h/%b/%b",
      exp.data,exp.keep,exp.last,tr.data,tr.keep,tr.last))
    output_count++;
   end
  endfunction
  function int unsigned pending_count(); return expected.size(); endfunction
 endclass

 class axis_fifo_agent extends uvm_agent;
  `uvm_component_utils(axis_fifo_agent)
  uvm_sequencer #(axis_fifo_item) sequencer;
  axis_fifo_driver driver;
  axis_fifo_monitor source_monitor,sink_monitor;
  function new(string name="axis_fifo_agent",uvm_component parent=null); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   sequencer=uvm_sequencer#(axis_fifo_item)::type_id::create("sequencer",this);
   driver=axis_fifo_driver::type_id::create("driver",this);
   source_monitor=axis_fifo_monitor::type_id::create("source_monitor",this);
   sink_monitor=axis_fifo_monitor::type_id::create("sink_monitor",this);
   uvm_config_db#(bit)::set(this,"source_monitor","is_output",0);
   uvm_config_db#(bit)::set(this,"sink_monitor","is_output",1);
  endfunction
  function void connect_phase(uvm_phase phase);
   super.connect_phase(phase); driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
 endclass

 class axis_fifo_env extends uvm_env;
  `uvm_component_utils(axis_fifo_env)
  axis_fifo_agent agent;
  axis_fifo_scoreboard scoreboard;
  function new(string name="axis_fifo_env",uvm_component parent=null); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   agent=axis_fifo_agent::type_id::create("agent",this);
   scoreboard=axis_fifo_scoreboard::type_id::create("scoreboard",this);
  endfunction
  function void connect_phase(uvm_phase phase);
   super.connect_phase(phase);
   agent.source_monitor.observed_ap.connect(scoreboard.observed_imp);
   agent.sink_monitor.observed_ap.connect(scoreboard.observed_imp);
  endfunction
 endclass

 class axis_fifo_test extends uvm_test;
  `uvm_component_utils(axis_fifo_test)
  axis_fifo_env env;
  virtual axis_fifo_if vif;
  function new(string name="axis_fifo_test",uvm_component parent=null); super.new(name,parent); endfunction
  function void build_phase(uvm_phase phase);
   super.build_phase(phase);
   if(!uvm_config_db#(virtual axis_fifo_if)::get(this,"","vif",vif))
    `uvm_fatal("NOVIF","Test did not receive axis_fifo_if")
   env=axis_fifo_env::type_id::create("env",this);
  endfunction
  task run_phase(uvm_phase phase);
   axis_fifo_sequence seq;
   bit drained;
   phase.raise_objection(this);
   wait(vif.aresetn==1);
   repeat(2) @(posedge vif.aclk);
   seq=axis_fifo_sequence::type_id::create("seq");
   seq.start(env.agent.sequencer);
   drained=0;
   for(int cycles=0;cycles<2000;cycles++) begin
    @(posedge vif.aclk);
    if(env.scoreboard.input_count==64 && env.scoreboard.pending_count()==0) begin drained=1; break; end
   end
   if(!drained) `uvm_fatal("TIMEOUT",$sformatf("input=%0d output=%0d pending=%0d",
    env.scoreboard.input_count,env.scoreboard.output_count,env.scoreboard.pending_count()))
   repeat(2) @(posedge vif.aclk);
   if(env.scoreboard.input_count!=64 || env.scoreboard.output_count!=64)
    `uvm_fatal("COUNT","Expected exactly 64 accepted input and output beats")
   if(env.scoreboard.output_stall_count==0 || env.scoreboard.input_stall_count==0 ||
      env.scoreboard.full_count==0 || !env.scoreboard.saw_full_keep ||
      !env.scoreboard.saw_partial_keep || !env.scoreboard.saw_zero_keep || !env.scoreboard.saw_tlast)
    `uvm_fatal("COVERAGE","FIFO full, source/sink stalls, or TKEEP/TLAST coverage incomplete")
   `uvm_info("PASS",$sformatf("64 beats checked; functional coverage=%0.1f%%; full cycles=%0d; source stalls=%0d; sink stalls=%0d",
    env.scoreboard.fifo_cg.get_coverage(),env.scoreboard.full_count,
    env.scoreboard.input_stall_count,env.scoreboard.output_stall_count),UVM_NONE)
   phase.drop_objection(this);
  endtask
 endclass
endpackage

module tb_axis_fifo_uvm;
 import uvm_pkg::*;
 import axis_fifo_uvm_pkg::*;
 axis_fifo_if vif();
 axis_packet_fifo #(.DATA_WIDTH(32),.DEPTH(4)) dut(
  .aclk(vif.aclk),.aresetn(vif.aresetn),
  .s_axis_tdata(vif.s_axis_tdata),.s_axis_tkeep(vif.s_axis_tkeep),
  .s_axis_tlast(vif.s_axis_tlast),.s_axis_tvalid(vif.s_axis_tvalid),
  .s_axis_tready(vif.s_axis_tready),.m_axis_tdata(vif.m_axis_tdata),
  .m_axis_tkeep(vif.m_axis_tkeep),.m_axis_tlast(vif.m_axis_tlast),
  .m_axis_tvalid(vif.m_axis_tvalid),.m_axis_tready(vif.m_axis_tready),
  .level(vif.level)
 );
 initial begin
  vif.aresetn=0; vif.s_axis_tvalid=0; vif.s_axis_tdata='0;
  vif.s_axis_tkeep='0; vif.s_axis_tlast=0; vif.m_axis_tready=0;
  uvm_config_db#(virtual axis_fifo_if)::set(null,"*","vif",vif);
  run_test("axis_fifo_test");
 end

 initial begin
  repeat(4) @(posedge vif.aclk);
  @(negedge vif.aclk); vif.aresetn=1;
 end
endmodule
