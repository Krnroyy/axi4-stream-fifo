$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$vivadoBin = "C:\AMDDesignTools\2026.1\Vivado\bin"
if (-not (Test-Path (Join-Path $vivadoBin "xvlog.bat"))) {
    throw "Vivado xvlog was not found at $vivadoBin. Edit `$vivadoBin in this script."
}

$buildDir = Join-Path $repoRoot "build\uvm_axis_fifo"
New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
Push-Location $buildDir
try {
    $xvlog = Join-Path $vivadoBin "xvlog.bat"
    $xvlogArgs = @(
        "-L", "uvm", "-sv",
        (Join-Path $repoRoot "rtl\sync_fifo.sv"),
        (Join-Path $repoRoot "rtl\axis_packet_fifo.sv"),
        (Join-Path $repoRoot "tb\uvm\tb_axis_fifo_uvm.sv")
    )
    & $xvlog @xvlogArgs
    if ($LASTEXITCODE -ne 0) { throw "xvlog compilation failed." }

    $xelab = Join-Path $vivadoBin "xelab.bat"
    & $xelab -L uvm tb_axis_fifo_uvm -s axis_fifo_uvm_sim
    if ($LASTEXITCODE -ne 0) { throw "xelab elaboration failed." }

    $xsim = Join-Path $vivadoBin "xsim.bat"
    & $xsim axis_fifo_uvm_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim simulation failed." }
} finally {
    Pop-Location
}
