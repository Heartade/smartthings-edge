# IRremoteESP8266 AC coverage

Pinned revision: `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.

All **66 identifiers** listed by upstream `IRac::isProtocolSupported` now have
generated encoders, covering **91 protocol/model combinations**. See the
[complete model table](ac-catalog-models.md) and [implementation guide](ac-catalog.md).
The former 22 handwritten protocol choices are retired from the selector and
their encoder modules are no longer packaged. Existing saved selections migrate
to the closest generated catalog variant; **Learn AC states** remains available.
Selector labels show protocol and model identifiers where upstream provides them.

The common-state catalog covers power, supported modes, integer Celsius setpoint,
four fan settings and automatic swing where upstream implements it. Optional
features, fixed vane positions and raw-only formats remain outside this scope.
Additional Carrier formats, Daikin200, Kelon168, Sanyo152 and TCL96 are examples
without common-state setters in this revision. A raw transmitter or decoder is
insufficient to generate a state from the AC UI without a known field mapping.

The generated graphs and shipped Lua runtime are compared against captured
upstream output. Physical AC reception and zero-mark continuation behavior on
the blaster still need hardware checks. Brand names alone do not prove model
compatibility; the user's LG 6711A90006C is not an upstream model.

Sources: [upstream common API](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/IRac.cpp)
and [supported protocols/models](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/SupportedProtocols.md).
