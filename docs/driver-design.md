# Driver design and requirements

Status: design contract and incremental implementation plan. The current package does **not** control an IR blaster yet. See [README](../README.md) for implemented pieces.

## Goal and device model

One Zigbee TS1201 IR blaster is the **parent**. Each TV, AC, fan, or generic remote is a separate SmartThings **child device** with its own profile, name, learned codes/configuration, and Routine target. The parent owns the Zigbee radio and schedules IR transmissions. A child never sends Zigbee directly.

| Profile | IR behavior | User-facing controls | Setup data |
| --- | --- | --- | --- |
| `ir-blaster` parent | Hardware transport and learning | Create/manage remotes, learning status | Blaster endpoint and pending capture |
| `remote-tv` | Learned independent commands | Power, volume, channel, navigation, digits | Named button-to-code mapping |
| `remote-fan` | Learned independent commands | Power, speed, oscillation, timer | Named button-to-code mapping |
| `remote-generic` | Learned independent commands | A few named actions | Named button-to-code mapping |
| `ac-button` | Learned independent button presses | Relative temp ±, mode next, fan next, power | Button-to-code mapping; no asserted numeric AC state |
| `ac-learned-state` | Stored complete-state frames | Power, mode, setpoint, fan, swing | State-key-to-code mapping; missing states block transmission |
| `ac-protocol` | Generated complete-state frames | Power, mode, setpoint, fan, swing | Protocol family, remote/model variant, encoder options |

Profiles stay distinct after setup. An AC profile is a command model, not just a visual theme. A child may later have alternate presentations without changing its IR model. Removing a child must release its code/configuration records; removing the parent removes its children under SmartThings parent/child semantics.

## Setup in the SmartThings app

Edge profiles and capabilities determine the device detail UI; preferences are edited under Settings. Edge does not provide a general arbitrary multi-page wizard. The intended setup uses parent controls and child Settings, with a separate companion UI only if the app's capability presentation proves insufficient. Do not represent the sketches below as an existing native wizard.

1. Pair or switch a supported TS1201 to this development driver. Verify its manufacturer/model, Zigbee endpoints, and clusters before assuming it is compatible.
2. On the parent, request a new remote with a name and one of the profiles above. The driver creates an `EDGE_CHILD` with a stable unique key and the selected profile. The interim implementation uses a single Settings request string of `unique-token|profile|name` (for example `bedroom|ac-protocol|Bedroom AC`); change the token for each new child. The target UI is a custom capability action with separate fields.
3. Open the child. For a learned-button profile, choose an action to learn, point the original remote at the TS1201, start capture, then press the original button. Store the captured code on that child and test playback. Relearn replaces that action only.
4. For `ac-learned-state`, select supported modes, temperature interval, fan/swing options, then learn each needed complete state. Show missing combinations and progress. Refuse a state not learned rather than sending a nearby frame.
5. For `ac-protocol`, select a **working encoder and explicit variant/model**. Show only controls that encoder supports. Test power on/off and a few state changes while the original remote and AC are available. A broad protocol catalog is for discovery, not a promise of compatibility.
6. Delete a child using the SmartThings device management UI. Never use a hidden `MAIN/TV1/AC1` selector inside the parent.

Creating a child must be idempotent across retries and restarts. A request is accepted once, gets a stable key, and is reconciled against existing children. An unsupported profile or duplicate request is rejected with a visible status. Learning is exclusive per parent: one pending `{child key, action/state key}` at a time, with a timeout and explicit cancellation. A capture must have bounded length and valid chunk checksums before persistence.

## AC state and Routines

The protocol and learned-state children maintain **desired/last-commanded state**, not physical feedback. The core fields are `power`, `mode`, integer Celsius `temperature`, `fan`, `swing_vertical`, `swing_horizontal`. An encoder declares supported values and range; unsupported combinations fail before changing desired state.

Routine actions should use standard `switch`, thermostat mode, cooling/heating setpoint, and fan capabilities where their semantics fit. Use custom capabilities for swing and an **atomic full-state command** if SmartThings' automation presentation can expose it. Verify every action in the mobile Routine editor; a YAML capability alone is insufficient proof. Commands from one Routine may arrive separately and without transaction boundaries, so a short coalescing window reduces intermediate transmissions but cannot guarantee atomicity. The dedicated full-state action updates all requested fields in one command and sends one final frame.

The controller validates a proposed state, encodes it, queues the resulting one or more frames, and commits/publishes the desired state only after the transport accepts the request. On restart, restore the saved desired state without automatically retransmitting. Power-off behavior, previous-state dependencies, repeats, and long frame gaps are encoder-specific. Do not claim the AC changed state without a return channel.

## IR pipeline and data ownership

`child capability command → child controller → code lookup or AC encoder → raw mark/space timings → Zosung timing payload → parent Zigbee 0xED00 transfer → IR`

The TS1201 transfer uses 0xED00 command 00 to announce an encoded message, responds to device chunk requests (02) with checked pieces (03), and completes via 04/05. Learning uses 0xE004 control and receives a bounded multi-chunk code through the reverse sequence. Keep a separate sequence, timeout, and queue for each physical parent. A child's persisted fields contain its configuration and learned codes; transfer buffers remain transient. The parent serializes access because learning and transmitting cannot safely share the same device session.

The currently implemented codec handles base64 timing encoding, send/receive session primitives, raw Zosung command payload serialization, and a per-parent transfer controller with timeout and learning cancellation. The SmartThings Zigbee address/ZCL adapter and dispatch, scheduling of expiry checks, queueing, persistence, and hardware behavior still require implementation and tests.

## Protocol catalog

The catalog can list every candidate in IRremoteESP8266, but only registered, tested Lua encoders appear as selectable `ac-protocol` choices. Each encoder declares its family, variant, supported state space, carrier, timings, special frame sequences, and whether previous state matters. Record upstream source version and license notices for ports. Sources and their distinct roles are in [protocol-sources.md](protocol-sources.md).

## Acceptance checks

- Pair a supported TS1201; create two independently named children with different profiles; restart and retain both; remove one without altering the other.
- Learn and replay a TV command; reject wrong sequence, checksum, oversize capture, simultaneous learning, and transfer timeout.
- For `ac-button`, relative actions send learned commands and never assert a numeric setpoint.
- For `ac-learned-state`, a covered state sends exactly its stored frame; an uncovered state sends nothing.
- For `ac-protocol`, compare generated frames to upstream fixtures and original remote captures, including on/off, mode, fan, swing, min/max temperature and unsupported values.
- In the SmartThings Routine editor, confirm separate temperature, mode, fan, swing, and power actions, and an atomic state action if the custom presentation is supported. A multi-action Routine should send only its final state when coalesced; its order-independent semantics must be documented where coalescing cannot guarantee that.
- Test parent and child deletion, hub/driver restart, repeated creation requests, queue overflow, and failed Zigbee delivery.

## Implementation stages

1. **Package and model:** profiles, child lifecycle, desired state, persistence. The parent scaffold and pure state model are present; child lifecycle is next.
2. **Transport:** Edge Zigbee message adapter around the tested Zosung primitives, learning, serialization queue, timeouts, integration tests, physical TS1201 smoke test.
3. **Learned remotes:** TV/fan/generic and `ac-button`; guided `ac-learned-state` with coverage checks.
4. **AC protocol:** encoder registry, model selection, ports with fixtures, Routine-compatible capabilities/presentations, physical AC verification. This is a core release requirement, not a deferred optional enhancement.

## Platform references

- [Edge profiles and package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Device preferences](https://developer.smartthings.com/docs/devices/preferences)
- [Child creation API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Capability presentations and Automations](https://developer.smartthings.com/docs/devices/capabilities/capability-presentations)
- [Zosung converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
