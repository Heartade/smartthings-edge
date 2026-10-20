# AC infrared protocol sources and integration plan

Research date: 2026-09-23. The linked upstream catalogs change over time; this file is a source map, not a claim that their protocols already work in this driver.

| Source | What it provides | Use here |
| --- | --- | --- |
| [IRremoteESP8266 supported protocols](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/SupportedProtocols.md), [IRac](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/src/IRac.h) | Many C++ AC state encoders, concrete remote/model mappings, a common AC state API, and tests | Primary reference for porting **send-side** protocol encoders into Lua. Select a specific variant/model, not merely a brand. |
| [arduino-heatpumpir](https://github.com/ToniA/arduino-heatpumpir) | Independently implemented C++ heat-pump protocols and model mappings | Cross-check supported models, frame construction, and timing for protocols not covered or not identical in IRremoteESP8266. |
| [ESPHome IR climate](https://esphome.io/components/climate/climate_ir/) | C++ climate components for particular remote families | Additional state encoders and platform-specific behavior; do not confuse with ESPHome's non-IR climate integrations. |
| [SmartIR climate codes](https://github.com/smartHomeHub/SmartIR/blob/master/docs/CLIMATE.md) | Model-specific pre-recorded command/state tables in JSON | Alternative data-backed *learned-state* profile, not a general-purpose protocol encoder. Inspect code format and license per dataset before importing. |
| [Zigbee2MQTT Zosung converter](https://github.com/Koenkk/zigbee-herdsman-converters/blob/master/src/lib/zosung.ts) | TS1201 Zigbee transport, chunking, learning, raw timings format | Physical IR transport. It does not identify or generate manufacturer AC protocols. |

## Why upstream C++ cannot simply be bundled

SmartThings Edge packages Lua driver source, while IRremoteESP8266 targets the Arduino framework on ESP8266/ESP32. There is no supported step in the Edge packaging workflow to compile that C++ library into the hub driver. A protocol family without fixture and hardware verification must be labeled **experimental** in Settings; an unknown ID must fail closed. An unimplemented choice should never silently send another manufacturer's frame.

The upstream IRremoteESP8266 library is LGPL-2.1; arduino-heatpumpir is GPL-2.0. When porting or copying implementation, retain notices and review obligations for the specific source. Reference-only research does not copy their code.

## Current LG family encoders

For the eight added Toshiba, Mitsubishi, Gree, Kelvinator and Electra variants,
see [additional AC encoders](added-ac-protocols.md), including pinned references,
338 waveform fixtures, model restrictions and retained LGPL notices. The
AKB74955603 choice now sends absolute vertical swing on/off auxiliary frames;
the older swing-off-only description below applies to generic LG/LG2 choices.

`src/ac/protocol_lg.lua` implements single-frame LG and LG2 28-bit state messages from the field layout and timing definitions in the [upstream LG protocol source](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/src/ir_LG.cpp) and [header](https://github.com/crankyoldgit/IRremoteESP8266/blob/master/src/ir_LG.h). These choices are experimental: they have no local timing fixtures and have not been checked on a TS1201 or AC. The encoder supports 16–30 °C, cool/heat/dry/fan/auto, and auto/low/medium/high fan. Swing remains off because several LG models require additional model-specific frames that are not implemented here.

The registered LG family candidates are GE6711AR2853M, LG6711A20083V, TS-H122ERM1, and AG1BH09AW101. The registered LG2 family candidates are AKB74395308, S4-W12JA3AA, AKB75215403, AKB74955603, A4UW30GFA2, AMNW09GSJA0, AMNW24GTPA1, AKB73757604, AKB73315611, and MS05SQ NW0. The separate AKB74955603 choice uses that variant's distinct low/high fan values. [LG's accessory catalog](https://www.lge.co.kr/care-accessories/floor-standing-cooler/akb74375306) lists remote part AKB74375306 as compatible with SNC063BBW, but that exact part number is absent from the upstream list.

The supplied remote part **6711A90006C** is indexed separately as **LG_AIR_06C** for older Whisen air conditioners, with compatibility notes referring to units made from 1997 onward ([remote profile listing](https://www.myremocon.com/index.php?document_srl=2790&mid=RemoconDownload)). It is not named in the current IRremoteESP8266 LG/LG2 model list, and the available listing does not establish that it uses either generated 28-bit variant. For SNC063BBW with this remote, keep **Learn complete states** selected. Do not treat the indoor-unit model alone as proof of an LG/LG2 variant. Exact-state learning is the fallback when the original remote sends a complete state on each command.

The encoder is a separate Lua implementation based on published protocol data, not a bundled copy of the upstream C++ library. The source repository identifies IRremoteESP8266 as LGPL-2.1 and its LG files attribute their contributors; keep those references with the implementation if it is redistributed.

## Encoder contract

A protocol module accepts `{power, mode, temperature, fan, swing_vertical, swing_horizontal}`, plus an explicit model/variant and any required previous state. It must:

1. Describe supported modes, fan values, swing values, temperature range and whether a previous state is required. Reject unsupported combinations before transmission.
2. Generate an ordered series of raw mark/space durations with carrier frequency and repeat/gap information. Some families require more than one frame for power transitions or special functions.
3. Pass these durations to the Zosung raw timing encoder, which encodes timings for TS1201 transfer. Verify the maximum payload size and hub memory before enabling a module.
4. Compare exact frame data against upstream fixtures and, where available, captures from the original remote. Follow with a real TS1201-to-AC test.

A protocol's `supported` entry is distinct from a catalog `candidate` entry. Do not assume `SAMSUNG_AC` covers every Samsung remote, for example. The [IRremoteESP8266 FAQ](https://github.com/crankyoldgit/IRremoteESP8266/wiki/Frequently-Asked-Questions) notes that its test example tries only a default model per protocol; the [new-AC-protocol guide](https://github.com/crankyoldgit/IRremoteESP8266/wiki/Adding-support-for-a-new-AC-protocol) recommends identifying both AC and remote models and capturing signals.

## Routine commands

The protocol child should expose independent settable controls for power, mode, target temperature, fan, and swing, plus a single atomic full-state action if SmartThings custom capability presentation supports it in Routines. The handlers update one desired state, validate it against the selected encoder, coalesce near-simultaneous changes, and transmit one complete frame. Multiple actions in one Routine are not guaranteed to arrive as a transaction; the atomic command provides that guarantee when needed. Report desired state rather than asserting the AC physically changed.

## First implementation sequence

1. Complete the TS1201 raw-timing transport and round-trip tests independent of AC brand.
2. Add an encoder registry with distinct **candidate**, **implemented**, and **hardware-verified** statuses, and a working protocol selection interface that only allows implemented encoders.
3. Port a small number of representative encoders with upstream fixtures, expanding coverage family by family. Keep each module optional in code organization but package validated modules by default.
4. When the AC/remote model is known, prioritize its variant and verify with real hardware. An unknown model can still be tried against candidate protocols, but that is a supervised compatibility test rather than confirmed support.
