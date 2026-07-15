$root = Split-Path $PSScriptRoot -Parent
$moduleDir = Join-Path $root 'module\PSCompletions'

New-Item -Path "$moduleDir/completions" -ItemType Directory -Force
Copy-Item -Path "$root/completions/psc" -Destination "$moduleDir/completions" -Force -Recurse

Test-ModuleManifest -Path "$moduleDir/PSCompletions.psd1"
if ($env:PSGALLERY_API_KEY) {
    Publish-Module -Path $moduleDir -NuGetApiKey $env:PSGALLERY_API_KEY -ErrorAction Stop
}
