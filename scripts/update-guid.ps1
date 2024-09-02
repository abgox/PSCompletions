param([array]$completion_list)

if (!$PSCompletions) {
    Write-Host "You should install PSCompletions module and import it." -ForegroundColor Red
    return
}
if (!$completion_list) {
    $PSCompletions.write_with_color("<@Yellow>You should enter an available completion list.`ne.g. <@Magenta>.\scripts\update-guid.ps1 psc`n     .\scripts\update-guid.ps1 psc,git")
    return
}

$root_dir = Split-Path $PSScriptRoot -Parent
$path_list = $completion_list | ForEach-Object {
    $completion_dir = $root_dir + "/completions/" + $_
    if (Test-Path $completion_dir) {
        $completion_dir
    }
}
if ($path_list) {
    foreach ($path in $path_list) {
        Write-Host "Updating Guid.txt file of " -NoNewline
        Write-Host $(Split-Path $path -Leaf) -ForegroundColor Magenta -NoNewline
        Write-Host "."
        (New-Guid).Guid | Out-File "$path/guid.txt" -Force
    }
    return
}

if ($PSUICulture -eq 'zh-CN') {
    $select = '选择一个或多个补全, 选中的补全的 "Guid.txt" 文件(按住 Ctrl 或 Shift 键选择多个)'
}
else {
    $select = 'Select one or more completions. The "Guid.txt" file of the selected completions will be updated. (Hold down the Ctrl or Shift key to select multiple)'
}

(Get-ChildItem "$PSScriptRoot/../completions").BaseName | Out-GridView -OutputMode Multiple -Title $select | ForEach-Object {
    (New-Guid).Guid | Out-File "$PSScriptRoot/../completions/$_/guid.txt" -Force
}
