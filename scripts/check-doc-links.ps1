<#
.SYNOPSIS
    Checks that every documentation link and cited repo path in the guidance docs resolves.

.DESCRIPTION
    Two kinds of reference are checked:

      1. Markdown links   [text](target)   — resolved relative to the containing file.
      2. Backticked repo paths   `core/cli/src/validate.rs`   — resolved relative to the
         repository root. A leading ./ or ../ is stripped first, as are a trailing #anchor
         and a trailing " §N" section suffix.

    Backticked tokens that are not pure paths still count: a command such as
    `cargo test --manifest-path core/Cargo.toml` and a sentence fragment such as
    `see core/engine/src/menu/ui.rs` are split on whitespace, and every fragment that
    looks like a path is checked. Placeholders in angle brackets are cut at the first `<`.

    A path that does not resolve from the root is retried as a **suffix match** against the
    repo tree. The design docs deliberately use short code paths (`menu/protocol.rs` for
    `core/engine/src/menu/protocol.rs`) — see `design/README.md` — so the checker honours
    that convention. A suffix match must be unique; zero or several matches is reported.

    A trailing `:296-309` line range is stripped before the extension test, so
    `scripts/psc-tools.cs:300-308` is still validated for the file even though the
    checker cannot verify that the cited lines still say what the doc claims.

    Markdown targets carrying an anchor are checked against explicit <a id="..."> markers
    and against heading slugs (GitHub rules). Both forms occur in this repo: decisions/
    declares <a id="d16"></a>, the design docs rely on slugs.

    Only .md files are scanned, and fenced code blocks are skipped — those are examples,
    not references. Script header comments are deliberately excluded too: those belong to
    the script that owns them and are read alongside the code.

    URLs, glob patterns, and tokens containing quotes are skipped. Paths matching
    `-ExcludePattern` are skipped as well; the default excludes `temp/`, which holds
    runtime scratch files written by the engine into its data directory rather than files
    of this repo.

    **Line-level opt-out.** A backticked path may be an illustration rather than a
    reference — e.g. `design/menu.md` walks through path-history ranking using
    `.\scripts\build.ps1`, a file that does not exist and is meant to be read as a
    generic path. Shape cannot tell the two apart, so put `<!-- nolink -->` somewhere in
    the same blank-line-delimited block as the reference to skip checks for it; an optional
    note may follow the word `nolink`. Suppression is block-scoped rather than line-scoped
    so that prose reflow cannot separate a marker from the reference it suppresses — an
    inline marker at the end of a wrapped line did not survive the formatter. The
    suppressed line count is reported, so the marker cannot be abused silently.

    This is the mechanism that keeps the split structure from rotting: pointers between
    AGENTS.md, authoring/, design/, and decisions/ have no other verifier.

.PARAMETER Path
    Files or directories to scan, relative to the repo root. Defaults to the four
    guidance locations.

.PARAMETER ExcludePattern
    Regex patterns (matched against the repo-root-relative path) whose references are not
    checked. Defaults to `^temp/` — runtime scratch files, not repo files. Pass an empty
    array to check everything.

.PARAMETER Json
    Emit structured output for automation instead of coloured console text.

.EXAMPLE
    .\scripts\check-doc-links.ps1

.EXAMPLE
    .\scripts\check-doc-links.ps1 -Path AGENTS.md authoring -Json
#>

[CmdletBinding()]
param(
    [string[]]$Path = @('AGENTS.md', 'authoring', 'design', 'decisions'),
    [string[]]$ExcludePattern = @('^temp/'),
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$KnownExt = @(
    '.md', '.json', '.jsonc', '.ps1', '.psd1', '.psm1', '.rs', '.cs', '.lua',
    '.ts', '.tsx', '.toml', '.yaml', '.yml', '.xml', '.cfg', '.ini'
)

function Get-Anchors {
    param([string]$File)

    $ids = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($File)) {
        foreach ($m in [regex]::Matches($line, '<a\s+(?:id|name)\s*=\s*"([^"]+)"')) {
            $ids[$m.Groups[1].Value.ToLowerInvariant()] = $true
        }
        if ($line -match '^(#{1,6})\s+(.+?)\s*$') {
            $slug = $Matches[2]
            $slug = $slug -replace '<[^>]+>', ''
            $slug = $slug -replace '[`*_\[\]()]', ''
            $slug = $slug.ToLowerInvariant()
            $slug = $slug -replace '[^a-z0-9\s\-]', ''
            $slug = $slug -replace '\s+', '-'
            $ids[$slug] = $true
        }
    }
    return $ids
}

function Test-Excluded {
    param([string]$Path, [string[]]$Patterns)
    foreach ($pat in $Patterns) {
        if ($Path -match $pat) { return $true }
    }
    return $false
}

# Pull the checkable repo paths out of a backticked token.
# Splits prose and commands on whitespace; cuts a <placeholder> off the end.
function Get-PathCandidates {
    param([string]$Token)

    $t = $Token
    $cut = $t.IndexOf('<')
    if ($cut -ge 0) { $t = $t.Substring(0, $cut) }

    $out = New-Object System.Collections.Generic.List[string]
    foreach ($part in @($t -split '\s+')) {
        $p = $part.Trim() -replace '#.+$', '' -replace '\s+§.*$', '' -replace '\\', '/'
        $p = $p -replace ':\d+(-\d+)?$', ''        # file.cs:300-308 -> file.cs
        if ($p.Length -eq 0 -or $p -notmatch '/') { continue }
        if ($p -match '[\*\?{}]') { continue }
        if ($p.Contains('"') -or $p.Contains("'")) { continue }
        if ($p -match '^[\w-]+://') { continue }
        foreach ($ext in $KnownExt) {
            if ($p -like "*$ext") { [void]$out.Add($p.TrimEnd('/')); break }
        }
    }
    return $out
}

# Repository file index, built once and reused for suffix matching.
function Get-RepoIndex {
    $index = New-Object System.Collections.Generic.List[string]
    $roots = @(Get-ChildItem $RepoRoot -Directory -Force | Where-Object { $_.Name -notin @('.git', 'node_modules', 'target') })
    foreach ($root in $roots) {
        Get-ChildItem $root.FullName -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $rel = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/'
            [void]$index.Add($rel)
        }
    }
    # Files at the repo root itself (README.md, AGENTS.md, completions.json, ...).
    Get-ChildItem $RepoRoot -File | ForEach-Object { [void]$index.Add($_.Name) }
    return $index
}

# Collect the markdown files to scan.
$files = New-Object System.Collections.Generic.List[string]
foreach ($p in $Path) {
    $full = Join-Path $RepoRoot $p
    if (-not (Test-Path $full)) {
        Write-Warning "Not found: $p"
        continue
    }
    if (Test-Path $full -PathType Leaf) {
        if ($full -like '*.md') { [void]$files.Add($full) }
    }
    else {
        Get-ChildItem $full -Recurse -Filter '*.md' -File | ForEach-Object { [void]$files.Add($_.FullName) }
    }
}

$broken      = New-Object System.Collections.Generic.List[object]
$checked     = 0
$suppressed  = 0
$repoIndex   = $null
$anchorCache = @{}

foreach ($file in $files) {
    $dir  = Split-Path $file -Parent
    $text = [System.IO.File]::ReadAllText($file)
    $lines = $text -split "`r?`n"
    $inFence = $false

    # Blank-line-delimited blocks. Suppression is block-scoped, not line-scoped: prose
    # reflows within a block, so a marker anywhere in it suppresses the whole block.
    $skip = New-Object 'bool[]' $lines.Count
    $b = 0
    while ($b -lt $lines.Count) {
        $e = $b
        while ($e -lt $lines.Count -and $lines[$e].Trim() -ne '') { $e++ }
        for ($k = $b; $k -lt $e; $k++) {
            if ($lines[$k] -match '<!--\s*nolink[^>]*-->') {
                for ($j = $b; $j -lt $e; $j++) { $skip[$j] = $true }
                $suppressed += ($e - $b)
                break
            }
        }
        $b = $e + 1
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
        if ($inFence) { continue }   # fenced blocks are examples, not references
        if ($skip[$i]) { continue }

        # 1. Markdown links.
        foreach ($m in [regex]::Matches($line, '\[[^\]]*\]\(([^)\s]+)\)')) {
            $target = $m.Groups[1].Value
            if ($target -match '^[\w-]+://|^mailto:|^#') {
                if ($target -match '^#') {
                    $checked++
                    if (-not $anchorCache.ContainsKey($file)) { $anchorCache[$file] = Get-Anchors $file }
                    if (-not $anchorCache[$file].ContainsKey($target.TrimStart('#').ToLowerInvariant())) {
                        [void]$broken.Add([pscustomobject]@{
                            File    = $file.Substring($RepoRoot.Length + 1)
                            Line    = $i + 1
                            Kind    = 'anchor'
                            Target  = $target
                            Reason  = 'anchor not found in this file'
                        })
                    }
                }
                else { continue }
            }

            $rel = $target
            $anchor = $null
            if ($rel -match '#(.+)$') { $anchor = $Matches[1]; $rel = $rel -replace '#.+$', '' }
            if ($rel -eq '') { continue }

            $resolved = Join-Path $dir $rel
            $checked++
            if (-not (Test-Path $resolved -PathType Leaf)) {
                [void]$broken.Add([pscustomobject]@{
                    File    = $file.Substring($RepoRoot.Length + 1)
                    Line    = $i + 1
                    Kind    = 'link'
                    Target  = $target
                    Reason  = 'target file does not exist'
                })
                continue
            }
            if ($anchor -and $resolved -like '*.md') {
                if (-not $anchorCache.ContainsKey($resolved)) { $anchorCache[$resolved] = Get-Anchors $resolved }
                if (-not $anchorCache[$resolved].ContainsKey($anchor.ToLowerInvariant())) {
                    [void]$broken.Add([pscustomobject]@{
                        File    = $file.Substring($RepoRoot.Length + 1)
                        Line    = $i + 1
                        Kind    = 'anchor'
                        Target  = $target
                        Reason  = 'anchor not found in ' + ($resolved.Substring($RepoRoot.Length + 1))
                    })
                }
            }
        }

        # 2. Backticked repo paths.
        foreach ($m in [regex]::Matches($line, '`([^`]+)`')) {
            foreach ($rel in Get-PathCandidates $m.Groups[1].Value) {
                $norm = $rel -replace '^(\.\.?/)+', ''
                if (Test-Excluded $norm $ExcludePattern) { continue }
                $checked++
                if (Test-Path (Join-Path $RepoRoot $norm) -PathType Leaf) { continue }
                if ($null -eq $repoIndex) { $repoIndex = Get-RepoIndex }
                $hits = New-Object System.Collections.Generic.List[string]
                foreach ($p in $repoIndex) {
                    if ($p -eq $norm -or $p -like "*/$norm") { [void]$hits.Add($p) }
                }
                if ($hits.Count -eq 1) { continue }
                $reason = 'referenced file does not exist'
                if ($hits.Count -gt 1) {
                    $top = @($hits | Select-Object -First 3) -join ', '
                    $reason = 'ambiguous: matches ' + $top
                }
                [void]$broken.Add([pscustomobject]@{
                    File    = $file.Substring($RepoRoot.Length + 1)
                    Line    = $i + 1
                    Kind    = 'path'
                    Target  = $rel
                    Reason  = $reason
                })
            }
        }
    }
}

if ($Json) {
    [pscustomobject]@{
        files      = $files.Count
        refs       = $checked
        suppressed = $suppressed
        broken     = $broken.Count
        findings   = $broken.ToArray()
    } | ConvertTo-Json -Depth 4
}
else {
    $summary = "Checked {0} files, {1} references." -f $files.Count, $checked
    if ($suppressed -gt 0) { $summary += " {0} line(s) suppressed via <!-- nolink -->." -f $suppressed }
    Write-Host $summary -ForegroundColor Cyan
    if ($broken.Count -eq 0) {
        Write-Host 'All documentation links resolve.' -ForegroundColor Green
    }
    else {
        Write-Host ("{0} broken reference(s):" -f $broken.Count) -ForegroundColor Red
        foreach ($b in $broken) {
            Write-Host ("  {0}:{1}  [{2}] {3}" -f $b.File, $b.Line, $b.Kind, $b.Target) -ForegroundColor Yellow
            Write-Host ("      {0}" -f $b.Reason)
        }
    }
}

if ($broken.Count -gt 0) { exit 1 }
