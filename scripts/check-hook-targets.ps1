#!/usr/bin/env pwsh

<#
.SYNOPSIS
Check that every psc.on target in a hooks.lua can actually fire.

.DESCRIPTION
A hook target that names an alias, or a subcommand the manifest never modelled,
fails silently: the hook simply never runs, and the slot stays empty with nothing
reported anywhere. Both other gates pass such a file -- they only look at internal
consistency.

    .\scripts\check-hook-targets.ps1                # recently changed completions
    .\scripts\check-hook-targets.ps1 -All           # every completion with hooks
    .\scripts\check-hook-targets.ps1 git gh         # just these
    .\scripts\check-hook-targets.ps1 -Json          # structured, for CI

Exit code 0 when every target resolves, 1 otherwise, 2 when the arguments do not
make sense.

With no names, the set comes from Get-RecentCompletions (scripts/utils.ps1) -- the
same source sort-json and compare-json use -- with -IncludeHooks, because a change
to hooks.lua is a change to the completion as far as this check is concerned.
Completions without a hooks.lua are skipped. -All takes every completion that has
one. An explicit name always wins, so the CI caller passes exactly what the PR
touched.

Why the alias case matters: psc.on matches command segments against CANONICAL
names only, and the canonical is the manifest's own `name` field --
core/engine/src/engine/completion.rs defines canonical_name() as
canonical_spelling(&self.name), and that value is what reaches
psc.typing.canonical. A manifest that stores `add` as an alias of `stage`
therefore cannot be targeted as `command = "add"`.

Which spelling to write is not a judgement call: scripts/sort-json.ps1 normalises
`name` and `alias` by length on every run, keeping the longest as `name`. Write the
longest form; the script has already made it canonical. A tool whose own primary
name is shorter -- jj's `evolog`, mise's `ls` -- is normal and is not reported,
because the tool's preference is not what psc.on compares against.

Scope: two files per completion, no execution. The tool being audited is never
run, so this cannot block, cannot prompt, and needs nothing installed. Drift
against the real CLI is caught by reading that CLI's own help while writing the
completion; a check that has to execute the tool to be believed is a second tool,
not a gate.
#>

[CmdletBinding()]
param(
    # ValueFromRemainingArguments is what makes `git gh` bind: a bare [string[]]
    # at Position 0 takes one positional value, so the second name would have no
    # parameter to land in. It also swallows a misspelled switch, which is why
    # $stray below refuses anything shaped like a flag.
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Completion,

    [switch]$All,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ---------------------------------------------------------------------------
# Localized text
# ---------------------------------------------------------------------------
$textPath = "$script:Root/scripts/language/$PSCulture.json"
if (!(Test-Path -LiteralPath $textPath)) {
    $textPath = "$script:Root/scripts/language/en-US.json"
}
$script:text = (Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json)
$script:text = $script:text.'check-hook-targets'

function msg {
    param([string]$Key, [hashtable]$Vars = @{})
    $s = [string]$script:text.$Key
    foreach ($k in $Vars.Keys) {
        $s = $s.Replace('{{ $' + $k + ' }}', [string]$Vars[$k])
    }
    $s
}

# Replace the <@Color> markers the other scripts use with real escape sequences.
function colorize {
    param([string]$Text)
    $map = @{
        '<@Red>'    = "`e[31m"
        '<@Green>'  = "`e[32m"
        '<@Yellow>' = "`e[33m"
        '<@Blue>'   = "`e[34m"
        '<@Cyan>'   = "`e[36m"
        '<@Magenta>' = "`e[35m"
        '<@Gray>'   = "`e[90m"
    }
    $out = $Text
    foreach ($k in $map.Keys) { $out = $out.Replace($k, $map[$k]) }
    $out -replace '<@[^>]+>', ''
}

function say {
    param([string]$Key, [hashtable]$Vars = @{})
    if ($script:Quiet) { return }
    Write-Host (colorize (msg $Key $Vars))
}

# Bail out with a message and the exit code the .SYNOPSIS documents. The message
# goes to stderr directly rather than through Write-Error, whose ConciseView
# rendering adds the offending source line to a one-line complaint; and because
# $ErrorActionPreference is 'Stop' for the whole script, a Write-Error would
# throw here and the exit code would never be reached.
function stop {
    param([string]$Key, [hashtable]$Vars = @{})
    [Console]::Error.WriteLine((colorize (msg $Key $Vars)))
    exit 2
}

# A misspelled switch reaches $Completion through ValueFromRemainingArguments
# and would otherwise be reported as a completion with no such name. Refuse it
# instead of going looking for one.
$stray = @($Completion | Where-Object { $_ -and $_.StartsWith('-') })
if ($stray.Count -gt 0) {
    stop 'unknownArg' @{ arg = ($stray -join ' ') }
}

# ---------------------------------------------------------------------------
# Manifest indexing
# ---------------------------------------------------------------------------
# Set-StrictMode makes a missing property an error, and a manifest entry simply
# omits `alias` / `option` / `next` whenever it has nothing to put there. Reading
# them through this keeps "absent" and "empty" the same thing.
# PowerShell's @{} is case-insensitive, which silently merges distinct targets:
# ssh-keygen registers both `-f`/`-F` and `-r`/`-R`. Every table keyed by a
# spelling has to be Ordinal.
function New-CaseTable {
    [System.Collections.Hashtable]::new([System.StringComparer]::Ordinal)
}

function Get-Prop {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) {
        return $(if ($Obj.Contains($Name)) { $Obj[$Name] } else { $null })
    }
    if ($Obj.PSObject.Properties.Name -contains $Name) { return $Obj.$Name }
    return $null
}

function Get-Manifest {
    param([string]$Name)
    $p = Join-Path $script:Root "completions/$Name/language/en-US.json"
    Get-Content -Path $p -Encoding utf8 -Raw | ConvertFrom-Json
}

# canonical path (joined by space) -> item, plus alias path -> canonical path.
# Paths are space-joined strings rather than tuples so they can key a hashtable;
# a subcommand name cannot contain a space unless quoted, and a quoted one keeps
# its quotes, so the join stays unambiguous.
function Get-IndexPaths {
    param($Doc)
    $paths = New-CaseTable
    $aliases = New-CaseTable
    $paths[''] = $Doc
    $stack = [System.Collections.Stack]::new()
    $stack.Push(@{ Node = $Doc; Path = '' })
    while ($stack.Count -gt 0) {
        $frame = $stack.Pop()
        foreach ($key in @('next', 'option', 'global_option')) {
            $items = Get-Prop $frame.Node $key
            if (!$items) { continue }
            foreach ($item in $items) {
                $p = if ($frame.Path) { $frame.Path + ' ' + $item.name } else { $item.name }
                $paths[$p] = $item
                $ialias = Get-Prop $item 'alias'
                if ($ialias) {
                    foreach ($a in $ialias) {
                        $ap = if ($frame.Path) { $frame.Path + ' ' + $a } else { $a }
                        if (!$aliases.ContainsKey($ap)) { $aliases[$ap] = $p }
                    }
                }
                $stack.Push(@{ Node = $item; Path = $p })
            }
        }
    }
    @{ paths = $paths; aliases = $aliases }
}

# ---------------------------------------------------------------------------
# Reading psc.on specs out of a hooks.lua
#
# Balanced-brace walk rather than a regex over the body: a regex loses psc.run(
# wrappers and leaves stray `end`s. No inner group means the outer table IS the
# spec, because psc.on takes psc_on_spec|psc_on_spec[].
# ---------------------------------------------------------------------------
$script:SpecCmdRe = [regex]'command\s*=\s*(?:"([^"]+)"|\{([^}]*)\})'
$script:SpecOptRe = [regex]'option\s*=\s*(?:"([^"]+)"|\{([^}]*)\})'
$script:SpecStrRe = [regex]'"([^"]+)"'

function Get-Specs {
    param([string]$Src)

    $specs = [System.Collections.Generic.List[string]]::new()
    $i = 0
    while (($i = $Src.IndexOf('psc.on(', $i)) -ge 0) {
        $start = $Src.IndexOf('{', $i)
        if ($start -lt 0) { break }

        # walk to the matching close brace of the outer table
        $depth = 0
        $k = $start
        while ($k -lt $Src.Length) {
            if ($Src[$k] -eq '{') { $depth++ }
            elseif ($Src[$k] -eq '}') {
                $depth--
                if ($depth -eq 0) { break }
            }
            $k++
        }
        $block = $Src.Substring($start + 1, $k - $start - 1)

        # top-level { } groups within the block
        $d = 0
        $gstart = -1
        $found = $false
        for ($idx = 0; $idx -lt $block.Length; $idx++) {
            $c = $block[$idx]
            if ($c -eq '{') {
                if ($d -eq 0) { $gstart = $idx }
                $d++
            }
            elseif ($c -eq '}') {
                $d--
                if ($d -eq 0 -and $gstart -ge 0) {
                    $specs.Add($block.Substring($gstart, $idx - $gstart + 1))
                    $gstart = -1
                    $found = $true
                }
            }
        }
        if (!$found -and ($block.Contains('command') -or $block.Contains('option'))) {
            $specs.Add($block)
        }
        $i = $k + 1
    }
    $specs
}

function Get-Strings {
    param([string]$Body)
    @($script:SpecStrRe.Matches($Body) | ForEach-Object { $_.Groups[1].Value })
}

# Every (command, option) target, deduplicated, in first-seen order. A spec with
# neither a command nor an option is the root and is not a target.
function Get-Targets {
    param([string]$Src)

    $out = [System.Collections.Generic.List[object]]::new()
    $seen = New-CaseTable
    foreach ($spec in (Get-Specs $Src)) {
        $cm = $script:SpecCmdRe.Match($spec)
        $om = $script:SpecOptRe.Match($spec)
        if (!$cm.Success -and !$om.Success) { continue }

        if ($cm.Success -and $cm.Groups[1].Success) {
            $cmd = @($cm.Groups[1].Value)
        }
        elseif ($cm.Success) {
            $cmd = @(Get-Strings $cm.Groups[2].Value)
        }
        else {
            $cmd = @()
        }

        if ($om.Success -and $om.Groups[1].Success) {
            $opt = @($om.Groups[1].Value)
        }
        elseif ($om.Success) {
            $opt = @(Get-Strings $om.Groups[2].Value)
        }
        else {
            $opt = @()
        }

        $key = ($cmd -join "`u{1}") + "`u{2}" + ($opt -join "`u{1}")
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $out.Add([pscustomobject]@{ command = $cmd; option = $opt })
    }
    $out
}

function Get-OptionNames {
    param($Item)
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in @('option', 'global_option')) {
        $items = Get-Prop $Item $key
        if (!$items) { continue }
        foreach ($o in $items) {
            [void]$names.Add([string]$o.name)
            $oalias = Get-Prop $o 'alias'
            if ($oalias) { foreach ($a in $oalias) { [void]$names.Add([string]$a) } }
        }
    }
    # The leading comma is load-bearing: a bare `$names` on the last line gets
    # enumerated by the output pipeline, so the caller would receive the
    # spellings rather than the set. A command with no options would then arrive
    # as $null and .Contains() would throw, and a command with options would
    # silently degrade to IList.Contains, which is case-insensitive -- the
    # opposite of the Ordinal rule the set was built for.
    , $names
}

function Get-AllOptionNames {
    param($Doc)
    $names = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $stack = [System.Collections.Stack]::new()
    $stack.Push($Doc)
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        foreach ($n in (Get-OptionNames $node)) { [void]$names.Add($n) }
        foreach ($key in @('next', 'option', 'global_option')) {
            $items = Get-Prop $node $key
            if ($items) { foreach ($c in $items) { $stack.Push($c) } }
        }
    }
    # Same reason as Get-OptionNames: a bare `$names` is enumerated away, and the
    # caller asks .Contains() on the result.
    , $names
}

function Get-Target {
    param($Item)
    if ($Item.command.Count -gt 0) { $Item.command -join ' ' } else { '(any command)' }
}

# ---------------------------------------------------------------------------
# Manifest-only check
# ---------------------------------------------------------------------------
function Test-HookTargets {
    param([string]$Name)

    $src = Get-Content -Path (Join-Path $script:Root "completions/$Name/hooks.lua") -Encoding utf8 -Raw
    $doc = Get-Manifest $Name
    $idx = Get-IndexPaths $doc

    $bad = [System.Collections.Generic.List[object]]::new()
    foreach ($t in (Get-Targets $src)) {
        $p = ($t.command -join ' ')
        if ($p -eq '') {
            # psc.on({ option = "--x" }, f) has no command to anchor on, so the
            # option can fire wherever it appears. The only honest check is that it
            # is declared somewhere; which context is narrow cannot be told from
            # the spec alone.
            $known = Get-AllOptionNames $doc
            $missing = @($t.option | Where-Object { !$known.Contains($_) })
            if ($missing.Count -gt 0) {
                $bad.Add([pscustomobject]@{
                    completion = $Name
                    target     = '(any command)'
                    option     = ($t.option -join ',')
                    reason     = (msg 'optionNowhere' -Vars @{ options = ($missing -join ', ') })
                })
            }
            continue
        }
        if ($idx.paths.ContainsKey($p)) {
            $owner = $idx.paths[$p]
        }
        elseif ($idx.aliases.ContainsKey($p)) {
            $canon = $idx.aliases[$p]
            $bad.Add([pscustomobject]@{
                completion = $Name
                target     = $p
                option     = ($t.option -join ',')
                reason     = (msg 'aliasReason' -Vars @{ canonical = $canon })
            })
            continue
        }
        else {
            $bad.Add([pscustomobject]@{
                completion = $Name
                target     = $p
                option     = ($t.option -join ',')
                reason     = (msg 'noPath')
            })
            continue
        }
        if ($t.option.Count -gt 0) {
            $names = Get-OptionNames $owner
            $missing = @($t.option | Where-Object { !$names.Contains($_) })
            if ($missing.Count -gt 0) {
                $bad.Add([pscustomobject]@{
                    completion = $Name
                    target     = $p
                    option     = ($t.option -join ',')
                    reason     = (msg 'optionNotThere' -Vars @{ options = ($missing -join ', ') })
                })
            }
        }
    }
    # @() because a PowerShell function's List output is unrolled by the
    # pipeline, so a one-target file comes back as a bare object and
    # Set-StrictMode then refuses .Count on it.
    $all = @(Get-Targets $src)
    @{ targets = $all.Count; failures = $bad }
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
$script:Quiet = $Json
$exit = 0

$completionsDir = Join-Path $script:Root 'completions'
function Test-HasHooks {
    param([string]$Name)
    Test-Path -LiteralPath (Join-Path $completionsDir "$Name/hooks.lua")
}

# Three sources, in order of precedence: an explicit name, -All, recently
# changed. The @() around the if-expression is load-bearing -- it unrolls a
# one-element array down to a scalar, and $names.Count then dies under
# StrictMode for a single completion ("./scripts/check-hook-targets.ps1 psc").
$names = @(if ($Completion) {
        $Completion
    }
    elseif ($All) {
        Get-ChildItem $completionsDir -Directory |
            Where-Object { Test-HasHooks $_.Name } |
            ForEach-Object { $_.Name } | Sort-Object
    }
    else {
        # -IncludeHooks because this check reads hooks.lua, so a completion whose
        # only change is a hook edit is exactly the case it exists for.
        . (Join-Path $script:Root 'scripts/utils.ps1')
        Get-RecentCompletions -CompletionsDir $completionsDir -IncludeHooks |
            Where-Object { Test-HasHooks $_ }
    })

if ($names.Count -eq 0) {
    if ($Json) { [pscustomobject]@{ targets = 0; failures = @() } | ConvertTo-Json -Depth 5 }
    else { say 'noRecent' }
    exit 0
}

# Only an explicit name can get here: the -All and recent sets are filtered by
# Test-HasHooks already. A name without a hooks.lua is a caller mistake -- most
# likely a typo -- and skipping it would exit 0 on a check that never ran, which
# is the silent pass this script exists to remove.
$hookless = @($names | Where-Object { !(Test-HasHooks $_) })
if ($hookless.Count -gt 0) {
    stop 'noHooks' @{ names = ($hookless -join ', ') }
}

$total = 0
$bad = [System.Collections.Generic.List[object]]::new()
foreach ($n in $names) {
    $r = Test-HookTargets $n
    $total += $r.targets
    foreach ($b in $r.failures) { $bad.Add($b) }
}
if ($Json) {
    [pscustomobject]@{ targets = $total; failures = $bad } | ConvertTo-Json -Depth 5
}
else {
    foreach ($f in $bad) {
        $loc = "$($f.completion) > $($f.target)"
        if ($f.option) { $loc += " [$($f.option)]" }
        Write-Host (colorize ((msg 'failLine' -Vars @{ loc = $loc; reason = $f.reason })))
    }
    say 'summary' -Vars @{ count = $names.Count; targets = $total; bad = $bad.Count }
}
if ($bad.Count -gt 0) { $exit = 1 }

exit $exit

