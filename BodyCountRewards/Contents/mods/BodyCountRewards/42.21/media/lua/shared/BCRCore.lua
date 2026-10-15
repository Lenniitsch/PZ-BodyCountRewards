-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRCore (Build 42.21+)
-- Engine: trait registry, pool builder, weighted selection,
-- milestone math, display names, ModData, trait add/remove.
-- ============================================================

require "BCRData"
require "BCRConfig"

BCR = BCR or {}

-- ============================================================
-- TRAIT REGISTRY
-- ============================================================

local traitUserdataCache = {}

-- Resolves a trait id to its engine userdata; caches hits and misses.
-- Returns nil (never false) when the id does not resolve.
function BCR.GetTraitUserdata(traitId)
    if not traitId or traitId == "" then
        return nil
    end
    local cached = traitUserdataCache[traitId]
    if cached ~= nil then
        -- Misses are cached as false; the public contract stays "nil".
        if cached == false then return nil end
        return cached
    end
    local ok, userdata = pcall(function()
        return CharacterTrait.get(ResourceLocation.of(traitId))
    end)
    if ok and userdata then
        traitUserdataCache[traitId] = userdata
        return userdata
    end
    traitUserdataCache[traitId] = false
    return nil
end

-- ============================================================
-- PLAYER TRAIT CHECKS (tri-state: true/has, false/doesn't, nil/error)
-- ============================================================

-- Tri-state: true = has, false = does not have, nil = engine could not tell.
function BCR.PlayerHasTrait(player, traitId)
    if not player then return nil end
    local traitObj = BCR.GetTraitUserdata(traitId)
    if not traitObj then return nil end
    local ok, result = pcall(function() return player:hasTrait(traitObj) end)
    if not ok then return nil end
    return result
end

-- Returns true, blockerId when a mutually exclusive trait is owned.
function BCR.HasMutuallyExclusiveTrait(player, traitId)
    local exclusions = BCR.Exclusions[traitId]
    if not exclusions then return false end
    for _, excludedId in ipairs(exclusions) do
        if BCR.PlayerHasTrait(player, excludedId) == true then
            return true, excludedId
        end
    end
    return false, nil
end

-- Engine trait name strings for a player; nil when the engine read fails.
function BCR.GetPlayerTraitsList(player)
    if not player then return nil end
    local traitsOk, traits = pcall(function() return player:getCharacterTraits() end)
    if not traitsOk or not traits then return nil end
    local knownOk, knownTraits = pcall(function() return traits:getKnownTraits() end)
    if not knownOk or not knownTraits then return nil end
    local result = {}
    local sizeOk, size = pcall(function() return knownTraits:size() end)
    if not sizeOk then return result end
    for i = 0, size - 1 do
        local getOk, trait = pcall(function() return knownTraits:get(i) end)
        if getOk and trait then
            local toStringOk, traitString = pcall(function() return tostring(trait) end)
            if toStringOk and traitString then
                table.insert(result, traitString)
            end
        end
    end
    return result
end

-- ============================================================
-- ENGINE TRAIT DUMP -- iterates what the running game actually
-- holds (every character_trait_definition: vanilla + mods).
-- Run in-game: BCRDumpTraits()
-- ============================================================

function BCR.DumpEngineTraits(quiet)
    local rows = {}
    local defsOk, defs = pcall(function() return CharacterTraitDefinition.getTraits() end)
    if not defsOk or not defs then
        if not quiet then
            print("[BCR] [Dump] Engine trait definitions unavailable in this context")
        end
        return rows
    end

    local count = 0
    pcall(function() count = defs:size() end)

    -- Sorted "count [id, id]" text for an engine id-list getter; a failed
    -- engine call degrades to "0" (the dump is diagnostic only).
    local function collectEngineTraitIds(getter)
        local ids = {}
        pcall(function()
            local list = getter()
            if list then
                for j = 0, list:size() - 1 do
                    local other = list:get(j)
                    if other then table.insert(ids, tostring(other)) end
                end
            end
        end)
        table.sort(ids)
        if #ids == 0 then return "0" end
        return #ids .. " [" .. table.concat(ids, ", ") .. "]"
    end

    for i = 0, count - 1 do
        local rowOk, row = pcall(function()
            local def = defs:get(i)
            local trait = def:getType()
            local id = trait and tostring(trait) or ("definition#" .. tostring(i))

            local keyOk, key = pcall(function() return def:getUIName() end)
            key = (keyOk and key) or ""
            local label = key
            if key ~= "" then
                local translated = getText(key)
                if translated and translated ~= key then label = translated end
            end

            local costOk, cost = pcall(function() return def:getCost() end)
            cost = (costOk and cost) or 0

            local mutexText = collectEngineTraitIds(function() return def:getMutuallyExclusiveTraits() end)
            local grantedText = collectEngineTraitIds(function() return def:getGrantedTraits() end)

            local mpDisabled = false
            pcall(function() mpDisabled = def:isDisabledInMultiplayer() == true end)

            -- isFree() == true marks the profession variant of a trait
            -- (same name, cost 0, granted by a profession, e.g. nutritionist2).
            local profession = false
            pcall(function() profession = def:isFree() == true end)

            -- Engine convention (script "Cost" field): positive traits have
            -- positive cost, negative traits have negative cost.
            local category = "free"
            if cost > 0 then category = "pos"
            elseif cost < 0 then category = "neg" end

            return {
                id = id,
                text = string.format("%s | %s | cost=%d | %s | profession=%s | mutex=%s | granted=%s%s",
                    id, category, cost, (label ~= "" and label or "(no ui name)"),
                    profession and "yes" or "no", mutexText, grantedText,
                    mpDisabled and " | MP-disabled" or ""),
            }
        end)
        if rowOk and row then
            table.insert(rows, row)
        end
    end

    table.sort(rows, function(a, b) return a.id < b.id end)
    if quiet then return rows end

    print("[BCR] [Dump] === Engine trait registry: " .. #rows .. " definition(s) ===")
    for _, row in ipairs(rows) do
        print("[BCR] [Dump] " .. row.text)
    end

    -- Engine ids are lowercase; BCR lists use ResourceLocation case.
    local present = {}
    for _, row in ipairs(rows) do present[string.lower(row.id)] = true end

    local missingBase = {}
    for _, e in ipairs(BCR.PositiveTraits or {}) do
        if not present[string.lower(e.id)] then table.insert(missingBase, e.id) end
    end
    for _, e in ipairs(BCR.NegativeTraits or {}) do
        if not present[string.lower(e.id)] then table.insert(missingBase, e.id) end
    end
    table.sort(missingBase)
    print("[BCR] [Dump] BCR base traits missing from engine: " .. #missingBase ..
        (#missingBase > 0 and (" -- " .. table.concat(missingBase, ", ")) or ""))

    local missingAddon = {}
    for id in pairs(BCR.CustomTraitSources or {}) do
        if not present[string.lower(id)] then table.insert(missingAddon, id) end
    end
    table.sort(missingAddon)
    print("[BCR] [Dump] Addon traits missing from engine: " .. #missingAddon ..
        (#missingAddon > 0 and (" -- " .. table.concat(missingAddon, ", ")) or ""))

    pcall(function()
        local player = getSpecificPlayer(0)
        if player then
            local list = BCR.GetPlayerTraitsList(player)
            if list then
                table.sort(list)
                print("[BCR] [Dump] Player traits (" .. #list .. "): " .. table.concat(list, ", "))
            end
        end
    end)

    return rows
end

function BCRDumpTraits()
    BCR.DumpEngineTraits(false)
end

-- ============================================================
-- TRAIT MODIFICATION -- unified internal function
-- ============================================================

local function canModifyTraits()
    return (not isClient() and not isServer()) or isServer()
end

local function modifyTrait(player, traitEntry, action)
    if not player or not traitEntry then return false end
    if type(traitEntry) ~= "table" then
        BCR.DebugPrint("Core", "modifyTrait: trait entry must be a table")
        return false
    end
    if not canModifyTraits() then
        BCR.DebugPrint("Core", "modifyTrait: cannot modify traits in this context")
        return false
    end
    local traitId = traitEntry.id
    if not traitId then return false end
    local traitObj = traitEntry.traitUserdata or BCR.GetTraitUserdata(traitId)
    if not traitObj then
        BCR.DebugPrint("Core", "modifyTrait: no userdata for " .. tostring(traitId))
        return false
    end

    if action == "add" then
        local has = BCR.PlayerHasTrait(player, traitId)
        if has ~= false then
            BCR.DebugPrint("Core", "modifyTrait: cannot add " .. traitId .. " (has=" .. tostring(has) .. ")")
            return false
        end
        local blocked, blockerId = BCR.HasMutuallyExclusiveTrait(player, traitId)
        if blocked then
            BCR.DebugPrint("Core", "modifyTrait: cannot add " .. traitId .. " (blocked by " .. tostring(blockerId) .. ")")
            return false
        end
    elseif action == "remove" then
        local has = BCR.PlayerHasTrait(player, traitId)
        if has ~= true then
            BCR.DebugPrint("Core", "modifyTrait: cannot remove " .. traitId .. " (has=" .. tostring(has) .. ")")
            return false
        end
    else
        return false
    end

    local ok, traits = pcall(function() return player:getCharacterTraits() end)
    if not ok or not traits then return false end
    local success, err = pcall(function()
        if action == "add" then
            traits:add(traitObj)
        else
            traits:remove(traitObj)
        end
    end)
    if not success then
        BCR.DebugPrint("Core", "modifyTrait: " .. action .. " failed for " .. traitId .. ": " .. tostring(err))
        return false
    end
    return true
end

-- Grants a trait (entry: { id = ..., cost = ... }); false when blocked or invalid.
function BCR.AddTrait(player, traitEntry)
    return modifyTrait(player, traitEntry, "add")
end

-- Removes a trait; false when not owned, blocked or invalid.
function BCR.RemoveTrait(player, traitEntry)
    return modifyTrait(player, traitEntry, "remove")
end

-- ============================================================
-- WEIGHTED SELECTION
-- ============================================================

function BCR.GetRarity(cost)
    if type(cost) ~= "number" then return "common" end
    local absCost = math.abs(cost)
    if absCost <= BCR.RarityTiers.common.maxCost then return "common" end
    if absCost <= BCR.RarityTiers.uncommon.maxCost then return "uncommon" end
    if absCost <= BCR.RarityTiers.rare.maxCost then return "rare" end
    return "veryRare"
end

function BCR.GetRarityColor(cost)
    local tier = BCR.RarityTiers[BCR.GetRarity(cost)]
    return tier and tier.color or { 0.80, 0.80, 0.80 }
end

function BCR.CalculateWeight(cost)
    if type(cost) ~= "number" then return 1 end
    return math.max(1, math.floor((BCR.MAX_WEIGHT_COST - math.abs(cost)) + 1))
end

-- Picks one entry by weight; nil for a nil or empty pool.
function BCR.WeightedRandomSelect(pool)
    if not pool or #pool == 0 then return nil end
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        totalWeight = totalWeight + (entry.weight or 1)
    end
    if totalWeight <= 0 then
        return pool[ZombRand(#pool) + 1]
    end
    local roll = ZombRand(totalWeight)
    local cumulative = 0
    for _, entry in ipairs(pool) do
        cumulative = cumulative + (entry.weight or 1)
        if roll < cumulative then
            return entry
        end
    end
    -- Unreachable for well-formed weights; kept as a fail-safe so a
    -- malformed pool can never return nil to a caller expecting a pick.
    BCR.DebugPrint("Core", "WeightedRandomSelect: roll " .. tostring(roll) .. " did not match any entry (totalWeight=" .. tostring(totalWeight) .. ")")
    return pool[#pool]
end

-- ============================================================
-- POOL BUILDING
-- ============================================================

local function mergeTraitTables(base, custom)
    local merged = {}
    if base then
        for _, v in ipairs(base) do
            table.insert(merged, v)
        end
    end
    if custom then
        for _, v in ipairs(custom) do
            table.insert(merged, v)
        end
    end
    return merged
end

-- Always start from copies, never aliases, so nothing can mutate the
-- base trait tables through the merged lists.
BCR.MergedPositiveTraits = mergeTraitTables(BCR.PositiveTraits, BCR.CustomPositiveTraits)
BCR.MergedNegativeTraits = mergeTraitTables(BCR.NegativeTraits, BCR.CustomNegativeTraits)

function BCR.RebuildMergedTraits()
    BCR.MergedPositiveTraits = mergeTraitTables(BCR.PositiveTraits, BCR.CustomPositiveTraits)
    BCR.MergedNegativeTraits = mergeTraitTables(BCR.NegativeTraits, BCR.CustomNegativeTraits)
end

-- ============================================================
-- TRAIT HISTORY GUARDS -- BCR's own record, independent of
-- live engine state. Prevents duplicate grants.
-- ============================================================

function BCR.GetLastHistoryAction(history, traitId)
    if not history or not traitId then return nil end
    -- Normalize legacy IDs (pre-v1.3.1 UPPER_SNAKE_CASE) so old-save
    -- history entries still match current ResourceLocation IDs.
    local normalized = traitId
    if BCR.TRAIT_ID_MIGRATION and BCR.TRAIT_ID_MIGRATION[traitId] then
        normalized = BCR.TRAIT_ID_MIGRATION[traitId]
    end
    for i = #history, 1, -1 do
        local entry = history[i]
        if entry and entry.id then
            local entryId = entry.id
            if BCR.TRAIT_ID_MIGRATION and BCR.TRAIT_ID_MIGRATION[entryId] then
                entryId = BCR.TRAIT_ID_MIGRATION[entryId]
            end
            if entryId == normalized then
                return entry.action
            end
        end
    end
    return nil
end

local function isExcludedFromEarnable(bcrData, traitId)
    -- Fail closed: if BCR's own records cannot be read, exclude the
    -- trait from the earnable pool rather than risking a duplicate grant.
    if not bcrData then return true end
    local last = BCR.GetLastHistoryAction(bcrData.traitHistory, traitId)
    return last == "added" or last == "baseline"
end

local function isExcludedFromRemovable(bcrData, traitId)
    if not bcrData then return true end
    return BCR.GetLastHistoryAction(bcrData.traitHistory, traitId) == "removed"
end

-- ============================================================
-- POOL BUILDING -- one shared builder behind both public functions
-- ============================================================

-- options:
--   wantOwned  : true -> include only owned traits (removable pool)
--                false -> include only NOT owned traits (earnable pool)
--   checkMutual: apply mutual-exclusion filtering (earnable pool)
--   excluded   : function(traitId) -> true when the trait must be
--                filtered out by history/baseline guards
local function buildPool(player, baseList, customTraits, options)
    if not options then options = {} end
    local wantOwned = options.wantOwned == true
    local checkMutual = options.checkMutual == true
    local excluded = options.excluded
    local allTraits = baseList
    if customTraits then
        allTraits = mergeTraitTables(allTraits, customTraits)
    end
    local pool = {}
    for _, entry in ipairs(allTraits) do
        local traitId = entry.id
        if not traitId then
            -- entry without id -- skip
        elseif type(entry.cost) ~= "number" then
            -- malformed entry from a third-party addon -- skip
        elseif not BCR.IsTraitAllowed(traitId) then
            -- disabled in sandbox -- skip
        elseif BCR.PlayerHasTrait(player, traitId) ~= wantOwned then
            -- ownership state doesn't match this pool -- skip
            -- (nil from the tri-state check also lands here: fail closed)
        elseif excluded and excluded(traitId) then
            -- history/baseline guard -- skip
        elseif checkMutual and BCR.HasMutuallyExclusiveTrait(player, traitId) then
            -- blocked by a mutually exclusive owned trait -- skip
        else
            local traitObj = BCR.GetTraitUserdata(traitId)
            if traitObj then
                local cost = entry.cost
                table.insert(pool, {
                    id = traitId,
                    traitUserdata = traitObj,
                    cost = cost,
                    rarity = BCR.GetRarity(cost),
                    weight = BCR.CalculateWeight(cost),
                })
            end
        end
    end
    return pool
end

-- Traits the player can still earn (not owned, allowed, not excluded).
function BCR.BuildEarnablePool(player, customTraits)
    if not player then return nil end
    local bcrData = BCR.EnsureModData(player)
    return buildPool(player, BCR.MergedPositiveTraits, customTraits, {
        wantOwned = false,
        checkMutual = true,
        excluded = function(traitId) return isExcludedFromEarnable(bcrData, traitId) end,
    })
end

-- Traits the player owns and can have removed (allowed, not excluded).
function BCR.BuildRemovablePool(player, customTraits)
    if not player then return nil end
    local bcrData = BCR.EnsureModData(player)
    return buildPool(player, BCR.MergedNegativeTraits, customTraits, {
        wantOwned = true,
        checkMutual = false,
        excluded = function(traitId) return isExcludedFromRemovable(bcrData, traitId) end,
    })
end

-- Removes pool entries whose id appears as a key in excludeSet.
function BCR.FilterPoolByExclusion(pool, excludeSet)
    if not pool then return {} end
    if not excludeSet then return pool end
    local empty = true
    for _ in pairs(excludeSet) do empty = false; break end
    if empty then return pool end
    local filtered = {}
    for _, entry in ipairs(pool) do
        local traitId = entry.id
        if excludeSet[traitId] == nil then
            table.insert(filtered, entry)
        end
    end
    return filtered
end

-- ============================================================
-- MILESTONE MATH (pure functions, from opts table)
-- ============================================================

function BCR.GetKillsForMilestone(milestone, opts)
    if not milestone or not opts then return 0 end
    if milestone <= 0 then return 0 end
    local bc = opts.bodyCount or BCR.DEFAULT_BODY_COUNT
    if opts.milestoneScaling == BCR.SCALING_PROGRESSIVE then
        local factor = opts.progressiveScalingFactor or BCR.DEFAULT_PROGRESSIVE_FACTOR
        if factor > 0 then
            return math.floor(bc * (milestone + factor * milestone * (milestone - 1) / 2))
        end
    end
    return milestone * bc
end

function BCR.GetMilestonesAtKills(kills, opts)
    if not kills or kills <= 0 then return 0 end
    if not opts then return 0 end
    local bc = opts.bodyCount or BCR.DEFAULT_BODY_COUNT
    if bc <= 0 then return 0 end
    if opts.milestoneScaling == BCR.SCALING_PROGRESSIVE then
        local factor = opts.progressiveScalingFactor or BCR.DEFAULT_PROGRESSIVE_FACTOR
        if factor > 0 then
            local quadA = factor * bc / 2
            local quadB = bc * (1 - factor / 2)
            local quadC = -kills
            local discriminant = quadB * quadB - 4 * quadA * quadC
            if discriminant < 0 then return 0 end
            -- Small epsilon guards against floating-point error flooring
            -- one milestone below the exact boundary.
            local root = math.floor((-quadB + math.sqrt(discriminant)) / (2 * quadA) + 1e-9)
            return math.max(0, root)
        end
    end
    return math.floor(kills / bc)
end

-- ============================================================
-- MILESTONE DELTA -- single source of truth for "how many rewards
-- are owed right now". Used by server validation, client-side
-- detection, and the stats UI.
-- ============================================================

function BCR.GetMissedMilestoneCount(bcrData, kills, opts)
    if not bcrData or not opts then return 0 end
    local milestonesAtKills = BCR.GetMilestonesAtKills(kills, opts)
    local answered = bcrData.rewardsGiven or 0
    if not opts.grantMissedOpportunities then
        answered = answered + (bcrData.withheldMilestones or 0)
    end
    return math.max(0, milestonesAtKills - answered)
end

-- Milestones already answered: granted, plus those withheld while
-- retroactive rewards are off.
function BCR.GetAnsweredMilestones(bcrData)
    if not bcrData then return 0 end
    return (bcrData.rewardsGiven or 0) + (bcrData.withheldMilestones or 0)
end

-- Each reward granted while retroactive rewards are on consumes one
-- withheld milestone, so the OFF-mode progress counter stays correct
-- if the option is switched off again later.
function BCR.ConsumeWithheldMilestones(bcrData, grantedCount, opts)
    if not bcrData or not opts or not opts.grantMissedOpportunities then return end
    if type(grantedCount) ~= "number" or grantedCount <= 0 then return end
    local withheld = bcrData.withheldMilestones or 0
    if withheld <= 0 then return end
    bcrData.withheldMilestones = math.max(0, withheld - grantedCount)
end

-- ============================================================
-- DISPLAY NAMES
-- ============================================================

-- Localized display name for a trait id; never returns nil.
function BCR.GetTraitDisplayName(traitId)
    if type(traitId) ~= "string" or traitId == "" then return "Unknown" end
    local override = BCR.DISPLAY_OVERRIDES[traitId]
    if override then
        local text = getText(override)
        if text and text ~= override then return text end
    end
    local colonPos = string.find(traitId, ":")
    local path = colonPos and string.sub(traitId, colonPos + 1) or nil
    if not path then
        local newId = BCR.TRAIT_ID_MIGRATION and BCR.TRAIT_ID_MIGRATION[traitId]
        if newId and newId ~= traitId then
            return BCR.GetTraitDisplayName(newId)
        end
        local formatted = string.gsub(traitId, "_", " ")
        local words = {}
        for word in string.gmatch(formatted, "%S+") do
            local first = string.upper(string.sub(word, 1, 1))
            local rest = string.lower(string.sub(word, 2))
            table.insert(words, first .. rest)
        end
        return #words > 0 and table.concat(words, " ") or "Unknown"
    end
    local translationKey = "UI_trait_" .. path
    local text = getText(translationKey)
    if text and text ~= translationKey then
        return text
    end
    local traitObj = BCR.GetTraitUserdata(traitId)
    if traitObj then
        local ok, name = pcall(function() return traitObj:getName() end)
        if ok and name and name ~= "" then
            local key2 = "UI_trait_" .. name
            local trans2 = getText(key2)
            if trans2 and trans2 ~= key2 then
                return trans2
            end
        end
        -- The engine definition already holds the translated UI name; it
        -- covers addon traits whose translation keys differ in case/prefix.
        local defOk, defName = pcall(function()
            local def = CharacterTraitDefinition.getCharacterTraitDefinition(traitObj)
            return def and def:getLabel() or nil
        end)
        if defOk and type(defName) == "string" and defName ~= ""
            and string.sub(defName, 1, 3) ~= "UI_" then
            return defName
        end
    end
    local readable = string.gsub(path, "([a-z])([A-Z])", "%1 %2")
    if readable ~= "" then
        return string.upper(string.sub(readable, 1, 1)) .. string.sub(readable, 2)
    end
    return "Unknown"
end

-- ============================================================
-- MODDATA
-- ============================================================

-- Returns the per-player BCR ModData table, creating and repairing it as
-- needed. Returns nil when ModData is unreadable.
function BCR.EnsureModData(player)
    if not player then return nil end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or not modData then return nil end
    if not modData.BCR or type(modData.BCR) ~= "table" then
        modData.BCR = {
            kills = 0,
            rewardsGiven = 0,
            traitHistory = {},
        }
    end
    if type(modData.BCR.traitHistory) ~= "table" then
        modData.BCR.traitHistory = {}
    end
    if type(modData.BCR.kills) ~= "number" or modData.BCR.kills < 0 then
        modData.BCR.kills = 0
    end
    if type(modData.BCR.rewardsGiven) ~= "number" or modData.BCR.rewardsGiven < 0 then
        modData.BCR.rewardsGiven = 0
    end
    -- withheldMilestones: number of milestones set aside while retroactive
    -- rewards stay off; absent/nil means none are set aside yet. Corrupt
    -- values are dropped so the next load can rebuild the pool.
    if modData.BCR.withheldMilestones ~= nil and
        (type(modData.BCR.withheldMilestones) ~= "number" or modData.BCR.withheldMilestones < 0) then
        modData.BCR.withheldMilestones = nil
    end
    -- One-time trait history sanitize: drop malformed entries and trim an
    -- oversized list. The marker keeps this O(n) pass out of the per-tick
    -- EnsureModData calls; recordTraitHistory keeps the list capped after it.
    if modData.BCR.traitHistoryChecked ~= true then
        local history = modData.BCR.traitHistory
        local cleaned = {}
        local count = #history
        local first = 1
        if count > BCR.MAX_TRAIT_HISTORY then
            first = count - BCR.MAX_TRAIT_HISTORY + 1
        end
        for i = first, count do
            local entry = history[i]
            local entryId = type(entry) == "table" and (entry.id or entry.trait) or nil
            if type(entryId) == "string" and entryId ~= ""
                and (entry.action == "added" or entry.action == "removed"
                    or entry.action == "baseline" or entry.action == "lost") then
                table.insert(cleaned, entry)
            end
        end
        modData.BCR.traitHistory = cleaned
        modData.BCR.traitHistoryChecked = true
    end
    return modData.BCR
end

-- ============================================================
-- AVAILABILITY
-- ============================================================

-- True when at least one reward can still be granted to this player.
function BCR.HasAvailableRewards(player)
    if not player then return false end
    local opts = BCR.GetOpts()
    if opts.enablePositive ~= false then
        local earnable = BCR.BuildEarnablePool(player, nil)
        if earnable and #earnable > 0 then return true end
    end
    if opts.enableNegative ~= false then
        local removable = BCR.BuildRemovablePool(player, nil)
        if removable and #removable > 0 then return true end
    end
    return false
end

-- ============================================================
-- THIRD-PARTY TRAIT TESTS
-- ============================================================

function BCR.RunThirdPartyTests()
    local passed, failed = 0, 0

    local function ok(msg, condition)
        if condition then
            passed = passed + 1
            print("[BCR] [ThirdPartyTest] PASS: " .. msg)
        else
            failed = failed + 1
            print("[BCR] [ThirdPartyTest] FAIL: " .. msg)
        end
    end

    local positiveCount = 0
    local negativeCount = 0
    if BCR.CustomPositiveTraits then
        for _ in ipairs(BCR.CustomPositiveTraits) do positiveCount = positiveCount + 1 end
    end
    if BCR.CustomNegativeTraits then
        for _ in ipairs(BCR.CustomNegativeTraits) do negativeCount = negativeCount + 1 end
    end

    if positiveCount == 0 and negativeCount == 0 then
        print("[BCR] [ThirdPartyTest] No third-party traits registered.")
        return true
    end

    print("[BCR] [ThirdPartyTest] ===== Checking " .. tostring(positiveCount) ..
        " custom positive, " .. tostring(negativeCount) .. " custom negative trait(s) =====")

    local sources = {}

    local function testTraitList(list, label)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if not traitId then
                failed = failed + 1
                print("[BCR] [ThirdPartyTest] FAIL: " .. label .. " entry missing id")
            else
                local source = BCR.CustomTraitSources and BCR.CustomTraitSources[traitId]
                local ns = BCR.CustomTraitNamespaces and BCR.CustomTraitNamespaces[traitId]
                local userdata = BCR.GetTraitUserdata(traitId)

                if not source then
                    failed = failed + 1
                    print("[BCR] [ThirdPartyTest] FAIL: " .. traitId .. " missing source")
                else
                    sources[source] = true
                end

                if not ns then
                    failed = failed + 1
                    print("[BCR] [ThirdPartyTest] FAIL: " .. traitId .. " missing sandbox namespace")
                end

                if not userdata then
                    failed = failed + 1
                    print("[BCR] [ThirdPartyTest] FAIL: " .. traitId .. " does not resolve via CharacterTrait")
                end

                if source and ns and userdata then
                    passed = passed + 1
                    print("[BCR] [ThirdPartyTest] OK: " .. traitId .. " (source=\"" .. source .. "\", ns=\"" .. ns .. "\")")
                end
            end
        end
    end

    testTraitList(BCR.CustomPositiveTraits, "positive")
    testTraitList(BCR.CustomNegativeTraits, "negative")

    ok("BCR.Exclusions exists and is a table",
        BCR.Exclusions ~= nil and type(BCR.Exclusions) == "table")

    -- ============================================================
    -- Sandbox toggle wiring -- every registered trait must declare
    -- its "allow_<id>" key in the sandbox namespace. Catches
    -- namespace / option-name mismatches between sandbox-options.txt
    -- and RegisterCustomTraits(). Checks the key's presence, not its
    -- value, so an admin who disables a toggle does not fail the test.
    -- ============================================================

    local function checkSandboxToggles(list, label)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            local namespace = traitId and BCR.CustomTraitNamespaces and BCR.CustomTraitNamespaces[traitId]
            if namespace then
                local key = "allow_" .. string.gsub(traitId, ":", "_")
                local sandboxVars = SandboxVars[namespace]
                ok(label .. " sandbox toggle declared for " .. traitId .. " (" .. namespace .. "." .. key .. ")",
                    sandboxVars ~= nil and sandboxVars[key] ~= nil)
            end
        end
    end
    checkSandboxToggles(BCR.CustomPositiveTraits, "positive")
    checkSandboxToggles(BCR.CustomNegativeTraits, "negative")

    -- ============================================================
    -- NEW (v1.3.3): Exclusion bidirectionality -- for every A -> B,
    -- verify B excludes A and no trait excludes itself.
    -- Only checks pairs where at least one side is a third-party
    -- trait (base-bcr-only pairs are maintained in BCRData.lua).
    -- ============================================================

    local function isCustomTrait(traitId)
        return BCR.CustomTraitSources and BCR.CustomTraitSources[traitId] ~= nil
    end

    if BCR.Exclusions then
        for traitId, excludeList in pairs(BCR.Exclusions) do
            if type(excludeList) == "table" then
                for _, excludedId in ipairs(excludeList) do
                    if type(excludedId) == "string" and excludedId ~= "" then
                        if isCustomTrait(traitId) or isCustomTrait(excludedId) then
                            ok("Exclusion " .. traitId .. " -> " .. excludedId .. " is bidirectional",
                                BCR.Exclusions[excludedId] ~= nil)
                            local reverseList = BCR.Exclusions[excludedId]
                            if reverseList then
                                local found = false
                                for _, r in ipairs(reverseList) do
                                    if r == traitId then found = true; break end
                                end
                                ok("Exclusion " .. excludedId .. " -> " .. traitId .. " exists in reverse list",
                                    found)
                            end
                            ok("Exclusion " .. traitId .. " does not exclude itself",
                                excludedId ~= traitId)
                        end
                    end
                end
            end
        end
    end

    -- ============================================================
    -- NEW (v1.3.3): Exclusion targets are real -- every excludedId
    -- in every exclusion list must be a known trait (base or custom).
    -- ============================================================

    local knownTraits = {}
    local function collectIds(list)
        if not list then return end
        for _, entry in ipairs(list) do
            if entry.id then knownTraits[entry.id] = true end
        end
    end
    collectIds(BCR.PositiveTraits)
    collectIds(BCR.NegativeTraits)
    collectIds(BCR.CustomPositiveTraits)
    collectIds(BCR.CustomNegativeTraits)
    if BCR.Exclusions then
        for _, excludeList in pairs(BCR.Exclusions) do
            if type(excludeList) == "table" then
                for _, excludedId in ipairs(excludeList) do
                        if type(excludedId) == "string" and excludedId ~= "" then
                            ok("Exclusion target " .. excludedId .. " is a known trait",
                                knownTraits[excludedId] ~= nil or BCR.GetTraitUserdata(excludedId) ~= nil)
                        end
                end
            end
        end
    end

    -- ============================================================
    -- NEW (v1.3.3): Display names all resolve -- protects against
    -- trait IDs that BCR can't look up via the translation system.
    -- ============================================================

    local function checkDisplayNames(list, label)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if traitId then
                local name = BCR.GetTraitDisplayName(traitId)
                ok(label .. " display name for " .. traitId .. " resolves",
                    name ~= nil and name ~= "" and name ~= "Unknown")
            end
        end
    end
    checkDisplayNames(BCR.CustomPositiveTraits, "positive")
    checkDisplayNames(BCR.CustomNegativeTraits, "negative")

    -- ============================================================
    -- NEW (v1.3.3): Rarity and weight -- every trait must produce
    -- a valid rarity tier and a weight >= 1 for pool selection.
    -- ============================================================

    local knownRarities = { common = true, uncommon = true, rare = true, veryRare = true }
    local function checkRarityAndWeight(list, label)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if traitId then
                local rarity = BCR.GetRarity(entry.cost or 0)
                ok(label .. " rarity for " .. traitId .. " is valid",
                    knownRarities[rarity] ~= nil)
                local weight = BCR.CalculateWeight(entry.cost or 0)
                ok(label .. " weight for " .. traitId .. " >= 1",
                    type(weight) == "number" and weight >= 1)
            end
        end
    end
    checkRarityAndWeight(BCR.CustomPositiveTraits, "positive")
    checkRarityAndWeight(BCR.CustomNegativeTraits, "negative")

    local sourceList = {}
    for s, _ in pairs(sources) do table.insert(sourceList, "\"" .. s .. "\"") end
    print("[BCR] [ThirdPartyTest] Active addon(s): " .. table.concat(sourceList, ", "))

    print("[BCR] [ThirdPartyTest] ===== " .. tostring(passed) .. " passed, " ..
        tostring(failed) .. " failed =====")
    return failed == 0
end

-- Backwards-compatible global name for console users who typed the
-- pre-1.3.4 identifier directly.
BCR_RunThirdPartyTests = BCR.RunThirdPartyTests
