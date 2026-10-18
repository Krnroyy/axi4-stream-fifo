# Requirements and verification plan

|ID|Requirement|Simulation check|Formal check|
|-|-|-|-|
|R1|Preserve accepted payloads in order|Independent expected queue, every output beat|Shift reference queue and memory correspondence|
|R2|Preserve TKEEP/TLAST with data|Packed 37-bit comparison; partial final beats|Packed 10-bit payload at selected configuration|
|R3|Stop accepting when full|Directed full hold; READY comparison|Occupancy and pointer invariants|
|R4|No output while empty|VALID comparison; empty cycles|VALID definition and reference occupancy|
|R5|Stable output under backpressure|Prior stalled payload comparison|Past-cycle stability assertions|
|R6|Simultaneous read/write|Event counter at depths >1; queue comparison|Reference update and simultaneous cover|
|R7|Correct pointer wrap|Sustained random traffic; receive-wrap counter|Pointer relation, queue invariant and write-wrap cover|
|R8|Reset flushes pending beats|Directed reset while nonempty|Initial reset and arbitrary later resets|
|R9|Reset disables handshake|VALID/READY checked while reset|Harness assertions|
|R10|Correct supported depth boundaries|Depths 1,3,4,16 with 32-bit data|Depth 4 with 8-bit data only|

| R11 | Preserve eight single-beat packets | Directed test with TKEEP=F, TLAST=1; scoreboard checks payloads and packet count increases by 8 | No dedicated eight-packet property |

| R12 | Reset flushes a stalled output beat | Hold receiver not ready for four cycles; check stable payload, then reset and require VALID=0 and level=0 | General reset and stall properties; no dedicated four-cycle scenario |



Simulation uses three reproducible xorshift seeds, 5,000 random drive cycles per
configuration/seed plus directed scenarios. Source payload is held when stalled;
receiver readiness is randomized independently.

Known scope: no asynchronous reset, CDC, packet drop policy, empty bypass,
store-and-forward admission, TKEEP legality validation, AXI-Lite control, UVM,
or liveness proof. Reset is allowed to abandon a partial packet; the system
integrator must define recovery framing for the application.

Useful next tests: reset during simultaneous transfer, directed back-to-back
single-beat packets, larger data widths, all supported keep patterns and a
separate count of complete vs reset-abandoned packets. Do not claim coverage
closure from the existing event counters.

