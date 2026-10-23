# AC infrared protocol sources and integration plan

Research date: 2026-09-23. The linked upstream catalogs change over time; this file maps upstream sources to the generated AC catalog and remaining research.

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

## Current implementation

The driver uses the generated catalog described in [AC protocol coverage](ac-protocol-coverage.md)
and [the catalog guide](ac-catalog.md): 66 common-state identifiers and 91
protocol/model variants. The previous handwritten encoder modules and selector
choices have been removed. Existing stored selections map to catalog variants
on startup; learned-state capture remains available. The supplied LG remote
**6711A90006C** is not named by the upstream LG/LG2 model data, so its exact
protocol remains unknown. Use complete-state learning for that remote when it
sends full state commands.

## Encoder contract

A protocol module accepts `{power, mode, temperature, fan, swing_vertical, swing_horizontal}`, plus an explicit model/variant and any required previous state. It must:

1. Describe supported modes, fan values, swing values, temperature range and whether a previous state is required. Reject unsupported combinations before transmission.
2. Generate an ordered series of raw mark/space durations with carrier frequency and repeat/gap information. Some families require more than one frame for power transitions or special functions.
3. Pass these durations to the Zosung raw timing encoder, which encodes timings for TS1201 transfer. Verify the maximum payload size and hub memory before enabling a module.
4. Compare exact frame data against upstream fixtures and, where available, captures from the original remote. Follow with a real TS1201-to-AC test.

A protocol's `supported` entry is distinct from a catalog `candidate` entry. Do not assume `SAMSUNG_AC` covers every Samsung remote, for example. The [IRremoteESP8266 FAQ](https://github.com/crankyoldgit/IRremoteESP8266/wiki/Frequently-Asked-Questions) notes that its test example tries only a default model per protocol; the [new-AC-protocol guide](https://github.com/crankyoldgit/IRremoteESP8266/wiki/Adding-support-for-a-new-AC-protocol) recommends identifying both AC and remote models and capturing signals.

## Routine commands

The protocol child should expose independent settable controls for power, mode, target temperature, fan, and swing, plus a single atomic full-state action if SmartThings custom capability presentation supports it in Routines. The handlers update one desired state, validate it against the selected encoder, coalesce near-simultaneous changes, and transmit one complete frame. Multiple actions in one Routine are not guaranteed to arrive as a transaction; the atomic command provides that guarantee when needed. Report desired state rather than asserting the AC physically changed.

## Remaining work

1. Check the catalog's full-state commands on the intended TS1201 blaster and physical ACs.
2. Add raw-only upstream formats only after establishing state mappings and model variants.
3. Keep model compatibility supervised; a brand match alone does not establish a usable protocol.

## Coverage review

See [AC protocol coverage](ac-protocol-coverage.md) and the [generated catalog](ac-catalog.md): all 66 pinned upstream common-AC identifiers have generated encoders, covering 91 protocol/model combinations. Raw-only formats and advanced features remain outside this catalog.
