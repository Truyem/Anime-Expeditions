# Anime Expeditions Ultimate

**Language:** **English** | [Tiếng Việt](./README.vi.md)

[![Price](https://img.shields.io/badge/price-free-22c55e)](#free--open-source)
[![Source](https://img.shields.io/badge/source-open-3b82f6)](#free--open-source)
[![Language](https://img.shields.io/badge/language-Luau-00a2ff)](https://luau.org/)
[![License](https://img.shields.io/badge/license-MIT-f59e0b)](./LICENSE)

**Anime Expeditions Ultimate** is a free and open-source Luau script for Anime Expeditions on Roblox. It brings automation, macros, and multi-mode management together in a single interface.

The script has no key system, no paywall, and no user fee.

> This is a community project and is not affiliated with or endorsed by Roblox or the developers of Anime Expeditions. Use third-party software at your own risk and follow the platform's terms of service.

## Features

- Auto Join Map with mode, world, difficulty, and act selection.
- In-game macro recording, saving, optimization, and map-specific playback.
- Auto Story, Daily/Weekly Quest, and Challenge with separate macros per map.
- Auto Event support for Guess That Unit, Boss Bounty, and Dragon's Wish.
- Auto Summon by banner, target unit, and summon amount.
- Auto Shop and Auto Craft in the lobby.
- Map-specific Auto Load Team configuration.
- Expedition automation for Fuel, Training Grounds, Research Lab, Building Rewards, and Geodes.
- Auto Encounter for supported Expedition dialogue choices.
- Auto Stat Roll with rarity, stat, and grade filters.
- Auto Claim for quests, battlepass, calendar, milestones, index, and achievements.
- Auto Redeem Code through the community API.
- Discord webhooks for summons, match results, and stat rolls.
- Config save/load with macro and config sharing.
- Built-in English and Vietnamese UI, with English selected by default.
- Anti-AFK, FPS cap, Fix Lag, Hide Player Names, and a mobile UI toggle.
- KickBlock enabled during script startup.

## Installation

Run the following loader in a compatible Luau environment after joining the game:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Truyem/Anime-Expeditions/refs/heads/main/AnimeExpeditionsUltimate.lua"))()
```

## Requirements

- A Luau execution environment with `loadstring` support.
- HTTP requests through `request`, `http_request`, or `syn.request`.
- File APIs such as `readfile`, `writefile`, `isfile`, and `makefolder` for UI/config persistence.
- Advanced features may require `getgc`, `getconnections`, `hookfunction`, `hookmetamethod`, and debug APIs.
- An internet connection for Fluent UI, SaveManager, the code API, and sharing services.

Compatibility depends on the execution environment. Missing APIs may prevent individual features from working even if the interface loads successfully.

## Basic Usage

1. Run the script in Anime Expeditions.
2. Press `LeftShift` to open or minimize the interface on PC.
3. Select the appropriate tab and configure your map, team, or macro before enabling automation.
4. Change `Language` in Settings and rerun the script if you prefer Vietnamese.
5. Verify your webhook URL and Auto Leave options before going AFK.
6. Save your config after finishing the setup.

Configs and UI cache files are stored in the `AnimeExpeditions` folder inside the executor workspace.

## Free & Open Source

The main source is available in [`AnimeExpeditionsUltimate.lua`](./AnimeExpeditionsUltimate.lua) for the community to inspect, improve, and contribute to at no cost.

- Do not pay anyone to obtain this script.
- Do not trust reuploads that require a key or payment.
- Download the latest version directly from the official GitHub repository.
- Keep the copyright and license notices when sharing or forking the project.

This project is released under the [MIT License](./LICENSE).

## Contributing

Bug reports and pull requests are welcome.

1. Fork the repository.
2. Create a branch for your change.
3. Keep changes focused and do not add obfuscated code.
4. Check the Luau syntax before opening a pull request.
5. Describe the changed behavior and how you verified it.

When reporting a bug, include the mode/map, reproduction steps, relevant console logs, and execution environment. Never publish webhook URLs, tokens, or personal data.

## Credits

- **Truyem789**: creator of Anime Expeditions Ultimate.
- [Fluent](https://github.com/dawid-scripts/Fluent): UI library and SaveManager.
- The Anime Expeditions community for shared knowledge, macros, and feedback.

## Disclaimer

This software is provided as-is and may stop working after a game update. The author is not responsible for data loss, account disruption, or other consequences resulting from its use.
