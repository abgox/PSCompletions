param(
    [switch]$github,
    [switch]$gitee
)

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json


if (!$PSCompletions) {
    Write-Host $text."import-psc" -ForegroundColor Red
    return
}

$text = $text."check-guid-valid"

if (!$github -and !$gitee) {
    $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidParams))
    return
}

$repoList = @()

if ($gitee) {
    $repoList += @{
        name = "Gitee"
        url  = "https://gitee.com/abgox/PSCompletions/raw/main/completions"
    }
}

if ($github) {
    $repoList += @{
        name = "Github"
        url  = "https://github.com/abgox/PSCompletions/raw/main/completions"
    }
}

foreach ($repo in $repoList) {
    $invalidGuid = @()
    foreach ($item in $PSCompletions.list) {
        $url = "$($repo.url)/$item/guid.txt"
        try {
            $content = Invoke-WebRequest -Uri $url
            $content = $content.Content.Trim()
            $content
            if (!($content -match "^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$")) {
                $invalidGuid += $item
            }
        }
        catch {
            $invalidGuid += $item
        }
    }
    if ($invalidGuid) {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.invalidGuid))
        foreach ($item in $invalidGuid) {
            Write-Host $item -ForegroundColor Red
        }
    }
    else {
        $PSCompletions.write_with_color($PSCompletions.replace_content($text.validGuid))
    }
}
