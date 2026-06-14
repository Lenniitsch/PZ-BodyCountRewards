# Body Count Rewards

> *Finally, a mod where your body count actually matters.* Yes, the tagline is dumb. No, I won't change it.

A Project Zomboid Build 42 mod that rewards zombie kills with trait upgrades. Earn positive traits or shed negative ones by hitting kill milestones. Fully configurable via Sandbox Options.

Works in **Singleplayer** and **Multiplayer**.

[![Steam Workshop](https://img.shields.io/badge/Steam%20Workshop-Body%20Count%20Rewards-blue?logo=steam)](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)

---

## Features

### Core
- **Full Stats UI** — Three-tab window: Progress (with visual progress bar), Reward History, and Trait Catalog with drop chances
- **Right-click context menu** — Quick-check your kills and how many you still need
- **Smart trait conflict handling** — Mutually exclusive traits are automatically resolved (34 conflict rules)
- **Server-authoritative Multiplayer** — All trait changes validated and applied server-side
- **Full Singleplayer support** — Same features, no server needed
- **Weighted random rewards** — Higher trait cost = lower drop chance

### Sandbox Options (all configurable by the host)
- **Kill threshold** — Set how many kills per milestone (2–10,000, default: 1,000)
- **Progressive milestone scaling** — Milestones get harder over time, or keep it linear
- **Reward priority modes** — Gain First / Lose First / Random
- **Grant Missed Opportunities** — Install the mod mid-game? Get all your owed rewards at once
- **Individual trait toggles** — Enable/disable every single one of the 43 traits
- **Positive/negative rewards** — Toggle each reward type on or off

---

## Rarity Tiers

| Tier | Trait Cost | Drop Chance |
|------|-----------|-------------|
| Common | 1–2 points | Drops often |
| Uncommon | 3–4 points | Drops sometimes |
| Rare | 5–6 points | Drops rarely |
| Very Rare | 7–8 points | Good luck |

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
- **Perk point traits** (Athletic, Strong, Stout, Fit, Brave, etc.) — These grant skill bonuses that need extra implementation. May be added in the future if there's demand.
- **Mod traits** — Only vanilla traits are supported. Mod trait support is not planned until Build 42 reaches stable.

---

## Architecture

The mod follows a **client-server split architecture** designed for Build 42.13+:

```
┌───────────────────┐         ┌───────────────────┐
│   BCR_Client      │         │   BCR_Server      │
│                   │         │                   │
│ • Kill tracking   │ ──MP──▶ │ • Validates kills │
│ • Milestone       │ command │ • Selects reward  │
│   detection       │         │ • Applies trait   │
│ • Context menu    │ ◀────── │ • Persists data   │
│ • Notifications   │ response│ • transmitModData │
│ • Stats UI        │         │                   │
└─────────┬─────────┘         └───────────────────┘
          │
          │ SP: calls BCR_Server
          │     functions directly
          │
    ┌─────┴──────────────────┐
    │   BCR_Shared           │
    │                        │
    │ • Trait registry       │
    │ • Weighted RNG         │
    │ • Milestone math       │
    │ • Mutual excl.         │
    │ • Sandbox opts         │
    └────────────────────────┘
```

- **Singleplayer:** Client calls server-side functions directly via `BCR.ProcessRewardDirect()`
- **Multiplayer:** Client sends `sendClientCommand()`, server validates and responds via `sendServerCommand()`
- **Shared module** contains all logic used by both sides (trait pools, milestone calculations, sandbox option parsing)

---

## Compatibility

- Built for **Project Zomboid Build 42.13.2+** (Unstable Branch)
- Works in both **Singleplayer** and **Multiplayer**
- **Safe to install mid-game** — reads your existing kill count
- **Safe to remove mid-game** — all earned traits are permanently applied
- **No vanilla file overwrites** — no conflicts with other mods

---

## Languages

| Language | UI | Sandbox Options |
|----------|----|----|
| 🇬🇧 English | ✅ | ✅ |
| 🇩🇪 German (Deutsch) | ✅ | ✅ |

**Translation contributions are welcome!** See the `Translate/` folder for the translation file format.

---

## Contributing

Contributions are welcome! Here's how you can help:

- 🌍 **Translations** — Add support for your language
- 🐛 **Bug fixes** — Found something broken? PRs welcome
- 💡 **Feature suggestions** — Open an issue to discuss ideas

---

## Credits

Inspired by Circuit's [Kill Milestones (Zombies) B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3540255691). Great concept — this mod builds on that idea with more configuration options and multiplayer support.

---

## License

This project is licensed under the [MIT License](LICENSE).

## Links

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3660382016)
- [Report Issues](https://github.com/Lenniitsch/PZ-BodyCountRewards/issues)
