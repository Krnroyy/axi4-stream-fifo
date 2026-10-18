#!/usr/bin/env python3
"""Run from any directory: python scripts/run_sim.py [--waves]."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--waves', action='store_true')
args = parser.parse_args()
for executable in ('iverilog', 'vvp'):
    if not shutil.which(executable):
        sys.exit(f'{executable} not found. See README.md for installation.')
(root/'build').mkdir(exist_ok=True)
logs=[]
try:
    for depth in (1, 3, 4, 16):
        output=root/'build'/f'fifo_d{depth}.vvp'
        subprocess.run(['iverilog','-g2012','-Wall','-s','tb_axis_packet_fifo',
                        f'-Ptb_axis_packet_fifo.DEPTH={depth}','-o',str(output),
                        'rtl/sync_fifo.sv','rtl/axis_packet_fifo.sv',
                        'tb/tb_axis_packet_fifo.sv'],cwd=root,check=True)
        for seed in (1,17,2026):
            cmd=['vvp',str(output),f'+SEED={seed}']
            if args.waves and depth==16 and seed==1: cmd.append('+WAVES')
            result=subprocess.run(cmd,cwd=root,text=True,stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT)
            print(result.stdout,end='')
            logs.append(result.stdout)
            if result.returncode or 'PASS depth=' not in result.stdout:
                sys.exit(result.returncode or 1)
    logs.append('REGRESSION PASS: 12 runs\n')
    print(logs[-1],end='')
finally:
    (root/'build'/'simulation.log').write_text(''.join(logs))
