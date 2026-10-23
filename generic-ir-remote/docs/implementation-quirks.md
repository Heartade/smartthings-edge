# SmartThings implementation quirks

These notes capture constraints and failure modes encountered while building
this driver. They describe this repository's current workarounds; SmartThings
may change its API or app rendering over time.

## Capabilities, profiles, and the mobile app

- A custom capability is identified by its registered ID and version. A `409`
  saying that the same version already exists means update that registered
  version with `smartthings capabilities:update`; do not try to create v1 again.
- Creating a presentation a second time also conflicts because one already
  exists for that capability version; update the existing presentation. A
  `Localization already exists` response means reconcile the existing locale
  record instead of creating another one.
- SmartThings rejected custom capabilities with more than 20 commands. Split a
  large command set or use a native capability when it provides the desired UI.
  The current TV profile uses native `keypadInput`; the old custom TV capability
  assets remain unbound for compatibility.
- Device-profile option keys must match `^\w+$`, and option values are limited
  to 36 characters. Keep machine keys short and put descriptive text in labels.
- Translation keys must be actual attribute or command names from the
  capability schema. A label such as `settings` is not a valid translation key
  unless the schema declares an attribute or command with that name. When a
  schema update races the localization validator, the registration script
  retries only the known invalid-name response; other API errors need separate
  correction.
- The capability schema, presentation, translations, manifest, and device
  profile must agree. A capability in the driver's `supported_capabilities`
  list alone does not put it on a device page; the selected profile must also
  include it. Existing child devices need a profile metadata update before new
  controls become available, and profile updates can be asynchronous.
- `src/capability_definitions.lua` is generated from the JSON capability
  definitions by `capabilities/register-tv-ui.ps1`. After changing a bundled
  schema, run the registration script before packaging so the command handlers
  and event builders use the same schema as the API.
- Capability presentations do not provide an arbitrary multi-page remote UI.
  The native TV keypad is rendered by the SmartThings app from `keypadInput` and
  its supported key codes. For AC, a single flat selector combines protocol and
  model in each label; a second selector dependent on the first did not render
  reliably on the device page.
- Dynamic status messages come from the driver and are not translated
  automatically. Translate fixed labels and status values, and keep dynamic
  messages concise.

## Zigbee transport and state

- `EDGE_CHILD` devices are identified by `parent_assigned_child_key`. Setting
  `device_network_id` explicitly produces a warning and may prevent normal
  child creation.
- Build custom ZCL transmissions with the SDK's typed objects. This driver uses
  `FrameCtrl` from `st.zigbee.zcl.frame_ctrl`, a typed `ZclHeader`, and
  `GenericBody` from `st.zigbee.generic_body`. Serialization errors such as a
  missing `FrameCtrl`, `is_mfg_specific_set`, or `_serialize` happened before a
  valid message reached the radio; check the message object types and SDK module
  paths before debugging IR protocol data.
- A physical blaster owns the radio and transfer state. Only one learning or
  transmit operation can be active per parent at a time; another child gets a
  busy result until it finishes or times out.
- `switch` and AC events report the last commanded or desired state. IR
  transmission completion confirms the blaster finished sending, not that the
  TV, fan, or AC received or obeyed the signal.
- Battery is a property of the physical blaster, not each logical child. The
  parent profile exposes standard `battery`; its Zigbee source is Power
  Configuration cluster `0x0001`, attribute `BatteryPercentageRemaining`
  (`0x0021`). The driver reads it on startup and refresh and runs `device:refresh()`
  plus `device:configure()` during `doConfigure`, so the SmartThings Zigbee
  battery default can read the value and configure future reports. One listed
  TS1201 manufacturer variant is reported to have no battery, so it cannot
  provide this attribute. See the [battery defaults documentation](https://developer.smartthings.com/docs/edge-device-drivers/zigbee/defaults/battery.html).
- `health_check = false` avoids the deprecated monitored-attribute health
  checks. Battery reporting still uses the battery default handler.

## Packaging and diagnosis

- SmartThings rejected a driver package larger than 655,360 bytes. Keep the Edge
  ZIP as the deployment artifact: do not embed a source archive, `LICENSE.md`,
  license text, or third-party notices in it. For a public distribution, link
  the ZIP to the exact public repository tag/commit that contains the matching
  editable source, licenses and notices. A separate source download is optional
  when that tagged source is publicly accessible. See
  [public release guidance](public-release.md#source-notices-and-the-smartthings-zip),
  [LICENSE.md](../../LICENSE.md), and [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- A successful package upload is not proof that a hub is running that build.
  Check the CLI's assigned driver version and installed hub version, then
  confirm the driver's startup log before diagnosing device commands.
- If interaction logs are absent, first verify that the driver started and that
  its startup `require` calls completed. Capability dispatch logs only appear
  after startup and after a command reaches the driver; a silent log does not
  by itself identify an IR or protocol failure.
- `IR transfer timed out` means the expected Zosung receive/transmit sequence
  did not complete before its deadline. Use the transfer's sequence/byte
  details, if present, to distinguish no response from a capture that stopped
  partway through. Do not treat timeout as proof that a learned signal is
  incompatible with the target appliance.
