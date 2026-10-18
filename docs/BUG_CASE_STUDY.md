# Bug case study: popping without receiver READY

## Design rule

An output transfer occurs on a rising clock edge only when both
`m_valid` and `m_ready` are high.

While the receiver is stalled, the FIFO must retain the output beat
unless reset occurs.

## Deliberately introduced bug

Correct logic:

```systemverilog
wire pop = m_valid && m_ready;
```

Injected mutation:

```systemverilog
wire pop = m_valid;
```

The mutation removes the receiver's acceptance condition. When
`m_valid=1` and `m_ready=0`, the faulty FIFO pops a beat even though
no output transfer occurred. This can discard an undelivered beat
and advance the read pointer incorrectly.

## Simulation detection

The preserved mutation log reports:

```text
simulation: expected nonzero exit, actual=1
FATAL: tb/tb_axis_packet_fifo.sv:51: Occupancy mismatch level=0 model=1
```

The testbench reference model still expected one queued beat, while
the mutated implementation reported zero. The checker stopped the
simulation with a nonzero exit status.

## Formal detection

The preserved log reports:

```text
Checking assertions in step 4..
BMC failed!
Assert failed in fifo_formal
Status: FAILED
```

An assertion in `rtl/sync_fifo.sv`, reached through the formal
harness, failed during bounded checking at step 4. The retained
excerpt identifies the assertion location but does not contain
the complete signal trace.

This failure detects the mutation; it is not a passing proof.

## Correction and baseline

The correct pop condition requires both VALID and READY.
The validation record states that the mutation was tested in a
temporary copy and that the production RTL was restored/unmodified.

Passing baseline evidence and configuration limits are recorded
separately. Formal results apply to the documented 8-bit, depth-4
configuration under its harness assumptions.

## What this experiment demonstrates

The simulation and formal checks are sensitive to this specific
handshake bug. Catching one mutation does not establish complete
bug coverage or full AXI protocol conformance.

## Evidence

- [Preserved mutation log](../results/mutation.log)
- [Validation record](../results/VALIDATION.md)
- [Bug-injection instructions](START_HERE.md#6-make-the-checker-catch-a-bug)
- [Current CI runs](https://github.com/Krnroyy/axis-packet-fifo/actions)