#Requires -Version 7.0

if (-not $env:GITHUB_ACTIONS) {
    throw 'It is a script for workflow'
}

function Add-GitHubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [String[]]$Label
    )

    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels" -Headers $headers -Method Post -Body (@{ labels = $Label } | ConvertTo-Json) -ContentType 'application/json'
}

function Remove-GitHubLabel {
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

$changedCompletions = @()

foreach ($file in $files) {
    $fn = $file.filename
    if ($fn -notmatch '^completions/([^/]+)/(config\.json|hooks\.lua|language/.+\.json)$') {
        continue
    }
    $completion = $Matches[1]
    if ($completion -notin $changedCompletions) {
        $changedCompletions += $completion
    }
}

$results = @()
$hasIssues = $false

if ($changedCompletions.Count -eq 0) {
    $results = @(
        $marker,
        '',
        '没有补全文件修改。 | No completion files modified.'
    )
}
else {
    & $PSScriptRoot\sort-json.ps1 @($changedCompletions) -Quiet

    $enFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-validation-en.md')
    $zhFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-validation-zh.md')
    $validationResults = & $PSScriptRoot\validate-completion.ps1 @($changedCompletions) -Lang en-US -OutFile $enFile
    $null = & $PSScriptRoot\validate-completion.ps1 @($changedCompletions) -Lang zh-CN -OutFile $zhFile

    $hasIssues = @($validationResults | Where-Object { $_.hasIssues }).Count -gt 0

    # Hook target audit: a psc.on target naming an alias never fires, and no other
    # gate looks at that.
    $hookTargets = @()
    $withHooks = @($changedCompletions | Where-Object {
            Test-Path -LiteralPath (Join-Path $PSScriptRoot "..\completions\$_\hooks.lua")
        })
    if ($withHooks.Count -gt 0) {
        $hookTargets = & $PSScriptRoot\check-hook-targets.ps1 @withHooks -Json |
            ConvertFrom-Json
        if ($hookTargets.failures.Count -gt 0) { $hasIssues = $true }
    }

    # hooks audit: hooks.lua uses psc.run / run_batch
    $hooksUsingRun = @()
    foreach ($c in $changedCompletions) {
        $hf = Join-Path $PSScriptRoot "..\completions\$c\hooks.lua"
        if (Test-Path -LiteralPath $hf) {
            $txt = Get-Content -LiteralPath $hf -Raw -ErrorAction SilentlyContinue
            if ($txt -match 'psc\.run(_batch)?\s*\(') {
                $hooksUsingRun += $c
            }
        }
    }

    $jsonChanges = git diff --name-only -- 'completions/' | Where-Object { $_ -match '\.json$' }

    $results = @(
        $marker,
        '',
        '## 补全检查结果 | Completion Validation',
        ''
    )

    if (Test-Path -LiteralPath $zhFile) {
        $results += @(
            '',
            '<details>',
            '<summary>中文版</summary>',
            ''
        )
        $results += (Get-Content -LiteralPath $zhFile -Raw -ErrorAction SilentlyContinue)
        $results += @(
            '',
            '</details>'
        )
    }
    if (Test-Path -LiteralPath $enFile) {
        $results += @(
            '',
            '<details>',
            '<summary>English</summary>',
            ''
        )
        $results += (Get-Content -LiteralPath $enFile -Raw -ErrorAction SilentlyContinue)
        $results += @(
            '',
            '</details>'
        )
    }

    if ($jsonChanges) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            '> Please run it to sort and compare JSON, then commit the changes.',
            '>',
            '> ```powershell',
            '> .\scripts\compare-json.ps1',
            '> ```',
            ''
        )
    }

    if ($hooksUsingRun.Count -gt 0) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            ('> hooks.lua uses `{0}` / `{1}`: {2}' -f 'psc.run', 'psc.run_batch', ($hooksUsingRun -join ' ')),
            ''
        )
    }

    if ($hookTargets.failures.Count -gt 0) {
        $results += @(
            '',
            '> [!WARNING]',
            '>',
            '> `hooks.lua` targets that can never fire (`psc.on` matches the canonical `name`, not an `alias`):',
            '>'
        )
        foreach ($f in $hookTargets.failures) {
            $loc = "$($f.completion) > $($f.target)"
            if ($f.option) { $loc += " [$($f.option)]" }
            $results += ('> - `{0}` -- {1}' -f $loc, $f.reason)
        }
        $results += ''
    }
}

$results | Out-File -FilePath ([System.IO.Path]::Combine($PSScriptRoot, '..', 'result.md')) -Encoding utf8

$labels = [ordered]@{
    'check-failed' = $hasIssues
}

$add_labels = @()
$rm_labels = @()

$labels.Keys | ForEach-Object { if ($labels.$_) { $add_labels += $_ } else { $rm_labels += $_ } }

if ($add_labels) { Add-GitHubLabel $add_labels }
if ($rm_labels) { Remove-GitHubLabel $rm_labels }
