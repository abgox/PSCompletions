#!/usr/bin/env pwsh
#Requires -Version 7.6.5

function Get-RecentCompletions {
    param(
        [string]$CompletionsDir,
        # A change to hooks.lua counts as a change to its completion too.
        # Off by default because the manifests are what most callers rewrite; a caller that reads hooks.lua (check-hook-targets) asks for it.
        [switch]$IncludeHooks
    )

    $current = @()
    $guid = [guid]::NewGuid()
    $recentCompletions = git -c core.safecrlf=false log --since="1 day ago" --name-only --pretty=format:"$guid%n" -- 'completions/' |
    ForEach-Object {
        if ($_ -eq '') { return }
        if ($_ -eq $guid) {
            if ($current) {
                $current
            }
            $current = @()
        }
        else {
            $current += $_
        }
    } -End {
        if ($current) {
            $current
        }
    }
    $trackedChanges = git -c core.safecrlf=false diff --name-only HEAD -- 'completions/'
    $untrackedChanges = git -c core.safecrlf=false ls-files --others --exclude-standard -- 'completions/'
    $extRe = if ($IncludeHooks) { '\.(json|lua)$' } else { '\.json$' }
    $allChanges = @($recentCompletions) + @($trackedChanges) + @($untrackedChanges) |
    Where-Object { $_ -match $extRe -and (Test-Path $_) } |
    Sort-Object -Unique

    $completionList = @()
    foreach ($change in $allChanges) {
        if ($change -match '^completions/([^/]+)/') {
            $completionList += $Matches[1]
        }
    }
    return $completionList | Sort-Object -Unique
}

function Write-CiLog {
    # One line per event, one fixed prefix, so a run log can be grepped for `[ci]` and read as a timeline.
    # A failure that only shows an exit code is unreadable after the fact: the runner keeps the log, not the state that produced it.
    # In Actions a warn/error line is repeated as an annotation, which survives in the run summary after the log is gone.
    param(
        [Parameter(Mandatory, Position = 0)][string]$Message,
        [ValidateSet('info', 'ok', 'warn', 'error')][string]$Level = 'info'
    )

    $tag = @{ info = 'INFO'; ok = 'OK  '; warn = 'WARN'; error = 'FAIL' }[$Level]
    Write-Host "[ci] $tag $Message"
    if ($env:GITHUB_ACTIONS) {
        if ($Level -eq 'warn') { Write-Host "::warning::$Message" }
        if ($Level -eq 'error') { Write-Host "::error::$Message" }
    }
}

function Format-PscText {
    # Fills `{Name}` placeholders in a `scripts/language/*.json` message.
    # Deliberately not the engine's template language: these scripts run in a fresh clone, where no `psc` binary has been built yet.
    #
    # A message is either one string or a list of lines, and the lines already carry their own newlines, so the list is joined with nothing — that reproduces the single string these messages used to be.
    # A caller only joins the *values* it passes (e.g. `($names -join ' ')`).
    param([Parameter(Mandatory)][object]$Text, [hashtable]$Values = @{})

    if ($Text -is [array]) { $Text = $Text -join '' } else { $Text = [string]$Text }
    foreach ($key in $Values.Keys) { $Text = $Text.Replace("{$key}", [string]$Values[$key]) }
    $Text
}
