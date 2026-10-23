# SmartThings Edge driver monorepo

Each driver lives in its own folder. The current driver is
[Generic IR Remote](generic-ir-remote/README.md), with its SmartThings
configuration, source, capabilities, profiles, documentation, and release tools
under `generic-ir-remote/`.

Build or install that driver from its folder so the SmartThings CLI finds its
`config.yaml`:

```powershell
Set-Location generic-ir-remote
smartthings edge:drivers:package . --install --channel <channel-id> --hub <hub-id>
```

Repository-wide legal terms are in [LICENSE.md](LICENSE.md) and
[TERMS.md](TERMS.md). Driver-specific third-party notices are in
[generic-ir-remote/THIRD_PARTY_NOTICES.md](generic-ir-remote/THIRD_PARTY_NOTICES.md).
