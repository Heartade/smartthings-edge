# Run from the repository root. Use -TvCapabilityId on subsequent runs.
param([string]$TvCapabilityId)
$ErrorActionPreference = 'Stop'
$encoding = [System.Text.UTF8Encoding]::new($false)
function Assert-CliSuccess {
    if ($LASTEXITCODE -ne 0) { throw 'SmartThings command failed; registration stopped.' }
}
$folder = 'capabilities/tv-remote'
if (-not $TvCapabilityId) {
    $created = smartthings capabilities:create -i "$folder/capability.json" --json | ConvertFrom-Json
    Assert-CliSuccess
    $TvCapabilityId = $created.id
    if (-not $TvCapabilityId -or $created.version -ne 1) { throw 'Expected a capability ID and version 1.' }
    Write-Host "Created $TvCapabilityId (version 1). Reuse this ID when rerunning."
} else {
    smartthings capabilities:update $TvCapabilityId --capability-version 1 -i "$folder/capability.json"
    Assert-CliSuccess
}
# Save the returned ID immediately, so an interrupted upload can be resumed.
$manifestPath = Join-Path (Get-Location) 'capabilities/manifest.json'
$manifest = Get-Content $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$tv = $manifest.capabilities | Where-Object key -eq 'tvRemote'
$previousId = $tv.registeredId
foreach ($path in @('src/gui.lua', 'profiles/remote-tv.yaml')) {
    $absolute = Join-Path (Get-Location) $path
    $content = [System.IO.File]::ReadAllText($absolute).Replace($previousId, $TvCapabilityId)
    [System.IO.File]::WriteAllText($absolute, $content, $encoding)
}
$tv.registeredId = $TvCapabilityId
$tv.registrationPending = $false
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 100) + "`n", $encoding)
# Extend the existing learning action enum without replacing saved device fields.
smartthings capabilities:update againmusic09479.irSignalLearning --capability-version 1 -i capabilities/ir-learning/capability.json
Assert-CliSuccess
foreach ($entry in @(@{ Folder = 'tv-remote'; Id = $TvCapabilityId }, @{ Folder = 'ir-learning'; Id = 'againmusic09479.irSignalLearning' })) {
    $folder = "capabilities/$($entry.Folder)"
    $presentation = Get-Content "$folder/presentation.json" -Raw -Encoding utf8 | ConvertFrom-Json
    $presentation | Add-Member -NotePropertyName id -NotePropertyValue $entry.Id -Force
    $payload = Join-Path $env:TEMP "ir-presentation-$([guid]::NewGuid()).json"
    try {
        [System.IO.File]::WriteAllText($payload, ($presentation | ConvertTo-Json -Depth 100), $encoding)
        smartthings capabilities:presentation:create $entry.Id --capability-version 1 -i $payload
        Assert-CliSuccess
        foreach ($locale in @('en', 'ko')) {
            smartthings capabilities:translations:create $entry.Id --capability-version 1 -i "$folder/$locale.json"
            Assert-CliSuccess
        }
    } finally {
        Remove-Item -LiteralPath $payload -ErrorAction SilentlyContinue
    }
}
Write-Host 'Capability registration complete. Install the repackaged driver and reopen the device pages.'
