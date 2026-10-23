# Third-party notices

Project licensing is described in the root [LICENSE.md](../LICENSE.md). Third-party material
retains its own license and copyright notices. The entries below distinguish
adapted implementations and generated data from design/reference acknowledgments.

## Otivax — SmartThings Community reference

- Reference: [post 97 in the Moes Smart IR Remote Control thread](https://community.smartthings.com/t/edge-moes-smart-ir-remote-control/271782/97).
- Use here: TS1201 manufacturer/model and Zigbee fingerprint information.
- The IR remote driver's source code is not publicly released; this discussion
  is the only reference used for Otivax's driver. No Otivax driver code is
  copied or distributed here, and no Otivax source-code license is claimed.

## IRremoteESP8266 — AC implementations and generated waveforms

The generated AC catalog and its Lua runtime derive waveforms from
IRremoteESP8266, distributed under LGPL 2.1. The generated Lua data and runtime
are provided in source form under the same license.

Upstream: https://github.com/crankyoldgit/IRremoteESP8266

Reference revision: `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.

The 66 common protocol identifiers and model variants captured from this
revision are listed in `tools/ac_catalog/manifest.json`. Upstream notices include:

- Copyright 2009 Ken Shirriff.
- Copyright 2016–2022 David Conran.
- Copyright 2019 Mark Kuchel.
- Copyright 2016–2017 sillyfrog (Daikin sources).
- Copyright 2019 pasna (Daikin source family).
- Contributions by the IRremoteESP8266 authors acknowledged in those files.

The complete license is in [licenses/IRremoteESP8266-LGPL-2.1.txt](licenses/IRremoteESP8266-LGPL-2.1.txt).
The upstream C++ library is used to generate catalog decision graphs during
development; it is not compiled into the SmartThings Edge driver. Capture
provenance and source hashes are recorded in `tools/ac_catalog/manifest.json`.

The generated catalog adds these LGPL-2.1-only portions:

- `src/ac/catalog_data/*.lua`: waveform decision graphs derived from native
  upstream state setters and transmitters for all 66 common-AC identifiers.
- `src/ac/catalog_index.lua` and `tools/ac_catalog/manifest.json`: accompanying
  protocol/model metadata and capture provenance.
- `src/ac/protocol_catalog.lua` and `tools/ac_catalog/capture.cpp`: the Lua
  runtime and native capture adapter, explicitly licensed LGPL-2.1-only.

The catalog uses the same pinned upstream revision above. Its generator,
capture adapter, editable Lua tables and verification scripts are included in
this repository; rebuilding instructions are in [docs/ac-catalog.md](docs/ac-catalog.md).
The hub does not execute upstream C++.

The expanded, deduplicated upstream copyright notices are retained in
[tools/ac_catalog/NOTICE.IRremoteESP8266.txt](tools/ac_catalog/NOTICE.IRremoteESP8266.txt).
A second copy of the upstream LGPL text is retained alongside that tooling in
[tools/ac_catalog/LICENSE.IRremoteESP8266.txt](tools/ac_catalog/LICENSE.IRremoteESP8266.txt).

## zigbee-herdsman-converters — Zosung protocol reference

- Project: [Koenkk/zigbee-herdsman-converters](https://github.com/Koenkk/zigbee-herdsman-converters).
- Reference: [`src/lib/zosung.ts`](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts).
- Copyright (c) 2018 Koen Kanters, as stated in the upstream license.
- License: MIT; complete notice retained in
  [licenses/zigbee-herdsman-converters-MIT.txt](licenses/zigbee-herdsman-converters-MIT.txt).
- Use here: reference for TS1201/Zosung transport commands, transfer chunking,
  learning and raw timing format in `src/ir/zosung.lua`,
  `src/ir/zosung_wire.lua`, and the transport controller/adapter.

The original reference revision was not recorded. The MIT license was checked
on 2026-10-22. This entry records protocol-reference use, rather than asserting
that the TypeScript implementation is bundled in this Lua driver.

## Other research and development dependencies

`docs/protocol-sources.md` links arduino-heatpumpir, ESPHome and SmartIR as
research sources/candidates. Their code and datasets are not imported by this
change; those projects' licenses do not become this project's default license.

The SmartThings Edge Lua SDK, IRremoteESP8266 C++ source tree, NumPy, Lupa and
the C++ compiler are external platform/development dependencies. Their source
and binaries are not vendored in this repository. Software redistributed with
future release bundles needs its applicable notices included as well.

## Distribution

When distributing the driver, keep this notice, the applicable full license
texts, and the corresponding editable source for the LGPL-covered portions
available from the public source repository. That source includes the generator,
capture tooling, editable Lua tables and pinned upstream provenance. Retain
existing notices and identify modifications in redistributed adaptations.

The SmartThings Edge ZIP is the deployment artifact only: do not put a source
archive, `LICENSE.md`, full license text, or third-party notices inside it. Link
from the ZIP's release page to the exact public repository tag/commit used to
build it, where those source and notice files are present. A separate source
download is optional when the matching tagged repository is publicly accessible;
if one is provided, keep it separate from the Edge ZIP and make it match that
tag. Measure the Edge package separately against SmartThings' 655,360-byte limit.
