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

function Sort-JsonStructure {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFile,

        [Parameter(Mandatory = $false)]
        [string]$OutputFile
    )

    $json = Get-Content $InputFile -Raw | ConvertFrom-Json

    # 顶层属性顺序
    $topLevelOrder = @('meta', 'next', 'option', 'global_option', 'config', 'info')
    # meta 属性顺序
    $metaOrder = @('url', 'description')
    # config 属性顺序
    $configOrder = @('name', 'value', 'values', 'tip')
    # next/option/global_option 属性顺序
    $itemPropertyOrder = @('name', 'alias', 'tip', 'repeat', 'option', 'next')

    # 递归排序函数
    function Sort-ObjectRecursively {
        param (
            $inputObject,
            # 定义属性的顺序
            [string[]]$propertyOrder = @()
        )

        # 处理数组: 如果数组元素有 name，则排序
        if ($inputObject -is [array]) {
            $array = $inputObject

            if ($array.Count -gt 0 -and $array[0] -is [pscustomobject] -and $array[0].PSObject.Properties.Name -contains 'name') {
                $array = $array | Sort-Object { [System.Tuple]::Create($_.name.ToUpperInvariant(), $_.name) }
            }

            $sortedArray = [System.Collections.ArrayList]::new()
            foreach ($item in $array) {
                $sortedArray += Sort-ObjectRecursively -inputObject $item -propertyOrder $propertyOrder
            }

            return , $sortedArray
        }
        # 处理对象
        elseif ($inputObject -is [System.Management.Automation.PSCustomObject]) {
            $sortedObject = [ordered]@{}
            # 先处理有顺序要求的属性
            foreach ($prop in $propertyOrder) {
                if ($inputObject.PSObject.Properties.Name -contains $prop) {
                    $sortedObject[$prop] = Sort-ObjectRecursively -inputObject $inputObject.$prop -propertyOrder $propertyOrder
                }
            }

            # 然后按字母序处理剩余属性
            $remainingProps = $inputObject.PSObject.Properties.Name |
            Where-Object { $propertyOrder -notcontains $_ } |
            Sort-Object { [System.Tuple]::Create($_.ToUpperInvariant(), $_) }

            foreach ($prop in $remainingProps) {
                $sortedObject[$prop] = Sort-ObjectRecursively -inputObject $inputObject.$prop -propertyOrder $propertyOrder
            }

            return $sortedObject
        }
        # 处理其他类型（字符串、数字等）直接返回
        else {
            return $inputObject
        }
    }

    # Create a new ordered hashtable for the sorted JSON
    $sortedJson = [ordered]@{}

    # Sort top-level properties
    foreach ($prop in $topLevelOrder) {
        if ($json.PSObject.Properties.Name -contains $prop) {
            if ($prop -in @('next', 'option', 'global_option')) {
                $inputObject = $json.$prop | Sort-Object { [System.Tuple]::Create($_.name.ToUpperInvariant(), $_.name) }
                $sortedJson[$prop] = Sort-ObjectRecursively -inputObject @($inputObject) -propertyOrder $itemPropertyOrder
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

    # Convert back to JSON with pretty formatting
    $sortedJsonString = $sortedJson | ConvertTo-Json -Depth 100

    # Output to file or return the object
    if ($OutputFile) {
        $sortedJsonString | Out-File -FilePath $OutputFile -Encoding utf8
    }
    else {
        return $sortedJsonString
    }
}

function Optimize-CompletionJson {
    param(
        [string]$Path
    )
    $content = Get-Content -Path $Path -Raw | ConvertFrom-Json
    function Optimize-Entry($entry) {
        if ($null -eq $entry) { return }
        foreach ($item in $entry) {
            if ($item.alias.Count -gt 0) {
                $sorted = @($item.name) + @($item.alias) | Sort-Object { $_.Length } -Descending
                $item.name = $sorted[0]
                $item.alias = $sorted[1..($sorted.Count - 1)]
            }
            if ($item.next) { Optimize-Entry $item.next }
            if ($item.option) { Optimize-Entry $item.option }
        }
    }
    Optimize-Entry $content.next
    Optimize-Entry $content.option
    Optimize-Entry $content.global_option

    $newJson = $content | ConvertTo-Json -Depth 100
    $newJson | Out-File -FilePath $Path -Encoding utf8
}

$allResults = @()

foreach ($completion in $CompletionList) {
    $langDir = "$completionsDir\$completion\language"
    if (!(Test-Path -LiteralPath $langDir)) {
        continue
    }
    $langFiles = Get-ChildItem -Path $langDir -File -Filter '*.json'
    if ($langFiles.Count -eq 0) {
        continue
    }
    $sortedCount = 0
    foreach ($file in $langFiles) {
        Optimize-CompletionJson $file.FullName
        Sort-JsonStructure -InputFile $file.FullName -OutputFile $file.FullName
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
