# Generated IRremoteESP8266 AC encoders

The AC detail-screen **AC protocol / model** selector covers all **66 identifiers** advertised by
IRremoteESP8266's common AC API at commit
`1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`, with **91 protocol/model combinations**.
The selector contains these 91 generated variants plus **Learn AC states**.
The former standalone protocol choices have been retired. Existing saved values
map to the closest generated variant on startup. Matching captured waveforms does
not establish compatibility with a particular physical AC or TS1201 firmware.

## Select a protocol and remote model

1. Create an AC child and open its device screen.
2. Select one **AC protocol / model** option. Variant identifiers appear in the
   option label, for example `LG2 2: AKB75215403`.
3. Use power, mode, the single temperature slider, fan and supported swing controls.

Selecting **Learn AC states** enables the separate learning controls; selecting
a complete protocol/model hides them. The selector capability must be registered
with `capabilities/register-tv-ui.ps1` before packaging. Model numbers are upstream
enum values, not numbers printed on the indoor unit. When the upstream model list
has a single entry, the selector shows the protocol without a variant suffix.
The 6711A90006C remote is not an upstream LG model; the family name alone does
not confirm its compatibility. Exact-state learning remains available.

## Supported controls and boundaries

The generated input domain is integer Celsius temperatures 10–32, five common
modes, four fan settings, power on/off, and off/automatic swing on each axis.
The UI advertises each model's normalized modes, temperature range and effective
swing axes. Native setters retain their restrictions: for example, fan or auto
modes can force particular fan speeds or temperatures. Returned desired state
reflects those normalized settings. Unsupported modes/models/swing fail before
sending. Fahrenheit display converts to integer Celsius as before.

Timers, clock, fixed vane positions, half-degree settings, quiet/turbo/economy,
light, sleep and other optional controls are outside this domain. Optional
features use upstream defaults with booleans disabled and timers unset.
This catalog does not implement every low-level AC format or every appliance
model mentioned anywhere in IRremoteESP8266. Raw-only formats such as additional
Carrier variants, Daikin200, Kelon168, Sanyo152 and TCL96 lack common-state
setters upstream and still need independently established state mappings.

Toggle formats compare against the last **completed** transfer for the same
protocol/model. A failed transfer does not advance this baseline. A new child or
changed protocol/model starts with an assumed off/no-swing state. IR provides no
feedback: using the original remote, a power failure, or a transfer that reached
the appliance despite a missing acknowledgment can desynchronize that assumption.
The switch reports commanded state, not measured AC power.

Some native idle gaps exceed the blaster format's 16-bit duration. These are
represented exactly as 65,535 µs idle plus a zero-duration mark and the remaining
idle; all other zero durations are rejected. This preserves software waveforms,
but zero-mark continuation behavior needs a check on the physical blaster.

## How the port works

`tools/ac_catalog/generate.py` builds a temporary native executable from the
pinned upstream source. Its instrumentation captures the actual transmitters'
carrier and pulse durations after applying the common AC setters. It captures
all input combinations, including previous power/swing for toggle protocols.
Each output duration is reduced to a shared decision graph. The hub evaluates
those graphs in Lua; no Arduino runtime, C++ executable or network service is
required. Model data loads on demand, with a four-model cache.

YORK is listed by upstream `isProtocolSupported` but has no `sendAc` case in this
revision. Its adapter calls the native York setters/transmitter and documented
raw power/swing fields. This is separately identified experimental behavior.
Mirage's class is inside upstream's decoder compile guard, so the capture build
also enables `DECODE_MIRAGE`. Neither workaround changes upstream frame coding.

## Reproduce

Use an unmodified source archive for the pinned commit, Python with NumPy, and
a C++11 compiler. Source hashes are checked before either build or capture.

```sh
python tools/ac_catalog/generate.py --upstream /path/to/IRremoteESP8266 --work /path/to/scratch
python tools/ac_catalog/verify.py --work /path/to/scratch
lua tests/ac_catalog.lua
```

The second command requires `lupa` with Lua 5.3. Generation checks every decision
graph output against its captured matrix. The verifier independently runs the
shipped Lua encoder for every captured input and compares every carrier/duration.
`manifest.json` records the upstream revision, model coverage, state counts and
SHA-256 of each native capture. `--resume` reuses existing capture metadata; use
a fresh scratch directory when changing the generator or capture instrumentation.

`tests/edge_zigbee_sdk.lua` serializes complete on/off chunk transfers through
the official SmartThings SDK for all 91 generated protocol/model choices.
`tests/gui_sdk.lua` checks completed-transfer persistence and timeout behavior.
These software checks do not confirm physical reception.

The initial catalog generation recorded **518,880 states** and **143,568,912
timing values**. An earlier source revision passed 16 repository check scripts
and produced a local SmartThings CLI package of about 133 KiB. This is historical
baseline information only; it is not evidence that the current checkout's tests
pass or that its package fits SmartThings' 655,360-byte limit. Run the current
checks and measure the package built from the exact release commit, as described
in the [public release checklist](public-release.md).

Generated tables and the capture/runtime port are LGPL-2.1-only. See the
[upstream license](../tools/ac_catalog/LICENSE.IRremoteESP8266.txt) and
[copyright notices](../tools/ac_catalog/NOTICE.IRremoteESP8266.txt). The generator,
capture adapter and editable Lua output are included for modification/rebuilding.
