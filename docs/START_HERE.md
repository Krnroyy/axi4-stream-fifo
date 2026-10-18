# First session: understand and run your FIFO

## 1. Understand the problem

Imagine an encryption engine creates data faster than a DMA consumer can accept
it for a few cycles. The FIFO stores those beats until the consumer is ready.
When storage is full, it tells the producer to wait by lowering READY.

One 32-bit beat has:

| Field | Width | Meaning |
|---|---:|---|
| TDATA | 32 | The data word |
| TKEEP | 4 | One bit per byte; marks bytes that belong to the stream |
| TLAST | 1 | Marks the last beat of a packet |
| TVALID | 1 | The source is presenting a beat |
| TREADY | 1 | The receiver can accept a beat |

The FIFO stores `{TLAST,TKEEP,TDATA}` as one 37-bit word. That keeps packet-end
and byte information aligned with the data through stalls.

**Handshake = VALID AND READY, sampled on the rising clock edge.** VALID alone
does not mean a transfer occurred. READY alone does not mean data exists.

## 2. Read the smallest useful pieces

Open `rtl/sync_fifo.sv`. First read only the section above `ifdef FORMAL`.

- `wr_ptr` selects the location for the next accepted input.
- `rd_ptr` selects the oldest queued output.
- `level` is the number of queued beats.
- `push` accepts input; `pop` accepts output.
- Push only: level increases. Pop only: level decreases.
- Push and pop together: both pointers move, but level stays constant.

Then read `rtl/axis_packet_fifo.sv` and find the packing/unpacking lines.

## 3. Predict five cycles before simulating

Assume reset has completed and the FIFO begins empty. A/B stand for complete
data+keep+last payloads. Values shown are immediately before each rising edge.

| Edge | Source | Input accepted? | Receiver READY | Output before edge | Level after edge |
|---:|---|---|---:|---|---:|
| 1 | A, VALID=1 | Yes | 0 | Invalid | 1 |
| 2 | B, VALID=1 | Yes | 0 | A, VALID=1 | 2 |
| 3 | VALID=0 | No | 0 | A, VALID=1 | 2 |
| 4 | VALID=0 | No | 1 | A is delivered | 1 |
| 5 | VALID=0 | No | 1 | B is delivered | 0 |

A must remain at the output during edges 2 and 3. That is backpressure behavior.

## 4. Run the simulation

Follow the Windows/WSL setup in README.md, then:

```bash
python3 scripts/run_sim.py --waves
```

The testbench checks every accepted output against the oldest expected beat.
Its counters require full/empty/stall/partial/packet/reset/wrap events; depths
above 1 must also observe simultaneous input/output. These are event counters,
not a functional or code-coverage percentage.

The test deliberately resets a nonempty FIFO, so transmitted and received
totals differ. Those pending beats are discarded by the reset contract.

## 5. Find a backpressure interval

In GTKWave, locate `mv=1` and `mr=0`. Check that `md`, `mk`, `ml` and `mv` remain
stable until a transfer or reset. Watch level rise while the consumer stalls,
and input READY fall when level reaches DEPTH.

## 6. Make the checker catch a bug

Make a backup or Git commit first. In `sync_fifo.sv`, temporarily change:

```systemverilog
wire pop = m_valid && m_ready;
```

to:

```systemverilog
wire pop = m_valid;
```

Predict the consequence: data leaves the queue even when the receiver cannot
accept it. Run simulation. It should fail. Run formal and inspect the failing
assertion. Restore the original line and rerun both before continuing.

## 7. Run and explain formal

```bash
python3 scripts/run_formal.py
```

- An **assumption** constrains the environment, such as stable input while stalled.
- An **assertion** states a required property of the design.
- A **cover** asks whether a particular event can happen.
- **Induction** must pass together with the base checks before you call the
  selected safety properties proven for that configuration.

Read the FORMAL block only after you understand normal pointer/count behavior.
The reference queue shifts on pop, unlike the implementation's circular memory.

## Questions you should be able to answer

1. Why is the stored width 37 rather than 32?
2. Why must TVALID remain high when TREADY is low?
3. Why does simultaneous push/pop leave level unchanged?
4. What happens when the FIFO is full and the receiver pops?
5. Does reset clear every memory bit, or only make old entries inaccessible?
6. Why does a passing random simulation differ from a formal proof?
7. Why can this version output a beat before its packet's TLAST arrives?

Suggested learning order: clocked/nonblocking RTL; FIFO pointers; handshakes;
scoreboards; SystemVerilog assertions; formal assumptions and induction.
