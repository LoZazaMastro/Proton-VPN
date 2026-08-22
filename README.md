# Proton VPN for Decky (Windows)

Decky Loader plugin for controlling an installed Proton VPN Windows client from Quick Access without desktop UI automation.

**Version:** 1.0.0  
**Author:** LoZazaMastro  
**Internal build:** `R16.6-auto-steam-language-i18n`

## QAM layout

The panel deliberately stays compact:

- **Proton VPN** title with plugin icon
- **VPN** toggle
- localized **Status** row
- localized **Country** label
- text-only country selector
- one summary card with a **large country flag**, localized country name and:
  - green closed lock when the VPN is active
  - red open lock when the VPN is inactive
- up to six unique recent successful countries in one vertical column

Country flags are bundled locally; they are not fetched from the network and are not shown inside the country menu.

## Localization

R16.6 automatically follows the Steam client language through `SteamClient.Settings.GetCurrentLanguage()` and falls back to the browser locale/English only if Steam language detection is unavailable.

The QAM UI supports all current Steam full-platform languages:

- Arabic
- Bulgarian
- Chinese (Simplified)
- Chinese (Traditional)
- Czech
- Danish
- Dutch
- English
- Finnish
- French
- German
- Greek
- Hungarian
- Indonesian
- Italian
- Japanese
- Korean
- Malay
- Norwegian
- Polish
- Portuguese (Portugal)
- Portuguese (Brazil)
- Romanian
- Russian
- Spanish (Spain)
- Spanish (Latin America)
- Swedish
- Thai
- Turkish
- Ukrainian
- Vietnamese

Country names are localized dynamically with `Intl.DisplayNames` in the detected Steam locale, with the bundled English country list as a fallback. Arabic uses RTL direction in the QAM content.

## Connection behavior

- Starts `ProtonVPN.Client.exe` automatically when Proton VPN is installed but its client process is not running.
- Detects the active country from Proton's own client connection log instead of treating the last selected country as the active one.
- Serializes connect/disconnect operations so QAM refreshes cannot start a second helper operation in parallel.
- Suppresses duplicate same-country connect requests.
- If the requested country is already active, no process or service is touched.
- Keeps up to six unique recent successful countries for quick reconnection.
- Connection completion uses fresh Proton client-log `Connected` events first, with Windows route detection as fallback.

## Current technical limitation

The current country-selection mechanism still relies on Proton's `RecentConnections.bin` plus a temporary `DefaultConnection=Last` bootstrap. Proton VPN for Windows does not expose a supported public country-switch CLI.

For a **real switch from one active country to another**, this stable branch uses one deterministic tunnel reset before the client reloads the selected recent connection. It does **not** claim to be true zero-restart switching. Same-country selections are immediate and do not reset anything.

The proper future architecture for zero-service-restart switching is Proton's internal gRPC named-pipe controller. Proton's service authorizes the official `ProtonVPN.Client.exe`, so an external Decky helper cannot simply call that endpoint without invasive techniques. This plugin deliberately does not use UI automation, injection or binary patching.

## Notes

- Windows only.
- Proton VPN must already be installed and authenticated at least once.
- No mouse/keyboard focus automation and no `interact UI` path is used.
- Public plugin version remains **1.0.0** until intentionally changed.
