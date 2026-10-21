# Third-party notices

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

The separately implemented LG encoder references upstream protocol data and
contributors as described in [docs/protocol-sources.md](docs/protocol-sources.md).
