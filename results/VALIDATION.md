# Validation record — 17 October 2026

These results were obtained while creating this project, on Linux. They are
not evidence that the project has already run on the user's laptop or FPGA.

| Check | Result | Scope |
|---|---|---|
| Icarus simulation | PASS: 12/12 | 32-bit data; depths 1,3,4,16; seeds 1,17,2026 |
| Scoreboard | 32,153 output beats compared | 32,165 accepted inputs; 12 beats deliberately discarded by reset |
| Formal base | PASS through 30 time steps | 8-bit data, 1-bit keep, 1-bit last, depth 4 |
| Temporal induction | PASS | Selected safety properties, same formal configuration |
| Formal cover | PASS: all 3 statements reached | Full, simultaneous push/pop, write-pointer wrap |
| Mutation sensitivity | PASS | Simulation and formal both reject pop without receiver READY |

Tools: Icarus Verilog 12.0; Yosys 0.33; Z3 4.8.12; Python 3.12.

## Yosys 0.52 compatibility correction

The initial direct runner omitted `async2sync`. With the Yosys 0.52 frontend,
properties are represented as clocked `$check` cells and were omitted from
the exported SMT model by that sequence. The original runner incorrectly
accepted the resulting solver PASS. This was reproduced locally using YoWASP
Yosys 0.52 (git fee39a328, matching the user's Yosys source revision).
The earlier 0.33 results retained properties and remain applicable to that
tested version; the user's pre-fix 0.52 formal result is not a valid proof.

The corrected runner includes `async2sync`, checks an exact inventory of
15 assertions, 3 assumptions and 3 covers, and requires three reached cover
statements. The corrected base, induction and cover flows passed with both
native Yosys 0.33 and YoWASP Yosys 0.52 using local Z3 4.8.12.

The missing-lowering negative check now stops at the inventory guard, and
an RTL pop-without-ready mutation is rejected by the corrected 0.52 flow.
See `yosys052-runner.log`, `yosys052-negative-checks.log`, and `yosys033/`.
The user's native Ubuntu 0.52/Z3 4.13.3 rerun is still pending.

The production RTL was restored/unmodified for the passing baseline. The
mutation ran only in a temporary copy. `mutation.log` preserves the failure
messages; passing baseline logs are stored separately.

The formal safety result combines base checking and successful induction.
It is unbounded in time under the harness assumptions, for this specific
configuration. Other widths/depths are not claimed formally proven. Event
counters are not coverage percentages. This is not an AXI certification.

Not run: optional SymbiYosys entry point, GitHub-hosted CI, Windows/WSL user
installation, Vivado implementation, timing closure, or physical board tests.
The tested direct formal script does not require SymbiYosys.
