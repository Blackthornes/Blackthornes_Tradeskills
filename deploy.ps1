<#
.SYNOPSIS
    Syntax-check and deploy Blackthornes Tradeskills into the WoW: Forever beta.

.DESCRIPTION
    Runs the Lua 5.1 syntax check, then mirrors the addon source into the
    client's Interface\AddOns folder. Development files (tools, deploy script,
    git metadata) are excluded from what ships to the client.

.PARAMETER GamePath
    Path to the client flavor folder. Defaults to the detected Forever beta.

.PARAMETER SkipCheck
    Skip the Lua syntax check. Not recommended: WoW disables an addon with a
    syntax error silently.

.EXAMPLE
    .\deploy.ps1
#>

[CmdletBinding()]
param(
    [string]$GamePath = 'D:\Blizzard\World of Warcraft\_classic_beta_',
    [switch]$SkipCheck
)

$ErrorActionPreference = 'Stop'

$AddonName = 'Blackthornes_TS'
$SourceRoot = $PSScriptRoot
$TargetRoot = Join-Path $GamePath "Interface\AddOns\$AddonName"

# Files and folders that belong in the repo but not in the client.
$Exclude = @('tools', 'docs', '.git', '.vscode')
$ExcludeFiles = @('deploy.ps1', '.gitignore', 'README.md', 'CLAUDE.md')

if (-not (Test-Path $GamePath)) {
    throw "Game path not found: $GamePath"
}

if (-not $SkipCheck) {
    Write-Host 'Running Lua syntax check...' -ForegroundColor Cyan

    $checker = Join-Path $SourceRoot 'tools\syntaxcheck.py'
    & python $checker
    if ($LASTEXITCODE -ne 0) {
        throw 'Syntax check failed. Nothing was deployed.'
    }

    # A call to a method that no longer exists is valid Lua and fails only
    # when that line runs, so it has to be checked separately.
    Write-Host 'Checking for undefined method calls...' -ForegroundColor Cyan

    $linter = Join-Path $SourceRoot 'tools\lintcalls.py'
    & python $linter
    if ($LASTEXITCODE -ne 0) {
        throw 'Undefined method calls found. Nothing was deployed.'
    }
}

Write-Host "Deploying to $TargetRoot" -ForegroundColor Cyan

# Refuse to touch a junction. The rebuild below is Remove-Item -Recurse -Force,
# and pointed at a link that can delete the contents of whatever it points at --
# which, if you have junctioned the client's addon folder to your working copy,
# is your source. Nothing to deploy in that case anyway: the client is already
# reading your files directly, so a reload is the whole workflow.
$existing = Get-Item $TargetRoot -Force -ErrorAction SilentlyContinue

if ($existing -and ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Write-Host ''
    Write-Host "$TargetRoot is a junction, not a folder." -ForegroundColor Yellow
    Write-Host 'The client is reading your working copy directly, so there is' -ForegroundColor Yellow
    Write-Host 'nothing to copy. Type /reload in game instead.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'Deploying would delete the files it points at. Refusing.' -ForegroundColor Yellow
    exit 0
}

# Rebuild the target so files deleted from source do not linger in the client.
if (Test-Path $TargetRoot) {
    Remove-Item $TargetRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $TargetRoot -Force | Out-Null

$copied = 0
Get-ChildItem $SourceRoot -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring($SourceRoot.Length).TrimStart('\')
    $topLevel = $relative.Split('\')[0]

    if ($Exclude -contains $topLevel) { return }
    if ($ExcludeFiles -contains $relative) { return }

    $destination = Join-Path $TargetRoot $relative
    $destinationDir = Split-Path $destination -Parent

    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    Copy-Item $_.FullName $destination -Force
    $script:copied++
}

Write-Host "Deployed $copied file(s)." -ForegroundColor Green
Write-Host 'In game: /reload  then  /bts probe' -ForegroundColor Yellow
