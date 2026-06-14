# Agent Task: Rewrite BodyCountRewards v1.3.0 from Scratch

You are implementing a complete Lua mod for **Project Zomboid Build 42.19+**. The mod already has scaffolding (mod.info, sandbox options, translations). You create the 9 Lua source files.

---

## Quick-Start

1. Read `docs/prompts/BCR_Coding_Guidelines.md` first — that's your rulebook
2. Read `docs/BCR_v1.3.0_Spec.md` — that's the full architecture spec
3. Read `docs/PZ_Codebase_Reference.md` — API references and vanilla patterns
4. The mod folder you work in: `BodyCountRewards/Contents/mods/BodyCountRewards/42.19/`
5. Do NOT read or reference `42.16/` — this is a from-scratch rewrite

**What the mod does:** Rewards zombie kill milestones with trait modifications. Earn positive traits, remove negative traits. Weighted random selection (higher cost = rarer drop). SP + MP. 43 traits in the pool, individually toggleable via sandbox. Three-tab stats UI. Halo text notifications.

---

## Files Already Present (do NOT modify)

```
42.19/
├── mod.info                     id=BCR, versionMin=42.19
├── poster.png
├── bcr_icon.png
├── media/
│   ├── sandbox-options.txt      Complete, no changes needed
│   └── lua/
│       ├── shared/Translate/    22 JSONs, 11 languages — complete
│       └── client/BCRTests_Research.lua  Research harness — do not touch
```

## Files You Create (9 total)

```
42.19/media/lua/
├── shared/
│   ├── BCRData.lua
│   ├── BCRConfig.lua
│   └── BCRCore.lua
├── server/
│   └── BCRServer.lua
└── client/
    ├── BCRClient.lua
    ├── BCRNotifications.lua
    ├── BCRStatsUI.lua
    ├── BCRModOptions.lua
    └── BCRTests.lua
```

Build in this order (each file depends on the ones above it).

---

## BCRData.lua

Pure data tables. Zero functions. Zero logic.

```lua
BCR = BCR or {}
```

Export these tables:
- `BCR.MAX_WEIGHT_COST = 8`
- `BCR.PositiveTraits` — array of `{ id = "UPPER_SNAKE", cost = negative_number }` — 21 entries
- `BCR.NegativeTraits` — array of `{ id = "UPPER_SNAKE", cost = positive_number }` — 22 entries
- `BCR.Exclusions` — `{ ["TRAIT_A"] = {"TRAIT_B", ...}, ... }` — 32 symmetric keys
- `BCR.RarityTiers` — `{ common = { maxCost=2, color={0.80,0.80,0.80} }, uncommon={ maxCost=4, color={0.60,1.00,0.20} }, rare={ maxCost=6, color={1.00,0.60,0.20} }, veryRare={ maxCost=99, color={0.80,0.30,1.00} } }`

**Positive traits and costs:**
SPEED_DEMON:-1, NIGHT_VISION:-3, DEXTROUS:-2, FAST_READER:-2, INVENTIVE:-2, LIGHT_EATER:-2, LOW_THIRST:-2, OUTDOORSMAN:-2, NEEDS_LESS_SLEEP:-3, IRON_GUT:-2, ADRENALINE_JUNKIE:-4, EAGLE_EYED:-4, GRACEFUL:-4, INCONSPICUOUS:-4, NUTRITIONIST:-2, ORGANIZED:-4, RESILIENT:-4, FAST_HEALER:-6, FAST_LEARNER:-6, KEEN_HEARING:-6, THICK_SKINNED:-8

**Negative traits and costs:**
HIGH_THIRST:2, SUNDAY_DRIVER:1, ALL_THUMBS:2, CLUMSY:2, COWARDLY:2, SLOW_READER:2, SLOW_HEALER:3, WEAK_STOMACH:2, SMOKER:3, AGORAPHOBIC:4, CLAUSTROPHOBIC:4, CONSPICUOUS:4, HEARTY_APPETITE:4, PACIFIST:5, PRONE_TO_ILLNESS:4, NEEDS_MORE_SLEEP:4, ASTHMATIC:5, HEMOPHOBIC:5, DISORGANIZED:6, SLOW_LEARNER:6, ILLITERATE:10, THIN_SKINNED:8

**Exclusions (every pair must be SYMMETRIC — if A excludes B, B excludes A too):**
ADRENALINE_JUNKIE → AGORAPHOBIC, CLAUSTROPHOBIC, COWARDLY
AGORAPHOBIC → ADRENALINE_JUNKIE, CLAUSTROPHOBIC
ALL_THUMBS → DEXTROUS
CLAUSTROPHOBIC → ADRENALINE_JUNKIE, AGORAPHOBIC
CLUMSY → GRACEFUL
CONSPICUOUS → INCONSPICUOUS
COWARDLY → ADRENALINE_JUNKIE
DEXTROUS → ALL_THUMBS
DISORGANIZED → ORGANIZED
FAST_HEALER → SLOW_HEALER
FAST_LEARNER → SLOW_LEARNER
FAST_READER → ILLITERATE, SLOW_READER
GRACEFUL → CLUMSY
HEARTY_APPETITE → LIGHT_EATER
HIGH_THIRST → LOW_THIRST
ILLITERATE → FAST_READER, SLOW_READER
INCONSPICUOUS → CONSPICUOUS
IRON_GUT → WEAK_STOMACH
LIGHT_EATER → HEARTY_APPETITE
LOW_THIRST → HIGH_THIRST
ORGANIZED → DISORGANIZED
PRONE_TO_ILLNESS → RESILIENT
RESILIENT → PRONE_TO_ILLNESS
NEEDS_MORE_SLEEP → NEEDS_LESS_SLEEP
NEEDS_LESS_SLEEP → NEEDS_MORE_SLEEP
SLOW_HEALER → FAST_HEALER
SLOW_LEARNER → FAST_LEARNER
SLOW_READER → FAST_READER, ILLITERATE
SPEED_DEMON → SUNDAY_DRIVER
SUNDAY_DRIVER → SPEED_DEMON
THICK_SKINNED → THIN_SKINNED
THIN_SKINNED → THICK_SKINNED
WEAK_STOMACH → IRON_GUT

---

## BCRConfig.lua

```lua
BCR = BCR or {}
require "BCRData"

BCR.PRIORITY_POSITIVE_FIRST = 1
BCR.PRIORITY_NEGATIVE_FIRST = 2
BCR.PRIORITY_RANDOM = 3
BCR.MODULE_NAME = "BCR"
BCR.MAX_NOTIFICATION_QUEUE = 8
BCR.opts = nil
BCR.DEBUG = false

function BCR.DebugPrint(msg)
    if BCR.DEBUG then print("[BCR] " .. tostring(msg)) end
end

function BCR.RefreshConfig()
    local sv = SandboxVars.BCR or {}
    BCR.opts = {
        BodyCount                = sv.BodyCount or 1000,
        enablePositive           = sv.enablePositiveTraits ~= false,
        enableNegative           = sv.enableNegativeTraits ~= false,
        rewardPriority           = sv.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST,
        grantMissedOpportunities = sv.grantMissedOpportunities == true,
        MilestoneScaling         = sv.MilestoneScaling or 1,
        ProgressiveScalingFactor = sv.ProgressiveScalingFactor or 0.5,
    }
    BCR.DEBUG = sv.enableDebugLogging == true
end

function BCR.IsTraitAllowed(id)
    local sv = SandboxVars.BCR or {}
    local key = "allow_" .. id
    if sv[key] == false then
        BCR.DebugPrint("Trait blocked by sandbox: " .. id)
        return false
    end
    return true
end
```

---

## BCRCore.lua

This is the engine. `require "BCRData"` and `require "BCRConfig"`.

**Trait Registry:**
- `BCR.GetTraitUserdata(traitId)` → CharacterTrait[traitId] with cache. Returns userdata or nil.
- Cache stores `false` for misses, `nil` means not-yet-looked-up. Check: `if cached ~= nil then return cached end`

**Player Trait Checks:**
- `BCR.PlayerHasTrait(player, traitId)` → tri-state: true/has, false/doesn't, nil/error. pcall-wrapped. Resolve trait first, then pcall `player:hasTrait(obj)`.
- `BCR.HasMutuallyExclusiveTrait(player, traitId)` → returns `true, blockerId` or `false`. For each exclusion, check `PlayerHasTrait == true`.
- `BCR.GetPlayerTraitsList(player)` → array of trait ID strings. pcall getCharacterTraits, getKnownTraits, iterate with size/get.

**Trait Modification:**
- Internal `modifyTrait(player, traitEntry, action)` where action="add"|"remove". Unified — handles nil check, trait resolution, pre-verification, pcall traits:add/remove, returns bool.
- `BCR.AddTrait(player, traitEntry)` → calls modifyTrait("add")
- `BCR.RemoveTrait(player, traitEntry)` → calls modifyTrait("remove")
- Pre-check for add: `PlayerHasTrait ~= false` (blocks if already has OR error)
- Pre-check for remove: `PlayerHasTrait == true` (blocks if doesn't have OR error)
- Trust pcall result — do NOT re-check hasTrait after modification

**Pool Building (accepts optional customTraits table for future extensibility):**
- `BCR.BuildEarnablePool(player, customTraits)` — merges PositiveTraits with customTraits, filters: IsTraitAllowed, player doesn't have (~=false), no mutual exclusion. Resolves trait userdata. Calculates rarity and weight. Returns array of `{ trait, traitUserdata, cost, rarity, weight }`.
- `BCR.BuildRemovablePool(player, customTraits)` — same but for negative traits, checks player HAS trait (==true).
- `BCR.FilterPoolByExclusion(pool, excludeSet)` — removes entries whose trait is in excludeSet. Nil/empty excludeSet returns pool unchanged. Use explicit loop, not next().

**Weighted Selection:**
- `BCR.WeightedRandomSelect(pool)` — cumulative sum of weights, ZombRand(totalWeight). Fallback: random index if totalWeight <= 0. Returns nil for empty pool.
- `BCR.GetRarity(cost)` → "common"|"uncommon"|"rare"|"veryRare" — absolute cost vs RarityTiers.maxCost
- `BCR.GetRarityColor(cost)` → {r,g,b} from RarityTiers
- `BCR.CalculateWeight(cost)` → `math.max(1, (MAX_WEIGHT_COST - math.abs(cost)) + 1)`

**Milestone Math (pure, from opts table):**
- `BCR.GetKillsForMilestone(n, opts)` — n ≤ 0 → 0. Linear: n × BodyCount. Progressive (factor > 0): quadratic formula `BodyCount × (n + F × n × (n-1) / 2)`. Factor ≤ 0 → linear.
- `BCR.GetMilestonesAtKills(kills, opts)` — kills ≤ 0 → 0. Linear: floor(kills / BodyCount). Progressive: inverse quadratic. BodyCount=0 → 0.

**Display Names:**
- `BCR.GetTraitDisplayName(traitId)` — override table {NEEDS_LESS_SLEEP="UI_trait_LessSleep", NEEDS_MORE_SLEEP="UI_trait_MoreSleep", DEXTROUS="UI_trait_Dexterous"}. Then title-case: `UI_trait_SpeedDemon`. Then trait:getName(). Fallback: formatTraitName (underscores→spaces, title case).

**ModData:**
- `BCR.EnsureModData(player)` — pcall getModData, init {kills=0, rewardsGiven=0, traitHistory={}}. Returns bcrData or nil.

**Availability:**
- `BCR.HasAvailableRewards(player)` — true if any trait still earnable or removable.

---

## BCRServer.lua

Guard: `if isClient() and not isServer() then return end`
Requires: BCRCore

Private helpers (not on BCR table):
- `getZombieKillsSafe(player)` → pcall-wrapped getZombieKills
- `getWorldAgeHoursSafe()` → pcall-wrapped getGameTime:getWorldAgeHours, guarded with `and`
- `validateMilestone(player, bcrData, opts)` → isValid:bool, missedCount:int
- `buildAndApplyReward(player, earnablePool, removablePool, opts, modifiedTraits)` → builds attempt order based on rewardPriority, applies first successful trait, returns result or nil
- `recordTraitHistory(bcrData, result)` → inserts {trait, action, rarity, timestamp} into bcrData.traitHistory

Exported:
- `BCR.ProcessRewardDirect(player)` — SP direct reward path: EnsureModData → validateMilestone → BuildEarnablePool + BuildRemovablePool → buildAndApplyReward → record history. Returns result {trait, displayName, action, rarity, color, cost} or nil.

MP handlers (locals, not exported):
- `handleRequestReward(player, args)` — EnsureModData, use best kills (max of ModData, reported, server API). Validate. If grantMissedOpportunities: loop rewardsToGive times, rebuild pools each iteration, deduplicate via modifiedTraits (check totalGranted > 0, not O(n) loop). Send RewardGranted per reward, send RewardBatchComplete at end. pcall transmitModData ONCE after batch.
- `handleSyncKills(player, args)` — EnsureModData, prefer server kill count (anti-cheat). Never decrease kills. Update bcrData.kills. pcall transmitModData. Send KillsSynced back.

Event: `Events.OnClientCommand.Add(module, command, player, args)` — dispatch RequestReward and SyncKills.

---

## BCRClient.lua

Requires: BCRCore, BCRNotifications, BCRStatsUI, BCRModOptions

`local BCR_Config = require "BCRModOptions"`

Constants: `PENDING_REWARD_DELAY_TICKS = 90`, `NOTIFICATION_DELAY_TICKS = 200` (use BCRCore's BCR.MAX_NOTIFICATION_QUEUE for cap).

State variables (all local): lastKnownKills, pendingRewardsCount, pendingRewardTimer, isPendingRequestInFlight, hasShownAllTraitsMessage, shouldShowFinalMessage, showFinalMessageTimer.

**OnCreatePlayer:** BCR.RefreshConfig(), EnsureModData, get kills. If HasAvailableRewards == false → set hasShownAllTraitsMessage = true, log it. Reset all state variables for new character.

**OnPlayerUpdate:** If hasShownAllTraitsMessage → return immediately. Detect new kills by comparing getZombieKills() vs lastKnownKills. Update bcrData.kills. If milestone reached:
- SP: getMissedMilestones, if >1 queue pending, else ProcessRewardDirect, enqueue notification, refresh stats, check exhaustion.
- MP: sendClientCommand RequestReward, if pending queue already active skip duplicate.
Drain pending rewards with PENDING_REWARD_DELAY_TICKS timer. Call BCR.UpdateNotifications(player). Show final message on exhaustion with timer.

**OnServerCommand handlers:**
- RewardGranted: increment bcrData.rewardsGiven, EnqueueNotification, RefreshStatsWindow
- RewardBatchComplete: set pendingRewardsCount from remainingMilestones, unpause processing, check exhaustion
- KillsSynced: update kills (align lastKnownKills), update rewardsGiven ONLY if server > client
- RewardError / NoRewardAvailable: clear isPendingRequestInFlight

**Context menu (OnFillWorldObjectContextMenu):** Respect BCR_Config.showContextMenu toggle. Show "View Stats" option. Show progress text OR "All rewards granted" based on exhaustion.

Event registration: Wrap OnPlayerUpdate in pcall. Register OnCreatePlayer, OnServerCommand, OnFillWorldObjectContextMenu.

---

## BCRNotifications.lua

Standalone. Requires BCRCore for getTraitDisplayName.

Local state: notificationQueue = {}, notificationTimer = 0, isShowingNotification = false.

- `BCR.EnqueueNotification(result)` — if queue >= BCR.MAX_NOTIFICATION_QUEUE: replace with batch entry {trait="BATCH", displayName="N rewards", action="batch", rarity="common", color={1,1,1}}. Then table.insert the new result.
- `BCR.UpdateNotifications(player)` — drain queue one per NOTIFICATION_DELAY_TICKS. Action "batch": HaloTextHelper.addTextWithArrow(200,200,200). "added": green (0,255,0). Else (removed): orange (255,165,0). Cooldown after queue drains.
- `BCR.ShowFinalMessage(player)` — HaloTextHelper.addText with getText("UI_BCR_AllRewardsGranted")

---

## BCRStatsUI.lua

Requires: BCRCore, ISUI components (ISCollapsableWindow, ISTabPanel, ISRichTextPanel, ISPanel).

**BCRProgressPanel** (ISPanel subclass with dirty-flag prerender):
- .cached = progress data table set by updateContent()
- prerender() only draws if self.cached is set, then sets self.cached = nil for dirty flag
- Content: kill counter header with large number, progress bar (color segments: red<35%, yellow<75%, green>=75%), next reward at, kills remaining, total rewards, scaling mode label, reward priority label, milestone roadmap (past 2 + next 5)
- Roadmap markers: [x] reached, [>] current, [ ] future — color-coded
- formatNumber helper: insert thousand separator (getText "UI_BCR_ThousandSeparator" or ",")

**BCRStatsWindow** (ISCollapsableWindow subclass):
- Title from getText("UI_BCR_StatsTitle")
- ISTabPanel with 3 tabs:
  1. "Progress" — BCRProgressPanel
  2. "History" — ISRichTextPanel, buildHistoryText: reverse chronological, colored +/- prefixes, rarity labels
  3. "Catalog" — ISRichTextPanel, buildCatalogText: all traits with status. Available: colored + rarity label. Unavailable: greyed + reason (sandbox disabled / already earned / already owned / conflicts with X / unavailable). Only show negative traits the player HAS or has already removed.

**Public API:**
- `BCR.ShowStatsWindow(player)` — create or toggle. Centers on screen.
- `BCR.RefreshStatsWindow()` — call updateContent() if window is visible.

---

## BCRModOptions.lua

```lua
local config = { showContextMenu = true }

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create("BodyCountRewards",
        getText("UI_BCR_MenuTitle") or "Body Count Rewards")
    options:addTickBox("showContextMenu",
        getText("UI_BCR_Option_ShowMenu") or "Show Context Menu", true,
        getText("UI_BCR_Option_ShowMenu_tooltip") or "When enabled, right-clicking shows Body Count Rewards progress in the context menu.")
    options.apply = function(self)
        for k, v in pairs(self.dict) do
            if v.type and v.type ~= "button" then
                config[k] = v:getValue()
            end
        end
    end
    Events.OnMainMenuEnter.Add(function()
        if options then options:apply() end  -- nil-guarded
    end)
end

return config
```

---

## BCRTests.lua

Requires all other modules. Export `BCRRunTests()` function.

Mini-framework: passed/failed/skipped counters, suite names, detailed failure messages, final summary.

13 suites, each run in its own pcall via `runSuite()`:
1. Trait Registry — all 43 traits resolve via GetTraitUserdata
2. Rarity & Weight — getRarity, calculateWeight per tier, weight decreases with cost
3. Mutual Exclusion — symmetry check, no self-exclusion
4. Weighted Selection — nil/empty/single/90:10 distribution/zero-weight fallback
5. Display Names — all 43 non-empty, nil→"Unknown"
6. Data Integrity — no duplicates, no overlap pos↔neg, counts 21/22, HasAvailableRewards(nil)=false
7. Sandbox — RefreshConfig types, IsTraitAllowed, priority constants
8. Filter Pool — nil/empty pools, nil/empty/single/all exclusions
9. Milestone Math — linear/progressive edge cases, zero/negative kills, zero BodyCount, factor zero
10. Add/Remove — add positive, duplicate fail, remove, absent fail, nil player (needs player)
11. Exclusions — add A→B blocked, add B→A blocked, 3-way FAST_READER (needs player)
12. Pool Building — field validation, already-owned filter, nil player guard (needs player)
13. Catch-Up — 0 kills, exact, 3x, below, duplicate, ProcessRewardDirect (needs player + SP)

Suites 10-13: skip if no player (not in SP game), print useful skip reason.
Suites 10-13: undo trait changes after testing (restore state).
Mutation test cleanup: if a suite crashes mid-test, attempt best-effort trait cleanup.

---

## Verification Checklist

After building all 9 files, verify:
- [ ] No require() failures in file headers
- [ ] BCRData: PositiveTraits has 21 entries, NegativeTraits 22, Exclusions 32 keys
- [ ] BCRConfig: RefreshConfig and IsTraitAllowed defined, constants set
- [ ] BCRCore: all functions listed above exist and are accessible via BCR.*
- [ ] BCRServer: guard line present, ProcessRewardDirect exported, pcall on transmitModData
- [ ] BCRClient: all event handlers registered, context menu respects ModOptions toggle
- [ ] BCRNotifications: EnqueueNotification, UpdateNotifications, ShowFinalMessage exported
- [ ] BCRStatsUI: ShowStatsWindow, RefreshStatsWindow exported
- [ ] BCRModOptions: returns config table with showContextMenu
- [ ] BCRTests: BCRRunTests function exists
- [ ] No raw SandboxVars.BCR access outside BCRConfig
- [ ] No ResourceLocation trait lookup
- [ ] No next() calls on tables
- [ ] No un-pcall'd Java bridge calls
- [ ] BCRTests_Research.lua still loads without modification
