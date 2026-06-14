# Body Count Rewards

> *Finally, a mod where your body count actually matters.* Yes, the tagline is dumb. No, I won't change it.

A Project Zomboid Build 42 mod that rewards zombie kills with trait upgrades. Earn positive traits or shed negative ones by hitting kill milestones. Fully configurable via Sandbox Options.

Works in **Singleplayer** and **Multiplayer**.

[![Steam Workshop](https://img.shields.io/badge/Steam%20Workshop-Body%20Count%20Rewards-blue?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)

---

## Features

### Core
- **Full Stats UI** ÔÇö Three-tab window: Progress (with visual progress bar), Reward History, and Trait Catalog with drop chances
- **Right-click context menu** ÔÇö Quick-check your kills and how many you still need
- **Smart trait conflict handling** ÔÇö Mutually exclusive traits are automatically resolved (34 conflict rules)
- **Server-authoritative Multiplayer** ÔÇö All trait changes validated and applied server-side
- **Full Singleplayer support** ÔÇö Same features, no server needed
- **Weighted random rewards** ÔÇö Higher trait cost = lower drop chance

### Sandbox Options (all configurable by the host)
- **Kill threshold** ÔÇö Set how many kills per milestone (2ÔÇô10,000, default: 1,000)
- **Progressive milestone scaling** ÔÇö Milestones get harder over time, or keep it linear
- **Reward priority modes** ÔÇö Gain First / Lose First / Random
- **Grant Missed Opportunities** ÔÇö Install the mod mid-game? Get all your owed rewards at once
- **Individual trait toggles** ÔÇö Enable/disable every single one of the 43 traits
- **Positive/negative rewards** ÔÇö Toggle each reward type on or off

---

## Rarity Tiers

| Tier | Trait Cost | Drop Chance |
|------|-----------|-------------|
| Common | 1ÔÇô2 points | Drops often |
| Uncommon | 3ÔÇô4 points | Drops sometimes |
| Rare | 5ÔÇô6 points | Drops rarely |
| Very Rare | 7ÔÇô8 points | Good luck |

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
- **Perk point traits** (Athletic, Strong, Stout, Fit, Brave, etc.) ÔÇö These grant skill bonuses that need extra implementation. May be added in the future if there's demand.
- **Mod traits** ÔÇö Only vanilla traits are supported. Mod trait support is not planned until Build 42 reaches stable.

---

## Architecture

The mod follows a **client-server split architecture** designed for Build 42.13+:

```
ÔöîÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÉ         ÔöîÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÉ
Ôöé   BCR_Client     Ôöé         Ôöé   BCR_Server     Ôöé
Ôöé                  Ôöé         Ôöé                  Ôöé
Ôöé ÔÇó Kill tracking  Ôöé ÔöÇÔöÇMPÔöÇÔöÇÔûÂ Ôöé ÔÇó Validates killsÔöé
Ôöé ÔÇó Milestone      Ôöé command Ôöé ÔÇó Selects reward Ôöé
Ôöé   detection      Ôöé         Ôöé ÔÇó Applies trait  Ôöé
Ôöé ÔÇó Context menu   Ôöé ÔùÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ Ôöé ÔÇó Persists data  Ôöé
Ôöé ÔÇó Notifications  Ôöé responseÔöé ÔÇó transmitModDataÔöé
Ôöé ÔÇó Stats UI       Ôöé         Ôöé                  Ôöé
ÔööÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔö¼ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÿ         ÔööÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÿ
         Ôöé
         Ôöé SP: calls BCR_Server
         Ôöé     functions directly
         Ôöé
    ÔöîÔöÇÔöÇÔöÇÔöÇÔö┤ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÉ
    Ôöé   BCR_Shared     Ôöé
    Ôöé                  Ôöé
    Ôöé ÔÇó Trait registry Ôöé
    Ôöé ÔÇó Weighted RNG   Ôöé
    Ôöé ÔÇó Milestone math Ôöé
    Ôöé ÔÇó Mutual excl.   Ôöé
    Ôöé ÔÇó Sandbox opts   Ôöé
    ÔööÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÿ
```

- **Singleplayer:** Client calls server-side functions directly via `BCR.ProcessRewardDirect()`
- **Multiplayer:** Client sends `sendClientCommand()`, server validates and responds via `sendServerCommand()`
- **Shared module** contains all logic used by both sides (trait pools, milestone calculations, sandbox option parsing)

---

## Compatibility

- Built for **Project Zomboid Build 42.13.2+** (Unstable Branch)
- Works in both **Singleplayer** and **Multiplayer**
- **Safe to install mid-game** ÔÇö reads your existing kill count
- **Safe to remove mid-game** ÔÇö all earned traits are permanently applied
- **No vanilla file overwrites** ÔÇö no conflicts with other mods

---

## Languages

| Language | UI | Sandbox Options |
|----------|----|----|
| ­ƒç¼­ƒçº English | Ô£à | Ô£à |
| ­ƒç®­ƒç¬ German (Deutsch) | Ô£à | Ô£à |

**Translation contributions are welcome!** See the `Translate/` folder for the translation file format.

---

## Contributing

Contributions are welcome! Here's how you can help:

- ­ƒîì **Translations** ÔÇö Add support for your language
- ­ƒÉø **Bug fixes** ÔÇö Found something broken? PRs welcome
- ­ƒÆí **Feature suggestions** ÔÇö Open an issue to discuss ideas

---

## Credits

Inspired by Circuit's [Kill Milestones (Zombies) B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3540255691). Great concept ÔÇö this mod builds on that idea with more configuration options and multiplayer support.

---

## License

This project is licensed under the [MIT License](LICENSE).

## Links

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)
- [Report Issues](https://github.com/Lenniitsch/BodyCountRewards/issues)
