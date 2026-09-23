# SmartThings Generic IR Remote

An in-progress SmartThings Edge driver for TS1201 (Moes/Zosung) IR blasters. Each logical remote is intended to be an Edge child device. AC children have separate button-based, learned-state, and protocol-based profiles.

## Status

The repository contains an AC state engine and encoder registry, a learned-state code table, TS1201 send/receive and command-payload primitives, and a minimal Edge package with parent/child profiles. The parent Settings page has an interim `unique-token|profile|name` field that requests a child device (for example `bedroom|ac-protocol|Bedroom AC`). **Packaging and pairing have not been verified; child controls do not transmit IR.** Zigbee message integration, guided learning, Routine presentations, and a verified AC protocol encoder remain to be implemented. A Galaxy Home Mini controlling an AC does not identify its IR protocol or expose its frames.

Read [the driver design](docs/driver-design.md) for profiles, setup, features, requirements, and acceptance checks. [Protocol sources](docs/protocol-sources.md) covers encoder references.

## AC protocol behavior

`src/ac/state.lua` maintains a complete desired state: power, mode, temperature, fan, and vertical/horizontal swing. A command applies a validated patch atomically. The transport should encode and transmit the resulting complete state, never a relative temperature command. SmartThings Routines should ultimately expose individual settable capabilities for power, mode, temperature, fan, and swing, plus one full-state command for atomic multi-field actions. Separate Routine commands should be coalesced briefly before encoding, with a generation counter to discard stale timers. State is desired/last transmitted state, not measured room or AC state.

An encoder is registered per supported AC protocol. Unknown protocols must fail closed: no guessed frame should be sent. On restart, restore the desired state without automatically replaying it. Before committing a new state, validate that the configured encoder supports the requested mode, temperature, fan, and swing combination.

## Next implementation gates

1. Wire the tested Zosung send/receive primitives to Edge Zigbee messages; add transport timeout and learning control, against the [Zigbee2MQTT converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts).
2. Validate the child creation flow on a hub; add persistent child configuration and cleanup on removal, then replace the interim Settings request with a better control.
3. Define and register custom SmartThings capabilities/presentations where standard capabilities cannot expose Routine actions. Verify available actions in the mobile app; the Edge profile alone does not guarantee an action is shown.
4. Identify the user's AC model and protocol. Implement a verified encoder and compare generated frames with captured original-remote frames before allowing transmission.
5. Package through the SmartThings CLI, install to a development channel and test on the physical hub/blaster/AC.

## References

- [SmartThings Edge package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Edge child-device API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Edge integration tests](https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver)
- [Zigbee2MQTT Zosung TS1201 converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
