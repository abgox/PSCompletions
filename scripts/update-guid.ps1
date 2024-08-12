param([string]$path)

if (Test-Path $path) {
    if ((Get-Item $path).Extension -eq ".txt") {
        (New-Guid).Guid | Out-File $path -Force
    }
    else {
        Get-ChildItem $path -Recurse -Filter "guid.txt" | ForEach-Object {
            (New-Guid).Guid | Out-File $_.FullName -Force
        }
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
