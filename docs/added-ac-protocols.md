# Additional AC encoders

Research and validation: 2026-10-20. The Lua adaptations in
`src/ac/protocol_irremote.lua` use IRremoteESP8266 revision
`1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.

| IDs | Upstream reference (and corresponding header) | Scope |
| --- | --- | --- |
| `toshiba-72-a`, `toshiba-72-b` | [ir_Toshiba.cpp](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Toshiba.cpp) | 17–30 °C, 72-bit state plus 56-bit vertical swing command, each repeated once; remote A/B nibble and inverted bytes |
| `mitsubishi-144` | [ir_Mitsubishi.cpp](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Mitsubishi.cpp) | 16–31 °C, Electric 144-bit family only, additive checksum, mandatory repeat, both swing axes |
| `gree-yaw1f`, `gree-ybofb`, `gree-yx1fsf` | [ir_Gree.cpp](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Gree.cpp) | 16–30 °C, model-specific power flag, split 32-bit blocks and 3-bit marker, nibble checksum, both swing axes |
| `kelvinator-128` | [ir_Kelvinator.cpp](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Kelvinator.cpp) | 16–30 °C, duplicated command bytes, two split blocks, per-block nibble checksum, basic/advanced fan values, both swing axes |
| `electra-104` | [ir_Electra.cpp](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/ir_Electra.cpp) | 16–32 °C, Electra/AUX family, additive checksum, LSB-first bytes, both swing axes |

All support power, cool/heat/dry/fan/auto, and auto/low/medium/high fan, subject
to native restrictions. Gree auto mode requires 25 °C and dry mode requires low
fan. Kelvinator auto/dry modes require 25 °C. Selecting a mode applies its required
defaults; explicitly incompatible settings are rejected. Toshiba horizontal swing
is rejected. Mitsubishi swing off parks vertical vanes at the top and horizontal
vanes at the center. Gree YBOFB and YX1FSF produce identical frames for this basic
subset but retain separate model identities for future features.

Physical messages, repeats and split blocks are concatenated into one timing
sequence, so TS1201 sends the entire command through one Zosung key. Electra's
upstream final 100,000 µs idle is bounded to 65,535 µs for TS1201's uint16 timing
format. Only that final idle is shortened; all data pulses are preserved. Turbo,
economy, timers, sensors and display toggles are excluded.

## Validation and regeneration

`tests/reference/generate_ac_fixtures.cpp` calls the unmodified upstream classes
and captures their simulated IR output. `tests/reference/ac_waveforms.lua` stores
338 vectors covering modes, fan speeds, power on/off, remote variants, temperature
bounds and swing axes. A vector records a pulse count and FNV-1a fingerprint over
every duration encoded as four little-endian bytes. Lua output matches all vectors,
including headers, gaps, bit order and repeats, with only Electra's documented
final-idle normalization. Run `lua tests/ac_protocols.lua` to compare them.

To regenerate using a C++11 compiler, compile the generator with `-DUNIT_TEST
-D_IR_ENABLE_DEFAULT_=false`, `-DSEND_TOSHIBA_AC=true -DSEND_MITSUBISHI_AC=true
-DSEND_GREE=true -DSEND_KELVINATOR=true -DSEND_ELECTRA_AC=true`, and upstream
`src/` and `test/` include paths. Link these upstream sources:

```
IRsend.cpp IRtimer.cpp IRutils.cpp IRtext.cpp
ir_Toshiba.cpp ir_Mitsubishi.cpp ir_Gree.cpp ir_Kelvinator.cpp ir_Electra.cpp
ir_Tcl.cpp
```

`ir_Tcl.cpp` supplies Mitsubishi112's checksum dependency. Redirect the generator's
stdout into `tests/reference/ac_waveforms.lua` and retain the source revision in
its header. The reference generator is not packaged into the driver.

The native Edge SDK tests serialize and reassemble complete Zosung chunk
transfers for all 11 generated choices, and validate the AC capability events
and UI command handlers. These checks establish software/reference agreement;
none of the added protocols has been confirmed on physical AC hardware here.

## UI and licensing

Both AC profiles use `airConditionerMode`, `temperatureSetpoint`, `fanMode` and
`fanOscillationMode`. The mode uses `dry` rather than thermostat `dryair`.
SmartThings' live Korean presentation (queried using
`smartthings capabilities:presentation airConditionerMode --language ko --json`)
labels `dry` as **제습** and `fanOnly` as **송풍**. Voice phrase recognition still
depends on Bixby; this driver cannot change its language model or synonyms.

LG2 AKB74955603 also supports absolute vertical swing commands (`0x8813149`
on, `0x881315A` off), concatenated after the normal state. Generic LG/LG2 profiles
keep swing off because those auxiliary messages are model-specific. Learned-state
UI swing uses `on`/`off` for the two axes and requires matching saved states.

The new adaptations retain the upstream LGPL-2.1 notices and full license;
see [third-party notices](../THIRD_PARTY_NOTICES.md). Sources are distributed
as editable Lua. No upstream C++ runtime or compiled library is shipped.
