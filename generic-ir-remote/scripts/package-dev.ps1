[CmdletBinding(PositionalBinding = $false)]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $CliArgs
)

$ErrorActionPreference = 'Stop'
$DriverDir = Split-Path -Parent $PSScriptRoot
$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("smartthings-ir-dev-" + [guid]::NewGuid().ToString('N'))

try {
  New-Item -ItemType Directory -Path $TempDir | Out-Null
  Get-ChildItem -LiteralPath $DriverDir -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $TempDir -Recurse -Force
  }
  Copy-Item -LiteralPath (Join-Path $DriverDir 'config.dev.yaml') -Destination (Join-Path $TempDir 'config.yaml') -Force

  & smartthings edge:drivers:package $TempDir @CliArgs
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
  if (Test-Path -LiteralPath $TempDir) {
    Remove-Item -LiteralPath $TempDir -Recurse -Force
  }
}
