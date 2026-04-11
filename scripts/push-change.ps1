param(
    [string]$branch = 'main',
    [string]$author = 'github-actions[bot]',
    [string]$email = '41898282+github-actions[bot]@users.noreply.github.com',
    [string]$message = 'chore: automatically update some content'
)

git -c core.safecrlf=false add -u

$has_change = git status --porcelain
if (-not $has_change) {
    Write-Host 'No changes to commit.' -ForegroundColor Green
    return
}

git -c user.name="$author" -c user.email="$email" commit --no-gpg-sign -m "$message"

# Push changes
$retryDelay = 15
for ($i = 0; $i -lt 5; $i++) {
    Write-Host 'Rebasing local branch before push ...' -ForegroundColor Cyan
    git pull --rebase origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Pull failed.'
        Write-Warning "Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        continue
    }
    Write-Host 'Pushing updates ...' -ForegroundColor Cyan
    git push origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Push failed.'
        Write-Warning "Retrying in $retryDelay seconds..."
        Start-Sleep -Seconds $retryDelay
        continue
    }
    break
}
