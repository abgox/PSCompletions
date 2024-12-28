param([string]$NuGetApiKey, [switch]$Verbose)

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) {
    Write-Host $text."import-psc" -ForegroundColor Red
    return
}

$text = $text."publish-module"

if (!$NuGetApiKey) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.requireKey))
    return
}


$path = @{
    module = "$PSScriptRoot\..\module\PSCompletions"
    dist   = "$PSScriptRoot\..\PSCompletions"
}

Remove-Item $path.dist -Recurse -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory $path.dist -Force

Copy-Item -Path "$($path.module)\core" -Destination "$($path.dist)\core" -Recurse -Force

Copy-Item -Path "$($path.module)\PSCompletions.psd1" -Destination "$($path.dist)\PSCompletions.psd1" -Force

Copy-Item -Path "$($path.module)\PSCompletions.psm1" -Destination "$($path.dist)\PSCompletions.psm1" -Force

Publish-Module -Path $path.dist -NuGetApiKey $NuGetApiKey -Verbose:$Verbose
