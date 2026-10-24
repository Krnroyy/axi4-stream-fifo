# AXI4-Lite control/status extension

## Why use both AXI protocols?

AXI4-Stream is the packet-data conveyor belt. AXI4-Lite is the control panel:
software or a processor reads and writes a few registers without carrying the
packet payload through the register bus.

## Address map

| Address | Name | Access | Definition |
|---:|---|---|---|
| `0x00` | CONTROL | R/W | Bit 0 enables the level-threshold interrupt. Other bits are reserved. |
| `0x04` | STATUS | R/O | Bit 0 `empty`, bit 1 `full`, bit 2 `irq`. |
| `0x08` | LEVEL | R/O | Number of beats currently stored. |
| `0x0C` | IRQ_THRESHOLD | R/W | Legal values are `1..DEPTH`. |

Reset disables the interrupt and sets the threshold to `DEPTH`. The interrupt
is level-sensitive: `irq = CONTROL.IRQ_ENABLE && (LEVEL >= IRQ_THRESHOLD)`.
It deasserts automatically when the FIFO level drops below the threshold or
CONTROL disables it. STATUS and LEVEL writes return SLVERR. An invalid threshold
write is rejected without changing the old threshold.

## One example

For a depth-4 FIFO, write `2` to `IRQ_THRESHOLD` (`0x0C`), then write `1` to
CONTROL (`0x00`). After two stream beats are accepted, LEVEL is 2 and IRQ is
high. STATUS reads `0x4` (IRQ=1, FULL=0, EMPTY=0). After one output beat is
accepted, LEVEL becomes 1 and IRQ goes low. The stream payload and its TKEEP and
TLAST fields remain entirely on the AXI4-Stream interface.

## AXI4-Lite handshakes

AW (address) and W (data plus WSTRB) can be accepted on different rising edges.
The wrapper stores each part and commits the write after both are available.
The B response is held until `BVALID && BREADY`; the read response is held until
`RVALID && RREADY`. A transfer happens only on a rising edge where that
channel's VALID and READY are both high.

## Verification boundary

Run the existing baseline with `python3 scripts/run_sim.py`, then run
`python3 scripts/run_axi_lite_control.py` for the added targeted test. The new
simulation checks channel
independence, byte strobes, read/write response stability under stalls,
register permissions, illegal addresses, threshold interrupt behavior, stream
sideband preservation, and common reset. The existing formal proof still
covers only `sync_fifo`; do not describe the new control wrapper as formally
proven until a formal harness for its AXI behavior is added and passes.
