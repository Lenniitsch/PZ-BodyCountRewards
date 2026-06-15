# Body Count Rewards

> *Finally, a mod where your body count actually matters.* Yes, the tagline is dumb. No, I won't change it.

A Project Zomboid Build 42 mod that rewards zombie kills with trait upgrades. Earn positive traits or shed negative ones by hitting kill milestones. Fully configurable via Sandbox Options.

Works in **Singleplayer** and **Multiplayer**.

[![Steam Workshop](https://img.shields.io/badge/Steam%20Workshop-Body%20Count%20Rewards-blue?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)

---

## Features

### Core
- **Full Stats UI** -- Three-tab window: Progress (with visual milestones), Reward History, and Trait Catalog with rarity and conflict info
- **Third-party addon API** -- Other mods can register their own trait packs. Traits merge into reward pools, UI, and history automatically. See the [I Am Not Your Mom](https://steamcommunity.com/sharedfiles/filedetails/?id=3745224257) addon for a working example.
- **Right-click context menu** -- Quick-check your kills and how many you still need. Toggleable in Mod Options.
- **Staggered notification queue** -- Halo text with staggered display so batch rewards don't flood your screen
- **Smart trait conflict handling** -- Mutually exclusive traits are resolved automatically. The Catalog tab shows exactly why any trait is unavailable.
- **Server-authoritative Multiplayer** -- All trait changes validated and applied server-side
- **Full Singleplayer support** -- Same features, no server needed
- **Weighted random rewards** -- Higher trait cost = lower drop chance

### Sandbox Options (all configurable by the host)
- **Kill threshold** -- Set how many kills per milestone (2--10,000, default: 1,000)
- **Progressive milestone scaling** -- Milestones get harder over time, or keep it linear. Adjustable steepness (0.1x--2.0x).
- **Reward priority modes** -- Gain First / Lose First / Random
- **Grant Missed Opportunities** -- Install the mod mid-game? Get all your owed rewards at once
- **Individual trait toggles** -- Enable/disable every single one of the 43 traits
- **Positive/negative rewards** -- Toggle each reward type on or off
- **Debug logging** -- For sending me log files when things break

---

## Rarity Tiers

| Tier | Trait Cost | Drop Chance |
|------|-----------|-------------|
| Common | 1--2 points | Drops often |
| Uncommon | 3--4 points | Drops sometimes |
| Rare | 5--6 points | Drops rarely |
| Very Rare | 7+ points | Good luck |

---

## Included Traits

### Positive Traits (21 Earnable)

| Rarity | Traits |
|--------|--------|
| Common | Speed Demon, Cat's Eyes, Dextrous, Fast Reader, Inventive, Light Eater, Low Thirst, Outdoorsman, Wakeful |
| Uncommon | Iron Gut, Adrenaline Junkie, Eagle Eyed, Graceful, Inconspicuous, Nutritionist, Organized, Resilient |
| Rare | Fast Healer, Fast Learner, Keen Hearing |
| Very Rare | Thick Skinned |

### Negative Traits (22 Removable)

| Rarity | Traits |
|--------|--------|
| Common | High Thirst, Sunday Driver, All Thumbs, Clumsy, Cowardly, Slow Reader |
| Uncommon | Slow Healer, Weak Stomach, Smoker, Agoraphobic, Claustrophobic, Conspicuous, Hearty Appetite, Pacifist, Prone to Illness, Sleepyhead |
| Rare | Asthmatic, Hemophobic, Disorganized, Slow Learner |
| Very Rare | Illiterate, Thin Skinned |

### Not Included
- **Perk point traits** (Athletic, Strong, Stout, Fit, etc.) -- These grant skill bonuses that need extra implementation. May be added in the future.
- **Brave / Desensitized / Short Sighted / Hard of Hearing / Insomniac / Deaf** -- Available via the [I Am Not Your Mom](https://steamcommunity.com/sharedfiles/filedetails/?id=3745224257) addon.

---

## Architecture

```
shared/                          client/                          server/
BCRData.lua  -- trait data       BCRClient.lua  -- kill tracking  BCRServer.lua  -- reward processor
BCRConfig.lua -- sandbox opts    BCRNotifications.lua -- halo     (SP: loaded alongside client,
BCRCore.lua  -- engine           BCRStatsUI.lua -- 3-tab window    called directly)
                                  BCRModOptions.lua -- prefs
                                  BCRTests.lua -- unit tests

SP flow:  Client detects milestone -> calls BCRServer.ProcessRewardDirect() directly (same Lua VM)
MP flow:  Client sends RequestReward command -> Server validates -> sends RewardGranted back
```

- **Shared module** (`BCRData`, `BCRConfig`, `BCRCore`) contains all logic used by both sides: trait pools, weighted selection, milestone math, mutual exclusions
- **Singleplayer:** Client calls server-side functions directly since both load in the same Lua VM
- **Multiplayer:** Client sends `sendClientCommand()`, server validates and responds via `sendServerCommand()`
- **Addon API:** Third-party mods register via `BCR.RegisterCustomTraits()`. The [I Am Not Your Mom](https://github.com/Lenniitsch/PZ-BodyCountRewards-IAmNotYourMom) addon is the reference implementation.

---

## Compatibility

- Built for **Project Zomboid Build 42.19+** (Unstable Branch)
- Works in both **Singleplayer** and **Multiplayer**
- **Safe to install mid-game** -- reads your existing kill count
- **Safe to remove mid-game** -- all earned vanilla traits are permanently applied
- **No vanilla file overwrites** -- no conflicts with other mods
- Works with Skill Recovery Journal

---

## Languages

| Language | UI | Sandbox Options |
|----------|----|----|
| English | Full | Full |
| Deutsch (German) | Full | Full |
| Espanol (Spanish) | Full | Full |
| Русский (Russian) | Full | Full |
| Portugues (BR) | Full | Full |
| 简体中文 (Chinese) | Full | Full |
| 한국어 (Korean) | Full | Full |
| Turkce (Turkish) | Full | Full |
| Francais (French) | Full | Full |
| Polski (Polish) | Full | Full |
| Українська (Ukrainian) | Full | Full |

Translations are machine-generated. If something reads awkwardly in your language, [open an issue](https://github.com/Lenniitsch/PZ-BodyCountRewards/issues) or submit a PR. Native speakers who want to improve a translation are very welcome.

---

## For Mod Developers

BCR exposes a third-party addon API. See the [I Am Not Your Mom](https://github.com/Lenniitsch/PZ-BodyCountRewards-IAmNotYourMom) repository for a complete developer guide and working template. The README there walks through the full process: file structure, trait data format, sandbox options, translations, and testing.

Quick overview:

```lua
BCR.RegisterCustomTraits(
    "Your Addon Name",       -- sourceName
    "YourNamespace",         -- sandboxNamespace
    { { id = "base:Brave", cost = -4 } },  -- positive traits
    { { id = "base:Deaf",  cost = 12 } },  -- negative traits
    { ["base:Brave"] = {"base:Cowardly"} } -- exclusions
)
```

Trait IDs use ResourceLocation format (`namespace:PascalCase`), e.g. `"base:SpeedDemon"`, `"YourMod:TraitName"`. BCR resolves all trait IDs via `CharacterTrait.get(ResourceLocation.of(traitId))` -- works for vanilla and custom mod traits equally.

---

## Contributing

- **Translations** -- Add or improve support for your language
- **Bug fixes** -- Found something broken? PRs welcome
- **Feature suggestions** -- Open an issue to discuss ideas

---

## Credits

Inspired by Circuit's [Kill Milestones (Zombies) B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3540255691). Great concept -- this mod builds on that idea with more configuration options and multiplayer support.

---

## License

This project is licensed under the [MIT License](LICENSE).

## Links

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)
- [I Am Not Your Mom Addon](https://steamcommunity.com/sharedfiles/filedetails/?id=3745224257)
- [GitHub Repository](https://github.com/Lenniitsch/PZ-BodyCountRewards)
- [Report Issues](https://github.com/Lenniitsch/PZ-BodyCountRewards/issues)
