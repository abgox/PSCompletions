#Requires -Version 7.0

param(
    [string[]]$CompletionList
)

$completions_dir = "$PSScriptRoot\..\completions"

if (-not $CompletionList) {
    $CompletionList = (Get-ChildItem $completions_dir -Directory).Name
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
    $topLevelOrder = @('meta', 'root', 'options', 'common_options', 'config', 'info')
    # meta 属性顺序
    $metaOrder = @('url', 'description')
    # config 属性顺序
    $configOrder = @('name', 'value', 'values', 'tip')
    # root/options/common_options 属性顺序
    $itemPropertyOrder = @('name', 'alias', 'tip', 'hide', 'options', 'next')

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
            if ($prop -in @('root', 'options', 'common_options')) {
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


foreach ($completion in $CompletionList) {
    Get-ChildItem "$completions_dir\$completion\language" -Filter *.json | ForEach-Object {
        Sort-JsonStructure -InputFile $_.FullName -OutputFile $_.FullName
    }
}
