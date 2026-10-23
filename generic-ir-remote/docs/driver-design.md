# Driver behavior and verification

This document describes the current implementation. It is not a claim that each
feature has passed a physical SmartThings hub check. See the
[implementation status](implementation-plan.md) and
[public release checklist](public-release.md) for outstanding verification.
AC catalog scope is described in the [catalog guide](ac-catalog.md).

## Device model and active profiles

One Zigbee IR blaster is the physical **parent**. Each logical remote is a
SmartThings **child** with its own profile, name, saved signals/configuration,
and device page. The parent owns Zigbee communication and serializes IR
operations. A child routes requests through its parent.

| Profile | Behavior | Controls in the profile | Signal setup |
| --- | --- | --- | --- |
| `ir-blaster` parent | Physical Zosung transport | Battery, remote creation, learning/transfer status | Create child request and parent transfer state |
| `remote-tv` | Learned TV signals | Switch, native `keypadInput`, learning card | Separate saved signal for each supported action |
| `remote-fan` | Learned power actions | Switch, learning card | `power_on` and `power_off` |
| `remote-generic` | Generic IR switch | Switch, learning card | `power_on`, `power_off`, and `power_toggle` fallback |
| `remote-button` | Stateless generic button | `momentary.push`, learning card | One `press` signal |
| `ac-learned-state` | Exact learned full-state frames | AC controls, protocol/model selector, setup and learning cards | Capture complete AC states |
| `ac-protocol` / `ac-protocol-generated` | Generated full-state frames | AC controls and protocol/model selector | No learning capability |
| `ac-protocol-learning` | Generated or learned full-state frames | AC controls, protocol/model selector, setup and learning cards | Use learning when **Learn AC states** is selected |

The `ac-button` profile exists in the repository but is not offered during child
creation. The old custom TV capability resources are also retained but are not
attached to an active profile; the TV page uses SmartThings' native keypad.

## App setup

1. Pair a Zigbee device matching one of the seven TS1201 manufacturer/model
   fingerprints, or the generic fallback's profile/cluster signature. A match
   is not proof that every hardware revision works.
2. Open the parent device page, choose **Remote type**, enter **Remote name**,
   and tap **Create remote**. The parent reports the creation result and adds a
   child. Legacy Settings requests remain supported for compatibility.
3. On a TV, fan, or generic switch child, use the learning card to choose an
   action and learn it from the original remote. TV uses the native keypad for
   navigation/keys; the learning card can also capture and test other listed
   signals. Fan and generic switch children learn power actions. Generic IR
   button children learn `press` and replay it with **Push**.
4. On a learned-state AC child, choose **Learn AC states** in the combined
   protocol/model selector. Enable **Edit capture state without sending**, set
   power/mode/temperature/fan/swing to match the original remote, and capture
   that complete state. The driver sends a saved frame only for an exact state
   match; an uncovered state should be rejected.
5. On a generated AC child, select one protocol/model entry, such as
   `LG2 2: AKB75215403`. The protocol/model label is a generated upstream variant
   identifier, not a model number inferred from the indoor unit. A selection
   hides learning controls when its profile supports learning. Listed choices
   are experimental until checked with the actual AC and blaster.

The app may group status and command cards or render native capabilities
differently across versions. Check the current app's presentation and Routine
editor as part of release verification. GUI status messages and switch/AC state
are not appliance feedback.

## State and transmission behavior

AC protocol and learned-state children maintain desired/last-commanded state:
power, mode, integer Celsius temperature, fan, and vertical/horizontal swing.
The generated catalog limits the available modes, temperatures, and swing
directions per choice. Unsupported combinations must fail before transmission.
See the [AC catalog](ac-catalog.md) for domain details and known limits.

The AC screen uses one target-temperature control for heating and cooling.
SmartThings' native AC modes include dry mode, translated as **제습** in Korean.
The GUI may convert the displayed temperature unit; learned-state Settings
requests use Celsius.

Switch and AC events represent assumed, desired, or last-commanded state. A
successful IR transfer confirms that the blaster completed its transfer, not
that the TV, fan, or AC received or obeyed the signal. Using the original remote
can desynchronize the driver's assumed state. IR has no return channel.

The parent owns one active transfer/learning operation at a time. A second
request can report busy while that operation is active. Captured signals and
child configuration belong to the requesting child; active transport buffers
are transient. Verify persistence, timeout cleanup, cancellation, and child
removal on the target hub before relying on them in a public release.

## Transport path

`child command → child handler → saved signal or AC encoder → raw mark/space timings → Zosung payload → parent Zigbee transfer → IR`

The driver builds typed ZCL messages for the Zosung send/receive flow using
clusters `0xED00` and `0xE004`. The standard Zigbee Power Configuration cluster
`0x0001`, attribute `0x0021`, supplies the physical parent's battery reading.
The driver refreshes and configures reporting through the Zigbee battery
defaults. Seven fingerprints match exact TS1201 manufacturer/model pairs; a
generic fallback checks profile `0x0104` and the three server clusters without
checking model identity. One listed variant is reported to have no battery. See
[SmartThings implementation quirks](implementation-quirks.md) for SDK and
packaging constraints encountered during development.

## Verification checklist

For a release candidate, verify these behaviors against the exact packaged
source revision. The complete checklist and recording fields are in
[public release checklist](public-release.md).

- Pair the intended blaster and verify startup, state initialization, battery
  reporting, and command logs.
- Create multiple children, verify their profiles and names, restart the driver,
  and delete one without affecting another.
- Learn and replay a signal; verify cancel, timeout, malformed input, busy, and
  persistence behavior.
- Compare generated AC waveforms with the pinned upstream implementation, then
  test each advertised hardware combination called compatible against its
  original remote and physical AC.
- Check TV keypad, learning cards, AC selector/setup visibility, and Routine
  behavior in the current mobile app.

## Platform references

- [Edge profiles and package structure](https://developer.smartthings.com/docs/devices/hub-connected/driver-components-and-structure)
- [Device preferences](https://developer.smartthings.com/docs/devices/preferences)
- [Child creation API](https://developer.smartthings.com/docs/edge-device-drivers/driver.html)
- [Capability presentations and Automations](https://developer.smartthings.com/docs/devices/capabilities/capability-presentations)
- [Zosung converter reference](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts)
