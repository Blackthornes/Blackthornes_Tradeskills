<#
.SYNOPSIS
    Point git at the repository's hooks. Run once per clone.

.DESCRIPTION
    Git does not install hooks when a repository is cloned, so this sets
    core.hooksPath to the .githooks folder that is in the repository. After
    this, a commit that would carry saved data in Data/Snapshot.lua is refused.

.EXAMPLE
    .\tools\install-hooks.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path $PSScriptRoot -Parent

Push-Location $ProjectRoot
try {
    git config core.hooksPath .githooks
    if ($LASTEXITCODE -ne 0) { throw 'Could not set core.hooksPath.' }
}
finally {
    Pop-Location
}

Write-Host 'Hooks installed. Commits carrying saved data will be refused.' -ForegroundColor Green
