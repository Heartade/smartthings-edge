# IRremoteESP8266 AC coverage gaps

Compared on 2026-10-21 against upstream commit `1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f`.
Sources: [IRac::isProtocolSupported](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/src/IRac.cpp#L192)
and [protocol/model catalog](https://github.com/crankyoldgit/IRremoteESP8266/blob/1e2f0f3ef0a93cbf2a8ddb2e95130f8f4c584b3f/SupportedProtocols.md).

The upstream IRac list contains **66 protocol identifiers**. This driver
implements selected variants of **16 identifiers**, exposed as **22 encoder
choices**. **50 identifiers have no local implementation**. These are protocol
counts, not AC model counts; a family match does not mean every remote variant works.
The current upstream commit is the same commit already pinned for the local ports.
The 11 subsequent experimental choices are documented in [expanded AC encoders](expanded-ac-protocols.md). They have not received the older ports' waveform validation.

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
| `SAMSUNG_AC` | `samsung_ac` (extended state) |
| `HAIER_AC` | `haier_72` |
| `HAIER_AC_YRW02` | `haier_yrw02` |
| `HAIER_AC160` | `haier_160` |
| `HAIER_AC176` | `haier_176_a`, `haier_176_b` |
| `CARRIER_AC64` | `carrier_64` |
| `TCL112AC` | `tcl112_tac09chsd`, `tcl112_gz055be1` |
| `MIDEA` | `midea_48` |
| `DAIKIN152` | `daikin_152` |

## Not implemented locally

`AIRTON`, `AIRWELL`, `AMCOR`, `ARGO`, `BOSCH144`, `COOLIX`, `CORONA_AC`, `DAIKIN`, `DAIKIN128`, `DAIKIN160`, `DAIKIN176`, `DAIKIN2`, `DAIKIN216`, `DAIKIN312`, `DAIKIN64`, `DELONGHI_AC`, `ECOCLIM`, `EUROM`, `FUJITSU_AC`, `GOODWEATHER`, `HITACHI_AC`, `HITACHI_AC1`, `HITACHI_AC264`, `HITACHI_AC296`, `HITACHI_AC344`, `HITACHI_AC424`, `KELON`, `MIRAGE`, `MITSUBISHI112`, `MITSUBISHI136`, `MITSUBISHI_HEAVY_152`, `MITSUBISHI_HEAVY_88`, `NEOCLIMA`, `PANASONIC_AC`, `PANASONIC_AC32`, `RHOSS`, `SANYO_AC`, `SANYO_AC88`, `SHARP_AC`, `TECHNIBEL_AC`, `TECO`, `TEKNOPOINT`, `TRANSCOLD`, `TROTEC`, `TROTEC_3550`, `TRUMA`, `VESTEL_AC`, `VOLTAS`, `WHIRLPOOL_AC`, `YORK`.

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

Panasonic, Fujitsu, Sharp and Coolix would broaden brand coverage further;
additional Daikin, Samsung and Carrier variants also remain. A next port must select a concrete protocol/model, preserve upstream
notices, map supported state fields, and account for absolute versus toggle-only
power/swing commands. Listing a name in Settings without an encoder is not support.
Hardware compatibility and waveform comparison remain separate work.
