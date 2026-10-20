# Driver design and requirements

Status: design contract with partial implementation. Power-action learning and AC complete-state control are implemented. AC children expose generated LG/LG2, Toshiba, Mitsubishi Electric, Gree, Kelvinator and Electra/AUX protocols through switch, AC mode, one temperature setpoint, fan and supported swing controls. There are 338 upstream waveform fixtures and official SDK serialization/capability tests. App-visible learning coverage/errors, Routine UI checks and physical AC validation remain outstanding. See [README](../README.md) and [additional protocol notes](added-ac-protocols.md).

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
3. For a TV, fan, or generic remote child, open Settings and set a fresh `token|power_on` or `token|power_off` request. Point the original remote at the TS1201 and press the matching power button. The capture is stored on that child; a new token relearns that action. Use `token|cancel` to stop an active capture. The child switch commands replay these two saved actions. Other named buttons remain planned.
4. For `ac-learned-state`, enter `token|on/off|mode|temp-C|fan|vertical-swing|horizontal-swing` in Settings, set the original remote to that complete state, and capture it. Repeat for each state you plan to use. Commands resolve only to an exact learned state; coverage visualization is not implemented yet.
5. For `ac-protocol`, select a compatible experimental remote variant from Settings. The [README model table](../README.md) lists ranges and swing support. Generated variants require no learned codes. The exact LG 6711A90006C remote remains unmapped.
6. Delete a child using the SmartThings device management UI. Never use a hidden `MAIN/TV1/AC1` selector inside the parent.

Creating a child must be idempotent across retries and restarts. A request is accepted once, gets a stable key, and is reconciled against existing children. An unsupported profile or duplicate request is rejected with a visible status. Learning is exclusive per parent: one pending `{child key, action/state key}` at a time, with a timeout and explicit cancellation. A capture must have bounded length and valid chunk checksums before persistence.

## AC state and Routines

The protocol and learned-state children maintain **desired/last-commanded state**, not physical feedback. The core fields are `power`, `mode`, integer Celsius `temperature`, `fan`, `swing_vertical`, `swing_horizontal`. An encoder declares supported values and range; unsupported combinations fail before changing desired state.

Routine actions should use standard `switch`, `airConditionerMode`, `temperatureSetpoint`, `fanMode` and `fanOscillationMode` capabilities. Use a custom capability for an **atomic full-state command** if SmartThings' automation presentation can expose it. Verify every action in the mobile Routine editor; a YAML capability alone is insufficient proof. Commands from one Routine may arrive separately and without transaction boundaries, so a short coalescing window reduces intermediate transmissions but cannot guarantee atomicity. The dedicated full-state action updates all requested fields in one command and sends one final frame.

The controller validates a proposed state, encodes it, queues the resulting one or more frames, and commits/publishes the desired state only after the transport accepts the request. On restart, restore the saved desired state without automatically retransmitting. Power-off behavior, previous-state dependencies, repeats, and long frame gaps are encoder-specific. Do not claim the AC changed state without a return channel.

## IR pipeline and data ownership

`child capability command → child controller → code lookup or AC encoder → raw mark/space timings → Zosung timing payload → parent Zigbee 0xED00 transfer → IR`

The TS1201 transfer uses 0xED00 command 00 to announce an encoded message, responds to device chunk requests (02) with checked pieces (03), and completes via 04/05. Learning uses 0xE004 control and receives a bounded multi-chunk code through the reverse sequence. Keep a separate sequence, timeout, and queue for each physical parent. A child's persisted fields contain its configuration and learned codes; transfer buffers remain transient. The parent serializes access because learning and transmitting cannot safely share the same device session.

The currently implemented codec handles base64 timing encoding, send/receive session primitives, raw Zosung command payload serialization, and a per-parent transfer controller with timeout and learning cancellation. The SmartThings adapter builds and sends raw ZCL messages, dispatches incoming `0xED00` commands, and schedules expiry checks. TV, fan, and generic children route two captured power actions through their physical parent and persist each code per child. AC children persist desired state, learn exact captured complete states, or select one of 11 generated protocol variants; power, AC mode, a shared heating/cooling setpoint, fan and supported swing commands route through the parent. A bounded queue, other named buttons, app-visible learning coverage/errors, SmartThings app checks and hardware verification remain outstanding.

## Protocol catalog

The profile currently offers registered experimental Lua encoders, so a selectable option is not proof of fixture or hardware verification. Each encoder declares its family, variant, supported state space, carrier, timings, special frame sequences, and whether previous state matters. Record upstream source version and license notices for ports. Sources and their distinct roles are in [protocol-sources.md](protocol-sources.md).

## Acceptance checks

- Pair a supported TS1201; create two independently named children with different profiles; restart and retain both; remove one without altering the other.
- Learn and replay a TV command; reject wrong sequence, checksum, oversize capture, simultaneous learning, and transfer timeout.
- For `ac-button`, relative actions send learned commands and never assert a numeric setpoint.
- For `ac-learned-state`, a covered state sends exactly its stored frame; an uncovered state sends nothing.
- For `ac-protocol`, compare generated frames to upstream fixtures and original remote captures, including on/off, mode, fan, swing, min/max temperature and unsupported values.
- In the SmartThings Routine editor, confirm separate temperature, mode, fan, swing, and power actions, and an atomic state action if the custom presentation is supported. A multi-action Routine should send only its final state when coalesced; its order-independent semantics must be documented where coalescing cannot guarantee that.
- Test parent and child deletion, hub/driver restart, repeated creation requests, queue overflow, and failed Zigbee delivery.

## Platform references

- [Edge profiles and package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Device preferences](https://developer.smartthings.com/docs/devices/preferences)
- [Child creation API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Capability presentations and Automations](https://developer.smartthings.com/docs/devices/capabilities/capability-presentations)
- [Zosung converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
