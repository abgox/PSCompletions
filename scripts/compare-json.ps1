#Requires -Version 7.0

param(
    [Parameter(Position = 0, ValueFromRemainingArguments)]
    [array]$CompletionList,
    [ArgumentCompletions('en-US', 'zh-CN')]
    [string]$BaseLang
)

if (-not $BaseLang) { $BaseLang = 'en-US' }
if (-not $CompletionList) {
    $CompletionList = (Get-ChildItem "$PSScriptRoot\..\completions" -Directory).Name
}

Set-StrictMode -Off

$textPath = "$PSScriptRoot/language/$PSCulture.json"
if (!(Test-Path $textPath)) {
    $textPath = "$PSScriptRoot/language/en-US.json"
}
$text = Get-Content -Path $textPath -Encoding utf8 | ConvertFrom-Json

if (!$PSCompletions) { . $PSScriptRoot\..\module\PSCompletions\PSCompletions.ps1 }

$text = $text.'compare-json'

function outText {
    param($text)
    if ($text -is [array]) { $text = $text -join "`n" }
    $PSCompletions.write_with_color($PSCompletions.replace_content($text))
}

function Get-ValueType {
    param($Value)
    if ($null -eq $Value) { return 'Null' }
    if ($Value -is [array]) { return 'Array' }
    if ($Value -is [System.Collections.IDictionary]) { return 'Hashtable' }
    return $Value.GetType().Name
}

function Compare-Lang {
    param (
        [string]$baseJson,
        [string]$targetJson,
        [string]$targetLang
    )

    $baseContent = Get-Content -Path $baseJson -Raw | ConvertFrom-Json -AsHashtable
    $targetContent = Get-Content -Path $targetJson -Raw | ConvertFrom-Json -AsHashtable

    $stats = @{
        totalTips        = 0
        translatedTips   = 0
        missingInTarget  = @()
        extraInTarget    = @()
        typeMismatch     = @()
        semanticMismatch = @()
        valueDiff        = @()
        untranslated     = @()
    }

    function Normalize-Value {
        param($Value, [string]$Key = '')

        if ($null -eq $Value) { return $null }
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.ContainsKey('name') -and $Key -in 'next', 'option', 'global_option', 'alias') {
                return , @($Value)
            }
            if ($Key -eq 'alias' -and $Value.Count -eq 0) {
                return @()
            }
        }
        if ($Value -is [string] -and $Key -eq 'alias') {
            return , @($Value)
        }

        return $Value
    }

    function Test-NamedObjectArray {
        param([array]$ArrA, [array]$ArrB)
        foreach ($arr in @($ArrA, $ArrB)) {
            if ($arr.Count -gt 0 -and $arr[0] -is [System.Collections.IDictionary] -and $arr[0].ContainsKey('name')) {
                return $true
            }
        }
        return $false
    }

    function Compare-TranslatableText {
        param($BaseVal, $TargetVal, [string]$Path)

        $baseArr = if ($null -eq $BaseVal) { @() } else { @($BaseVal) }
        $targetArr = if ($null -eq $TargetVal) { @() } else { @($TargetVal) }

        foreach ($item in $baseArr) {
            if ($item -isnot [string]) { return }
        }
        foreach ($item in $targetArr) {
            if ($item -isnot [string]) { return }
        }

        if ($baseArr.Count -eq 0 -and $targetArr.Count -eq 0) { return }
        if ($baseArr.Count -eq 0) { return }

        $stats.totalTips++

        if ($targetArr.Count -eq 0) {
            $stats.missingInTarget += @{ path = $Path; name = $Path }
            return
        }

        $baseStr = $baseArr -join ''
        $targetStr = $targetArr -join ''

        $isTemplate = $targetStr -like '{{*}}' -and $baseStr -like '{{*}}' -and $targetStr -eq $baseStr
        if ($isTemplate -or $targetStr -ne $baseStr) {
            $stats.translatedTips++
        }
        else {
            $stats.untranslated += @{ path = $Path; name = $Path }
        }
    }

    function Compare-Value {
        param($BaseVal, $TargetVal, [string]$Path, [string]$Key, [bool]$SkipValueCheck)

        if ($Key -in 'tip', 'description') {
            Compare-TranslatableText -BaseVal $BaseVal -TargetVal $TargetVal -Path $Path
            return
        }
        $BaseVal = Normalize-Value -Value $BaseVal -Key $Key
        $TargetVal = Normalize-Value -Value $TargetVal -Key $Key

        $baseType = Get-ValueType $BaseVal
        $targetType = Get-ValueType $TargetVal

        if ($baseType -eq 'Null' -and $targetType -eq 'Null') { return }

        if ($baseType -eq 'Null') {
            $stats.extraInTarget += @{ path = "$Path"; name = $Path }
            return
        }
        if ($targetType -eq 'Null') {
            $stats.missingInTarget += @{ path = "$Path"; name = $Path }
            return
        }
        if ($baseType -ne $targetType) {
            if ($baseType -eq 'Array' -or $targetType -eq 'Array' -or $baseType -eq 'Hashtable' -or $targetType -eq 'Hashtable') {
                $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
                $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
                return
            }
        }
        if ($Key -eq 'next' -and $baseType -ne 'Array' -and $targetType -ne 'Array') {
            if ($BaseVal -eq 0 -or $TargetVal -eq 0) {
                if ($BaseVal -ne $TargetVal) {
                    $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
                    $stats.semanticMismatch += @{ path = "$Path$suffix"; name = $Path }
                }
                return
            }
        }
        if ($baseType -eq 'Array' -or $targetType -eq 'Array') {
            $baseArr = @($BaseVal)
            $targetArr = @($TargetVal)

            if (Test-NamedObjectArray $baseArr $targetArr) {
                if ($baseType -ne $targetType) {
                    $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
                    $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
                    return
                }
                Compare-NamedArray -BaseArr $baseArr -TargetArr $targetArr -Path $Path
            }
            else {
                if ($SkipValueCheck) { return }
                foreach ($v in $baseArr) {
                    if ($v -notin $targetArr) { $stats.missingInTarget += @{ path = "$Path > $v"; name = $Path } }
                }
                foreach ($v in $targetArr) {
                    if ($v -notin $baseArr) { $stats.extraInTarget += @{ path = "$Path > $v"; name = $Path } }
                }
            }
            return
        }
        if ($baseType -eq 'Hashtable' -and $targetType -eq 'Hashtable') {
            Compare-Fields -BaseObj $BaseVal -TargetObj $TargetVal -Path $Path -SkipValueCheck $SkipValueCheck
            return
        }
        if ($baseType -ne $targetType) {
            $suffix = " (<@Red>$baseType<@Cyan> > <@Red>$targetType<@Cyan>)"
            $stats.typeMismatch += @{ path = "$Path$suffix"; name = $Path }
            return
        }
        if ($Key -eq 'name') {
            if ($BaseVal -ne $TargetVal) {
                $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
                $stats.valueDiff += @{ path = "$Path$suffix"; name = $Path }
            }
            return
        }
        if (-not $SkipValueCheck -and $BaseVal -ne $TargetVal) {
            $suffix = " (<@Red>$BaseVal<@Cyan> > <@Red>$TargetVal<@Cyan>)"
            $stats.valueDiff += @{ path = "$Path$suffix"; name = $Path }
        }
    }

    function Compare-Fields {
        param([hashtable]$BaseObj, [hashtable]$TargetObj, [string]$Path, [bool]$SkipValueCheck = $false)

        $baseKeys = if ($BaseObj) { @($BaseObj.Keys) } else { @() }
        $targetKeys = if ($TargetObj) { @($TargetObj.Keys) } else { @() }
        $allKeys = @($baseKeys) + @($targetKeys) | Select-Object -Unique

        foreach ($key in $allKeys) {
            if ($Path -eq 'meta' -and $key -eq 'url') { continue }

            $baseVal = if ($BaseObj -and $BaseObj.ContainsKey($key)) { $BaseObj[$key] } else { $null }
            $targetVal = if ($TargetObj -and $TargetObj.ContainsKey($key)) { $TargetObj[$key] } else { $null }

            $currentPath = if ($Path) { "$Path > $key" } else { $key }
            $childSkip = $SkipValueCheck -or ($CompletionName -eq 'psc' -and $key -ne 'name')

            Compare-Value -BaseVal $baseVal -TargetVal $targetVal -Path $currentPath -Key $key -SkipValueCheck $childSkip
        }
    }

    function Compare-NamedArray {
        param([array]$BaseArr, [array]$TargetArr, [string]$Path)

        $targetByName = @{}
        foreach ($item in $TargetArr) { if ($item.name) { $targetByName[$item.name] = $item } }

        $baseByName = @{}
        foreach ($item in $BaseArr) { if ($item.name) { $baseByName[$item.name] = $item } }

        foreach ($baseItem in $BaseArr) {
            $baseName = $baseItem.name
            $currentPath = if ($Path) { "$Path > $baseName" } else { $baseName }

            if ($targetByName.ContainsKey($baseName)) {
                Compare-Fields -BaseObj $baseItem -TargetObj $targetByName[$baseName] -Path $currentPath -SkipValueCheck $SkipValueCheck
            }
            else {
                $stats.missingInTarget += @{ path = $currentPath; name = $baseName }
                foreach ($tKey in @('tip', 'description')) {
                    if ($baseItem.ContainsKey($tKey) -and $null -ne $baseItem[$tKey]) {
                        $arr = @($baseItem[$tKey])
                        if ($arr.Count -gt 0 -and !([string]::IsNullOrEmpty(($arr -join '').Trim()))) {
                            $stats.totalTips++
                        }
                    }
                }
            }
        }
        foreach ($targetItem in $TargetArr) {
            $targetName = $targetItem.name
            if ($targetName -and !$baseByName.ContainsKey($targetName)) {
                $currentPath = if ($Path) { "$Path > $targetName" } else { $targetName }
                $stats.extraInTarget += @{ path = $currentPath; name = $targetName }
            }
        }
    }

    Compare-Fields -BaseObj $baseContent -TargetObj $targetContent -Path ''

    $translationRate = 100
    if ($stats.totalTips -gt 0) {
        $translationRate = [Math]::Round(($stats.translatedTips / $stats.totalTips) * 100, 2)
    }

    return @{
        stats = $stats
        rate  = $translationRate
    }
}

$allResults = @()

foreach ($CompletionName in $CompletionList) {
    if (!$CompletionName.Trim()) {
        outText $text.invalidName
        continue
    }
    $langDir = [System.IO.Path]::Combine($PSScriptRoot, '..', 'completions', $CompletionName, 'language')
    if (!(Test-Path $langDir)) {
        outText $text.invalidLang
        continue
    }
    $allLangFiles = Get-ChildItem -Path $langDir -Filter '*.json' | ForEach-Object { $_.BaseName }
    $otherLangs = $allLangFiles | Where-Object { $_ -ne $BaseLang } | Sort-Object
    if ($otherLangs.Count -eq 0) {
        outText "<@Yellow>No language files found besides $BaseLang"
        continue
    }
    $baseJson = [System.IO.Path]::Combine($langDir, $BaseLang + '.json')
    if (!(Test-Path $baseJson)) {
        outText $text.invalidLang
        continue
    }
    & $PSScriptRoot\sort-json.ps1 $CompletionName

    foreach ($lang in $otherLangs) {
        $targetJson = [System.IO.Path]::Combine($langDir, $lang + '.json')
        $result = Compare-Lang $baseJson $targetJson $lang
        $stats = $result.stats

        $missing = $stats.missingInTarget.Count
        $extra = $stats.extraInTarget.Count
        $translated = $stats.translatedTips
        $total = $stats.totalTips
        $rate = $result.rate

        if ($total -eq 0) { continue }

        $hasIssues = $missing -gt 0 -or $extra -gt 0 -or $rate -ne 100 -or $stats.typeMismatch.Count -gt 0 -or $stats.semanticMismatch.Count -gt 0 -or $stats.valueDiff.Count -gt 0

        $allResults += @{
            completion = $CompletionName
            lang       = $lang
            stats      = $stats
            rate       = $rate
            missing    = $missing
            extra      = $extra
            translated = $translated
            total      = $total
            hasIssues  = $hasIssues
        }
    }
}

$totalFiles = $allResults.Count
$completedFiles = ($allResults | Where-Object { -not $_.hasIssues }).Count
$issueFiles = ($allResults | Where-Object { $_.hasIssues }).Count

outText $text.summary

$issueResults = @($allResults | Where-Object { $_.hasIssues })
if ($issueResults.Count -gt 0) {
    foreach ($r in $issueResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $missing = $r.missing
        $extra = $r.extra
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        $count = $r.stats.untranslated.Count
        outText $text.langHeader

        if ($r.stats.missingInTarget.Count -gt 0) {
            outText $text.missingInTarget
            foreach ($item in $r.stats.missingInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.extraInTarget.Count -gt 0) {
            outText $text.extraInTarget
            foreach ($item in $r.stats.extraInTarget) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.typeMismatch.Count -gt 0) {
            outText $text.typeMismatch
            foreach ($item in $r.stats.typeMismatch) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.semanticMismatch.Count -gt 0) {
            outText $text.semanticMismatch
            foreach ($item in $r.stats.semanticMismatch) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.valueDiff.Count -gt 0) {
            outText $text.valueDiff
            foreach ($item in $r.stats.valueDiff) { outText "<@Cyan>  $($item.path)" }
        }
        if ($r.stats.untranslated.Count -gt 0) {
            outText $text.untranslated
            foreach ($item in $r.stats.untranslated) { outText "<@Cyan>  $($item.path)" }
        }
    }
}

$completeResults = @($allResults | Where-Object { -not $_.hasIssues })
if ($completeResults.Count -gt 0) {
    Write-Host
    foreach ($r in $completeResults) {
        $targetShortPath = "$($r.completion)/$($r.lang).json"
        $translated = $r.translated
        $total = $r.total
        $rate = $r.rate
        outText $text.langHeaderComplete
    }
}
