# IRremoteESP8266 AC coverage gaps

Compared on 2026-10-21 against upstream commit `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.
Sources: [IRac::isProtocolSupported](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/IRac.cpp#L192)
and [protocol/model catalog](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/SupportedProtocols.md).

The upstream IRac list contains **66 protocol identifiers**. This driver
implements selected variants of **7 identifiers**, exposed as **11 encoder
choices**. **59 identifiers have no local implementation**. These are protocol
counts, not AC model counts; a family match does not mean every remote variant works.
The current upstream commit is the same commit already pinned for the local ports.
No new encoder was added as part of this coverage review.

## Locally implemented subsets

| Upstream identifier | Local Settings choices |
| --- | --- |
| `LG` | `lg_28` |
| `LG2` | `lg2_28`, `lg2_akb74955603` |
| `TOSHIBA_AC` | `toshiba_72_a`, `toshiba_72_b` |
| `MITSUBISHI_AC` | `mitsubishi_144` |
| `GREE` | `gree_yaw1f`, `gree_ybofb`, `gree_yx1fsf` |
| `KELVINATOR` | `kelvinator_128` |
| `ELECTRA_AC` | `electra_104` |

## Not implemented locally

`AIRTON`, `AIRWELL`, `AMCOR`, `ARGO`, `BOSCH144`, `CARRIER_AC64`, `COOLIX`, `CORONA_AC`, `DAIKIN`, `DAIKIN128`, `DAIKIN152`, `DAIKIN160`, `DAIKIN176`, `DAIKIN2`, `DAIKIN216`, `DAIKIN312`, `DAIKIN64`, `DELONGHI_AC`, `ECOCLIM`, `EUROM`, `FUJITSU_AC`, `GOODWEATHER`, `HAIER_AC`, `HAIER_AC160`, `HAIER_AC176`, `HAIER_AC_YRW02`, `HITACHI_AC`, `HITACHI_AC1`, `HITACHI_AC264`, `HITACHI_AC296`, `HITACHI_AC344`, `HITACHI_AC424`, `KELON`, `MIDEA`, `MIRAGE`, `MITSUBISHI112`, `MITSUBISHI136`, `MITSUBISHI_HEAVY_152`, `MITSUBISHI_HEAVY_88`, `NEOCLIMA`, `PANASONIC_AC`, `PANASONIC_AC32`, `RHOSS`, `SAMSUNG_AC`, `SANYO_AC`, `SANYO_AC88`, `SHARP_AC`, `TCL112AC`, `TECHNIBEL_AC`, `TECO`, `TEKNOPOINT`, `TRANSCOLD`, `TROTEC`, `TROTEC_3550`, `TRUMA`, `VESTEL_AC`, `VOLTAS`, `WHIRLPOOL_AC`, `YORK`.

## Additional gaps within existing families

- Toshiba is limited to the selected 72-bit A/B formats; longer variants are not covered.
- Mitsubishi Electric is limited to the 144-bit format. Mitsubishi112/136 and Mitsubishi Heavy are distinct missing protocols.
- Gree exposes only the three documented variants.
- LG/LG2 expose only the documented 28-bit choices and AKB74955603 swing handling.
- Advanced functions such as timers, sensor reporting, quiet/turbo and model-specific auxiliary messages are not generally implemented.

## Scope and next ports

This comparison uses IRac's common AC-state interface, rather than every decoder
or low-level send function. The broader upstream catalog contains additional
formats without common-state support, including further Carrier variants; they
also require separate investigation.

Daikin, Panasonic, Samsung, Fujitsu, Midea/Coolix and Haier would broaden brand
coverage. A next port must select a concrete protocol/model, preserve upstream
notices, map supported state fields, and account for absolute versus toggle-only
power/swing commands. Listing a name in Settings without an encoder is not support.
Hardware compatibility and waveform comparison remain separate work.
