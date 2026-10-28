# Development driver package and channel

The stable and development builds are intentionally separate SmartThings driver packages.

| Build | Driver name | Package key |
| --- | --- | --- |
| Stable | `SmartThings Generic IR Remote` | `heartade.ir-remote` |
| Development | `SmartThings Generic IR Remote (dev)` | `heartade.ir-remote.dev` |

The development package also uses the description `Unstable TS1201 IR remote development builds`, so it is visibly distinguishable from the stable driver in SmartThings driver listings.

A SmartThings driver **channel** has its own name and description, independent of the driver metadata above. Create a separate channel for development builds and give it an explicit unstable label, for example `Generic IR Remote — Dev / Unstable`. Do not assign the development package to the stable release channel.

## Package the development driver

Run from `generic-ir-remote/`.

Bash:

```sh
bash scripts/package-dev.sh
```

PowerShell:

```powershell
./scripts/package-dev.ps1
```

Both helpers copy the driver to a temporary directory, replace `config.yaml` with `config.dev.yaml`, remove the temporary `config.dev.yaml`, and invoke `smartthings edge:drivers:package`. The checkout's stable `config.yaml` is never modified.

Additional package options can be supplied directly. For example:

```sh
bash scripts/package-dev.sh --channel <dev-channel-id>
```

```powershell
./scripts/package-dev.ps1 -Channel <dev-channel-id>
```

## Deploy to a development hub

Create a dedicated development channel once, enroll the test hub in it, then package/install the dev driver with the helper scripts.

Bash:

```sh
bash scripts/deploy-dev.sh <dev-channel-id> <hub-id>
```

PowerShell:

```powershell
./scripts/deploy-dev.ps1 -Channel <dev-channel-id> -Hub <hub-id>
```

The deployment helpers pass `--install --channel <dev-channel-id> --hub <hub-id>` to the SmartThings CLI.

Users who want stable releases should join only the stable channel. Users who explicitly opt into unstable builds can join the development channel and install `SmartThings Generic IR Remote (dev)`. Because the development build has a different package key, publishing it cannot update an installation of the stable package.
