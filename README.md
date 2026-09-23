# SmartThings Generic IR Remote

An in-progress SmartThings Edge driver for TS1201 (Moes/Zosung) IR blasters. Each logical remote is intended to be an Edge child device. AC children have separate button-based, learned-state, and protocol-based profiles.

## Status

This repository currently contains the AC state engine, TS1201 send-side timing/packet primitives, and the Edge package scaffold. **It is not yet installable or able to transmit IR.** The TS1201 Zigbee message integration and receive/learning handler, child creation controls, custom capability definitions, and a verified encoder for a specific AC protocol are still required. In particular, a Galaxy Home Mini controlling an AC does not identify the manufacturer's IR protocol or expose its encoded frames.

## AC protocol behavior

`src/ac/state.lua` maintains a complete desired state: power, mode, temperature, fan, and vertical/horizontal swing. A command applies a validated patch atomically. The transport should encode and transmit the resulting complete state, never a relative temperature command. SmartThings Routines should ultimately expose individual settable capabilities for power, mode, temperature, fan, and swing, plus one full-state command for atomic multi-field actions. Separate Routine commands should be coalesced briefly before encoding, with a generation counter to discard stale timers. State is desired/last transmitted state, not measured room or AC state.

An encoder is registered per supported AC protocol. Unknown protocols must fail closed: no guessed frame should be sent. On restart, restore the desired state without automatically replaying it. Before committing a new state, validate that the configured encoder supports the requested mode, temperature, fan, and swing combination.

## Next implementation gates

1. Implement and test Zosung TS1201 transfer, including chunk requests, CRC, sequence isolation, timeout, and learning, against the [Zigbee2MQTT converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts).
2. Add parent controls to create child devices with a chosen profile, and persist child-specific configuration and state. Removal through SmartThings must clean up stored data.
3. Define and register custom SmartThings capabilities/presentations where standard capabilities cannot expose Routine actions. Verify available actions in the mobile app; the Edge profile alone does not guarantee an action is shown.
4. Identify the user's AC model and protocol. Implement a verified encoder and compare generated frames with captured original-remote frames before allowing transmission.
5. Package through the SmartThings CLI, install to a development channel and test on the physical hub/blaster/AC.

## References

- [SmartThings Edge package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Edge child-device API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Edge integration tests](https://developer.smartthings.com/docs/devices/hub-connected/test-your-driver)
- [Zigbee2MQTT Zosung TS1201 converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
