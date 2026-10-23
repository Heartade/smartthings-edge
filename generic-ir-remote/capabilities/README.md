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
| `ac-protocol-selection` | One AC detail-screen selector combining protocol and known remote model |

The child-creation UI offers TV, fan, generic IR switch, generic IR button,
learned-state AC, protocol-only AC, and protocol AC with learning. The `ac-button`
profile is not offered. Fan learning currently covers `power_on` and
`power_off`; generic IR switches also support `power_toggle`, generic IR buttons
use `press`, and AC learning captures `ac_state`. TV learning offers the actions
in `src/ir/tv_buttons.lua`, each with its own saved signal.

## TV controls and updated layout

The namespace owner/maintainer runs this from the `generic-ir-remote/` driver
folder when updating
the existing learning and creation definitions, presentations and translations.
It also refreshes the bundled SDK schemas. A normal user installing a published
driver should not run it:

```powershell
./capabilities/register-tv-ui.ps1
smartthings edge:drivers:package . --install
```

TV uses SmartThings' standard `keypadInput` for navigation, OK, Back/Home/Menu/
Settings/Exit and digits. The SmartThings app controls the native remote
rendering. The official presentation also provides a list fallback; the circular
pad's appearance must be checked on your phone.

TV children now contain only power, the native keypad and the learning card.
All separate custom TV button rows have been removed. The old TV capability
resources remain registered for compatibility, but are no longer attached or
required by TV profiles. The registration script updates only capabilities still
used by a profile; it does not recreate retired TV controls.

Power On and Off remain on the main switch. Every button sends its separately
learned signal; no TV protocol or manufacturer code is assumed. Select each
button in the learning card at the bottom, then learn it from the original remote.
Navigation and digits use the native keypad. Extra learned signals can still be selected and tested from the learning card, without separate button rows.

Normal controls precede setup/learning cards. The **AC protocol / model** list on
the device detail page contains the 91 generated IRremoteESP8266 variants and
**Learn AC states**. New protocol children default to the generated LG model
`GE6711AR2853M`; learned-state children default to **Learn AC states**. Choosing
a complete protocol hides setup/learning controls; choosing **Learn AC states**
shows them. Existing `acProtocol` and `acModel` values migrate at startup.
Selections from the retired handwritten encoders map to the closest generated
variant and are then stored under its current key. Child classification also uses
profile/capabilities and saved parent child-type records, because Zigbee children
may not expose creation model metadata. No child deletion/recreation is required.
Reopen the page after profile migration.

SmartThings groups status and command cards separately; exact rendering remains
under app control. See [Device Configurations](https://developer.smartthings.com/docs/devices/configurations-and-presentations/device-configurations).

## Registered capabilities

| Role | Capability ID | Version |
| --- | --- | --- |
| Remote creation | `againmusic09479.irRemoteCreation` | 1 |
| Signal learning | `againmusic09479.irSignalLearning` | 1 |
| AC learning setup | `againmusic09479.acLearningSetup` | 1 |
| AC protocol/model selector | `againmusic09479.acProtocolSelection` | 1 |

The profiles and driver reference these registered IDs. Only the namespace
owner can update their definitions. Driver users install a build that references
the published IDs and reopen device pages; they do not need to register the
capabilities. Existing child profiles request updates on startup, preserving
preferences and learned signals.

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

For this installation, reuse the registered IDs above. The checked-in
registration script contains owner-specific IDs and is not namespace-neutral.
A fork that needs a different namespace must create its own definitions and
presentations, then update `manifest.json`, every referencing profile,
`src/gui.lua`, and its registration workflow. Search the repository for
`againmusic09479` and replace each capability reference as appropriate. Do not
run the checked-in script unchanged against a different namespace.

Run these PowerShell commands from the `generic-ir-remote/` driver folder. They create account
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

Repeat for all four used definitions: `remote-creation`, `ir-learning`,
`ac-learning-setup`, and `ac-protocol-selection`. Record each returned ID and
replace every matching reference in the manifest, profiles, Lua handlers, and
the fork's adapted registration workflow. Create each definition once; later
changes update that existing capability and presentation instead of creating
duplicates. The checked-in script also has owner-specific update calls for the
creation and learning IDs, so a fork must change those before running it. The
installed CLI uses `--capability-version`, not an extra positional version
argument.

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

The learning selector's options are now embedded in each profile: all TV actions
for TV, power actions for fan/generic, and `ac_state` for AC. It no longer uses
`supportedActions` to filter the list, so old on/off-only device status cannot hide
new buttons. Select any TV action, press Learn, and press that original remote
button. Existing saved codes are unchanged.

Non-AC power switches initialize from the last successfully sent state, then the
cached switch state, or Off if neither exists. This is an assumed state, not IR
feedback. A successful power transmission persists the new state. Learning or
testing a signal does not change the power state.

The driver bundles the exact creation, learning and AC setup schemas in
`src/capability_definitions.lua`. It builds native SDK capability objects from
those definitions for both events and commands, rather than using a stale hub
schema. The registration script regenerates this Lua module from the same JSON
files uploaded to SmartThings. Capability IDs and version 1 remain unchanged.

## Generic IR types

The existing `remote-generic` choice is now labeled **Generic IR switch**
(**일반 IR 스위치**). Its On/Off controls and saved signals are preserved;
`power_toggle` is available in its learning selector.

The new **Generic IR button** (**일반 IR 버튼**, `remote-button`) uses standard
`momentary.push` with no state attributes. Its learning selection is **Button
press** (`press`); Learn, Test, Delete and cancellation use the existing per-child
signal store and shared blaster lock. A press passes no switch value to the
transfer callback, so transmission cannot emit On/Off events.

Run the registration script to update the two existing custom definitions,
presentations, locales and bundled SDK schemas before installing. No new custom
capability registration is needed for the standard momentary control.
