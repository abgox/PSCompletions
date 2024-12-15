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

if (!$ReferenceJsonPath) {
    $completion_dir = Split-Path (Split-Path $DifferenceJsonPath -Parent) -Parent
    $path_config = Join-Path $completion_dir "config.json"
    $lang_list = (Get-Content -Path $path_config -Raw -Encoding utf8 | ConvertFrom-Json).language

    $ReferenceJsonPath = "$($completion_dir)/language/$($lang_list[0]).json"
}

function Compare-JsonProperty {
    param (
        [string]$DifferenceJsonPath,
        [string]$ReferenceJsonPath
    )

    # 读取 JSON 文件
    $DifferenceContent = Get-Content -Path $DifferenceJsonPath -Raw | ConvertFrom-Json -AsHashtable
    $ReferenceContent = Get-Content -Path $ReferenceJsonPath -Raw | ConvertFrom-Json -AsHashtable

    # 初始化统计变量
    $count = @{
        totalTips        = 0
        untranslatedList = @() # 未翻译的
        missingList      = @() # 缺少的
        extraList        = @() # 多余的
    }

    function noTranslated() {
        param($Difference, $Reference)
        # XXX: 以中文为例，可以通过判断是否存在中文字符
        # 直接判断是否相等，目前也可用
        return $Difference -eq $Reference
    }
    function _replace {
        param ($data, $separator = '')
        $data = $data -join $separator
        $pattern = '\{\{(.*?(\})*)(?=\}\})\}\}'
        $matches = [regex]::Matches($data, $pattern)
        foreach ($match in $matches) {
            $data = $data.Replace($match.Value, (Invoke-Expression $match.Groups[1].Value) -join $separator )
        }
        if ($data -match $pattern) { (_replace $data) }else { return $data }
    }

    # 定义递归函数以遍历
    function Traverse {
        param (
            [array]$ReferenceArray,
            [array]$DifferenceArray,
            $attr = ''
        )
        for ($i = 0; $i -lt [Math]::Max($ReferenceArray.Count, $DifferenceArray.Count); $i++) {
            if ($ReferenceArray[$i]) {
                if ($ReferenceArray[$i].tip) {
                    $count.totalTips++
                    if ($DifferenceArray[$i].tip) {
                        $json = $DifferenceContent
                        $info = $json.info
                        $Difference = _replace $DifferenceArray[$i].tip

                        $json = $ReferenceContent
                        $info = $json.info
                        $Reference = _replace $ReferenceArray[$i].tip
                        if (noTranslated $Difference $Reference) {
                            $count.untranslatedList += @{
                                value = $DifferenceArray[$i].tip
                                attr  = "$($attr)[$($i)].tip"
                            }
                        }
                    }
                    else {
                        $count.missingList += "$($attr)[$($i)].tip"
                    }
                }
                else {
                    if ($DifferenceArray[$i].tip) {
                        $count.extraList += "$($attr)[$($i)].tip"
                    }
                }
            }
            else {
                if ($DifferenceArray[$i]) {
                    $count.extraList += "$($attr)[$($i)]"
                }
            }

            # 处理 next 属性
            if ($ReferenceArray[$i].next -and $DifferenceArray[$i].next) {
                Traverse $ReferenceArray[$i].next $DifferenceArray[$i].next "$($attr)[$($i)].next"
            }

            # 处理 options 属性
            if ($ReferenceArray[$i].options -and $DifferenceArray[$i].options) {
                Traverse $ReferenceArray[$i].options $DifferenceArray[$i].options "$($attr)[$($i)].options"
            }
        }
    }

    if ($ReferenceContent.root) {
        Traverse $ReferenceContent.root $DifferenceContent.root 'root'
    }
    if ($ReferenceContent.options) {
        Traverse $ReferenceContent.options $DifferenceContent.options 'options'
    }
    if ($ReferenceContent.common_options) {
        Traverse $ReferenceContent.common_options $DifferenceContent.common_options 'common_options'
    }

    if ($ReferenceContent.config) {
        for ($i = 0; $i -lt [Math]::Max($ReferenceContent.config.Count, $DifferenceContent.config.Count); $i++) {
            if ($ReferenceContent.config[$i].name -eq 'enable_hooks') {
                continue
            }
            if ($ReferenceContent.config[$i]) {
                if ($ReferenceContent.config[$i].tip) {
                    $count.totalTips++
                    if ($DifferenceContent.config[$i].tip) {
                        $Difference = $DifferenceContent.config[$i].tip -join ''
                        $Reference = $ReferenceContent.config[$i].tip -join ''
                        if (noTranslated $Difference $Reference) {
                            $count.untranslatedList += @{
                                value = $DifferenceContent.config[$i].tip
                                attr  = "config[$($i)].tip"
                            }
                        }
                    }
                    else {
                        $count.missingList += "config[$($i)].tip"
                    }
                }
                else {
                    if ($DifferenceContent.config[$i].tip) {
                        $count.extraList += "config[$($i)].tip"
                    }
                }
            }
            else {
                if ($DifferenceContent.config[$i]) {
                    $count.extraList += "config[$($i)]"
                }
            }
        }
    }

    if ($ReferenceContent.info) {
        if ($ReferenceContent.info.completion_info.description) {
            $count.totalTips++
            if ($DifferenceContent.info.completion_info.description) {
                $Difference = $DifferenceContent.info.completion_info.description -join ''
                $Reference = $ReferenceContent.info.completion_info.description -join ''
                if (noTranslated $Difference $Reference) {
                    $count.untranslatedList += @{
                        value = $DifferenceContent.info.completion_info.description
                        attr  = "info.completion_info.description"
                    }
                }
            }
            else {
                $count.missingList += "info.completion_info.description"
            }
        }
        else {
            if ($DifferenceContent.info.completion_info.description) {
                $count.extraList += "info.completion_info.description"
            }
        }
    }

    if ($count.totalTips -gt 0) {
        $completionRate = 100 - (($count.untranslatedList.Count + $count.missingList.Count) / $count.totalTips) * 100
    }
    else {
        $completionRate = 100
    }
    if ($count.extraList.Count) {
        $completionRate += ($count.extraList.Count / $count.totalTips) * 100
    }
    if ($completionRate -gt 100) {
        $completionRate = [Math]::Ceiling($completionRate)
    }
    else {
        $completionRate = [Math]::Floor($completionRate)
    }

    if ($PSUICulture -eq "zh-CN") {
        $PSCompletions.write_with_color("<@Blue>tip 的翻译进度: <@Magenta>$($completionRate)%")

        if ($count.untranslatedList) {
            $PSCompletions.write_with_color("`n<@Yellow>以下是未翻译的提示(个数: <@Magenta>$($count.untranslatedList.Count)<@Yellow>):")
            foreach ($o in $count.untranslatedList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------`n位置: <@Magenta>$($o.attr)")
                $PSCompletions.write_with_color("<@Cyan>当前的属性值:")
                $o.value
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------`n")
        }
        if ($count.missingList.Count) {
            $PSCompletions.write_with_color("<@Red>以下是 <@Magenta>$($DifferenceJsonPath)<@Red> 文件中缺失的属性(个数: <@Magenta>$($count.missingList.Count)<@Red>):")
            foreach ($item in $count.missingList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------<@Magenta>`n$($item)")
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------")
        }
        if ($count.extraList.Count) {
            $PSCompletions.write_with_color("<@Red>以下是 <@Magenta>$($DifferenceJsonPath)<@Red> 文件中多余的属性(个数: <@Magenta>$($count.extraList.Count)<@Red>):")
            foreach ($item in $count.extraList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------<@Magenta>`n$($item)")
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------")
        }
    }
    else {
        $PSCompletions.write_with_color("<@Blue>Tip translation progress: <@Magenta>$($completionRate)%")
        if ($count.untranslatedList) {
            $PSCompletions.write_with_color("`n<@Yellow>The following tips are not translated (count: <@Magenta>$($count.untranslatedList.Count)<@Yellow>):")
            foreach ($o in $count.untranslatedList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------`nLocation: <@Magenta>$($o.attr)")
                $PSCompletions.write_with_color("<@Cyan>Current value:")
                $o.value
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------`n")
        }
        if ($count.missingList.Count) {
            $PSCompletions.write_with_color("<@Red>The following tips are missing property in the <@Magenta>$($DifferenceJsonPath)<@Red> file (count: <@Magenta>$($count.missingList.Count)<@Red>):")
            foreach ($item in $count.missingList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------<@Magenta>`n$($item)")
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------")
        }
        if ($count.extraList.Count) {
            $PSCompletions.write_with_color("<@Red>The following tips are extra property in the <@Magenta>$($DifferenceJsonPath)<@Red> file (count: <@Magenta>$($count.extraList.Count)<@Red>):")
            foreach ($item in $count.extraList) {
                $PSCompletions.write_with_color("<@Cyan>--------------------<@Magenta>`n$($item)")
            }
            $PSCompletions.write_with_color("<@Cyan>--------------------")
        }
    }
}
Compare-JsonProperty $DifferenceJsonPath $ReferenceJsonPath
