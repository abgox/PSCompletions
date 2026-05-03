#Requires -PSEdition Core

if (-not $env:GITHUB_ACTIONS) {
    throw 'It is a script for workflow'
}

function Add-GithubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [String[]]$Label
    )

    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels" -Headers $headers -Method Post -Body (@{ labels = $Label } | ConvertTo-Json) -ContentType 'application/json'
}

function Remove-GithubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Label
    )

    foreach ($name in $Label) {
        $encoded = [uri]::EscapeDataString($name)
        try {
            Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels/$encoded" -Headers $headers -Method Delete
        }
        catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
                throw
            }
        }
    }
}

$repo = $env:REPO
$pr = $env:PR_NUMBER
$marker = $env:MARKER
$headers = @{
    Authorization = "Bearer $env:GITHUB_TOKEN"
    Accept        = 'application/vnd.github.v3+json'
}

$page = 1
$files = @()
$api = "https://api.github.com/repos/$repo/pulls/$pr/files?per_page=100"

while ($true) {
    $res = Invoke-RestMethod -Uri "$api&page=$page" -Headers $headers
    if (-not $res) { break }
    $files += $res
    if ($res.Count -lt 100) { break }
    $page++
}

$results = @()
$labels = [ordered]@{
    'security-review-needed' = $false
}
$hasCompletion = $false
$hasScriptBlock = $false

foreach ($file in $files) {
    $match = $file.filename -match '^completions/([^/]+)/language/(.*)\.json$'
    if (-not $match) {
        continue
    }
    $hasCompletion = $true

    $completion = $matches[1]
    Write-Host $completion

    $line = @()

    # Status
    $line += $file.status

    # Completion
    $line += $completion

    # Language
    $line += $matches[2]

    # Script
    $c = Invoke-RestMethod -Uri $file.raw_url -Headers $headers
    if ($c -like '*{{*') {
        $hasScriptBlock = $true
        $line += 'Yes'
    }
    else {
        $line += 'No'
    }

    $results += '|' + ($line -join '|') + '|'
}

$guide = @'

<details>

<summary>Guide</summary>

<br />

- **Status**: The status of the file in the PR.
- **Completion**: The completion name.
- **Language**: The language of the completion.
- **Script**: Whether the completion contains dynamic script, like `{{ xxx }}`.

</details>

'@

if ($hasCompletion) {
    $results = @(
        $marker,
        $guide,
        '',
        '| Status | Completion | Language | Script |',
        '| :-: | :-: | :-: | :-: |'
    ) + $results


    if ($hasScriptBlock) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            '> - Some completions contain dynamic script, like `{{ xxx }}`',
            '> - Please check them carefully before merging.'
        )
    }
}
else {
    $results = @(
        $marker,
        '',
        'No JSON for completion in PR.'
    )
}

$results | Out-File result.md


# Labels
$add_labels = @()
$rm_labels = @()

$labels.Keys | ForEach-Object { if ($labels.$_) { $add_labels += $_ } else { $rm_labels += $_ } }

if ($add_labels) { Add-GithubLabel $add_labels }
if ($rm_labels) { Remove-GithubLabel $rm_labels }
