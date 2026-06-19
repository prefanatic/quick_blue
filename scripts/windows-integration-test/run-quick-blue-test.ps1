$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'windows-integration-common.ps1')

$sharedRoot = Resolve-SharedFolder
$sharedEnvPath = Join-Path $sharedRoot '.dart_tool\dockur_windows\oem\quick-blue-env.ps1'
$localEnvPath = 'C:\OEM\quick-blue-env.ps1'
if (Test-Path $sharedEnvPath) {
  . $sharedEnvPath
} elseif (Test-Path $localEnvPath) {
  . $localEnvPath
} else {
  throw "Could not find quick_blue env file at $sharedEnvPath or $localEnvPath"
}

$logDir = Join-Path $sharedRoot '.dart_tool\dockur_windows\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir 'windows-integration-test.log'
$statusPath = Join-Path $logDir 'status.txt'
Start-Transcript -Path $logPath -Append

function Set-Status([string] $value) {
  Set-Content -Path $statusPath -Value $value -Encoding ASCII
}

function Add-ToPath([string] $path) {
  if ((Test-Path $path) -and (($env:Path -split ';') -notcontains $path)) {
    $env:Path = "$path;$env:Path"
  }
}

function Invoke-Native([string] $command, [string[]] $arguments) {
  Write-Host "Running: $command $($arguments -join ' ')"
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $command @arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }
  foreach ($line in $output) {
    Write-Host $line
  }
  if ($exitCode -ne 0) {
    throw "$command exited with code $exitCode"
  }
}

function Ensure-Chocolatey {
  if (Get-Command choco.exe -ErrorAction SilentlyContinue) {
    return
  }

  Set-ExecutionPolicy Bypass -Scope Process -Force
  [System.Net.ServicePointManager]::SecurityProtocol =
    [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
  Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
    'https://community.chocolatey.org/install.ps1'
  ))
  Add-ToPath 'C:\ProgramData\chocolatey\bin'
}

function Ensure-Toolchain {
  Ensure-Chocolatey

  if (Get-Command git.exe -ErrorAction SilentlyContinue) {
    Write-Host 'Git is already installed.'
  } else {
    Invoke-Native 'choco' -Arguments @('install', 'git', '-y', '--no-progress')
  }

  if (Get-Command nuget.exe -ErrorAction SilentlyContinue) {
    Write-Host 'NuGet is already installed.'
  } else {
    Invoke-Native 'choco' -Arguments @(
      'install',
      'nuget.commandline',
      '-y',
      '--no-progress'
    )
  }

  $cl = Get-ChildItem `
    -Path 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe' `
    -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if ($cl) {
    Write-Host "Visual Studio C++ toolchain is already installed at $($cl.FullName)."
  } else {
    Invoke-Native 'choco' -Arguments @(
      'install',
      'visualstudio2022buildtools',
      '-y',
      '--no-progress',
      '--package-parameters',
      '--includeRecommended --includeOptional --passive --norestart'
    )
    Invoke-Native 'choco' -Arguments @(
      'install',
      'visualstudio2022-workload-vctools',
      '-y',
      '--no-progress',
      '--package-parameters',
      '--includeRecommended --includeOptional --passive --norestart'
    )
  }

  Add-ToPath 'C:\Program Files\Git\cmd'
}

function Ensure-Flutter {
  $flutterRoot = 'C:\tools\flutter'
  $installedFlutter = $false
  if (-not (Test-Path (Join-Path $flutterRoot 'bin\flutter.bat'))) {
    New-Item -ItemType Directory -Force -Path 'C:\tools' | Out-Null
    Invoke-Native 'git' -Arguments @(
      'clone',
      '--depth',
      '1',
      '--branch',
      $Env:QUICK_BLUE_WINDOWS_FLUTTER_CHANNEL,
      'https://github.com/flutter/flutter.git',
      $flutterRoot
    )
    $installedFlutter = $true
  }
  Add-ToPath (Join-Path $flutterRoot 'bin')
  Invoke-Native 'flutter' -Arguments @('config', '--enable-windows-desktop')
  if ($installedFlutter -or $Env:QUICK_BLUE_WINDOWS_RUN_DOCTOR -eq '1') {
    Invoke-Native 'flutter' -Arguments @('doctor', '-v')
  } else {
    Invoke-Native 'flutter' -Arguments @('--version')
  }
}

function Write-DeviceDiagnostics {
  Write-Host 'Windows Bluetooth and USB device diagnostics:'
  Get-PnpDevice -PresentOnly |
    Where-Object {
      $_.Class -eq 'Bluetooth' -or
        $_.FriendlyName -match 'Bluetooth|Realtek|Radio' -or
        $_.InstanceId -match 'VID_0BDA|PID_8771'
    } |
    Sort-Object Class, FriendlyName |
    Format-Table -AutoSize Class, Status, Problem, FriendlyName, InstanceId |
    Out-String -Width 240 |
    Write-Host
}

function Copy-CheckoutToNtfs([string] $source) {
  if ([string]::IsNullOrWhiteSpace($source)) {
    throw 'Cannot copy quick_blue checkout because the shared folder path is empty.'
  }

  $workRoot = 'C:\quick_blue_workspace'
  $workTree = Join-Path $workRoot 'quick_blue'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  if ((Test-Path $workTree) -and ($Env:QUICK_BLUE_WINDOWS_CLEAN_WORKTREE -eq '1')) {
    Write-Host "Removing cached NTFS checkout at $workTree."
    Remove-Item -Recurse -Force -Path $workTree
  } elseif (Test-Path $workTree) {
    Write-Host "Reusing cached NTFS checkout at $workTree."
  }

  & robocopy @(
    $source,
    $workTree,
    '/MIR',
    '/XD',
    '.dart_tool',
    '.git',
    '.plugin_symlinks',
    'build',
    'ephemeral',
    '/XF',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    'pubspec.lock',
    '/NFL',
    '/NDL',
    '/NJH',
    '/NJS',
    '/NC',
    '/NS'
  ) | Out-Null
  if ($LASTEXITCODE -gt 7) {
    throw "robocopy exited with code $LASTEXITCODE"
  }
  & attrib.exe -R "$workTree\*" /S /D | Out-Null

  return $workTree
}

function Test-PubGetNeeded([string] $workTree) {
  $packageConfig = Join-Path $workTree '.dart_tool\package_config.json'
  if (-not (Test-Path $packageConfig)) {
    return $true
  }

  $packageConfigTime = (Get-Item $packageConfig).LastWriteTimeUtc
  $pubspecs = @(
    'pubspec.yaml',
    'quick_blue\pubspec.yaml',
    'quick_blue\example\pubspec.yaml',
    'quick_blue_darwin\pubspec.yaml',
    'quick_blue_linux\pubspec.yaml',
    'quick_blue_platform_interface\pubspec.yaml',
    'quick_blue_windows\pubspec.yaml'
  ) |
    ForEach-Object { Join-Path $workTree $_ } |
    Where-Object { Test-Path $_ } |
    ForEach-Object { Get-Item $_ }

  foreach ($pubspec in $pubspecs) {
    if ($pubspec.LastWriteTimeUtc -gt $packageConfigTime) {
      return $true
    }
  }

  return $false
}

try {
  Set-Status 'starting'

  New-ItemProperty `
    -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' `
    -Name LongPathsEnabled `
    -Value 1 `
    -PropertyType DWord `
    -Force | Out-Null

  Ensure-Toolchain
  Ensure-Flutter
  Write-DeviceDiagnostics

  $workTree = Copy-CheckoutToNtfs $sharedRoot
  $exampleDir = Join-Path $workTree 'quick_blue\example'

  Set-Location $exampleDir
  if (Test-PubGetNeeded $workTree) {
    Invoke-Native 'flutter' -Arguments @('pub', 'get')
  } else {
    Write-Host 'Skipping flutter pub get; package_config.json is newer than pubspec files.'
  }

  $flutterArgs = @(
    'test',
    $QuickBlueTestTarget,
    '-d',
    'windows',
    '--no-pub'
  ) + $QuickBlueDartDefines

  Set-Status 'running'
  Invoke-Native 'flutter' -Arguments $flutterArgs
  Set-Status 'passed'
} catch {
  Set-Status 'failed'
  Write-Error $_
  exit 1
} finally {
  Stop-Transcript
}
