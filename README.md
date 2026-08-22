# Proton VPN for Decky (Windows)

Decky Loader plugin for controlling an installed Proton VPN Windows client from Quick Access without desktop UI automation.

**Version:** 1.0.0  
**Author:** LoZazaMastro  
**Internal build:** `R16.2-qam-state-first-input-embedded-flags`

## QAM layout

The panel deliberately stays compact:

- **Proton VPN** title with plugin icon
- **VPN** toggle
- **Stato**
- **Paese**
- country dropdown with text-only country names
- one summary card below the dropdown with a **large country flag**, country name and:
  - green closed lock when the VPN is active
  - red open lock when the VPN is inactive

Country flags are bundled locally; they are not fetched from the network and are not shown inside the dropdown.

## Connection behavior

- Starts `ProtonVPN.Client.exe` automatically when Proton VPN is installed but its client process is not running.
- Detects the active country from Proton's own client connection log instead of treating the last selected country as the active one.
- Serializes connect/disconnect operations so QAM refreshes cannot start a second helper operation in parallel.
- Suppresses duplicate same-country connect requests.
- If the requested country is already active, no process or service is touched.
- Keeps the successful country in `RecentConnections.bin` instead of restoring that file while Proton is alive, avoiding the live-file race introduced during the R15 experiment.

## Current technical limitation

The current country-selection mechanism still relies on Proton's `RecentConnections.bin` plus a temporary `DefaultConnection=Last` bootstrap. Proton VPN for Windows does not expose a supported public country-switch CLI.

For a **real switch from one active country to another**, this stable branch uses one deterministic tunnel reset before the client reloads the selected recent connection. It does **not** claim to be true zero-restart switching. Same-country selections are immediate and do not reset anything.

The proper future architecture for zero-service-restart switching is Proton's internal gRPC named-pipe `IVpnController`, which the official Windows client itself uses for `Connect` / `Disconnect`. That route should be implemented and tested separately rather than mixed into the stable fallback speculatively.

## Notes

- Windows only.
- Proton VPN must already be installed and authenticated at least once.
- No mouse/keyboard focus automation and no `interact UI` path is used.


### Internal R16.5 test build
- Recent connections are now shown in one vertical column, each button matching the full width of the Country selector.

- Country menu focus/hover keeps white text and uses a white outline.
- Drop-down popup is box-sized to exactly the trigger width.
- Up to six unique recent successful countries are persisted and shown below the active-country card.
- Connection completion uses fresh Proton client-log Connected events first, with Windows route detection only as fallback.
- QAM status skips full diagnostics and uses the fast route probe.
