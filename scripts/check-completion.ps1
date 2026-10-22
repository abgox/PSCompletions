#!/usr/bin/env pwsh
#Requires -Version 7.6.5

if (-not $env:GITHUB_ACTIONS) {
    throw 'It is a script for workflow'
}

. $PSScriptRoot/utils.ps1

function Get-ToolVersion {
    # The verdict is only reproducible against the versions that produced it, and ajv is installed unpinned on every run.
    # CI-only drift is the first thing to rule out when a definition passes here and fails on the runner.
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { return 'absent' }
    $first = & $Name --version 2>$null | Select-Object -First 1
    if ($first) { return ([string]$first).Trim() }
    return 'unknown'
}

function Add-GitHubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [String[]]$Label
    )

    Write-CiLog "adding label: $($Label -join ', ')"
    Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels" -Headers $headers -Method Post -Body (@{ labels = $Label } | ConvertTo-Json) -ContentType 'application/json' | Out-Null
}

function Remove-GitHubLabel {
    param(
        [ValidateNotNullOrEmpty()]
        [string[]]$Label
    )

    foreach ($name in $Label) {
        $encoded = [uri]::EscapeDataString($name)
        try {
            Write-CiLog "removing label: $name"
            Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/issues/$pr/labels/$encoded" -Headers $headers -Method Delete | Out-Null
        }
        catch {
            if ($_.Exception.Response.StatusCode -ne [System.Net.HttpStatusCode]::NotFound) {
                Write-CiLog "removing label $name failed: $($_.Exception.Message)" -Level error
                throw
            }
            Write-CiLog "label not present, nothing to remove: $name"
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

# The workflow lays base/ and pr/ side by side (check-completion.yml); every audit that needs "before" reads from base/.
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$baseIndex = Join-Path $workspaceRoot 'base/completions.json'

Write-CiLog ('environment: pwsh {0} · node {1} · ajv {2} · {3}' -f $PSVersionTable.PSVersion, (Get-ToolVersion node), (Get-ToolVersion ajv), (Get-ToolVersion git))
Write-CiLog "repo=$repo pr=$pr workspace=$workspaceRoot"
Write-CiLog ('base index: {0}' -f $(if (Test-Path -LiteralPath $baseIndex) { $baseIndex } else { 'not found, the id audit has no baseline' }))

$stage = [System.Diagnostics.Stopwatch]::StartNew()
$total = [System.Diagnostics.Stopwatch]::StartNew()
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
Write-CiLog ('pull request files: {0} in {1:N1}s' -f @($files).Count, $stage.Elapsed.TotalSeconds)

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

if ($changedCompletions.Count -eq 0) {
    Write-CiLog 'changed completions: none, nothing to validate'
}
else {
    Write-CiLog ('changed completions: {0}' -f ($changedCompletions -join ', '))
}

$results = @()
$hasIssues = $false
$failed = [System.Collections.Generic.List[string]]::new()

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
    $stage.Restart()
    & $PSScriptRoot/sort-json.ps1 @($changedCompletions) -Quiet
    Write-CiLog ('sort-json: {0} completion(s) in {1:N1}s' -f $changedCompletions.Count, $stage.Elapsed.TotalSeconds)

    # Hook target audit: a psc.on target naming an alias never fires, and no other gate looks at that.
    $hookTargets = @()
    $withHooks = @($changedCompletions | Where-Object {
            Test-Path -LiteralPath (Join-Path $PSScriptRoot "../completions/$_/hooks.lua")
        })
    if ($withHooks.Count -gt 0) {
        $hookTargets = & $PSScriptRoot/check-hook-targets.ps1 @withHooks -Json |
        ConvertFrom-Json
    }
    $hookDetails = if ($hookTargets.failures) { @($hookTargets.failures) } else { @() }
    Write-CiLog ('hook target audit: {0} completion(s) with hooks.lua, {1} dead target(s)' -f $withHooks.Count, @($hookDetails).Count)
    foreach ($f in @($hookDetails)) {
        Write-CiLog ('dead psc.on target in {0}: {1}' -f $f.completion, $f.target) -Level error
    }

    # Stable-id audit: a changed config.json id breaks rename detection and orphans per-completion settings.
    # Compare against the base checkout, which sits beside pr/ in CI (check-completion.yml).
    # New completions (no base config) and removed ones (no head config) have nothing to compare: only a config that HAS an id on both sides with different values is dangerous.
    $idChanged = @()
    # Version-baseline audit: same base checkout, same both-sides discipline.
    # Maps completion -> base version, only when both sides carry a non-empty version and they differ: the report then shows old -> new on the baseline line, so reviewers see the bump without opening config.json.
    $versionChanged = @{}
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

    Write-CiLog ('config audits: {0} id change(s), {1} version baseline change(s)' -f @($idChanged).Count, $versionChanged.Count)

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
    if ($jsonChanges) {
        Write-CiLog ('not normalized: {0} (sort-json rewrote them, commit the result)' -f ($jsonChanges -join ', '))
    }

    # One validate run, English only: the comment is English-only, and schema / config / compare checks cover every language file regardless of -Lang (it only picks the wording).
    # validate renders the per-completion body (badge, inline CAUTIONs/WARNING, manifest details) into a file, and returns the counts the todo list below needs as JSON.
    $runUsage = @{}
    foreach ($h in $hooksUsingRun) { $runUsage[$h.completion] = ($h.apis -join ' / ') }
    $bodyFile = [System.IO.Path]::Combine($PSScriptRoot, 'result-body.md')
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
    $stage.Restart()
    $validationData = @( & $PSScriptRoot/validate-completion.ps1 @($changedCompletions) -Lang en-US -Json -NoTitle -OutFile $bodyFile -HookTargetDetails $hookDetails -IdChanged $idChanged -VersionChanged $versionChanged -RunUsage $runUsage | ConvertFrom-Json )
    Write-CiLog ('validate-completion: {0} result(s) in {1:N1}s' -f @($validationData).Count, $stage.Elapsed.TotalSeconds)

    # A check that never ran must not pass: one missing result means one completion went unvalidated, which is a failure, not a gap.
    $incomplete = @($validationData).Count -ne $changedCompletions.Count
    if ($incomplete) {
        Write-CiLog ('validate-completion returned {0} of {1} requested completions, treating the check as failed' -f @($validationData).Count, $changedCompletions.Count) -Level error
    }

    # A per-completion verdict line is what makes the log readable without fetching the comment: which definitions were checked, and which of them failed on what.
    foreach ($v in @($validationData)) {
        $counts = 'schema {0}, config {1}, hooks {2}, compare {3}' -f $v.counts.schema, $v.counts.config, $v.counts.hooks, $v.counts.compare
        if ($v.hasIssues) {
            Write-CiLog ('{0}: FAILED ({1})' -f $v.name, $counts) -Level error
        }
        else {
            Write-CiLog ('{0}: ok ({1})' -f $v.name, $counts) -Level ok
        }
    }

    $hasIssues = $incomplete -or @($validationData | Where-Object { $_.hasIssues }).Count -gt 0

    # NOTE: the inner $_ below must not be reused for the outer completion; PowerShell rebinds $_ at every Where-Object, silently comparing each validation entry against itself.
    # Hence the explicit foreach loops.
    foreach ($c in $changedCompletions) {
        $v = $validationData | Where-Object { $_.name -eq $c } | Select-Object -First 1
        if (-not $v -or $v.hasIssues) { $failed.Add($c) }
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
            if (-not $v) {
                $results += ('- [ ] Re-run the check: `{0}` produced no validation result.' -f $c)
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

    # validate rendered the per-completion body (badge, inline CAUTIONs and WARNING, manifest details); splice it in as-is.
    $results += Get-Content -LiteralPath $bodyFile -Raw -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
}

$resultFile = [System.IO.Path]::Combine($PSScriptRoot, '..', 'result.md')
$results | Out-File -FilePath $resultFile -Encoding utf8

# The log is read before the comment is: on a failing run the report is printed here too, so the reason is in the run itself.
if ($hasIssues) {
    Write-CiLog 'report follows'
    Get-Content -LiteralPath $resultFile -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
    Write-CiLog 'report ends'
}

$labels = [ordered]@{
    'check-failed' = $hasIssues
}

$add_labels = @()
$rm_labels = @()

$labels.Keys | ForEach-Object { if ($labels.$_) { $add_labels += $_ } else { $rm_labels += $_ } }

if ($add_labels) { Add-GitHubLabel $add_labels }
if ($rm_labels) { Remove-GitHubLabel $rm_labels }

Write-CiLog ('labels: add [{0}] remove [{1}]' -f ($add_labels -join ', '), ($rm_labels -join ', '))

if ($hasIssues) {
    Write-CiLog ('result: FAILED, {0} of {1} completion(s) have issues, {2:N1}s total' -f $failed.Count, $changedCompletions.Count, $total.Elapsed.TotalSeconds) -Level error
    exit 1
}
Write-CiLog ('result: passed, {0:N1}s total' -f $total.Elapsed.TotalSeconds) -Level ok
