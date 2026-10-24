#!/usr/bin/env python3
"""Compile and run the AXI4-Lite control/status integration test."""
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
for executable in ('iverilog', 'vvp'):
    if not shutil.which(executable):
        sys.exit(f'{executable} not found. Install Icarus Verilog first.')

build = root / 'build'
build.mkdir(exist_ok=True)
image = build / 'axi_lite_axis_fifo.vvp'
compile_cmd = [
    'iverilog', '-g2012', '-Wall', '-s', 'tb_axi_lite_axis_fifo',
    '-o', str(image), 'rtl/sync_fifo.sv', 'rtl/axis_packet_fifo.sv',
    'rtl/axi_lite_axis_fifo.sv', 'tb/tb_axi_lite_axis_fifo.sv'
]
subprocess.run(compile_cmd, cwd=root, check=True)
result = subprocess.run(['vvp', str(image)], cwd=root, text=True,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
print(result.stdout, end='')
(build / 'axi_lite_control_test.log').write_text(result.stdout)
if result.returncode or 'AXI-LITE CONTROL PASS:' not in result.stdout:
    sys.exit(result.returncode or 'Targeted test did not report PASS.')
