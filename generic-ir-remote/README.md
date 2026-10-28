# SmartThings Generic IR Remote

An experimental SmartThings Edge driver for TS1201-compatible Zigbee IR blasters. Each logical remote is an Edge child device. AC children use either exact learned-state control or generated protocol/model control.

## Status

The driver includes exact learned-state control and a generated catalog covering all 66 common AC protocol identifiers in the pinned IRremoteESP8266 revision (91 protocol/model combinations). These are software encoder choices, not 91 hardware-verified appliance models. AC children expose power, AC mode, one target-temperature slider, fan speed, and supported swing directions. Native SmartThings AC modes label `dry` as **제습** in Korean. The catalog remains experimental pending physical AC/blaster checks. TV children use the native keypad and can learn individual signals; fan and generic switch children learn power actions.

Use the **AC protocol / model** selector on the AC device screen. Each option combines the protocol and its known remote variant, such as **LG2 2: AKB75215403**. Choose **Learn AC states** when no listed variant matches. See the [model table](docs/ac-catalog-models.md) and [catalog scope, limits and rebuilding](docs/ac-catalog.md).

See [the driver design](docs/driver-design.md) for behavior, [implementation status](docs/implementation-plan.md) for outstanding checks, [protocol sources](docs/protocol-sources.md) for encoder references, and the [public release checklist](docs/public-release.md) for compatibility, custom capability ownership, and distribution guidance.
Platform and runtime gotchas from implementation are collected in the
[SmartThings implementation quirks](docs/implementation-quirks.md) note.

## License and acknowledgments

Original project code is licensed under Apache-2.0, with LGPL-2.1-only exceptions
for the AC adaptations and generated catalog. See the root
[LICENSE.md](../LICENSE.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
for the AC ports' LGPL terms,
retained third-party licenses, and acknowledgments, including the Otivax
SmartThings Community reference thread and the Zosung transport reference.
Publish the source, notices, and license texts in the public repository/release
separately from the SmartThings Edge ZIP. Do not add them to that ZIP; see the
[release guide](docs/public-release.md).

## Create remotes and learn signals in the app

After installing this version, reopen the blaster page. Choose **Remote type**,
enter **Remote name**, and tap **Create remote**. The creation status confirms
when the child is added. Existing devices request the updated GUI profiles on
startup, keeping their saved codes and preferences.

The physical blaster page also exposes SmartThings' standard battery percentage.
Battery reporting is configured on device setup and refreshed through the
standard Zigbee defaults. Logical child remotes share that hardware battery.
The `_TZ3290_7v1k4vufotpowp9z` TS1201 variant is reported to have no battery,
so it cannot provide a battery percentage ([device note](https://community.smartthings.com/t/edge-moes-smart-ir-remote-control/271782)).

On a TV, fan or generic remote, choose **Power on** or **Power off**, tap **Learn
selected signal**, then press the original remote button. **Cancel**, **Test**,
**Delete**, saved-signal status and learning/timeout/error status appear on that
page. Test completion means the blaster transfer finished.

For AC capture, enable **Edit capture state without sending**. Set power, mode,
temperature, fan and swing using the usual controls; these edit an isolated draft
without IR transmission. Set the original remote to the same state, tap **Learn**,
and send its command. Use **Test** to transmit the saved state. Disable setup mode
to restore normal controls; captures remain saved. Legacy token-based Settings
requests continue to work. See the [GUI guide](capabilities/README.md).

Choose **IR signal logger** from **Remote type** to create a diagnostic child.
Tap **Capture IR signal**, then press a remote button toward the blaster. Its
detail page shows the assumed carrier, timing counts, total duration, and signed
microsecond timings (`+` mark, `-` space). The log keeps the three most recent
captures and does not claim to identify the remote's protocol. Use **Clear log**
to reset it.

## How to run

Run commands from this driver folder, `generic-ir-remote/`.

### Run the local Lua checks

Install a Lua 5.3 interpreter, then run the standalone checks individually:

```sh
lua tests/ac_state.lua
lua tests/ac_registry.lua
lua tests/ac_catalog.lua
lua tests/ac_learned_state.lua
lua tests/children.lua
lua tests/ir_controller.lua
lua tests/edge_zigbee.lua
lua tests/ir_learned_actions.lua
lua tests/zosung.lua
lua tests/zosung_wire.lua
```

These scripts exercise state, child controls, Zosung transport and the generated AC catalog. For native SmartThings SDK serialization and capability-schema checks, extract the [official Lua libraries](https://github.com/SmartThingsCommunity/SmartThingsEdgeDrivers/releases), set `SMARTTHINGS_LUA_LIBS` to the directory containing `st/`, and run:

```sh
lua tests/edge_zigbee_sdk.lua
lua tests/edge_ac_controls_sdk.lua
lua tests/gui_sdk.lua
lua tests/edge_lifecycle.lua
lua tests/edge_child_control.lua
```

The SDK test files cover complete on/off payload transfers for all 91 generated protocol/model choices, AC controls, transfer-state persistence and profile migration. They do not confirm physical AC reception. Run the checks for the exact source revision being released; waveform comparisons and software tests are not hardware certification. See the [release checklist](docs/public-release.md).

### Package and install on a development hub

You need a SmartThings account, the [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli#installation), a compatible SmartThings hub, and a driver channel that the hub has joined. Sign in through the CLI when prompted.

1. List your hubs and copy the development hub ID:

   ```sh
   smartthings devices --type=HUB
   ```

2. If you do not already have a driver channel, create one and follow the prompts:

   ```sh
   smartthings edge:channels:create
   ```

3. Enroll the hub in that channel, using the IDs from the previous steps:

   ```sh
   smartthings edge:channels:enroll <hub-id> --channel <channel-id>
   ```

4. Build and upload this driver package, then install it to the enrolled hub:

   ```sh
   smartthings edge:drivers:package . --install --channel <channel-id> --hub <hub-id>
   ```

   The CLI may prompt for values if flags are omitted. Re-run the package command after code changes to publish and install an updated version.

5. In the SmartThings app, add the supported TS1201 device using **Add device → Scan nearby**.

The parent receives Zosung `0xED00` messages and runs one transfer at a time. For a TV, fan, or generic switch child, the in-app learning card is preferred. The legacy Settings field **Learn or cancel a power action** also accepts a new value such as `on-001|power_on` or `off-001|power_off`; point the original remote at the blaster during capture. Use a new token for every request. A switch's state records assumed/last-commanded state after a completed blaster transfer; it does not confirm that the TV or fan responded. Seven exact TS1201 manufacturer/model fingerprints are included. A generic fallback also matches profile `0x0104` with server clusters `0xED00`, `0xE004`, and `0x0001`, without checking manufacturer/model. Confirm which path matched and the exact blaster revision when troubleshooting. See [implementation status](docs/implementation-plan.md) and the [release checklist](docs/public-release.md). For the official workflow, see the [Edge driver packaging and deployment guide](https://developer.smartthings.com/docs/devices/hub-connected/edge-architecture) and [driver channel guide](https://developer.smartthings.com/docs/devices/hub-connected/driver-channels).

On learned-state AC children, **AC protocol / model** defaults to **Learn AC states**. Set the original remote to a complete state, aim it at the blaster, then set **Learn complete AC state** to a fresh request such as `learn-01|on|cool|24|auto|off|off`. The fields are token, power, mode (`cool`, `heat`, `dry`, `fan`, `auto`), integer Celsius temperature, fan (`auto`, `low`, `medium`, `high`), vertical swing, and horizontal swing. Capture each state you plan to use; the driver sends an exact saved match and refuses an unlearned state. `token|cancel` cancels a capture. The SmartThings controls update desired/last-commanded state after a send starts; they do not report physical AC feedback. Set **AC temperature unit** to match the SmartThings setpoint display.

Selecting a complete protocol/model replaces the learning controls with the regular AC controls. **Learning is not required** for listed variants. Select the remote variant rather than assuming every AC from a brand uses the same protocol.

See the [generated model table](docs/ac-catalog-models.md) for all 91 choices,
their temperature ranges and upstream model identifiers. Every choice remains
experimental. The catalog applies upstream protocol restrictions, including
mode-specific setpoints and fan defaults, and rejects unsupported combinations
before transmission. Extra functions such as turbo, timers, display toggles and
fixed vane positions are not exposed.

The swing selector offers only directions supported by the selected protocol. Learned-state users must capture the exact on/off swing state they intend to select (`on` for an enabled direction).

Both AC profiles now use **one temperature control for heating and cooling**, `airConditionerMode` (`제습`, `송풍`, etc.), and `fanOscillationMode`. Existing AC children request the updated profile when this driver starts, preserving saved IR codes and preferences. After installing, reopen the device page; existing Routines that referenced the old thermostat capabilities may need their actions reselected. Bixby phrase recognition must be checked on the user's account/device.

### Physical smoke test: learn and send a TV power code

This first hardware check assumes a TS1201-compatible Zigbee IR blaster, a SmartThings hub that supports Edge drivers, a TV, and the TV's original IR remote. Keep the remote and blaster close together for learning, then aim the blaster's IR emitter at the TV. Seven manufacturer-specific fingerprints cover the listed TS1201 pairs; a generic fallback matches profile `0x0104` and server clusters `0xED00`, `0xE004`, and `0x0001`. A different hardware revision may not match or work.

1. Install and authenticate the SmartThings CLI. Check the CLI with `smartthings --version`, then list hubs with `smartthings devices --type=HUB`.
2. Create a driver channel if you do not already have one by running `smartthings edge:channels:create`. Enroll your development hub in that channel and package/install this checkout using the commands above. Keep the hub ID and channel ID for later updates.
3. In a second PowerShell window, start live logs for the hub (replace the address with the hub's LAN IP):

   ```powershell
   smartthings edge:drivers:logcat --hub-address=192.168.1.20
   ```

   Select this driver if the CLI asks. Leave logcat running while pairing and learning.
4. Put the blaster into Zigbee pairing mode using the reset/pairing procedure for its exact model. In the SmartThings app, choose **Add device → Scan nearby**. A successful match should appear as **IR Blaster (development)**. If it does not, confirm the model and its reported Zigbee clusters before continuing.
5. Open the blaster's Settings in the SmartThings app. Under **Add remote request**, save a fresh request such as `test-tv|remote-tv|Test TV`. The child remote should appear as a separate device.
6. Open the new child's Settings. Under **Learn or cancel a power action**, enter `learn-on-01|power_on`, save, then press the TV remote's power button while pointing it at the blaster. A successful capture logs `Learned IR action saved: power_on`; repeat with a new request, `learn-off-01|power_off`, and press the power button again. A timeout or malformed-message warning means the capture did not complete.
7. Return to the child remote and send **On**, then **Off**. Confirm that the TV responds and check logcat for the outgoing transfer and its completion. The SmartThings switch state only reports that the blaster transfer completed; verify the TV itself to confirm IR reception.

If pairing succeeds but learning or sending fails, save the logcat output and note the blaster's exact model/revision, hub model, and which step failed. This helps distinguish a fingerprint mismatch from a receive/transmit or protocol issue.

## References

The child-creation and learning GUI uses the registered custom capabilities
listed in [capabilities/](capabilities/README.md), with English/Korean presentations.
That guide includes the complete setup workflow and registration instructions.

- [SmartThings Edge package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Edge child-device API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Edge integration tests](https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver)
- [Zigbee2MQTT Zosung TS1201 converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)

### TV controls and learning layout

TV remotes use SmartThings' native `keypadInput` presentation for navigation,
OK, digits and the other keys supported by that capability. The driver maps
those key commands to learned signals. The learning card at the bottom lets you
capture and test available actions, including volume/channel and playback
signals; it does not add a row of separate volume/channel buttons to the device
page. See [TV controls and registration](capabilities/README.md#tv-controls-and-updated-layout).

Child types **AC protocol** and **AC protocol with learning** now have separate
profiles. Protocol-only children contain no IR learning capability. Existing
protocol children select the appropriate profile from their encoder preference.
The capability registration script is for the namespace owner/maintainer. A
normal user installing a published build should not run it; see the
[registration guide](capabilities/README.md#registered-capabilities).

TV detail pages now omit all separate button rows below the native keypad.
To learn a button, choose it in **Signal to learn**, then press **Learn selected
signal** and use the original remote. Profile-defined choices expose all TV
signals even if an older device status listed only on/off. Extra signals remain
available through the learning card's Test action. Non-AC power switches now
start with a usable assumed state and retain the last successfully sent state.

For learned remotes, On/Off first use their dedicated `power_on`/`power_off`
signal. If that signal is missing, they use `power_toggle`. A repeated request
matching the last successfully sent power state skips the fallback toggle, so
repeated On or Off does not invert the appliance again. The first request with
no sent-state history transmits the toggle. This tracks assumed state only;
using the physical remote can leave it out of sync. Tests and learning continue
to address the exact selected signal, without substituting toggle codes.

## Generic IR switch and generic IR button

- **Generic IR switch** keeps the existing `remote-generic` profile and saved
  signals. Learn separate Power on/off codes, or learn Power toggle once for the
  On/Off fallback. The switch tracks the last sent/assumed state.
- **Generic IR button** (`remote-button`) exposes a stateless **Push** command
  through SmartThings' standard `momentary` capability. Learn **Button press**,
  then tap Push (or invoke it in a Routine) to replay that signal every time.
  It has no switch capability, On/Off state, or power-state updates.
- **IR signal logger** (`ir-logger`) captures a button press and displays a
  bounded history of decoded mark/space timings. It does not transmit or classify
  the signal.

Create either type from the blaster's **Remote type** selector. Legacy creation
requests also work, e.g. `doorbell|remote-button|Doorbell` and
`lamp|remote-generic|IR lamp`. For a button, Settings learning uses `token|press`.
Existing user-assigned child names are retained.

Maintainers with access to the registered `againmusic09479` namespace can update
the creation/learning capabilities and install:

```powershell
./capabilities/register-tv-ui.ps1
smartthings edge:drivers:package . --install
```

See the [AC protocol catalog](docs/ac-catalog.md) for its 91 protocol/model
choices and the [coverage review](docs/ac-protocol-coverage.md) for remaining
raw-only formats. The former standalone encoder choices have been removed;
existing saved selections migrate to the closest generated catalog variant.

## Hardware compatibility

Seven manufacturer-specific fingerprints match the listed TS1201 manufacturer
strings and model. A generic fallback matches profile `0x0104` and server
clusters `0xED00`, `0xE004`, and `0x0001` without checking manufacturer/model.
Either match is only a candidate, not proof that every TS1201, Moes, or Zosung
hardware revision works. No AC protocol/model choice should be treated as
hardware-verified from its presence in the selector alone. Record the exact hub,
blaster, appliance and remote models when reporting a successful check. See the
[release checklist](docs/public-release.md).
