<#
.SYNOPSIS
    Carry the last session's data forward, then start the game.

.DESCRIPTION
    Closing the game loses the addon's CVar store, so the price database has
    to be handed to the next session as an addon file. That has to happen
    after the game has written its saved variables and before it next reads
    its addon folder -- which is exactly the gap between quitting and
    launching.

    So: launch through this instead of through the game's own shortcut, and
    the hand-off happens by itself.

    Make a desktop shortcut for it once:

        1. Right-click the desktop, New > Shortcut.
        2. Paste this as the location, with your own path to the repo:

           powershell -ExecutionPolicy Bypass -File "D:\Blackthornes_Repo\Blackthornes_Tradeskills\tools\play.ps1"

        3. Call it whatever you like and use it instead of the game icon.

    If the restore fails -- no saved file yet, a locked folder -- the game
    still starts. Losing a session's history is bad; not being able to play
    is worse, and the failure is printed rather than swallowed.

.EXAMPLE
    .\tools\play.ps1
#>

[CmdletBinding()]
param(
    [string]$GamePath = 'D:\Blizzard\World of Warcraft\_classic_beta_',
    [string]$Account,
    [string]$Executable
)

$ErrorActionPreference = 'Stop'

$restore = Join-Path $PSScriptRoot 'restore.ps1'

try {
    $arguments = @{ GamePath = $GamePath }
    if ($Account) { $arguments.Account = $Account }

    & $restore @arguments
}
catch {
    Write-Host "Could not carry the last session's data over: $_" -ForegroundColor Red
    Write-Host 'Starting the game anyway.' -ForegroundColor Yellow
}

# The beta's executable is not named the same in every build, so look rather
# than hardcode, and prefer the 64-bit one when both are there.
if (-not $Executable) {
    $found = @(Get-ChildItem $GamePath -Filter '*.exe' -File |
        Where-Object { $_.Name -notmatch 'Launcher|Uninstall|Repair|BsSndRpt|dxsetup' } |
        Sort-Object { $_.Name -notmatch '64' }, Name)

    if ($found.Count -eq 0) {
        throw "No game executable found in $GamePath. Pass -Executable."
    }

    $Executable = $found[0].FullName
}

Write-Host "Starting $(Split-Path $Executable -Leaf)..." -ForegroundColor Green
Start-Process -FilePath $Executable -WorkingDirectory $GamePath
