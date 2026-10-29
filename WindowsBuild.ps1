param([string]$OutputDirectory = 'windows-build')
$ErrorActionPreference = 'Stop'
Push-Location $PSScriptRoot
try {
    $root = [IO.Path]::GetFullPath($OutputDirectory)
    $app = Join-Path $root 'app'
    dotnet publish QuietDesktop.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=false -p:DebugType=None -o $app
    if ($LASTEXITCODE -ne 0) { throw 'Windows compilation failed.' }
    $checks = Join-Path $root 'validation'
    New-Item -ItemType Directory -Force $checks | Out-Null
    $process = Start-Process (Join-Path $app 'QuietDesktop.exe') -ArgumentList @('--self-test', "`"$checks`"") -PassThru
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Native smoke check timed out.' }
    if ($process.ExitCode -ne 0) { throw "Native smoke check failed: $($process.ExitCode)" }
    Compress-Archive -Path "$app\*" -DestinationPath (Join-Path $root 'Quiet-Desktop-Windows-x64-1.6.0.zip') -Force
    Get-FileHash (Join-Path $root 'Quiet-Desktop-Windows-x64-1.6.0.zip') -Algorithm SHA256 | Select-Object Hash | ConvertTo-Json | Set-Content (Join-Path $root 'download-sha256.json')
} finally { Pop-Location }
