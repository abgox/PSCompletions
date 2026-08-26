#Requires -Version 7.0

param(
    [string[]]$CompletionList,
    [switch]$All,
    [switch]$Quiet
)

Set-StrictMode -Off

. $PSScriptRoot\utils.ps1

$completionsDir = "$PSScriptRoot\..\completions"

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path -LiteralPath $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }
$PSCompletions.initialize($true)

$text = $text.'sort-json'

function outText {
    param($text)
    if ($text -is [array]) { $text = $text -join "`n" }
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

if (-not $CompletionList) {
    if ($All) {
        $CompletionList = (Get-ChildItem $completionsDir -Directory).Name
    }
    else {
        $CompletionList = Get-RecentCompletions -CompletionsDir $completionsDir
        if ($CompletionList.Count -eq 0) {
            if (-not $Quiet) {
                outText $text.noRecent
            }
            return
        }
    }
}

# Compiled helpers (scripts/psc-tools.cs): read-only canonicality check so that
# already-normalized files skip the expensive PS rebuild entirely.
# When the type is unavailable, everything falls back to the rebuild path below.
if (-not ('PscTools.SortCheck' -as [type])) {
    try { Add-Type -Path "$PSScriptRoot\psc-tools.cs" } catch { Write-Verbose "SortCheck unavailable: $_" }
}
$script:sortCheckType = 'PscTools.SortCheck' -as [type]

# Reorder a completion's config.json fields: id, hooks, alias, language (others appended at end).
function Sort-ConfigJson {
    param(
        [string]$Path
    )
    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $order = @('id', 'hooks', 'alias', 'language')
    $sorted = [ordered]@{}
    foreach ($prop in $order) {
        if ($json.PSObject.Properties.Name -contains $prop) {
            $sorted[$prop] = $json.$prop
        }
    }
    foreach ($prop in $json.PSObject.Properties.Name) {
        if (-not $sorted.Contains($prop)) {
            $sorted[$prop] = $json.$prop
        }
    }
    $sorted | ConvertTo-Json | Out-File -FilePath $Path -Encoding utf8
}

# Normalize alias (longest form becomes name) and usage forms (short -> long).
# Mutates the parsed tree in place. Runs before sorting so sibling order uses final names.
function Optimize-Entry {
    param($entry)

    if ($null -eq $entry) { return }
    foreach ($item in $entry) {
        if ($item.alias.Count -gt 0) {
            # name + aliases, longest first (stable: equal lengths keep original order)
            $combined = [System.Collections.Generic.List[object]]::new(@($item.alias).Count + 1)
            $combined.Add([string]$item.name)
            foreach ($a in @($item.alias)) { $combined.Add([string]$a) }
            $sorted = [System.Linq.Enumerable]::ToArray(
                [System.Linq.Enumerable]::OrderByDescending(
                    [System.Linq.Enumerable]::Cast[object]($combined.ToArray()),
                    [Func[object, int]] { param($x) $x.Length }))
            $item.name = $sorted[0]
            $item.alias = $sorted[1..($sorted.Count - 1)]
        }
        if ($item.usage.Count -gt 0) {
            $newUsage = [System.Collections.Generic.List[object]]::new()
            foreach ($uu in $item.usage) {
                $u = $uu
                if ($u -is [string]) {
                    $m = [regex]::Match($u, '^([^\s,|<=\[|]+(?:\s*[,|]\s*[^\s,|<=\[|]+)*)')
                    if ($m.Success) {
                        $block = $m.Value
                        $hasPipe = $block.Contains('|')
                        $hasComma = $block.Contains(',')
                        if ($hasPipe -and $hasComma) {
                            # mixed separators, skip
                        }
                        elseif ($hasPipe -or $hasComma) {
                            $sep = if ($hasPipe) { '|' } else { ',' }
                            $parts = @($block -split '[,|]')
                            $forms = [System.Collections.Generic.List[string]]::new()
                            foreach ($p in $parts) {
                                $t = $p.Trim()
                                if ($t -ne '') { $forms.Add($t) }
                            }
                            $sortedForms = [System.Linq.Enumerable]::ToArray(
                                [System.Linq.Enumerable]::OrderBy(
                                    [System.Linq.Enumerable]::Cast[string]($forms.ToArray()),
                                    [Func[string, int]] { param($x) $x.Length }))
                            $newBlock = if ($sep -eq '|') { $sortedForms -join '|' } else { $sortedForms -join ', ' }
                            $u = $u.Replace($block, $newBlock)
                        }
                    }
                }
                $newUsage.Add($u)
            }
            $item.usage = $newUsage.ToArray()
        }
        if ($item.next) { Optimize-Entry $item.next }
        if ($item.option) { Optimize-Entry $item.option }
    }
}

# Stable name-order sorts, without per-call cmdlet/pipeline overhead.
$nameKeyFunc = [Func[object, object]] {
    param($x)
    $n = $x.name
    [System.Tuple]::Create($n.ToUpperInvariant(), $n)
}
function Sort-NamedArray {
    param([array]$Array)
    # comma-wrap: without it a single-element result is unrolled to a bare object by the pipeline
    , [System.Linq.Enumerable]::ToArray(
        [System.Linq.Enumerable]::OrderBy(
            [System.Linq.Enumerable]::Cast[object]($Array),
            $nameKeyFunc))
}

function Sort-ObjectRecursively {
    param (
        $inputObject,
        [string[]]$propertyOrder = @()
    )

    if ($inputObject -is [array]) {
        $array = $inputObject

        if ($array.Count -gt 0 -and $array[0] -is [pscustomobject] -and $array[0].PSObject.Properties.Name -contains 'name') {
            $array = Sort-NamedArray $array
        }

        $sortedArray = [System.Collections.Generic.List[object]]::new($array.Count)
        foreach ($item in $array) {
            $sortedArray.Add((Sort-ObjectRecursively -inputObject $item -propertyOrder $propertyOrder))
        }

        return , $sortedArray
    }
    elseif ($inputObject -is [System.Management.Automation.PSCustomObject]) {
        $names = @($inputObject.PSObject.Properties.Name)
        $sortedObject = [ordered]@{}
        foreach ($prop in $propertyOrder) {
            if ($names -contains $prop) {
                $sortedObject[$prop] = Sort-ObjectRecursively -inputObject $inputObject.$prop -propertyOrder $propertyOrder
            }
        }

        # Remaining properties are appended in alphabetical order
        $remainingProps = [System.Collections.Generic.List[string]]::new()
        foreach ($n in $names) {
            if ($propertyOrder -notcontains $n) { $remainingProps.Add($n) }
        }
        if ($remainingProps.Count -gt 1) {
            $remainingProps = @($remainingProps | Sort-Object { [System.Tuple]::Create($_.ToUpperInvariant(), $_) })
        }

        foreach ($prop in $remainingProps) {
            $sortedObject[$prop] = Sort-ObjectRecursively -inputObject $inputObject.$prop -propertyOrder $propertyOrder
        }

        return $sortedObject
    }
    else {
        return $inputObject
    }
}

# Parse once; when the tree is already canonical (common case), only re-serialize for
# the byte comparison. Otherwise run the full optimize + sort rebuild.
# Returns the JSON string to write, or $null when content is unchanged (skip write).
function Get-SortedJsonString {
    param(
        [string]$JsonText,
        [string]$CurrentRaw
    )

    $json = $JsonText | ConvertFrom-Json

    $canonical = $false
    if ($script:sortCheckType) {
        $canonical = ($null -eq $script:sortCheckType::CheckCanonical($json))
    }

    if ($canonical) {
        $sortedJsonString = $json | ConvertTo-Json -Depth 100
    }
    else {
        Optimize-Entry $json.next
        Optimize-Entry $json.option
        Optimize-Entry $json.global_option

        $topLevelOrder = @('meta', 'next', 'option', 'global_option', 'config', 'info')
        $metaOrder = @('url', 'description')
        $configOrder = @('name', 'value', 'values', 'tip')
        $itemPropertyOrder = @('name', 'alias', 'usage', 'tip', 'example', 'repeat', 'option', 'next')

        $sortedJson = [ordered]@{}

        foreach ($prop in $topLevelOrder) {
            if ($json.PSObject.Properties.Name -contains $prop) {
                if ($prop -in @('next', 'option', 'global_option')) {
                    $inputObject = Sort-NamedArray @($json.$prop)
                    $sortedJson[$prop] = Sort-ObjectRecursively -inputObject $inputObject -propertyOrder $itemPropertyOrder
                }
                elseif ($prop -eq 'meta') {
                    $sortedJson[$prop] = Sort-ObjectRecursively -inputObject $json.$prop -propertyOrder $metaOrder
                }
                elseif ($prop -eq 'config') {
                    $sortedJson[$prop] = Sort-ObjectRecursively -inputObject @($json.$prop) -propertyOrder $configOrder
                }
                else {
                    $sortedJson[$prop] = Sort-ObjectRecursively -inputObject $json.$prop
                }
            }
        }

        # Add any remaining properties not in the order list
        foreach ($prop in $json.PSObject.Properties.Name) {
            if (-not $sortedJson.Contains($prop) -and -not $topLevelOrder.Contains($prop)) {
                $sortedJson[$prop] = Sort-ObjectRecursively -inputObject $json.$prop
            }
        }

        $sortedJsonString = $sortedJson | ConvertTo-Json -Depth 100
    }

    # Out-File appends a trailing newline; treat EOL-style-only differences as unchanged
    $candidate = $sortedJsonString + "`r`n"
    if ($CurrentRaw -eq $candidate) { return $null }
    if (($CurrentRaw -replace "`r", '') -eq ($candidate -replace "`r", '')) { return $null }
    return $sortedJsonString
}

$allResults = @()

foreach ($completion in $CompletionList) {
    $langDir = "$completionsDir\$completion\language"
    if (!(Test-Path -LiteralPath $langDir)) {
        continue
    }
    # Keep config.json fields in a stable order (id, hooks, alias, language).
    $configFile = "$completionsDir\$completion\config.json"
    if (Test-Path -LiteralPath $configFile) {
        Sort-ConfigJson -Path $configFile
    }
    $langFiles = Get-ChildItem -Path $langDir -File -Filter '*.json'
    if ($langFiles.Count -eq 0) {
        continue
    }
    $sortedCount = 0
    foreach ($file in $langFiles) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw
        $result = Get-SortedJsonString -JsonText $raw -CurrentRaw $raw
        if ($null -ne $result) {
            $result | Out-File -FilePath $file.FullName -Encoding utf8
        }
        $sortedCount++
    }
    $allResults += @{
        completion  = $completion
        totalFiles  = $langFiles.Count
        sortedFiles = $sortedCount
    }
}

$processedCount = $allResults.Count
$sortedFilesTotal = if ($allResults.Count -gt 0) { ($allResults | Measure-Object -Property sortedFiles -Sum).Sum } else { 0 }
if (-not $Quiet) {
    outText $text.summary
    foreach ($r in $allResults) {
        $completion = $r.completion
        $sortedFiles = $r.sortedFiles
        $totalFiles = $r.totalFiles
        outText $text.sortedHeader
    }
}
