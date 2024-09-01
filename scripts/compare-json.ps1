param(
    [string]$DifferenceJsonPath, # 差异文件
    [string]$ReferenceJsonPath # 参考文件
)
if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}

if (!$DifferenceJsonPath -or !(Test-Path $DifferenceJsonPath)) {
    $PSCompletions.write_with_color("<@Yellow>You should enter available json path.`ne.g. <@Magenta>.\scripts\compare-json.ps1 .\completions\psc\language\zh-CN.json`n     .\scripts\compare-json.ps1 .\completions\psc\language\zh-CN.json .\completions\psc\language\en-US.json")
    return
}

function ConvertTo-FlatHashtable {
    param (
        [Parameter(Mandatory = $true)][hashtable]$InputHashtable,
        [string]$Prefix = ""
    )
    $flatHashtable = @{}

    foreach ($key in $InputHashtable.Keys) {
        $fullKey = if ($Prefix) { "$Prefix.$key" } else { $key }

        if ($InputHashtable[$key] -is [hashtable]) {
            $nestedHashtable = ConvertTo-FlatHashtable -InputHashtable $InputHashtable[$key] -Prefix $fullKey
            foreach ($nestedKey in $nestedHashtable.Keys) {
                $flatHashtable[$nestedKey] = $nestedHashtable[$nestedKey]
            }
        }
        elseif ($InputHashtable[$key] -is [array]) {
            $array = $InputHashtable[$key]
            if ($array -and $array[0] -is [hashtable]) {
                for ($i = 0; $i -lt $array.Count; $i++) {
                    $element = $array[$i]
                    $elementPrefix = if ($element.ContainsKey("name")) { "$fullKey`[{name:`"$($element.name)`"}]" } else { "$fullKey[$i]" }
                    $nestedHashtable = ConvertTo-FlatHashtable -InputHashtable $element -Prefix $elementPrefix
                    foreach ($nestedKey in $nestedHashtable.Keys) {
                        $flatHashtable[$nestedKey] = $nestedHashtable[$nestedKey]
                    }
                }
            }
            else {
                $flatHashtable[$fullKey] = ($array -join ",")
            }
        }
        else {
            $flatHashtable[$fullKey] = $InputHashtable[$key]
        }
    }
    return $flatHashtable
}

function Compare-JsonProperties {
    param (
        [Parameter(Mandatory = $true)][hashtable]$hashTableEN,
        [Parameter(Mandatory = $true)][hashtable]$hashTableCN
    )

    $flatEN = ConvertTo-FlatHashtable -InputHashtable $hashTableEN
    $flatCN = ConvertTo-FlatHashtable -InputHashtable $hashTableCN

    $missingProperties = $flatEN.Keys | Where-Object { $_ -notin $flatCN.Keys }
    $extraProperties = $flatCN.Keys | Where-Object { $_ -notin $flatEN.Keys }
    $totalProperties = $flatEN.Count
    $missingCount = $missingProperties.Count
    $extraCount = $extraProperties.Count
    $completionPercentage = ((($totalProperties - $missingCount) + $extraCount) / $totalProperties) * 100

    return @{
        MissingProperties    = $missingProperties
        ExtraProperties      = $extraProperties
        CompletionPercentage = [math]::Round($completionPercentage, 2)
    }
}

if (!$ReferenceJsonPath) {
    $completion_dir = Split-Path (Split-Path $DifferenceJsonPath -Parent) -Parent
    $path_config = Join-Path $completion_dir "config.json"
    $lang_list = (Get-Content -Path $path_config -Raw | ConvertFrom-Json).language

    $ReferenceJsonPath = "$($completion_dir)/language/$($lang_list[0]).json"
}
$json1 = Get-Content -Path $ReferenceJsonPath -Raw | ConvertFrom-Json -Depth 100
$json2 = Get-Content -Path $DifferenceJsonPath -Raw | ConvertFrom-Json -Depth 100

$hashTableEN = $json1 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100
$hashTableCN = $json2 | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable -Depth 100

$result = Compare-JsonProperties -hashTableEN $hashTableEN -hashTableCN $hashTableCN

if ($PSUICulture -eq "zh-CN") {
    if ($result.MissingProperties) {
        Write-Host "`n与 $(Split-Path $ReferenceJsonPath -Leaf) 相比，$(Split-Path $DifferenceJsonPath -Leaf) 缺少的属性: " -f Cyan
        $result.MissingProperties
        Write-Host "--------------------------------" -f Yellow
    }
    if ($result.ExtraProperties) {
        Write-Host "与 $(Split-Path $ReferenceJsonPath -Leaf) 相比，$(Split-Path $DifferenceJsonPath -Leaf) 多余的属性: " -f Cyan
        $result.ExtraProperties
        Write-Host "--------------------------------" -f Yellow
    }
    Write-Host "补全的完成度: $($result.CompletionPercentage)%" -f Blue
}
else {
    if ($result.MissingProperties) {
        Write-Host "`nThe following properties are missing in $(Split-Path $DifferenceJsonPath -Leaf) compared to $(Split-Path $ReferenceJsonPath -Leaf): " -f Cyan
        $result.MissingProperties
        Write-Host "--------------------------------" -f Yellow
    }
    if ($result.ExtraProperties) {
        Write-Host "The following properties are extra in $(Split-Path $DifferenceJsonPath -Leaf) compared to $(Split-Path $ReferenceJsonPath -Leaf): " -f Cyan
        $result.ExtraProperties
        Write-Host "--------------------------------" -f Yellow
    }
    Write-Host "Completion Percentage: $($result.CompletionPercentage)%" -f Blue
}
