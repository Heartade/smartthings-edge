# Child creation and IR learning capabilities

These capability definitions and presentation templates are integrated with the
SmartThings setup GUI in `src/gui.lua`. Each folder contains `capability.json`, `presentation.json`,
`en.json` and `ko.json`. `manifest.json` maps each capability to its intended
device profiles; it is an installer/development manifest, not an API payload.

| Folder | Controls |
| --- | --- |
| `remote-creation` | Remote type, editable name, Create, creation status and details |
| `ir-learning` | Selected signal, saved status, Learn, Cancel, Test, Delete, learning status and details |
| `ac-learning-setup` | Switch between normal AC operation and editing a capture draft without transmitting |

The first version offers TV, fan, generic, learned-state AC and generated-protocol
AC children. The unfinished `ac-button` profile is not offered. Ordinary remote
learning supports `power_on` and `power_off`; AC learning uses `ac_state`.
TV remotes additionally support every button in `src/ir/tv_buttons.lua`, each with its own saved signal.

## TV controls and updated layout

Run this once from the repository root to register the three TV control groups and update
IR Signal Learning with the expanded button choices and a clean dashboard:

```powershell
./capabilities/register-tv-ui.ps1
smartthings edge:drivers:package . --install
```

TV controls are split into navigation/volume (19 commands), keypad (11), and
media/extras (12), within SmartThings' limit of 20 commands per capability.
The script prints and records each actual capability ID and updates its Lua and
profile references. Intended IDs are `againmusic09479.irTvRemote`,
`againmusic09479.irTvKeypad`, and `againmusic09479.irTvMedia` until registration
returns actual IDs. Rerun the same script after an interruption; registrations
already recorded in the manifest are reused. Translations use `upsert`, so existing English/Korean localizations are updated without a conflict. Existing presentations are updated with `presentation:update` after the specific duplicate-version response from `presentation:create`; other API errors stop the script with the failing step. `-TvCapabilityId <returned-id>` can
also resume a previously created navigation capability. The script updates account resources
only when you run it. Do not package before registering the new capability.

TV controls include power toggle; arrows and OK; Back/Home/Menu/Exit; volume,
mute and channel controls; previous channel; digits 0–9 and subchannel dash;
input, guide and info; playback/record; colored keys; subtitles and audio language.
Power On and Off remain on the main switch. Every button sends its separately
learned signal; no TV protocol or manufacturer code is assumed. Select each
button in the learning card at the bottom, then learn it from the original remote.
Native SmartThings uses individual button rows, rather than a graphical keypad.

Normal controls precede setup/learning cards in all profiles. Signal learning no
longer adds a status tile to the dashboard. Generated AC protocols use the
`ac-protocol-generated` profile, which omits both learning capabilities and the
legacy learning preference. Selecting **Learn states** restores the learning
profile. Profile changes retain stored codes. Existing devices request the new
profile revision on startup; reopen the device page after installing.

SmartThings groups status and command cards separately; exact rendering remains
under app control. See [Device Configurations](https://developer.smartthings.com/docs/devices/configurations-and-presentations/device-configurations).

## Registered capabilities

| Role | Capability ID | Version |
| --- | --- | --- |
| Remote creation | `againmusic09479.irRemoteCreation` | 1 |
| Signal learning | `againmusic09479.irSignalLearning` | 1 |
| AC learning setup | `againmusic09479.acLearningSetup` | 1 |

The profiles and driver reference these IDs. Install the updated driver and reopen
its device pages. Existing parent and remote profiles request their updated
capabilities on startup, preserving preferences and learned signals.

## Using the GUI

On the blaster page, select **Remote type**, edit **Remote name**, and press
**Create remote**. Creation status changes after the child is confirmed. A pending
request blocks repeated taps; a timed-out retry reuses the same child key.

On an ordinary remote, select the desired button (TV) or **Power on** / **Power off**, press **Learn selected
signal**, and press the original remote's button while the status asks for it.
**Test saved signal** sends that selection; **Delete selected signal** removes it.
**Cancel learning** cancels only this child's capture. The parent blaster handles
one capture or transmission at a time.

On an AC remote, turn on **Edit capture state without sending**. The normal power,
mode, temperature, fan and swing controls now edit a capture draft. Set the original
remote to the same state, press **Learn selected signal**, then send a command from
the original remote. AC capture drafts use 16–30 °C and both swing directions.
Testing transmits the saved signal; editing the draft does not. Turn setup off to
restore normal controls and discard the draft; the saved signal remains stored.
Restarting the driver exits draft mode. Transfer completion describes the blaster's
transfer, not physical appliance feedback.

The token-based Settings requests remain available for compatibility.

## Registration for another namespace

For this installation, reuse the registered IDs above. The following block is for
creating definitions under a different namespace; integration then requires updating
`manifest.json`, `src/gui.lua` and the corresponding profile capability IDs.

Run these PowerShell commands from the repository root. They create account
resources only when you execute them. Use the namespace-qualified ID returned
by SmartThings, rather than inventing a namespace or assuming a generated ID.

```powershell
$folder = 'capabilities/remote-creation'
$cap = smartthings capabilities:create -i "$folder/capability.json" --json |
    ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Capability registration failed' }
$capId = $cap.id
$capVersion = $cap.version
if (-not $capId -or -not $capVersion) { throw 'Missing capability ID/version' }

# The checked-in presentation intentionally has no account-specific ID.
# Add the returned ID/version to a temporary API payload before uploading it.
$presentation = Get-Content "$folder/presentation.json" -Raw -Encoding utf8 |
    ConvertFrom-Json
$presentation | Add-Member -NotePropertyName id -NotePropertyValue $capId -Force
$presentation.version = $capVersion
$payload = Join-Path $env:TEMP "ir-presentation-$([guid]::NewGuid()).json"
$json = $presentation | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($payload, $json, [System.Text.UTF8Encoding]::new($false))

smartthings capabilities:presentation:create $capId `
    --capability-version $capVersion -i $payload
smartthings capabilities:translations:upsert $capId `
    --capability-version $capVersion -i "$folder/en.json"
smartthings capabilities:translations:upsert $capId `
    --capability-version $capVersion -i "$folder/ko.json"

Write-Output "$folder = $capId (version $capVersion)"
```

Repeat with `capabilities/ir-learning` and `capabilities/ac-learning-setup`.
Record all three returned IDs for the later profile and Lua integration. Create
each definition once; subsequent changes should update its existing capability
or presentation instead of creating additional account resources. The installed
CLI uses `--capability-version`, not an extra positional version argument.

The templates reference translation labels with `{{i18n...}}` paths. Both locale
files must be registered. All setup/learning commands are omitted from the
automation view; the device detail page contains the interactive controls.

## Implemented handler contract

The GUI handlers are in `src/gui.lua`; transfer and persistence callbacks are
connected in `src/init.lua`. The following describes their behavior.

### Remote creation

- `setRemoteType(remoteType)` and `setRemoteName(name)` save and publish draft
  fields without creating a child. Name input must be nonblank, at most 60
  characters and contain no `|`. The request parser now counts UTF-8 characters,
  so Korean names have the same 60-character limit as English names.
- `createRemote()` validates the saved draft and allocates a unique internal
  child key. Users do not enter tokens. Repeated taps while creation is pending
  must reuse that request and prevent duplicate children.
- Publish `creationStatus=creating` while waiting. Publish `created` after the
  child is confirmed, or `error` and a useful `statusMessage` on failure.
  `created` refers to the most recent request, not the current draft contents.

### IR learning

- Initialize `supportedActions` to `["power_on", "power_off"]` for ordinary
  remotes and `["ac_state"]` for AC children. Publish a valid selected `action`.
  The presentation filters its choices using `supportedActions.value`.
- `selectAction(action)` changes the selected capture target and refreshes
  `signalStatus` (`empty` or `saved`). Freeze the target during capture/testing.
- `learn()` snapshots the selected action or AC capture draft, then starts the
  existing parent-owned learning session. Publish `learning`, followed by
  `learned` only once the captured code has been validated and persisted.
- `cancel()` cancels only this child's learning session. Report `cancelled`,
  `timeout`, `busy` or `error` as appropriate; retain existing saved signals
  when a new capture fails or is cancelled.
- `test()` sends the selected saved code through the shared transfer controller.
  Publish `testing`, then `sent` after transfer completion. This indicates
  blaster transfer completion, not confirmation that the appliance responded.
- `deleteSignal()` deletes only the selected saved action/state. Reject deletion
  during a pending capture or transfer, and publish `deleted` plus
  `signalStatus=empty` after persistence.
- Dynamic `statusMessage` text is provided by the handler, not translated
  automatically. The fixed statuses and all control labels are translated here.

### AC learning setup

- `setSetupMode("on")` starts an isolated draft based on the desired AC state.
  While on, power, AC mode, target temperature, fan and swing controls edit the
  draft and publish it to the page without sending appliance commands.
- `learn()` with `action=ac_state` captures against a snapshot of that draft.
  Require setup mode first so the target is deliberate and visible.
- `setSetupMode("off")` discards the draft and republishes the prior desired
  control state without transmitting. End any owned learning session before
  leaving setup mode; successfully saved captures remain stored.
- A driver restart must exit setup mode and restore normal control events,
  clearing stale busy/learning status. Setup mode must not create an IR send.

## References

- [Custom capabilities](https://developer.smartthings.com/docs/devices/capabilities/custom-capabilities)
- [Display types](https://developer.smartthings.com/docs/devices/capabilities/display-types)
- [Translations](https://developer.smartthings.com/docs/devices/capabilities/capability-translations)
