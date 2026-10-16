# SmartThings Generic IR Remote

An in-progress SmartThings Edge driver for TS1201 (Moes/Zosung) IR blasters. Each logical remote is intended to be an Edge child device. AC children have separate button-based, learned-state, and protocol-based profiles.

## Status

The repository contains an AC state engine and encoder registry, a learned-state code table, TS1201 send/receive payloads and a per-parent transfer controller, and a minimal Edge package with parent/child profiles. The parent Settings page has an interim `unique-token|profile|name` field that requests a child device (for example `bedroom|ac-protocol|Bedroom AC`). **The driver is not yet functional as an IR remote:** Zigbee message integration, guided learning, Routine presentations, and a verified AC protocol encoder remain to be implemented. Packaging and pairing have not been verified; child controls do not transmit IR. A Galaxy Home Mini controlling an AC does not identify its IR protocol or expose its frames.

See [the driver design](docs/driver-design.md) for the intended behavior and acceptance checks, [the implementation plan](docs/implementation-plan.md) for the remaining work, and [protocol sources](docs/protocol-sources.md) for encoder references.

## How to run

Run commands from the repository root.

### Run the local Lua checks

Install a Lua interpreter, then run the standalone checks individually:

```sh
lua tests/ac_state.lua
lua tests/ac_registry.lua
lua tests/ac_learned_state.lua
lua tests/children.lua
lua tests/edge_lifecycle.lua
lua tests/ir_controller.lua
lua tests/zosung.lua
lua tests/zosung_wire.lua
```

These scripts exercise the current state, child-request, and Zosung codec/controller code. They do not test the SmartThings runtime or physical hardware.

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

The current package is a development scaffold. Its parent refresh handler only logs that transport integration is pending; the child request setting can create child metadata, but child controls do not send IR. Pairing and package installation are not yet verified. See the [implementation plan](docs/implementation-plan.md) before treating any feature as complete. For the full driver workflow, see the official [Edge driver packaging and deployment guide](https://developer.smartthings.com/docs/devices/hub-connected/edge-architecture) and [driver channel guide](https://developer.smartthings.com/docs/devices/hub-connected/driver-channels).

## References

- [SmartThings Edge package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Edge child-device API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Edge integration tests](https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver)
- [Zigbee2MQTT Zosung TS1201 converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
