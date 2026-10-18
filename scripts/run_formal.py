#!/usr/bin/env python3
"""Direct Yosys + SMTBMC flow; no SBY installation needed."""
from pathlib import Path
import shutil
import subprocess
import sys

root=Path(__file__).resolve().parents[1]
for executable in ('yosys','yosys-smtbmc','z3'):
    if not shutil.which(executable):
        sys.exit(f'{executable} not found. See README.md.')
build=root/'build'/'formal'
build.mkdir(parents=True,exist_ok=True)
script='; '.join([
    'read_verilog -formal -sv rtl/sync_fifo.sv rtl/axis_packet_fifo.sv formal/fifo_formal.sv',
    'prep -top fifo_formal -flatten',
    # Yosys 0.52 emits clocked $check cells. async2sync samples/lowers
    # these to $assert/$assume/$cover before write_smt2. Without this step
    # that backend can omit the properties and return a meaningless PASS.
    'memory_map','opt','async2sync','dffunmap',
    'write_smt2 -wires build/formal/fifo.smt2'])
commands=[('elaborate',['yosys','-p',script]),
          ('base',['yosys-smtbmc','-s','z3','--unroll','--timeout','60','--presat','-t','30','build/formal/fifo.smt2']),
          ('induction',['yosys-smtbmc','-s','z3','--unroll','--timeout','60','-i','-t','30','build/formal/fifo.smt2']),
          ('cover',['yosys-smtbmc','-s','z3','--unroll','--timeout','60','-c','-t','30',
                    '--dump-vcd','build/formal/cover.vcd','build/formal/fifo.smt2'])]
for name,cmd in commands:
    with (build/f'{name}.log').open('w') as log:
        result=subprocess.run(cmd,cwd=root,stdout=log,stderr=subprocess.STDOUT,timeout=180)
    text=(build/f'{name}.log').read_text()
    print('\n'.join(text.splitlines()[-8:]))
    if result.returncode:
        sys.exit(f'{name} failed; inspect build/formal/{name}.log')
    if name == 'elaborate':
        model=(build/'fifo.smt2').read_text()
        counts={kind: model.count(f'; yosys-smt2-{kind} ')
                for kind in ('assert','assume','cover')}
        print(f"PROPERTY CHECK: assert={counts['assert']} assume={counts['assume']} cover={counts['cover']}")
        # Fixed harness inventory. Changes to the property set must be reviewed
        # and reflected here rather than silently allowing empty checks.
        expected={'assert':15, 'assume':3, 'cover':3}
        if counts != expected:
            sys.exit(f'Formal property inventory mismatch: expected {expected}; got {counts}. No proof claimed.')
    elif 'Status: PASSED' not in text:
        sys.exit(f'{name} did not report PASSED; no proof claimed.')
    if name == 'cover':
        reached=text.count('Reached cover statement')
        print(f'COVERAGE CHECK: reached={reached}/3')
        if reached != 3:
            sys.exit('Expected three reached cover statements; no cover success claimed.')
print('FORMAL PASS: base, induction, cover (DATA_WIDTH=8, DEPTH=4)')
