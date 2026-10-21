# Run from the repository root. Completed registrations are reused from manifest.json.
# -TvCapabilityId can resume a TV navigation capability created by an earlier run.
param([string]$TvCapabilityId)
$ErrorActionPreference = 'Stop'
# Handle native CLI exit codes explicitly, including the expected POST conflict.
$PSNativeCommandUseErrorActionPreference = $false
$encoding = [System.Text.UTF8Encoding]::new($false)
$script:RegistrationStep = 'initialization'
function Assert-CliSuccess {
    if ($LASTEXITCODE -ne 0) { throw "SmartThings command failed during $script:RegistrationStep (exit $LASTEXITCODE); registration stopped." }
}
$manifestPath = Join-Path (Get-Location) 'capabilities/manifest.json'
$manifest = Get-Content $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$tvEntries = @($manifest.capabilities | Where-Object { $_.key -in @('tvRemote', 'tvKeypad', 'tvMedia') })
# Catch command-limit errors before making any API writes.
foreach ($entry in $tvEntries) {
    $definition = Get-Content "capabilities/$($entry.definition)" -Raw -Encoding utf8 | ConvertFrom-Json
    if (@($definition.commands.PSObject.Properties).Count -gt 20) {
        throw "$($entry.key) exceeds SmartThings' 20-command limit."
    }
}
foreach ($entry in $tvEntries) {
    $capId = $entry.registeredId
    if ($entry.key -eq 'tvRemote' -and $TvCapabilityId) {
        $capId = $TvCapabilityId
        $entry.registrationPending = $false
    }
    if ($entry.registrationPending) {
        $script:RegistrationStep = "creating capability $($entry.key)"
        Write-Host $script:RegistrationStep
        $created = smartthings capabilities:create -i "capabilities/$($entry.definition)" --json | ConvertFrom-Json
        Assert-CliSuccess
        $capId = $created.id
        if (-not $capId -or $created.version -ne 1) { throw 'Expected a capability ID and version 1.' }
        Write-Host "Created $($entry.key): $capId (version 1)."
    } else {
        $script:RegistrationStep = "updating capability $capId"
        Write-Host $script:RegistrationStep
        smartthings capabilities:update $capId --capability-version 1 -i "capabilities/$($entry.definition)"
        Assert-CliSuccess
    }
    # Persist each returned ID before continuing, so retries reuse completed creations.
    $previousId = $entry.registeredId
    foreach ($path in @('src/gui.lua', 'profiles/remote-tv.yaml')) {
        $absolute = Join-Path (Get-Location) $path
        $content = [System.IO.File]::ReadAllText($absolute).Replace($previousId, $capId)
        [System.IO.File]::WriteAllText($absolute, $content, $encoding)
    }
    $entry.registeredId = $capId
    $entry.registrationPending = $false
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 100) + "`n", $encoding)
}
$script:RegistrationStep = "updating learning capability"
Write-Host $script:RegistrationStep
smartthings capabilities:update againmusic09479.irSignalLearning --capability-version 1 -i capabilities/ir-learning/capability.json
Assert-CliSuccess
$learning = $manifest.capabilities | Where-Object key -eq 'irLearning'
foreach ($entry in @($tvEntries) + @($learning)) {
    $presentation = Get-Content "capabilities/$($entry.presentation)" -Raw -Encoding utf8 | ConvertFrom-Json
    $presentation | Add-Member -NotePropertyName id -NotePropertyValue $entry.registeredId -Force
    $payload = Join-Path $env:TEMP "ir-presentation-$([guid]::NewGuid()).json"
    try {
        [System.IO.File]::WriteAllText($payload, ($presentation | ConvertTo-Json -Depth 100), $encoding)
        $script:RegistrationStep = "creating presentation for $($entry.registeredId)"
        Write-Host $script:RegistrationStep
        # POST conflicts if this capability/version already has a presentation.
        # Capture only this call's error and retry PUT only for the known conflict.
        $createOutput = @(smartthings capabilities:presentation:create $entry.registeredId --capability-version 1 -i $payload 2>&1)
        $createExit = $LASTEXITCODE
        if ($createExit -ne 0) {
            $detail = $createOutput -join "`n"
            if ($detail -match 'Capability with same version already exists') {
                $script:RegistrationStep = "updating presentation for $($entry.registeredId)"
                Write-Host $script:RegistrationStep
                smartthings capabilities:presentation:update $entry.registeredId --capability-version 1 -i $payload
                Assert-CliSuccess
            } else {
                throw "SmartThings failed during $script:RegistrationStep (exit $createExit):`n$detail"
            }
        } else {
            $createOutput | ForEach-Object { Write-Output $_ }
        }
        foreach ($locale in @('en', 'ko')) {
            $script:RegistrationStep = "upserting $locale translation for $($entry.registeredId)"
            Write-Host $script:RegistrationStep
            smartthings capabilities:translations:upsert $entry.registeredId --capability-version 1 -i "capabilities/$($entry.translations.$locale)"
            Assert-CliSuccess
        }
    } finally {
        Remove-Item -LiteralPath $payload -ErrorAction SilentlyContinue
    }
}
Write-Host 'Capability registration complete. Install the repackaged driver and reopen the device pages.'
