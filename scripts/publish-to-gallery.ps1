$root = Split-Path $PSScriptRoot -Parent
$moduleDir = Join-Path $root 'module\PSCompletions'
$completionsDir = Join-Path $root 'completions'

New-Item -Path "$moduleDir/completions" -ItemType Directory -Force
New-Item -Path "$moduleDir/temp" -ItemType Directory -Force

Copy-Item -Path "$root/completions.json" -Destination "$moduleDir/temp/completions.json" -Force
Copy-Item -Path "$completionsDir/psc" -Recurse -Destination "$moduleDir/completions/psc" -Force

Test-ModuleManifest -Path "$moduleDir/PSCompletions.psd1"
Write-Output '::notice::Module manifest validation passed'

if ($env:PSGALLERY_API_KEY) {
    Publish-Module -Path $moduleDir -NuGetApiKey $env:PSGALLERY_API_KEY -ErrorAction Stop
    Write-Output '::notice::Published to PowerShell Gallery successfully'
}
