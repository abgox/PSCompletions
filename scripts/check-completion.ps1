#!/usr/bin/env pwsh
#Requires -Version 7.6.5

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

function Format-Noun {
    param([int]$Count, [string]$Singular, [string]$Plural)
    if ($Count -eq 1) { return "1 $Singular" }
    return "$Count $Plural"
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
        '## Completion check',
        '',
        'No completion files modified.'
    )
}
else {
    & $PSScriptRoot/sort-json.ps1 @($changedCompletions) -Quiet

    # Hook target audit: a psc.on target naming an alias never fires, and no other
    # gate looks at that.
    $hookTargets = @()
    $withHooks = @($changedCompletions | Where-Object {
            Test-Path -LiteralPath (Join-Path $PSScriptRoot "../completions/$_/hooks.lua")
        })
    if ($withHooks.Count -gt 0) {
        $hookTargets = & $PSScriptRoot/check-hook-targets.ps1 @withHooks -Json |
        ConvertFrom-Json
    }
    $hookDetails = if ($hookTargets.failures) { @($hookTargets.failures) } else { @() }

    # Stable-id audit: a changed config.json id breaks rename detection and
    # orphans per-completion settings. Compare against the base checkout, which
    # sits beside pr/ in CI (check-completion.yml). New completions (no base
    # config) and removed ones (no head config) have nothing to compare: only a
    # config that HAS an id on both sides with different values is dangerous.
    $idChanged = @()
    # Version-baseline audit: same base checkout, same both-sides discipline.
    # Maps completion -> base version, only when both sides carry a non-empty
    # version and they differ: the report then shows old -> new on the
    # baseline line, so reviewers see the bump without opening config.json.
    $versionChanged = @{}
    $workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    foreach ($c in $changedCompletions) {
        $headCfg = Join-Path $PSScriptRoot "../completions/$c/config.json"
        $baseCfg = Join-Path $workspaceRoot "base/completions/$c/config.json"
        if (-not (Test-Path -LiteralPath $headCfg)) { continue }
        if (-not (Test-Path -LiteralPath $baseCfg)) { continue }
        try {
            $headJson = Get-Content -LiteralPath $headCfg -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $baseJson = Get-Content -LiteralPath $baseCfg -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        }
        catch { continue }
        $headId = $headJson.id
        $baseId = $baseJson.id
        if ($headId -is [string] -and $baseId -is [string] -and $headId -ne '' -and $baseId -ne '' -and $headId -cne $baseId) {
            $idChanged += $c
        }
        $headVer = $headJson.version
        $baseVer = $baseJson.version
        if ($headVer -is [string] -and $baseVer -is [string] -and $headVer -ne '' -and $baseVer -ne '' -and $headVer -cne $baseVer) {
            $versionChanged[$c] = $baseVer
        }
    }

    # hooks audit: which of psc.run / psc.run_batch each changed hooks.lua uses.
    $hooksUsingRun = @()
    foreach ($c in $changedCompletions) {
        $hf = Join-Path $PSScriptRoot "../completions/$c/hooks.lua"
        if (Test-Path -LiteralPath $hf) {
            $txt = Get-Content -LiteralPath $hf -Raw -ErrorAction SilentlyContinue
            $apis = @()
            if ($txt -match 'psc\.run\s*\(') { $apis += '`psc.run`' }
            if ($txt -match 'psc\.run_batch\s*\(') { $apis += '`psc.run_batch`' }
            if ($apis.Count -gt 0) {
                $hooksUsingRun += [pscustomobject]@{ completion = $c; apis = $apis }
            }
        }
    }

    $jsonChanges = git diff --name-only -- 'completions/' | Where-Object { $_ -match '\.json$' }

    # One validate run, English only: the comment is English-only, and schema /
    # config / compare checks cover every language file regardless of -Lang
    # (it only picks the wording). validate renders the per-completion body
    # (badge, inline CAUTIONs/WARNING, manifest details) into a file, and
    # returns the counts the todo list below needs as JSON.
    $runUsage = @{}
    foreach ($h in $hooksUsingRun) { $runUsage[$h.completion] = ($h.apis -join ' / ') }
    $bodyFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-body.md')
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    $validationData = @( & $PSScriptRoot/validate-completion.ps1 @($changedCompletions) -Lang en-US -Json -NoTitle -OutFile $bodyFile -HookTargetDetails $hookDetails -IdChanged $idChanged -VersionChanged $versionChanged -RunUsage $runUsage | ConvertFrom-Json )

    $hasIssues = @($validationData | Where-Object { $_.hasIssues }).Count -gt 0

    # NOTE: the inner $_ below must not be reused for the outer completion;
    # PowerShell rebinds $_ at every Where-Object, silently comparing each
    # validation entry against itself. Hence the explicit foreach loops.
    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $changedCompletions) {
        $v = $validationData | Where-Object { $_.name -eq $c } | Select-Object -First 1
        if ($v -and $v.hasIssues) { $failed.Add($c) }
    }

    $results = @(
        $marker,
        '',
        '## Completion check',
        ''
    )

    if ($hasIssues) {
        $results += @(
            '### What to do',
            ''
        )
        $deadCounts = @{}
        foreach ($f in @($hookTargets.failures)) {
            if ($f -and $f.completion) {
                if (-not $deadCounts.ContainsKey($f.completion)) { $deadCounts[$f.completion] = 0 }
                $deadCounts[$f.completion] += 1
            }
        }
        foreach ($c in $failed) {
            $v = $validationData | Where-Object { $_.name -eq $c } | Select-Object -First 1
            if ($deadCounts.ContainsKey($c)) {
                $n = $deadCounts[$c]
                $t = if ($n -eq 1) { 'dead hook target' } else { 'dead hook targets' }
                $results += ('- [ ] Fix {0} {1} in `{2}` (see below).' -f $n, $t, $c)
            }
            if ($c -in $idChanged) {
                $results += ('- [ ] Change the `id` in `{0}/config.json` back. Do not change the `id`.' -f $c)
            }
            if ($v) {
                $parts = @()
                if ($v.counts.schema -gt 0) { $parts += (Format-Noun $v.counts.schema 'Schema issue' 'Schema issues') }
                if ($v.counts.config -gt 0) { $parts += (Format-Noun $v.counts.config 'Config issue' 'Config issues') }
                if ($v.counts.hooks -gt 0) { $parts += (Format-Noun $v.counts.hooks 'Hooks issue' 'Hooks issues') }
                if ($v.counts.compare -gt 0) { $parts += (Format-Noun $v.counts.compare 'Compare issue' 'Compare issues') }
                if ($parts.Count -gt 0) {
                    $results += ('- [ ] Fix `{0}`: {1} (see below).' -f $c, ($parts -join ', '))
                }
            }
        }
        if ($jsonChanges) {
            $results += '- [ ] Run `./scripts/compare-json.ps1` and commit the changes.'
        }
        $results += ''
    }

    # validate rendered the per-completion body (badge, inline CAUTIONs and
    # WARNING, manifest details); splice it in as-is.
    $results += Get-Content -LiteralPath $bodyFile -Raw -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
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
