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

Run this once from the repository root to register the TV control capabilities and update
IR Signal Learning with the expanded button choices and a clean dashboard:

```powershell
./capabilities/register-tv-ui.ps1
smartthings edge:drivers:package . --install
```

TV uses SmartThings' standard `keypadInput` for navigation, OK, Back/Home/Menu/
Settings/Exit and digits. This is the capability used by Otivax's IR driver:
[author's explanation](https://community.smartthings.com/t/edge-moes-smart-ir-remote-control/271782/49).
The app controls the native remote rendering. The official presentation also
provides a list fallback; the circular pad's appearance must be checked on your phone.

Volume/channel, mute, power toggle, previous channel, input/guide/info and
media/extras remain custom buttons. The existing `irTvKeypad` resource is retained
in the manifest for compatibility but is no longer attached to TV children.
The script registers/reuses the two custom TV capabilities, extends learning,
and updates parent creation choices. Existing translations and presentations
are updated on repeat runs. Run the same script again after an interruption.

Power On and Off remain on the main switch. Every button sends its separately
learned signal; no TV protocol or manufacturer code is assumed. Select each
button in the learning card at the bottom, then learn it from the original remote.
Navigation and digits use the native keypad; the extra controls use button rows.

Normal controls precede setup/learning cards. **AC protocol** (`ac-protocol`)
has no learning capabilities or learning preference and defaults to LG 28-bit;
choose the correct encoder in Settings. **AC protocol with learning**
(`ac-protocol-learning`) defaults to Learn states and exposes setup/learning at
the bottom. Selecting a generated encoder on that child installs the clean
protocol-only profile. **AC learned states** remains available independently.
Existing protocol children migrate by their selected encoder, without deleting
signals. Child classification also uses profile/capabilities and saved parent
child-type records, because Zigbee children may not expose creation model metadata.
No child deletion/recreation is required. Reopen the page after the migration.

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

Schema updates can become visible to capability reads before the localization
validator sees them. The registration script retries only invalid attribute/command
name localization responses, with bounded delays (up to 50 seconds total per
locale). Other failures stop immediately, and an unresolved validation error is
reported in full. This retains Settings as a native keypad action and a learnable
signal; it does not remove labels to accommodate an older cached schema.
