# AXI4-Stream FIFO: RTL, Simulation and Formal Verification

[![FIFO verification](https://github.com/Krnroyy/axis-packet-fifo/actions/workflows/verify.yml/badge.svg?branch=master)](https://github.com/Krnroyy/axis-packet-fifo/actions/workflows/verify.yml)

A learning project for RTL/design verification and formal verification interviews.
The default design stores 16 beats of 32-bit data, together with 4-bit TKEEP
and 1-bit TLAST. This is a **beat FIFO that preserves packet markers**: output
can begin before a whole packet has arrived. It does not drop malformed packets,
require a complete packet before output, or implement packet-level admission.

Start with `docs/START_HERE.md`. Actual validation status is in
`results/VALIDATION.md`; do not infer a proof from the presence of assertions.

## Verification status

- Simulation: 12 passing runs across FIFO depths 1, 3, 4 and 16,
  using three reproducible seeds per depth.
- Added directed tests for eight single-beat packets and reset
  while an output beat is stalled.
- Formal: 15 assertions checked under 3 assumptions for an
  8-bit, depth-4 configuration; base checks and induction passed.
- All 3 formal cover scenarios were reached.
- A deliberately introduced pop-without-ready bug was detected
  by both simulation and formal verification.
- GitHub Actions runs simulation and formal checks on pushes
  and pull requests, using Ubuntu 24.04.

Latest local simulation evidence: `results/simulation-current.log`.


## Files

| File | Purpose |
|---|---|
| `rtl/sync_fifo.sv` | Circular storage, pointers, occupancy and formal invariants |
| `rtl/axis_packet_fifo.sv` | Packs and unpacks TDATA/TKEEP/TLAST |
| `tb/tb_axis_packet_fifo.sv` | Directed/random stimulus, scoreboard and event counters |
| `formal/fifo_formal.sv` | Symbolic inputs and source assumptions |
| `formal/fifo.sby` | Optional SymbiYosys prove/cover tasks |
| `scripts/run_sim.py` | Regression at depths 1, 3, 4, 16 and three seeds |
| `scripts/run_formal.py` | Yosys/SMTBMC base, induction and cover checks |
| `docs/TEST_PLAN.md` | Requirements and checks |
| `.github/workflows/verify.yml` | Simulation and formal CI definition |

## Run on Windows (recommended: WSL Ubuntu)

If WSL is not already installed, open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu
```

Restart if Windows requests it, launch Ubuntu and finish its username/password
setup. If WSL is already available, use your existing Ubuntu terminal.

Extract this project ZIP to `C:\vlsi\axis-packet-fifo`. In **Ubuntu**, run:

```bash
cd /mnt/c/vlsi/axis-packet-fifo
sudo apt update
sudo apt install -y iverilog yosys z3 python3 gtkwave
python3 scripts/run_sim.py --waves
```

Successful simulation ends with:

```text
REGRESSION PASS: 12 runs
```

The driver uses Icarus Verilog's `-g2012` mode and a portable subset of
SystemVerilog. It intentionally avoids UVM and class-based constrained random
features so the first version can run with free tools.

To view signals (requires WSL GUI support, or a native GTKWave installation):

```bash
gtkwave build/fifo.vcd
```

Start with `clk`, `rst_n`, `sv`, `sr`, `mv`, `mr`, `level`, `sd`, `md`, `sl`, `ml`.
The VCD is generated only for depth 16, seed 1 so later runs do not replace it.

Then run formal:

```bash
python3 scripts/run_formal.py
```

The expected final line, **only when all checks pass**, is:

```text
FORMAL PASS: base, induction, cover (DATA_WIDTH=8, DEPTH=4)
```

This direct flow does not require `sby`. If you already use OSS CAD Suite with
SymbiYosys, an alternative is:

```bash
cd formal
sby -f fifo.sby prove
sby -f fifo.sby cover
```

The direct runner checks the exported solver model contains **15 assertions,
3 assumptions and 3 covers** before attempting a proof. It also requires all
3 cover statements to be reached. Yosys 0.52 uses clocked `$check` cells; the
runner includes `async2sync` to lower them before SMT export. A solver PASS
without the intended properties is not a valid verification result.

On native Windows, simulation can also run with `py scripts\run_sim.py` if
`iverilog` and `vvp` are on PATH. The validation environment and formal setup use
Linux; WSL keeps your commands aligned with that environment.

## Design contract

- A beat is accepted on a rising clock edge with `s_axis_tvalid && s_axis_tready`.
- A beat is delivered with `m_axis_tvalid && m_axis_tready`.
- The source must hold VALID and all payload fields stable while stalled.
- The FIFO holds its output VALID and payload stable while stalled, until reset.
- Reset is synchronous, active-low, and must include at least one rising edge.
  Hold reset for three cycles in the provided testbench. VALID/READY are gated
  low while reset is asserted, and queued beats are discarded on the reset edge.
- Reset clears pointers and occupancy. It does **not** scrub storage bits.
- TDATA is unspecified when output VALID is low. Do not compare it then.
- There is no combinational empty bypass; a write to an empty FIFO becomes
  visible after the accepting rising edge.
- READY is low when full, even if the receiver will pop on that edge. This
  deliberate conservative policy creates a one-cycle input bubble at full.
- Both push and pop can occur together when occupancy is between 1 and DEPTH-1.
- TKEEP is preserved exactly. The FIFO does not interpret or validate byte masks.
- TID, TDEST, TUSER and TSTRB are outside this version's interface.
- Supported configuration: DEPTH >= 1; DATA_WIDTH is a positive multiple of 8.
  Leave derived width parameters at their defaults. The scripts test depths
  1/3/4/16 with 32-bit data; the formal harness uses 8-bit data and depth 4.

## What the formal checks mean

The harness starts in reset and allows arbitrary later resets, source data,
packet markers and receiver stalls. It assumes a compliant source keeps an
unaccepted beat stable. No assumption requires the receiver ever to become
ready, so this checks safety, not eventual delivery or fairness.

The core's reference model is an independent shift queue. Invariants relate
each valid circular-memory location to its corresponding queue entry; output
comparisons include data, keep and last because they are packed together.
The property checks cover occupancy bounds, pointer bounds/relationship,
queue correspondence, stalled output stability and reset clearing occupancy.

Base checking plus successful induction establishes unbounded safety for the
**specific formal configuration**. Passing 30 base cycles alone is only bounded
evidence. Cover checks ask whether full, simultaneous push/pop and write-pointer
wrap are reachable. A cover trace demonstrates reachability, not correctness.
Nothing here proves every parameter value or full AXI protocol conformance.

## Next milestones

1. Explain each signal and trace five transfers manually.
2. Run the regression and inspect a stall in GTKWave.
3. Run formal and identify one assertion and one assumption.
4. Complete the bug-injection exercise in `docs/START_HERE.md`.
5. Add a new requirement: packet-length counting, then tests and assertions.
6. Later add store-and-forward packet admission or an AXI-Lite status interface.

Keep the baseline green before adding features. UVM, asynchronous clock-domain
crossing and FPGA integration are later extensions with additional requirements.

## Official references

- Icarus usage: https://steveicarus.github.io/iverilog/usage/getting_started.html
- SymbiYosys: https://symbiyosys.readthedocs.io/en/latest/
- OSS CAD Suite: https://github.com/YosysHQ/oss-cad-suite-build
- Arm AXI-Stream specification (IHI 0051): https://developer.arm.com/documentation/ihi0051/latest/

This is an educational implementation. Report only checks you personally ran
and understand. The delivered results record what was run during creation.


## Verification bug case study

[Pop-without-ready: simulation and formal detection](docs/BUG_CASE_STUDY.md).
