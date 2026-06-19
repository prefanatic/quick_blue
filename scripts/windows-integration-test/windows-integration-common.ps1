function Resolve-SharedFolder {
  $sharedCandidates = @(
    (Join-Path $env:USERPROFILE 'Desktop\Shared'),
    'C:\Users\Docker\Desktop\Shared',
    'C:\Shared'
  )
  $shared = $sharedCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
  if (-not $shared) {
    throw "Could not find Dockur shared folder. Tried: $($sharedCandidates -join ', ')"
  }
  return $shared
}
