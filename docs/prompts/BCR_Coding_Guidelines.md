# BCR Coding Guidelines for Agents

> Rules, patterns, and pitfalls for writing Project Zomboid B42.19+ Lua mod code. Read this before touching any file.

---

## PZ Architecture

| Domain | Folder | Runs where | Purpose |
|--------|--------|------------|---------|
| shared | `media/lua/shared/` | Client + Server | Definitions, shared logic |
| server | `media/lua/server/` | Server (or SP host) | Authoritative logic, trait mutations |
| client | `media/lua/client/` | Player machine only | UI, input, HUD, polling |

**SP:** All three load in the same Lua VM. Server guard: `if isClient() and not isServer() then return end`

**Load order:** shared (mods) → client (mods) → server (mods, on save load)

---

## Module Bootstrap

Every file starts with:
```lua
BCR = BCR or {}
```

No module should use `local BCR = {}` — the global table is shared across all files.

Files can `require()` other files. Load order matters: `require "BCRData"` before `require "BCRCore"` etc. The spec defines the dependency chain.

---

## Naming

| Item | Convention | Example |
|------|-----------|---------|
| File names | PascalCase, no `_` | `BCRCore.lua`, `BCRClient.lua` |
| Trait IDs | UPPER_SNAKE_CASE | `SPEED_DEMON`, `KEEN_HEARING` |
| Public functions | PascalCase | `BCR.GetEarnableTraits()` |
| Private functions | camelCase | `buildTraitPool()` |
| Module constants | UPPER_SNAKE_CASE | `BCR.PRIORITY_POSITIVE_FIRST` |
| Sandbox keys | camelCase | `grantMissedOpportunities` |
| Translation keys | `Sandbox_BCR_*` / `UI_BCR_*` | keep existing keys, don't rename |

---

## Must-Do: pcall All Java Bridge Calls

Every call that touches Java (not pure Lua) must be wrapped in `pcall`:

```lua
-- ✅ CORRECT
local ok, modData = pcall(function() return player:getModData() end)
if not ok or not modData then return nil end

local ok, result = pcall(function() return player:hasTrait(traitObj) end)
if not ok then return nil end  -- tri-state

-- ❌ WRONG
local modData = player:getModData()  -- can crash!
local hasTrait = player:hasTrait(traitObj)  -- can crash!
```

**Java calls that need pcall:**
- `player:getModData()`
- `player:getZombieKills()` / `getLastZombieKills()`
- `player:getCharacterTraits()`
- `traits:add(userdata)` / `traits:remove(userdata)`
- `player:hasTrait(userdata)`
- `player:transmitModData()`
- `getGameTime():getWorldAgeHours()`
- `knownTraits:size()` / `knownTraits:get(i)`

---

## Must-Do: Tri-State hasTrait Handling

`player:hasTrait()` can return:
- `true` — definitely has the trait
- `false` — definitely does NOT have the trait
- `nil` — error checking (player invalid, trait not found, etc.)

Callers must handle all three. The pattern:

```lua
-- Checking if player has a trait (requires "definitely has")
if BCR.PlayerHasTrait(player, traitId) == true then
    -- player definitely has it
end

-- Checking if player does NOT have a trait (must not have, no error)
local hasTrait = BCR.PlayerHasTrait(player, traitId)
if hasTrait ~= false then
    return -- already has OR error — block the operation
end
-- Now safe: player definitely does NOT have the trait
```

---

## Must-Do: Trust pcall Result, Don't Re-Verify

After `traits:add()` or `traits:remove()`, the engine may take a tick to sync visible state. `player:hasTrait()` may return stale data.

```lua
-- ✅ CORRECT
local success, err = pcall(function() traits:add(traitUserdata) end)
if success then
    return true  -- trust the pcall, don't check hasTrait now
end

-- ❌ WRONG
traits:add(traitUserdata)
if player:hasTrait(traitUserdata) then  -- may return false even though add succeeded!
    return true
end
```

---

## Must-Do: Guard getGameTime()

```lua
-- ✅ CORRECT
local gt = getGameTime()
local hours = gt and gt:getWorldAgeHours() or 0

-- ❌ WRONG
local hours = getGameTime():getWorldAgeHours()  -- nil error during early init
```

---

## Must-Do: SandboxVars Only in BCRConfig

Read `SandboxVars.BCR` **only** in `BCR.RefreshConfig()`. Everywhere else: use `BCR.opts`.

```lua
-- ✅ CORRECT anywhere
local bodyCount = BCR.opts.BodyCount

-- ❌ WRONG anywhere outside BCRConfig
local bodyCount = SandboxVars.BCR.BodyCount or 1000
```

---

## Must-Do: Trait Access via CharacterTrait[id]

```lua
-- ✅ CORRECT — confirmed 43/43 traits resolve this way in B42.19
local userdata = CharacterTrait[traitId]

-- ❌ WRONG — old pattern, more expensive, not needed
local stripped = string.lower(string.gsub(traitId, "_", ""))
local rl = ResourceLocation.of("base:" .. stripped)
local userdata = CharacterTrait.get(rl)
```

Cache results:
```lua
local traitUserdataCache = {}
local cached = traitUserdataCache[traitId]
if cached ~= nil then return cached end  -- nil = not yet looked up, false = looked up and not found
```

---

## Never-Do: use `next()` on Tables

`next()` is a blocking operation in PZ's coroutine/CSP environment. Use explicit loops instead:

```lua
-- ✅ CORRECT
local empty = true
for _ in pairs(t) do empty = false; break end
if empty then return end

-- ❌ WRONG
if not next(t) then return end
```

---

## Never-Do: transmitModData() Without pcall

A disconnected player causes `transmitModData()` to throw. Always wrap:

```lua
-- ✅ CORRECT
if isServer() then
    pcall(function() player:transmitModData() end)
end

-- Also: call only ONCE after batch, not per-reward
```

---

## Event Registration Patterns

```lua
-- Client lifecycle
Events.OnPlayerUpdate.Add(function(player) ... end)
Events.OnCreatePlayer.Add(function(playerNum, player) ... end)
Events.OnServerCommand.Add(function(module, command, args) ... end)
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test) ... end)

-- Server lifecycle
Events.OnClientCommand.Add(function(module, command, player, args) ... end)
```

**OnPlayerUpdate:** Wrap handler body in pcall so a single error doesn't break the whole event chain:
```lua
Events.OnPlayerUpdate.Add(function(player)
    local ok, err = pcall(function() BCR_OnPlayerUpdate(player) end)
    if not ok then BCR.DebugPrint("OnPlayerUpdate error: " .. tostring(err)) end
end)
```

---

## MP Communication

```lua
-- Client → Server
sendClientCommand(player, "BCR", "RequestReward", { kills = count })

-- Server → Client (one player)
sendServerCommand(player, "BCR", "RewardGranted", { trait = id, action = "added", ... })

-- Server → Client (all players) — NOT used in BCR
-- sendServerCommandV("BCR", "eventName", "key1", val1, ...)
```

---

## SP vs MP

```lua
-- SP detection (for informational use only)
function BCR.isSinglePlayer()
    return not isClient() and not isServer()
end

-- In SP, client calls server function directly:
if BCR.isSinglePlayer() then
    local result = BCR.ProcessRewardDirect(player)  -- defined in BCRServer.lua
else
    sendClientCommand(player, "BCR", "RequestReward", { kills = kills })
end
```

This cross-module call works in SP because both client and server share the same Lua VM.

---

## Performance

| Rule | Why |
|------|-----|
| Cache sandbox options | `BCR.opts` read once, not `SandboxVars.BCR` every tick |
| Cache trait userdata | `CharacterTrait[id]` lookup cached per trait name |
| Exit early when exhausted | `hasShownAllTraitsMessage` check at TOP of OnPlayerUpdate |
| Dirty-flag UI redraw | StatsUI progress panel only redraws when data changes |
| Batch transmitModData | Once after reward batch, not per reward |

---

## File Structure Rules

- Blank lines between logical sections
- Section comment bars for major sections:
  ```lua
  -- ============================================================
  -- TRAIT REGISTRY
  -- ============================================================
  ```
- No inline comments on data — data should be self-explanatory
- Complex logic gets ONE concise line comment explaining intent (not mechanics)
- Module header at top stating file purpose and build version

---

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `KillsSynced` overwrites client rewardsGiven with stale server value | Only update if `args.rewardsGiven > client.rewardsGiven` |
| Pending reward re-entry (SP) | Set `isPendingRequestInFlight = true`, clear after ProcessRewardDirect returns |
| Pending reward re-entry (MP) | Hold `isPendingRequestInFlight` until RewardBatchComplete/RewardError arrives |
| Batch dedup uses O(n) empty-check per iteration | Use `totalGranted > 0` instead of looping modifiedTraits |
| Notification queue unbounded growth | Coalesce to batch entry at `MAX_NOTIFICATION_QUEUE` |
| StatsUI crashes on invalid player | pcall `getModData()` in `getBCRData()` |
| ModOptions handler crashes | Nil-guard `if options then options:apply() end` |
| getPlayer() doesn't exist as global | Use `getSpecificPlayer(0)` to get local player |
| getName() returns lowercase "speeddemon" | Translation key uses PascalCase: `"UI_trait_SpeedDemon"` |

---

## Reference: How Vanilla Does Things

For patterns you're unsure about, check the vanilla Lua source at `pz-codebase-files/lua/`:

| Pattern | File |
|---------|------|
| Dynamic trait add/remove | `lua/server/XpSystem/XpUpdate.lua` lines 207-243 |
| Client→Server commands | `lua/server/ClientCommands.lua` |
| Player stats display (getZombieKills) | `lua/client/ISUI/PlayerStats/ISPlayerStatsUI.lua` |
| Character creation (traits, exclusions) | `lua/client/OptionScreens/CharacterCreationProfession.lua` |
| Sandbox options structure | `lua/shared/Sandbox/Apocalypse.lua` |
| ModData usage | `lua/server/XpSystem/XpUpdate.lua` lines 337-347 |
| Halo text notifications | `XpUpdate.lua` line 197, also `PZ_Codebase_Reference.md` §2.5 |
| OOP base class | `lua/shared/ISBaseObject.lua` |

Vanilla code does NOT pcall trait add/remove — we do it defensively. Vanilla also doesn't pcall transmitModData — we do.
