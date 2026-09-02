<div align="center">

# Proton VPN for Decky

### Your VPN in the QAM, without turning your controller into a mouse.

Control the Proton VPN client for Windows from Steam Big Picture with real-time status, country selection, and recent connections.

[![Release](https://img.shields.io/github/v/release/LoZazaMastro/Proton-VPN?style=for-the-badge&label=Release&labelColor=111111&color=ffffff)](https://github.com/LoZazaMastro/Proton-VPN/releases/latest)
[![Licenza MIT](https://img.shields.io/badge/Licenza-MIT-ffffff?style=for-the-badge&labelColor=111111)](LICENSE)

</div>

## Proton VPN, without leaving Steam

The plugin controls an existing Proton VPN installation and maintains an essential panel: a toggle switch, connection status, the active country, a country selector, and your last six successful connections. Flags are included locally, and country names adapt to Steam's language settings.

- automatic launch of `ProtonVPN.Client.exe` when needed;
- status and active country read from real Proton client events;
- serialized connection and disconnection operations;
- duplicate requests to the same country are automatically ignored;
- stores up to six recent countries with no duplicates;
- localized interface for all complete languages currently supported by Steam;
- RTL layout support for Arabic;
- no mouse or keyboard automation, code injection, or modifications to Proton binaries.

## Requirements

- Windows;
- [Decky Loader](https://decky.xyz) and Steam Big Picture;
- official Proton VPN client installed and authenticated at least once.

## Current technical limitation

Proton VPN for Windows does not expose a supported public CLI to switch countries. Version 1.0.0 therefore utilizes `RecentConnections.bin` and a temporary switch to `DefaultConnection=Last`.

If you choose a different country while the VPN is already connected, the plugin performs a single deterministic reset of the tunnel before the client reloads your chosen connection. Selecting the already active country will not restart any processes or services. This is not presented as a seamless, restart-free switch.

The alternative would be Proton's internal gRPC controller, which authorizes the official client. This plugin does not bypass that protection through invasive injection or patches.

## Installation

You can install and update Proton VPN for Decky from the [Playhub](https://github.com/LoZazaMastro/Playhub) Plugin Store, or download the ZIP from the [latest release](https://github.com/LoZazaMastro/Proton-VPN/releases/latest) and install it via **Decky → Settings → Developer → Install plugin from ZIP**.

## License

The plugin is distributed under the [MIT](LICENSE) license. Proton VPN and its related trademarks belong to Proton AG; this project is independent and is not affiliated with or endorsed by Proton.

<div align="center">

Created and maintained by **[LoZazaMastro](https://github.com/LoZazaMastro)**.

</div>
