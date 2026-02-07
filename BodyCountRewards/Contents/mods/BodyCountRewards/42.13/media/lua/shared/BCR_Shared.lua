-- ============================================================
-- BodyCountRewards - Shared Logic (Build 42.13.2)
-- 
-- Core logic shared between client and server:
--   - Trait registry helpers and pool building
--   - Weighted random selection with rarity tiers
--   - Milestone math (linear & progressive scaling)
--   - Mutual exclusion and sandbox filtering
-- ============================================================

BCR = BCR or {}
BCR.DEBUG = false

function BCR.DebugPrint(msg)
    if BCR.DEBUG then
        print("[BodyCountRewards] " .. tostring(msg))
    end
end

function BCR.isSinglePlayer()
    return not isClient() and not isServer()
end


-- ============================================================
-- TRAIT REGISTRY HELPER
-- Normalizes names by removing underscores for registry lookup

local function toRegistryName(name)
    if not name or type(name) ~= "string" then return nil end
    return string.lower(string.gsub(name, "_", ""))
end

local function getTraitUserdata(traitName)
    if not traitName then return nil end
    
    if type(traitName) == "userdata" then
        return traitName
    end
    
    -- Direct access works for some traits
    local direct = CharacterTrait[traitName]
    if type(direct) == "userdata" then
        return direct
    end
    
    local registryName = toRegistryName(traitName)
    if not registryName then return nil end
    
    local success, result = pcall(function()
        local rl = ResourceLocation.of("base:" .. registryName)
        return CharacterTrait.get(rl)
    end)
    
    if success and result then
        return result
    end
    
    BCR.DebugPrint("Warning: Trait '" .. tostring(traitName) .. "' not found in registry")
    return nil
end

BCR.getTraitUserdata = getTraitUserdata


-- ============================================================
-- WEIGHTED RANDOM SELECTION & RARITY
-- Formula: weight = maxCost - |cost| + 1
-- Higher cost = lower weight = rarer selection

local maxCost = 8

BCR.rarityColors = {
    common   = { 0.8, 0.8, 0.8 },
    uncommon = { 0.6, 1.0, 0.2 },
    rare     = { 1.0, 0.6, 0.2 },
    veryRare = { 0.8, 0.3, 1.0 },
}

function BCR.getRarityTier(cost)
    local c = math.abs(cost or 0)
    if c <= 2 then return "common"
    elseif c <= 4 then return "uncommon"
    elseif c <= 6 then return "rare"
    else return "veryRare"
    end
end

function BCR.getRarityColor(cost)
    local tier = BCR.getRarityTier(cost)
    return BCR.rarityColors[tier] or BCR.rarityColors.common
end

function BCR.calculateWeight(cost)
    local c = math.abs(cost or 0)
    return math.max(1, (maxCost - c) + 1)
end


-- ============================================================
-- TRAIT WHITELIST TABLES
-- Costs: negative = positive traits, positive = negative traits
-- Excluded: Occupation-only traits, traits granting perk points
-- Use UPPER_CASE here; helpers normalize automatically

-- POSITIVE TRAITS (Can be EARNED)
BCR.PositiveTraitsList = {
    -- COMMON (cost -1 to -2)
    { trait = "SPEED_DEMON",      cost = -1 },
    { trait = "NIGHT_VISION",     cost = -2 },  -- In-game: "Cat's Eyes"
    { trait = "DEXTROUS",         cost = -2 },
    { trait = "FAST_READER",      cost = -2 },
    { trait = "INVENTIVE",        cost = -2 },
    { trait = "LIGHT_EATER",      cost = -2 },
    { trait = "LOW_THIRST",       cost = -2 },
    { trait = "OUTDOORSMAN",      cost = -2 },
    { trait = "NEEDS_LESS_SLEEP", cost = -2 },  -- In-game: "Wakeful"

    -- UNCOMMON (cost -3 to -4)
    { trait = "IRON_GUT",         cost = -3 },
    { trait = "ADRENALINE_JUNKIE", cost = -4 },
    { trait = "EAGLE_EYED",       cost = -4 },
    { trait = "GRACEFUL",         cost = -4 },
    { trait = "INCONSPICUOUS",    cost = -4 },
    { trait = "NUTRITIONIST",     cost = -4 },
    { trait = "ORGANIZED",        cost = -4 },
    { trait = "RESILIENT",        cost = -4 },

    -- RARE (cost -5 to -6)
    { trait = "FAST_HEALER",      cost = -6 },
    { trait = "FAST_LEARNER",     cost = -6 },
    { trait = "KEEN_HEARING",     cost = -6 },

    -- VERY RARE (cost -7 to -X)
    { trait = "THICK_SKINNED",    cost = -8 },
}

-- NEGATIVE TRAITS (Can be REMOVED)
BCR.NegativeTraitsList = {
    -- COMMON (cost 1-2)
    { trait = "HIGH_THIRST",      cost = 1 },
    { trait = "SUNDAY_DRIVER",    cost = 1 },
    { trait = "ALL_THUMBS",       cost = 2 },
    { trait = "CLUMSY",           cost = 2 },
    { trait = "COWARDLY",         cost = 2 },
    { trait = "SLOW_READER",      cost = 2 },

    -- UNCOMMON (cost 3-4)
    { trait = "SLOW_HEALER",      cost = 3 },
    { trait = "WEAK_STOMACH",     cost = 3 },
    { trait = "SMOKER",           cost = 4 },
    { trait = "AGORAPHOBIC",      cost = 4 },
    { trait = "CLAUSTROPHOBIC",   cost = 4 },
    { trait = "CONSPICUOUS",      cost = 4 },
    { trait = "HEARTY_APPETITE",  cost = 4 },
    { trait = "PACIFIST",         cost = 4 },
    { trait = "PRONE_TO_ILLNESS", cost = 4 },
    { trait = "NEEDS_MORE_SLEEP", cost = 4 },  -- In-game: "Sleepyhead"

    -- RARE (cost 5-6)
    { trait = "ASTHMATIC",        cost = 5 },
    { trait = "HEMOPHOBIC",       cost = 5 },
    { trait = "DISORGANIZED",     cost = 6 },
    { trait = "SLOW_LEARNER",     cost = 6 },

    -- VERY RARE (cost 7-X)
    { trait = "ILLITERATE",       cost = 8 },
    { trait = "THIN_SKINNED",     cost = 8 },
}


-- ============================================================
-- MUTUALLY EXCLUSIVE TRAITS

BCR.MutuallyExclusiveTraits = {
    ["ADRENALINE_JUNKIE"] = { "AGORAPHOBIC", "CLAUSTROPHOBIC", "COWARDLY" },
    ["AGORAPHOBIC"]       = { "ADRENALINE_JUNKIE", "CLAUSTROPHOBIC" },
    ["ALL_THUMBS"]        = { "DEXTROUS" },
    ["CLAUSTROPHOBIC"]    = { "ADRENALINE_JUNKIE", "AGORAPHOBIC" },
    ["CLUMSY"]            = { "GRACEFUL" },
    ["CONSPICUOUS"]       = { "INCONSPICUOUS" },
    ["COWARDLY"]          = { "ADRENALINE_JUNKIE" },
    ["DEXTROUS"]          = { "ALL_THUMBS" },
    ["DISORGANIZED"]      = { "ORGANIZED" },
    ["FAST_HEALER"]       = { "SLOW_HEALER" },
    ["FAST_LEARNER"]      = { "SLOW_LEARNER" },
    ["FAST_READER"]       = { "ILLITERATE", "SLOW_READER" },
    ["GRACEFUL"]          = { "CLUMSY" },
    ["HEARTY_APPETITE"]   = { "LIGHT_EATER" },
    ["HIGH_THIRST"]       = { "LOW_THIRST" },
    ["ILLITERATE"]        = { "FAST_READER", "SLOW_READER" },
    ["INCONSPICUOUS"]     = { "CONSPICUOUS" },
    ["IRON_GUT"]          = { "WEAK_STOMACH" },
    ["LIGHT_EATER"]       = { "HEARTY_APPETITE" },
    ["LOW_THIRST"]        = { "HIGH_THIRST" },
    ["ORGANIZED"]         = { "DISORGANIZED" },
    ["PRONE_TO_ILLNESS"]  = { "RESILIENT" },
    ["RESILIENT"]         = { "PRONE_TO_ILLNESS" },
    ["NEEDS_MORE_SLEEP"]  = { "NEEDS_LESS_SLEEP" },
    ["NEEDS_LESS_SLEEP"]  = { "NEEDS_MORE_SLEEP" },
    ["SLOW_HEALER"]       = { "FAST_HEALER" },
    ["SLOW_LEARNER"]      = { "FAST_LEARNER" },
    ["SLOW_READER"]       = { "FAST_READER", "ILLITERATE" },
    ["SPEED_DEMON"]       = { "SUNDAY_DRIVER" },
    ["SUNDAY_DRIVER"]     = { "SPEED_DEMON" },
    ["THICK_SKINNED"]     = { "THIN_SKINNED" },
    ["THIN_SKINNED"]      = { "THICK_SKINNED" },
    ["WEAK_STOMACH"]      = { "IRON_GUT" },
}


-- ============================================================
-- SANDBOX OPTIONS

BCR.PRIORITY_POSITIVE_FIRST = 1
BCR.PRIORITY_NEGATIVE_FIRST = 2
BCR.PRIORITY_RANDOM = 3

function BCR.getSandboxOptions()
    local SandboxSetting = SandboxVars.BCR or {}
    return {
        BodyCount = SandboxSetting.BodyCount or 1000,
        givePositiveTraits = SandboxSetting.enablePositiveTraits ~= false,
        removeNegativeTraits = SandboxSetting.enableNegativeTraits ~= false,
        rewardPriority = SandboxSetting.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST,
        grandMissedOpportunities = SandboxSetting.grandMissedOpportunities == true,
        MilestoneScaling = SandboxSetting.MilestoneScaling or 1,
        ProgressiveScalingFactor = SandboxSetting.ProgressiveScalingFactor or 1.0,
    }
end

function BCR.isTraitAllowed(traitName)
    local sandboxVars = SandboxVars.BCR or {}
    local settingName = "allow_" .. traitName
    
    if sandboxVars[settingName] == false then
        BCR.DebugPrint("Trait blocked by sandbox: " .. traitName)
        return false
    end
    
    return true
end


-- ============================================================
-- MILESTONE MATH
-- Linear:      milestone n = n * BodyCount
-- Progressive: milestone n = BodyCount * (n + F * n * (n-1) / 2)
--   F=1.0 = triangular, F=0.5 = gentler growth

function BCR.getKillsForMilestone(n, opts)
    if n <= 0 then return 0 end
    local scaling = opts.MilestoneScaling or 1

    if scaling == 2 then
        local F = opts.ProgressiveScalingFactor or 1.0
        return math.floor(opts.BodyCount * (n + F * n * (n - 1) / 2))
    end

    return n * opts.BodyCount
end

function BCR.getMilestonesAtKills(kills, opts)
    if kills <= 0 then return 0 end
    local x = opts.BodyCount
    if x <= 0 then return 0 end
    local scaling = opts.MilestoneScaling or 1

    if scaling == 2 then
        local F = opts.ProgressiveScalingFactor or 1.0
        if F <= 0 then
            return math.floor(kills / x)
        end
        local a = F / 2
        local b = 1 - F / 2
        return math.floor((-b + math.sqrt(b * b + 4 * a * kills / x)) / (2 * a))
    end

    return math.floor(kills / x)
end


-- ============================================================
-- PLAYER TRAIT HELPERS

local function playerHasTrait(player, traitName)
    if not player then return false end
    
    local traitUserdata = getTraitUserdata(traitName)
    if not traitUserdata then return false end
    
    local success, result = pcall(function()
        return player:hasTrait(traitUserdata)
    end)
    
    if not success then
        BCR.DebugPrint("Error in hasTrait: " .. tostring(result))
        return false
    end
    
    return result == true
end

local function hasMutuallyExclusiveTrait(player, traitName)
    local exclusiveTraits = BCR.MutuallyExclusiveTraits[traitName]
    if not exclusiveTraits then return false end

    for _, exclTraitName in ipairs(exclusiveTraits) do
        if playerHasTrait(player, exclTraitName) then
            BCR.DebugPrint("Mutual exclusion: " .. traitName .. " blocked by " .. exclTraitName)
            return true, exclTraitName
        end
    end
    return false
end

local function getPlayerTraitsList(player)
    if not player then return {} end
    
    local traits = player:getCharacterTraits()
    if not traits then return {} end
    
    local traitList = {}
    local knownTraits = traits:getKnownTraits()
    
    if knownTraits then
        local success, size = pcall(function() return knownTraits:size() end)
        if success and size then
            for i = 0, size - 1 do
                local ok, trait = pcall(function() return knownTraits:get(i) end)
                if ok and trait then
                    table.insert(traitList, tostring(trait))
                end
            end
        end
    end
    
    return traitList
end

BCR.playerHasTrait = playerHasTrait
BCR.hasMutuallyExclusiveTrait = hasMutuallyExclusiveTrait
BCR.getPlayerTraitsList = getPlayerTraitsList


-- ============================================================
-- WEIGHTED RANDOM SELECTION

function BCR.weightedRandomSelect(traitPool)
    if not traitPool or #traitPool == 0 then return nil end
    
    local totalWeight = 0
    for _, entry in ipairs(traitPool) do
        totalWeight = totalWeight + entry.weight
    end
    
    if totalWeight <= 0 then
        return traitPool[ZombRand(#traitPool) + 1]
    end
    
    local rand = ZombRand(totalWeight)
    local cumulative = 0
    
    for _, entry in ipairs(traitPool) do
        cumulative = cumulative + entry.weight
        if rand < cumulative then
            BCR.DebugPrint("Selected: " .. entry.trait .. " (roll=" .. rand .. "/" .. totalWeight .. ")")
            return entry
        end
    end
    
    return traitPool[#traitPool]
end


-- ============================================================
-- TRAIT POOL BUILDING

local function buildTraitPool(player, traitList, checkFunction)
    local pool = {}
    
    for _, entry in ipairs(traitList) do
        if BCR.isTraitAllowed(entry.trait) and checkFunction(player, entry.trait) then
            local traitUserdata = getTraitUserdata(entry.trait)
            if traitUserdata then
                table.insert(pool, {
                    trait = entry.trait,
                    traitUserdata = traitUserdata,
                    cost = entry.cost,
                    rarity = BCR.getRarityTier(entry.cost),
                    weight = BCR.calculateWeight(entry.cost),
                })
            end
        end
    end
    
    return pool
end

local function canEarnTrait(player, traitName)
    if playerHasTrait(player, traitName) then return false end
    if hasMutuallyExclusiveTrait(player, traitName) then return false end
    return true
end

local function canRemoveTrait(player, traitName)
    return playerHasTrait(player, traitName)
end

function BCR.getEarnableTraits(player)
    if not player then return {} end
    return buildTraitPool(player, BCR.PositiveTraitsList, canEarnTrait)
end

function BCR.getRemovableTraits(player)
    if not player then return {} end
    return buildTraitPool(player, BCR.NegativeTraitsList, canRemoveTrait)
end

function BCR.HasAvailableRewards(player)
    if not player then return false end
    
    local opts = BCR.getSandboxOptions()
    local earnablePool = {}
    local removablePool = {}
    
    if opts.givePositiveTraits then
        earnablePool = BCR.getEarnableTraits(player)
    end
    
    if opts.removeNegativeTraits then
        removablePool = BCR.getRemovableTraits(player)
    end
    
    return #earnablePool > 0 or #removablePool > 0
end


-- ============================================================
-- TRAIT APPLICATION (Singleplayer & Server only)

local function canModifyTraits()
    if BCR.isSinglePlayer() then return true end
    if isServer() then return true end
    return false
end

function BCR.addTraitToPlayer(player, traitEntry)
    if not player then 
        BCR.DebugPrint("addTraitToPlayer: No player provided")
        return false 
    end
    
    if not canModifyTraits() then
        BCR.DebugPrint("addTraitToPlayer: Cannot modify traits in this context")
        return false
    end
    
    local traitName = traitEntry.trait
    local traitUserdata = traitEntry.traitUserdata or getTraitUserdata(traitName)
    
    if not traitUserdata then
        BCR.DebugPrint("addTraitToPlayer: Trait '" .. tostring(traitName) .. "' not found")
        return false
    end
    
    if playerHasTrait(player, traitName) then
        BCR.DebugPrint("addTraitToPlayer: Player already has '" .. traitName .. "'")
        return false
    end
    
    local traits = player:getCharacterTraits()
    if not traits then
        BCR.DebugPrint("addTraitToPlayer: Could not get character traits")
        return false
    end
    
    local success, err = pcall(function()
        traits:add(traitUserdata)
    end)
    
    if not success then
        BCR.DebugPrint("addTraitToPlayer: Error - " .. tostring(err))
        return false
    end
    
    local hasNow = playerHasTrait(player, traitName)
    BCR.DebugPrint("addTraitToPlayer: " .. traitName .. " added = " .. tostring(hasNow))
    
    return hasNow
end

function BCR.removeTraitFromPlayer(player, traitEntry)
    if not player then 
        BCR.DebugPrint("removeTraitFromPlayer: No player provided")
        return false 
    end
    
    if not canModifyTraits() then
        BCR.DebugPrint("removeTraitFromPlayer: Cannot modify traits in this context")
        return false
    end
    
    local traitName = traitEntry.trait
    local traitUserdata = traitEntry.traitUserdata or getTraitUserdata(traitName)
    
    if not traitUserdata then
        BCR.DebugPrint("removeTraitFromPlayer: Trait '" .. tostring(traitName) .. "' not found")
        return false
    end
    
    if not playerHasTrait(player, traitName) then
        BCR.DebugPrint("removeTraitFromPlayer: Player doesn't have '" .. traitName .. "'")
        return false
    end
    
    local traits = player:getCharacterTraits()
    if not traits then
        BCR.DebugPrint("removeTraitFromPlayer: Could not get character traits")
        return false
    end
    
    local success, err = pcall(function()
        traits:remove(traitUserdata)
    end)
    
    if not success then
        BCR.DebugPrint("removeTraitFromPlayer: Error - " .. tostring(err))
        return false
    end
    
    local removed = not playerHasTrait(player, traitName)
    BCR.DebugPrint("removeTraitFromPlayer: " .. traitName .. " removed = " .. tostring(removed))
    
    return removed
end


-- ============================================================
-- TRAIT DISPLAY NAME TRANSLATION
-- Fallback chain: Override → TitleCase key → getName() key → formatted string

local function formatTraitName(traitID)
    if not traitID or type(traitID) ~= "string" then
        return "Unknown"
    end
    
    local formatted = traitID:gsub("_", " "):lower()
    local result = {}
    
    for word in formatted:gmatch("%S+") do
        if word and #word > 0 then
            local first = word:sub(1, 1):upper()
            local rest = word:sub(2) or ""
            table.insert(result, first .. rest)
        end
    end
    
    return table.concat(result, " ")
end

function BCR.getTraitDisplayName(traitID)
    local traitUserdata = getTraitUserdata(traitID)
    if not traitUserdata then return formatTraitName(traitID) end
    
    -- Overrides for traits with non-standard translation keys
    local overrides = {
        NEEDS_LESS_SLEEP = "UI_trait_LessSleep",
        NEEDS_MORE_SLEEP = "UI_trait_MoreSleep",
        DEXTROUS = "UI_trait_Dexterous",
    }
    
    if overrides[traitID] then
        local trans = getText(overrides[traitID])
        if trans ~= overrides[traitID] then return trans end
    end
    
    local titleCase = traitID:lower():gsub("_(%l)", function(c) return c:upper() end):gsub("^%l", string.upper)
    local key1 = "UI_trait_" .. titleCase
    local trans1 = getText(key1)
    if trans1 ~= key1 then return trans1 end
    
    local success, name = pcall(function() return traitUserdata:getName() end)
    if success and name then
        local key2 = "UI_trait_" .. name
        local trans2 = getText(key2)
        if trans2 ~= key2 then return trans2 end
    end
    
    return formatTraitName(traitID)
end

print("[BodyCountRewards] Shared.lua loaded - " 
    .. #BCR.PositiveTraitsList .. " positive, " 
    .. #BCR.NegativeTraitsList .. " negative traits")
