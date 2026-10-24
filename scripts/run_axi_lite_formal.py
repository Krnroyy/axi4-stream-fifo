#!/usr/bin/env python3
"""Prove AXI-Lite wrapper properties against a bounded FIFO-level abstraction."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for executable in ('yosys', 'yosys-smtbmc', 'z3'):
    if not shutil.which(executable):
        sys.exit(f'{executable} not found. Install Yosys and Z3 first.')

build = root / 'build' / 'formal'
build.mkdir(parents=True, exist_ok=True)
smt = build / 'axi_lite.smt2'
yosys_script = '; '.join([
    'read_verilog -formal -sv -DAXI_LITE_FORMAL rtl/axi_lite_axis_fifo.sv formal/axi_lite_formal.sv',
    'prep -top axi_lite_formal -flatten',
    'memory_map', 'opt', 'async2sync', 'dffunmap',
    f'write_smt2 -wires {smt.as_posix()}'
])
commands = [
    ('axi_lite_elaborate', ['yosys', '-p', yosys_script]),
    ('axi_lite_base', ['yosys-smtbmc', '-s', 'z3', '--unroll', '--timeout', '60',
                       '--presat', '-t', '30', str(smt)]),
    ('axi_lite_induction', ['yosys-smtbmc', '-s', 'z3', '--unroll', '--timeout', '60',
                            '-i', '-t', '30', str(smt)]),
    ('axi_lite_cover', ['yosys-smtbmc', '-s', 'z3', '--unroll', '--timeout', '60',
                        '-c', '-t', '30', '--dump-vcd',
                        str(build / 'axi_lite_cover.vcd'), str(smt)])
]
for name, command in commands:
    log_path = build / f'{name}.log'
    with log_path.open('w') as log:
        result = subprocess.run(command, cwd=root, stdout=log,
                                stderr=subprocess.STDOUT, timeout=180)
    output = log_path.read_text()
    print('\n'.join(output.splitlines()[-10:]))
    if result.returncode:
        sys.exit(f'{name} failed; inspect build/formal/{name}.log')
    if name == 'axi_lite_elaborate':
        model = smt.read_text()
        counts = {kind: model.count(f'; yosys-smt2-{kind} ')
                  for kind in ('assert', 'assume', 'cover')}
        print(f"PROPERTY CHECK: assert={counts['assert']} assume={counts['assume']} cover={counts['cover']}")
        if counts['assert'] < 20 or counts['assume'] < 5 or counts['cover'] != 5:
            sys.exit('Formal property inventory is incomplete; no proof claimed.')
    elif 'Status: PASSED' not in output:
        sys.exit(f'{name} did not report PASSED; no proof claimed.')
    if name == 'axi_lite_cover':
        reached = output.count('Reached cover statement')
        print(f'COVERAGE CHECK: reached={reached}/5')
        if reached != 5:
            sys.exit('Expected all five wrapper cover statements to be reached.')
print('AXI-LITE FORMAL PASS: response stability, register behavior, reset, IRQ (DEPTH=2)')
