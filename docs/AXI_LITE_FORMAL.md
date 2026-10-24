# Formal checks for the AXI-Lite control wrapper

Run in WSL after the simulation test passes:

```bash
python3 scripts/run_axi_lite_formal.py
```

The runner uses Yosys, `yosys-smtbmc`, and Z3. It checks bounded base cases,
induction, and reachability of five cover events at `DEPTH=2` and
`DATA_WIDTH=8`.

The wrapper's formal-only properties check:

- BVALID/BRESP remain stable while the write response is stalled.
- RVALID/RDATA/RRESP remain stable while the read response is stalled.
- Reset clears responses, disables IRQ, and restores the threshold.
- Only legal register writes change CONTROL or IRQ_THRESHOLD; byte strobes
  and rejected writes preserve the other state.
- Read data and response match the address map at the AR handshake.
- The threshold stays in range and IRQ matches enable, threshold, and level.

The harness substitutes a bounded, arbitrary FIFO occupancy for the stream
FIFO. This lets the proof explore low, threshold, and full occupancy values
without duplicating the stream FIFO's proof. `formal/fifo_formal.sv` separately
proves the FIFO safety properties. These are compositional checks; they do not
prove end-to-end packet behavior through the combined wrapper, and they do not
certify the complete AXI protocol.

The source assumptions are limited to the AXI manager holding AW, W, and AR
VALID plus payload stable while each channel is stalled. BREADY and RREADY may
stall responses arbitrarily; no eventual-ready assumption is made. A PASS is
reported only if the property inventory is present, base checks and induction
pass, and all five cover events are reached.
