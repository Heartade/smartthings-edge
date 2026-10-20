# Implementation plan

This is the outstanding work required to turn the current development scaffold into a usable SmartThings IR remote. Tasks are ordered by dependency. A feature is not complete until its code, automated checks, and applicable SmartThings or hardware acceptance checks pass. See [driver design](driver-design.md) for the behavior contract and acceptance criteria.

## 1. Confirm device compatibility and finish child lifecycle

- [ ] Test a TS1201 on a development hub. Record its manufacturer/model values, endpoints, server clusters, and relevant command framing; confirm the existing `0xED00` and `0xE004` fingerprint matches the intended hardware.
- [ ] Tighten device matching to the verified TS1201 identity and reject unsupported variants with useful diagnostics.
- [ ] Reconcile child creation requests against existing children and persisted configuration so retries and driver restarts do not create duplicates or lose each child's selected profile and name.
- [ ] Persist each child's configuration and learned-code records under that child; define how the parent tracks its child keys.
- [ ] Handle child creation errors, duplicate keys, invalid profile names, and invalid labels with status the user can see in the app, rather than only a driver log entry.
- [ ] Verify deleting one child removes only its stored data, and verify parent deletion follows SmartThings parent/child behavior.
- [ ] Replace or deliberately retain the interim `unique-token|profile|name` parent preference after evaluating whether a custom capability/presentation can provide a usable child-creation control.
- [ ] Add lifecycle coverage for repeated requests, duplicate display names, retries after restart, invalid requests, and deletion/cleanup.

## 2. Connect Zosung primitives to Edge Zigbee

- [x] Add a SmartThings Zigbee adapter that serializes outgoing `0xED00` and `0xE004` commands, decodes incoming `0xED00` messages, and dispatches them to the existing controller API.
- [ ] Verify sequence numbers, byte order, payload lengths, endpoints, checksums, and command framing against captures from the target TS1201.
- [x] Route TV, fan, and generic child power learning/playback through the physical parent and keep one active transfer per parent.
- [ ] Extend parent routing and serialization to AC and other profile command paths as they are implemented.
- [ ] Add a bounded per-parent queue with explicit behavior for duplicate requests, queue overflow, failed delivery, and device removal.
- [ ] Schedule and cancel transfer expiry checks using the Edge runtime timer API; ensure expired sends and learning sessions clear their transient state and report a useful result.
- [ ] Surface progress, completion, cancellation, malformed frames, and timeout failures to the appropriate parent/child status or logs.
- [ ] Add SmartThings integration tests for send start/chunk/ack/completion, receive start/chunk/completion, bad sequence/checksum, oversize data, timeout, cancellation, queue contention, and failed Zigbee delivery.
- [ ] Verify one send and one learning session on the physical TS1201 before building child controls on top of the adapter.

## 3. Implement learned-button remotes

- [x] Define a validated, bounded persisted format for each child's `power_on` and `power_off` capture; keep transfer buffers and active sessions transient.
- [x] Implement TV, fan, and generic child switch handlers that look up the exact saved power action, route it through the parent controller, and refuse to send when the code is missing.
- [x] Add child Settings requests to start/cancel `power_on` or `power_off` capture; save a completed capture on its owning child and expire an abandoned session.
- [ ] Surface learning progress, completion, cancellation, timeout, and send failures in the SmartThings app rather than only through logs.
- [ ] Add named button actions beyond the two switch power commands, plus relearn and delete controls in the app.
- [ ] Implement `ac-button` as independent learned button presses; do not publish numeric AC state for relative button commands.
- [x] Add mocked tests for power-action capture, persistence, cancellation, timeout, switch playback, missing-code rejection, per-child isolation, and bounded code validation.
- [ ] Verify learned codes survive a SmartThings driver restart and reject corrupted records in the Edge runtime.

## 4. Complete AC state and learned-state control

- [ ] Define the persisted desired-state lifecycle for power, mode, integer Celsius setpoint, fan, and vertical/horizontal swing. Validate a proposed full state before saving or publishing it.
- [ ] Ensure restart restores desired state without retransmitting automatically, and only commit/publish a new state after the transport accepts the send request.
- [ ] Add the `ac-learned-state` setup and learning flow: choose the supported dimensions, capture complete-state frames, and show coverage and missing combinations.
- [ ] Resolve a requested state only to an exact learned frame. Refuse transmission for every uncovered combination; do not silently substitute a nearby setting.
- [ ] Define cleanup and update behavior when a learned state is replaced, removed, or its child is deleted.
- [ ] Test state validation, persistence, exact frame lookup, missing-state rejection, restart behavior, and state/code cleanup.

## 5. Register and verify AC protocol encoders

- [ ] Select a concrete AC make/model and identify its protocol, remote variant, and power-on/off behavior from reliable documentation and original-remote captures.
- [ ] Add an encoder only after its supported modes, temperature range, fan/swing values, carrier, timing format, frame sequence, and previous-state dependencies are known.
- [ ] Port the encoder into the Lua registry, record upstream source/version and required license notices, and fail closed for unknown models or unsupported state combinations.
- [ ] Add fixtures from upstream references and captured original-remote frames. Compare generated timings/frames byte for byte or with a documented protocol-aware comparison.
- [ ] Test minimum/maximum temperatures, every supported mode/fan/swing value, power transitions, state-dependent sequences, and unsupported values.
- [ ] Verify generated commands against the original remote and target AC on physical hardware before making the encoder selectable.
- [ ] Do not present an unverified protocol family or guessed variant as supported.

## 6. Complete SmartThings commands and Routine actions

- [x] Connect TV, fan, and generic child switch `on`/`off` commands to their captured power actions and emit switch state only after the transfer completes.
- [ ] Connect child capabilities to the state/learned-code controllers and implement handlers for every command shown by each child profile.
- [ ] Confirm standard switch, thermostat mode, cooling/heating setpoint, and fan capabilities have semantics that match the selected encoder; use custom capabilities for unsupported standard actions such as swing.
- [ ] Define and register capability presentations needed for swing and, if the app supports it, a single atomic full-state action.
- [ ] Inspect each child in the SmartThings mobile app and verify each intended control appears in the Routine editor and invokes the expected handler.
- [ ] Coalesce separate Routine commands with a bounded delay where appropriate; use a generation counter to discard stale callbacks and document that separate Routine actions are not guaranteed to be atomic.
- [ ] Validate all state combinations before changing desired state or queuing an IR frame; report unsupported settings visibly and send nothing.
- [ ] Verify commands from the app and Routines update only desired/last-commanded state; do not imply physical feedback from the AC.

## 7. End-to-end verification and release readiness

- [ ] Run all standalone Lua checks and SmartThings integration tests after implementing the feature paths.
- [ ] Package the driver with the SmartThings CLI, install it through a development channel, and verify pairing, logs, child creation, restart persistence, and deletion on a real hub.
- [ ] Exercise every profile on the physical blaster. For AC profiles, confirm emitted commands against captured originals and verify resulting behavior on the target AC.
- [ ] Repeat reliability scenarios: repeated child creation, driver/hub restart, learning cancellation, transfer timeout, queue overflow, failed Zigbee delivery, and parent/child removal.
- [ ] Update the README status and supported-device/model list only after the corresponding checks pass; document any remaining limitations and exact verified hardware/software versions.

The detailed acceptance checks are in [driver design](driver-design.md#acceptance-checks). Do not describe the driver as a working IR remote until the transport, at least one end-to-end learned command, and a verified AC control path have passed on target hardware.
