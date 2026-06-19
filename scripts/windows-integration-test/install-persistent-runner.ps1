param(
  [switch] $RunNow
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'windows-integration-common.ps1')

$shared = Resolve-SharedFolder
$sharedOem = Join-Path $shared '.dart_tool\dockur_windows\oem'
$sharedLogs = Join-Path $shared '.dart_tool\dockur_windows\logs'
$runner = Join-Path $sharedOem 'run-quick-blue-test.ps1'
$markerPath = Join-Path $sharedLogs 'runner-installed.txt'

New-Item -ItemType Directory -Force -Path $sharedLogs | Out-Null

if (-not (Test-Path $runner)) {
  throw "Could not find quick_blue test runner at $runner"
}

$action = New-ScheduledTaskAction `
  -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$runner`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal `
  -UserId $env:USERNAME `
  -RunLevel Highest

Register-ScheduledTask `
  -TaskName 'QuickBlueWindowsIntegrationTest' `
  -Action $action `
  -Trigger $trigger `
  -Principal $principal `
  -Description 'Runs the quick_blue Windows integration test from the Dockur shared folder.' `
  -Force | Out-Null

if ($RunNow) {
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner
  if ($LASTEXITCODE -ne 0) {
    throw "quick_blue test runner exited with code $LASTEXITCODE"
  }
}

Set-Content -Path $markerPath -Value (Get-Date -Format o) -Encoding ASCII
