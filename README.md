# SmartThings Generic IR Remote

An in-progress SmartThings Edge driver for TS1201 (Moes/Zosung) IR blasters. Each logical remote is intended to be an Edge child device. AC children have separate button-based, learned-state, and protocol-based profiles.

## Status

The repository contains an AC state engine and encoder registry, a bounded learned power-action store, TS1201 send/receive payloads, and a SmartThings Edge adapter with per-parent transfer locking and expiry handling. TV, fan, and generic remote children can learn `power_on`/`power_off` from their Settings page and send those captured codes from their switch commands. **The driver is still in development:** child learning/transport status is primarily in logs, other named remote buttons are not implemented, AC control and Routine presentations are incomplete, and no transfer or encoder has been verified on physical hardware. Packaging and pairing have not been verified. A Galaxy Home Mini controlling an AC does not identify its IR protocol or expose its frames.

See [the driver design](docs/driver-design.md) for the intended behavior and acceptance checks, [the implementation plan](docs/implementation-plan.md) for the remaining work, and [protocol sources](docs/protocol-sources.md) for encoder references.

## How to run

Run commands from the repository root.

### Run the local Lua checks

Install a Lua 5.3 interpreter, then run the standalone checks individually:

```sh
lua tests/ac_state.lua
lua tests/ac_registry.lua
lua tests/ac_learned_state.lua
lua tests/children.lua
lua tests/edge_lifecycle.lua
lua tests/edge_child_control.lua
lua tests/ir_controller.lua
lua tests/edge_zigbee.lua
lua tests/ir_learned_actions.lua
lua tests/zosung.lua
lua tests/zosung_wire.lua
```

These scripts exercise the state, child-request, Zosung codec/controller, learned-action store, and mocked Edge adapter/child command paths. They do not test the SmartThings runtime or physical hardware.

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

The parent receives Zosung `0xED00` messages and runs one transfer at a time. For a TV, fan, or generic remote child, open its Settings and set **Learn or cancel a power action** to a new value such as `on-001|power_on` or `off-001|power_off`; point the original remote at the blaster during capture. Use a new token for every request. Set a new `<token>|cancel` value to cancel learning. After capture, the child's switch `on` and `off` commands send only the matching saved code. Its switch state records a completed blaster transfer; it does not confirm that the TV or fan responded. AC controls remain unimplemented, and the supported-device, transfer, and package flows need validation on a development hub. See the [implementation plan](docs/implementation-plan.md) before treating any feature as complete. For the full driver workflow, see the official [Edge driver packaging and deployment guide](https://developer.smartthings.com/docs/devices/hub-connected/edge-architecture) and [driver channel guide](https://developer.smartthings.com/docs/devices/hub-connected/driver-channels).

### Physical smoke test: learn and send a TV power code

This first hardware check assumes a TS1201-compatible Zigbee IR blaster, a SmartThings hub that supports Edge drivers, a TV, and the TV's original IR remote. Keep the remote and blaster close together for learning, then aim the blaster's IR emitter at the TV. The current fingerprint matches Zigbee profile `0x0104` devices that report server clusters `0xED00` and `0xE004`; a different hardware revision may not match.

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

- [SmartThings Edge package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Edge child-device API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Edge integration tests](https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver)
- [Zigbee2MQTT Zosung TS1201 converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
