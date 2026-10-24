# UVM test for the AXI4-Stream FIFO

This optional Vivado Simulator test is separate from the Icarus/Yosys regression. It instantiates the existing `axis_packet_fifo` at depth 4 and sends 64 beats through a UVM sequence.

The UVM environment includes a sequencer, driver, source and sink monitors, and a scoreboard. The sink applies periodic and randomized backpressure. The test also checks that the FIFO reaches full and that the source is stalled. The scoreboard compares every accepted output beat against the accepted input queue, including `TDATA`, `TKEEP`, and `TLAST`. It also requires observed stalls and full, partial, and zero `TKEEP` patterns plus `TLAST`.

## Run on Windows

Extract the package into `C:\vlsi\axis-packet-fifo`, then run from PowerShell:

```powershell
Set-Location C:\vlsi\axis-packet-fifo
.\scripts\run_uvm_axis_fifo.ps1
```

The script defaults to Vivado 2026.1 at `C:\AMDDesignTools\2026.1\Vivado\bin`. Edit `$vivadoBin` in the script if your installation is elsewhere.

A successful test prints a UVM message beginning with `PASS: 64 beats checked`. This is a starter UVM environment; the existing open-source simulation and formal checks remain the portable baseline.
