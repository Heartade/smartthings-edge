[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string] $Channel,

  [Parameter(Mandatory = $true)]
  [string] $Hub,

  [string[]] $AdditionalCliArgs = @()
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'package-dev.ps1') -Install -Channel $Channel -Hub $Hub -AdditionalCliArgs $AdditionalCliArgs
exit $LASTEXITCODE
