# Implementation status and release checks

This page describes the current source tree and the work needed before a
versioned public driver release. It replaces the original feature plan, whose
counts and unchecked tasks no longer matched the implementation. Source-level
presence and automated tests do not establish that SmartThings renders the
controls correctly or that a physical device responds. See the
[public release checklist](public-release.md) for the evidence to record.

## Present in the source

- A Zigbee parent profile with custom remote creation UI and standard battery
  capability. Battery defaults read/report Power Configuration cluster `0x0001`,
  attribute `0x0021`; the driver refreshes and configures those attributes.
- Child profiles for TV, fan, generic IR switch, generic IR button, learned-state
  AC, protocol-only AC, and protocol AC with learning. The `ac-button` profile
  is not offered by the child-creation UI.
- Parent-owned Zosung transfer and receive paths for `0xED00`/`0xE004`, with
  learning, cancellation, transfer status, and one active operation per parent.
- TV keypad integration with learned actions; ordinary power-action learning;
  a stateless push action for generic IR buttons; and switch state that records
  an assumed or last-commanded value.
- AC exact-state learning and a generated catalog covering 66 common
  IRremoteESP8266 identifiers and 91 protocol/model selector choices. The AC UI
  uses one temperature control, mode, fan, and supported swing controls. Old
  stored AC selections have migration logic.
- Custom capability definitions and presentations, including Korean and English
  translations. The active profiles use registered IDs in the
  `againmusic09479` namespace. See the [capability guide](../capabilities/README.md)
  before registering or changing account resources.

These are implementation facts, not release test results. Check behavior in the
exact build being published.

## Still needs release evidence

- [ ] Run the standalone Lua checks and the SmartThings SDK checks in the
  [README](../README.md) against the release commit. Record runtime/SDK versions
  and results. If a check cannot run, identify it as unverified.
- [ ] Build the SmartThings Edge ZIP with the supported CLI and confirm it is
  no larger than 655,360 bytes. Keep source and license materials outside the
  ZIP; see [public release and distribution](public-release.md#source-notices-and-the-smartthings-zip).
- [ ] Install the exact build on a development hub and record hub model, driver
  version, app version, blaster model/revision, endpoints, clusters, startup
  logs, and command logs.
- [ ] Verify pairing, startup/state initialization, battery reporting, child
  creation, deletion, restart persistence, and existing-child profile
  migration.
- [ ] Verify a learned signal from an original remote and its replay to a target
  appliance. Record which remote button and target model were used.
- [ ] Verify each AC variant that release notes call hardware-compatible on a
  physical AC. Record indoor-unit model, original remote model, exact selector
  option, states tested, and result. Other selector choices remain experimental.
- [ ] Check current mobile app rendering and Routine behavior for TV keypad,
  learning cards, AC model selection, and AC controls.
- [ ] Check timeout, malformed frame, cancellation, concurrent request, hub
  restart, and parent/child removal behavior on hardware where applicable.
- [ ] Publish the Edge ZIP separately from the exact tagged public source,
  notices, and licenses. State untested areas in the release notes.

## Scope and support language

Seven manufacturer-specific fingerprints match the supplied TS1201 pairs. A
generic fallback matches profile `0x0104` and server clusters `0xED00`, `0xE004`,
and `0x0001`, without checking manufacturer/model. Neither path proves that
every TS1201/Moes/Zosung revision works. One listed manufacturer variant,
`_TZ3290_7v1k4vufotpowp9z`, is reported to have no battery.

The AC catalog's counts describe the encoders exposed by the selector. A
generated waveform comparison is not the same as capturing a matching remote
or observing the intended AC respond. Model compatibility is specific to the
indoor unit and original remote; the brand name alone is insufficient. AC
switch and state events report last-commanded/desired state, not physical
feedback.

The driver depends on SmartThings custom capabilities owned by the
`againmusic09479` namespace. The checked-in registration script updates those
registered resources and includes owner-specific IDs. Driver users should
install a published build without running the registration script. A fork must
register and consistently substitute its own IDs before using that script.

For the Edge ZIP, do not embed a source archive, license files, or third-party
notices. Publish a link to the exact tagged source and its license/notice files
as separate public release materials. See [LICENSE.md](../../LICENSE.md) and
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
