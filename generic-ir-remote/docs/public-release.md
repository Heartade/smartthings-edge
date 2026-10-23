# Public release checklist

This project is an experimental SmartThings Edge driver. A public source release
can be useful before every device has been verified, but describe it as
experimental until the release checks below have evidence for the exact source
revision being published. The 66 AC protocol identifiers and 91 selector choices
describe generated encoder coverage; they do not mean 91 appliance models have
been verified in a room.

## What the current checkout supports

- Seven manufacturer-specific fingerprints match the supplied TS1201 pairs.
  A generic fallback also matches profile `0x0104` devices reporting server
  clusters `0xED00`, `0xE004`, and `0x0001`, without a manufacturer/model check.
  Neither path certifies every TS1201/Moes/Zosung revision.
- The physical parent exposes the blaster's battery level. Child remotes share
  that hardware and transfer controller.
- The `_TZ3290_7v1k4vufotpowp9z` TS1201 variant is reported to have no battery;
  it cannot provide a battery percentage ([device note](https://community.smartthings.com/t/edge-moes-smart-ir-remote-control/271782)).
- TV remotes provide the native SmartThings keypad, switch power control, and a
  learning card for separately captured signals. Fan remotes currently provide
  learned power actions. Generic IR switch has assumed On/Off state; generic IR
  button is stateless. AC children use either exact learned full-state frames or
  the generated protocol/model selector. `ac-button` is not offered in the
  creation UI.
- Protocol selection and waveform comparisons are software evidence only. AC
  commands, IR reception, Zigbee pairing, mobile rendering, Routines, child
  lifecycle and battery reports still need checks on the target hub and hardware.
- Device state is last commanded or desired state. Transfer completion does not
  confirm that an appliance received or obeyed an IR signal.

See [AC catalog coverage and limits](ac-catalog.md),
[protocol coverage](ac-protocol-coverage.md), and
[SmartThings implementation quirks](implementation-quirks.md) for details.

## Custom capability ownership

The shipped profiles use the registered IDs in the `againmusic09479` namespace:
`irRemoteCreation`, `irSignalLearning`, `acLearningSetup`, and
`acProtocolSelection`, all at version 1. The namespace owner controls updates to
these definitions. The registration script in this repository updates those
account resources and is intended for the namespace owner/maintainer; ordinary
driver users should not run it when installing a release.

A fork that needs its own capability namespace must register its own definitions
and presentations, then consistently update the returned IDs in the manifest,
profiles, Lua handlers, and registration workflow. The checked-in script is not
a namespace-neutral setup tool: it contains owner-specific capability IDs. A
fork should review and adapt it before running it. See the
[capability registration guide](../capabilities/README.md).

The old custom TV capability definitions are retained in the repository, but
are not attached to active profiles; the TV page uses SmartThings'
`keypadInput` capability.

## Source, notices, and the SmartThings ZIP

Treat the SmartThings Edge ZIP as a deployment artifact. **Do not put a source
archive, `LICENSE.md`, third-party license text, or notices inside that ZIP.**
Keep the ZIP within SmartThings' 655,360-byte package limit.

For a public release, publish the driver ZIP separately from the source and
notices. Tag the exact source revision used to build the ZIP, and link the ZIP
to that tag/repository release. The tagged public repository is the source
location; it contains the editable Lua implementation, generated catalog and
build/verification tooling, `LICENSE.md`, `THIRD_PARTY_NOTICES.md`, and the
applicable full license texts under `licenses/` and `tools/ac_catalog/`. Do not
create a second source archive inside the Edge package. If a release page offers
a source download, it is a separate release asset and must match the tagged
source.

The generated AC catalog and runtime have LGPL-2.1-only terms. Keep their
corresponding editable source and the full LGPL text available in the public
source release; retain the upstream copyright notices and identify changes as
described in [LICENSE.md](../../LICENSE.md) and
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). The notices identify the
IRremoteESP8266 source revision. The Otivax reference is the specific community
thread post cited there; the original revision consulted for the
zigbee-herdsman-converters reference was not recorded. Do not replace that
missing provenance with a guessed revision.

## Checks before publishing a versioned driver release

Record the source tag or commit and the results for that same revision:

- [ ] Run the standalone Lua checks and SmartThings SDK checks listed in the
  [README](../README.md). Record the Lua version and SmartThings SDK revision.
- [ ] Package with the SmartThings CLI and confirm the resulting package is at
  most 655,360 bytes. Keep source and license documents outside the Edge ZIP.
- [ ] Install that package on a development hub. Record hub model, driver
  version, exact blaster model/revision, Zigbee endpoints/clusters, and whether
  startup and command logs appear.
- [ ] Verify pairing, battery reporting, create/reopen/delete child behavior,
  restart persistence, learning and replay, and timeout/error presentation.
- [ ] Verify at least one end-to-end learned signal with a real target device.
  For each AC variant called hardware-verified, record the indoor-unit model,
  original remote model, selected protocol/model value, tested states, and
  observed result. Do not use a brand name as model-level evidence.
- [ ] Check TV keypad and learning controls, AC selector/setup visibility, and
  Routine actions in the current SmartThings app. Record app/platform version.
- [ ] Publish the ZIP and a link to its exact tagged source, license and notice
  files. State which hardware tests were not performed.

If a check has not been run for the release commit, mark it unverified in the
release notes rather than carrying forward results from an older commit.
