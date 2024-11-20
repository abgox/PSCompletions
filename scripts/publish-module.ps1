param([string]$NuGetApiKey, [switch]$Verbose)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}

if (!$NuGetApiKey) {
    $PSCompletions.write_with_color("<@Red>The parameter <@Magenta>NuGetApiKey<@Red> is required.")
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

Publish-Module -Path $dist -NuGetApiKey $NuGetApiKey -Verbose:$Verbose
