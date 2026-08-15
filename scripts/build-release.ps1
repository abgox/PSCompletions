#Requires -Version 7.0

param(
    [ValidateSet('windows', 'darwin', 'linux', 'macos')]
    [string]$Platform,
    [ValidateSet('x64', 'arm64')]
    [string]$Arch
)

# Build the Rust core binaries and copy them into the module.

$ErrorActionPreference = 'Stop'

# Host platform/arch detection, mirroring the module's resolution logic in
# module\PSCompletions\PSCompletions.ps1 (platform: windows/darwin/linux).
$hostPlatform = if ($IsWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } else { 'linux' }
try {
    $hostArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
}
catch {
    $hostArch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'Arm64' } else { 'X64' }
}
$hostArch = if ($hostArch -match 'ARM64') { 'arm64' } else { 'x64' }

if (-not $Platform) { $Platform = $hostPlatform }
if ($Platform -eq 'macos') { $Platform = 'darwin' }
if (-not $Arch) { $Arch = $hostArch }

$coreDir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'core')
$manifest = [System.IO.Path]::Combine($coreDir, 'Cargo.toml')

# Cargo target triples for each module platform/arch pair.
$tripleMap = @{
    'windows-x64'   = 'x86_64-pc-windows-msvc'
    'windows-arm64' = 'aarch64-pc-windows-msvc'
    'linux-x64'     = 'x86_64-unknown-linux-gnu'
    'linux-arm64'   = 'aarch64-unknown-linux-gnu'
    'darwin-x64'    = 'x86_64-apple-darwin'
    'darwin-arm64'  = 'aarch64-apple-darwin'
}
$triple = $tripleMap["$Platform-$Arch"]
$isHost = ($Platform -eq $hostPlatform) -and ($Arch -eq $hostArch)

# Windows binaries carry an .exe extension; the module looks in bin\<platform>-<arch>.
$moduleBinDir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'module', 'PSCompletions', 'bin', "$Platform-$Arch")
$ext = if ($Platform -eq 'windows') { '.exe' } else { '' }
$artifactDir = if ($isHost) { @('target', 'release') } else { @('target', $triple, 'release') }

$artifacts = @('psc-menu', 'psc')

# Stop any process whose executable is exactly $exePath (matches by full path
# so unrelated programs with a same-named exe are left alone).
function Stop-BinaryProcess([string]$exePath) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
    $full = [System.IO.Path]::GetFullPath($exePath)
    $running = Get-Process -Name $name -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Path -and [System.String]::Equals(
            [System.IO.Path]::GetFullPath($_.Path), $full,
            [System.StringComparison]::OrdinalIgnoreCase)
    }
    foreach ($p in $running) {
        Write-Host "  Stopping $($p.ProcessName) (PID $($p.Id)) to release the file lock"
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    }
}

# Retry the copy: the lock can linger briefly after the process exits.
function Copy-WithRetry([string]$src, [string]$dst) {
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            return
        }
        catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Milliseconds 500
        }
    }
}

if (-not $isHost) {
    $installed = @(& rustup target list --installed 2>$null | ForEach-Object { $_.Trim() })
    if ($LASTEXITCODE -eq 0 -and $installed -notcontains $triple) {
        Write-Warning "Target $triple is not installed — run: rustup target add $triple"
    }
}

Write-Host "`n==> cargo fmt" -ForegroundColor Cyan
& cargo fmt --manifest-path $manifest --all
if ($LASTEXITCODE -ne 0) {
    throw 'format failed.'
}

# Cross-compilation uses cargo-zigbuild (requires `cargo install cargo-zigbuild`
# and zig on PATH); the host build is plain cargo.
if ($isHost) {
    Write-Host "`n==> cargo build --release ($Platform-$Arch)" -ForegroundColor Cyan
    & cargo build --release --manifest-path $manifest
}
else {
    Write-Host "`n==> cargo zigbuild --release --target $triple ($Platform-$Arch)" -ForegroundColor Cyan
    & cargo zigbuild --release --target $triple --manifest-path $manifest
}
if ($LASTEXITCODE -ne 0) {
    throw "build --release failed for $triple. Ensure the Rust target is installed (rustup target add $triple) and cargo-zigbuild + zig are available for cross-compilation."
}

Write-Host "`n==> Copying binaries to $moduleBinDir" -ForegroundColor Cyan
$null = New-Item -ItemType Directory -Path $moduleBinDir -Force
$srcRoot = [System.IO.Path]::Combine($coreDir, ($artifactDir -join [System.IO.Path]::DirectorySeparatorChar))
foreach ($name in $artifacts) {
    $file = "$name$ext"
    $src = [System.IO.Path]::Combine($srcRoot, $file)
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Warning "Missing build artifact: $src"
        continue
    }
    $dst = [System.IO.Path]::Combine($moduleBinDir, $file)
    Stop-BinaryProcess $dst
    try {
        Copy-WithRetry $src $dst
        Write-Host "Copied $file"
    }
    catch {
        Write-Warning "Failed to copy ${file}: $($_.Exception.Message)"
    }
}
