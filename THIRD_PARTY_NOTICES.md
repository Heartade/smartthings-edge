# Third-party notices

Project licensing is described in [LICENSE.md](LICENSE.md). Third-party material
retains its own license and copyright notices. The entries below distinguish
adapted implementations and generated data from design/reference acknowledgments.

## otivax — SmartThings Edge drivers (reference acknowledgment)

- Project: [otivax/smartthings-edge-drivers](https://github.com/otivax/smartthings-edge-drivers).
- Credit: otivax and the upstream contributors.
- Use here: a reference for SmartThings Edge driver behavior and remote UI work,
  including the investigation of SmartThings' remote/keypad presentation.
- Upstream license: Apache License 2.0, retained in
  [licenses/otivax-Apache-2.0.txt](licenses/otivax-Apache-2.0.txt).
- License reviewed on 2026-10-22 at revision
  `5606563e6e4c952d12b6d60cf49302a4a44625c0`. The exact revision originally
  consulted was not recorded. No upstream `NOTICE` file was found in that tree.

This acknowledgment records the reference relationship. It does not identify a
verbatim code import or apply Apache-2.0 to the separately licensed AC ports.

## IRremoteESP8266 — AC implementations and generated waveforms

`src/ac/protocol_irremote.lua` and `src/ac/protocol_expanded.lua` adapt the AC protocol layouts, state construction,
checksums and waveform generation of IRremoteESP8266, distributed under LGPL 2.1.
The Lua adaptations are provided in source form under the same license.

Upstream: https://github.com/crankyoldgit/IRremoteESP8266

Reference revision: `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.

Referenced source/header pairs: `ir_Toshiba`, `ir_Mitsubishi`, `ir_Gree`,
`ir_Kelvinator`, `ir_Electra`, `ir_Samsung`, `ir_Haier`, `ir_Carrier`,
`ir_Tcl`, `ir_Midea`, and `ir_Daikin`. Upstream notices include:

- Copyright 2009 Ken Shirriff.
- Copyright 2016–2022 David Conran.
- Copyright 2019 Mark Kuchel.
- Copyright 2016–2017 sillyfrog (Daikin sources).
- Copyright 2019 pasna (Daikin source family).
- Contributions by the IRremoteESP8266 authors acknowledged in those files.

The complete license is in [licenses/IRremoteESP8266-LGPL-2.1.txt](licenses/IRremoteESP8266-LGPL-2.1.txt).
The upstream C++ library is used to generate reference vectors during development;
it is not compiled into the SmartThings Edge driver. The generator source and
waveform fingerprints are retained under `tests/reference/`.

The LG/LG2 implementation in `src/ac/protocol_lg.lua` also uses upstream field
layouts, checksums and timings from `ir_LG.cpp` / `ir_LG.h`; it is distributed
under LGPL-2.1-only with the other AC adaptations.

The generated catalog adds these LGPL-2.1-only portions:

- `src/ac/catalog_data/*.lua`: waveform decision graphs derived from native
  upstream state setters and transmitters for all 66 common-AC identifiers.
- `src/ac/catalog_index.lua` and `tools/ac_catalog/manifest.json`: accompanying
  protocol/model metadata and capture provenance.
- `src/ac/protocol_catalog.lua` and `tools/ac_catalog/capture.cpp`: the Lua
  runtime and native capture adapter, explicitly licensed LGPL-2.1-only.
- `tests/reference/ac_waveforms.lua`: upstream-generated reference waveforms.

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

When distributing the driver, provide this notice, the applicable full license
texts, and the corresponding editable source for the LGPL-covered portions,
including the generator/capture tooling and pinned upstream provenance. Retain
existing notices and identify modifications in redistributed adaptations.
SmartThings' build-only ZIP does not automatically include root-level Markdown
or the `licenses/` directory; release the source and notices alongside that ZIP.
