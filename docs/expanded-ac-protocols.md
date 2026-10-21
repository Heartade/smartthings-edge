# Expanded AC encoders

Added 2026-10-21 in `src/ac/protocol_expanded.lua`. These are experimental
send-side ports from IRremoteESP8266 revision `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.
The upstream C++ code is not executed on the SmartThings hub.

## Settings choices and model scope

| Settings key | Family and upstream model candidates | Implemented subset |
| --- | --- | --- |
| `samsung_ac` | Samsung AC: AR09FSSDAWKNFA, AR09HSFSBWKN, AR12KSFPEWQNET, AR12HSSDBWKNEU, AR12NXCXAWKXEU, AR12TXEAAWKNEU; DB93-14195A / DB96-24901C | 16–30 °C, five modes, four fan choices, both swing axes. Always sends the complete 168-bit extended state with section checksums. Auto requires auto fan. |
| `haier_72` | Haier HSU07-HEA03 | 16–30 °C, five modes, four fan choices, vertical swing; 72-bit message with explicit On/Off command. |
| `haier_yrw02` | Haier YR-W02 / HSU-09HMC203 | 16–30 °C, five modes, four fan choices, both swing axes; 112 bits. |
| `haier_160` | Haier KFR-26GW/83@UI-Ge | Same basic state, vertical swing only; 160 bits, second checksum, heat auxiliary flag. |
| `haier_176_a`, `haier_176_b` | Haier V9014557 M47 8D A/B model identifiers; upstream also lists Mabe and Daichi family candidates | Same basic state, both swing axes; 176 bits with two checksums and secondary fan field. |
| `carrier_64` | Carrier/Surrey 42QG5A55970 / 53NGK009/012 family | 16–30 °C, Cool/Heat/Fan only, four fan choices and vertical swing; 64-bit state with nibble checksum. |
| `tcl112_tac09chsd`, `tcl112_gz055be1` | TCL TAC09CHSD and GZ055BE1 model flags; upstream maps Daewoo DSB-F0934ELH-V / GYKQ-52E to TCL112AC, and Teknopoint Allegro SSA-09H to GZ055BE1 | 16–31 °C, five modes, four fan choices and both swing axes; additive checksum. The exact Daewoo subtype must be matched, not inferred from brand alone. |
| `midea_48` | Midea family, including listed Pioneer, Comfee, MrCool, Lennox and Trotec models | 17–30 °C, five modes, four fan choices; native Celsius state, reversed-bit checksum and required inverted second payload. No swing auxiliary commands. |
| `daikin_152` | Daikin ARC480A5 / DAIKIN152 family | 18–32 °C common IRac Celsius subset, five modes, four fan choices and vertical swing; five-bit leader plus 152-bit payload and additive checksum. |

These mappings come from the upstream headers/catalog; they are not hardware
compatibility claims. Other Samsung, Haier, Daewoo, Carrier, Midea and Daikin
protocols exist and may be incompatible. Existing protocol choices remain intact.

## Source references

- [Samsung source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Samsung.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Samsung.h).
- [Haier source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Haier.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Haier.h).
- [Carrier source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Carrier.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Carrier.h).
- [Tcl source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Tcl.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Tcl.h).
- [Midea source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Midea.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Midea.h).
- [Daikin source](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Daikin.cpp), [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Daikin.h).

## Implementation details

All frames are encoded into the existing TS1201 raw-timing transport. Bits,
byte order, checksum algorithms, auxiliary sections and leader pulses follow
the selected upstream formats. Samsung always uses the extended power/state
message rather than inferring previous appliance power from the last UI request.
TCL retains the native model bit. Haier long formats use explicit Power-button
states after assembling the whole configuration.

Samsung, Carrier, TCL and Midea have an upstream final idle around 100 ms;
Haier uses a guessed 150 ms. Their **final trailing idle only** is bounded to
65,535 µs for TS1201's uint16 timing format. Samsung's gaps between its seven-byte
sections and Midea's gap between normal/inverted payloads remain unchanged.
Daikin152 timings fit directly. Each send ends after that final idle; no unrelated
command is concatenated after it.

Midea swing is intentionally excluded: its upstream swing message is a toggle,
not an absolute on/off state. The Off-only selector means no swing command is
sent; it cannot stop swing previously enabled by the physical remote. Advanced
quiet/turbo, timers, sensor reporting, display and cleaning controls are not
exposed. Haier health/cleaning and optional timers are disabled. TCL light is
disabled; Samsung's normal display flag remains enabled.

Carrier's unsupported Auto/Dry modes are rejected rather than silently encoded
as Cool. The driver publishes the selected encoder's available modes. Samsung
Auto applies automatic fan by default and rejects an explicit incompatible fan
request. Daikin152 uses the upstream common-state order of setMode then setTemp;
it does not implement the raw class's standalone fan/dry sentinel-temperature
shortcut or its heat-only temperatures below 18 °C.

## Validation status

The additions were reviewed against the pinned upstream layouts and setters.
No new tests were added or run for this change. No waveform-reference comparison,
package installation or physical AC verification has been performed for these
new choices. The existing 338 waveform fixtures cover the older encoders only.
Use the exact remote/model mapping and treat every new choice as experimental.

## Installation

No custom capability registration is needed. Package and install the updated
driver, reopen an AC protocol child's Settings, and select the compatible
**AC infrared protocol**. The protocol-only profile continues to omit learning
controls. Learned signals are retained. Firmware and model differences may need
additional encoders; an unknown model must not be represented as verified support.

The ports retain LGPL-2.1 licensing; see `THIRD_PARTY_NOTICES.md` and the full
license under `licenses/`.
