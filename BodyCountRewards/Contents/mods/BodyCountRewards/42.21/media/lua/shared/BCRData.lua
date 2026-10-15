-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRData (Build 42.21+)
-- Base trait lists, rarity tiers, exclusions, and the third-party
-- trait registration API (BCR.RegisterCustomTraits).
-- ============================================================

BCR = BCR or {}

-- ============================================================
-- CONSTANTS
-- ============================================================

BCR.MAX_WEIGHT_COST = 8

-- ============================================================
-- POSITIVE TRAITS -- earnable (cost = negative number)
-- ============================================================

BCR.PositiveTraits = {
    { id = "base:SpeedDemon",      cost = -1 },
    { id = "base:NightVision",     cost = -3 },
    { id = "base:Dextrous",         cost = -2 },
    { id = "base:FastReader",      cost = -2 },
    { id = "base:Inventive",        cost = -2 },
    { id = "base:LightEater",      cost = -2 },
    { id = "base:LowThirst",       cost = -2 },
    { id = "base:Outdoorsman",      cost = -2 },
    { id = "base:NeedsLessSleep", cost = -3 },
    { id = "base:IronGut",         cost = -2 },
    { id = "base:AdrenalineJunkie",cost = -4 },
    { id = "base:EagleEyed",       cost = -4 },
    { id = "base:Graceful",         cost = -4 },
    { id = "base:Inconspicuous",    cost = -4 },
    { id = "base:Nutritionist",     cost = -2 },
    { id = "base:Organized",        cost = -4 },
    { id = "base:Resilient",        cost = -4 },
    { id = "base:FastHealer",      cost = -6 },
    { id = "base:FastLearner",     cost = -6 },
    { id = "base:KeenHearing",     cost = -6 },
    { id = "base:ThickSkinned",    cost = -8 },
}

-- ============================================================
-- NEGATIVE TRAITS -- removable (cost = positive number)
-- ============================================================

BCR.NegativeTraits = {
    { id = "base:HighThirst",      cost = 2 },
    { id = "base:SundayDriver",    cost = 1 },
    { id = "base:AllThumbs",       cost = 2 },
    { id = "base:Clumsy",           cost = 2 },
    { id = "base:Cowardly",         cost = 2 },
    { id = "base:SlowReader",      cost = 2 },
    { id = "base:SlowHealer",      cost = 3 },
    { id = "base:WeakStomach",     cost = 2 },
    { id = "base:Smoker",           cost = 3 },
    { id = "base:Agoraphobic",      cost = 4 },
    { id = "base:Claustrophobic",   cost = 4 },
    { id = "base:Conspicuous",      cost = 4 },
    { id = "base:HeartyAppetite",  cost = 4 },
    { id = "base:Pacifist",         cost = 5 },
    { id = "base:ProneToIllness", cost = 4 },
    { id = "base:NeedsMoreSleep", cost = 4 },
    { id = "base:Asthmatic",        cost = 5 },
    { id = "base:Hemophobic",       cost = 5 },
    { id = "base:Disorganized",     cost = 6 },
    { id = "base:SlowLearner",     cost = 6 },
    { id = "base:Illiterate",       cost = 10 },
    { id = "base:ThinSkinned",     cost = 8 },
}

-- ============================================================
-- MUTUAL EXCLUSIONS -- symmetric (A excludes B <-> B excludes A)
-- ============================================================

BCR.Exclusions = {
    ["base:AdrenalineJunkie"]  = { "base:Agoraphobic", "base:Claustrophobic", "base:Cowardly" },
    ["base:Agoraphobic"]        = { "base:AdrenalineJunkie", "base:Claustrophobic" },
    ["base:AllThumbs"]         = { "base:Dextrous" },
    ["base:Claustrophobic"]     = { "base:AdrenalineJunkie", "base:Agoraphobic" },
    ["base:Clumsy"]             = { "base:Graceful" },
    ["base:Conspicuous"]        = { "base:Inconspicuous" },
    ["base:Cowardly"]           = { "base:AdrenalineJunkie" },
    ["base:Dextrous"]           = { "base:AllThumbs" },
    ["base:Disorganized"]       = { "base:Organized" },
    ["base:FastHealer"]        = { "base:SlowHealer" },
    ["base:FastLearner"]       = { "base:SlowLearner" },
    ["base:FastReader"]        = { "base:Illiterate", "base:SlowReader" },
    ["base:Graceful"]           = { "base:Clumsy" },
    ["base:HeartyAppetite"]    = { "base:LightEater" },
    ["base:HighThirst"]        = { "base:LowThirst" },
    ["base:Illiterate"]         = { "base:FastReader", "base:SlowReader" },
    ["base:Inconspicuous"]      = { "base:Conspicuous" },
    ["base:IronGut"]           = { "base:WeakStomach" },
    ["base:LightEater"]        = { "base:HeartyAppetite" },
    ["base:LowThirst"]         = { "base:HighThirst" },
    ["base:Organized"]          = { "base:Disorganized" },
    ["base:ProneToIllness"]   = { "base:Resilient" },
    ["base:Resilient"]          = { "base:ProneToIllness" },
    ["base:NeedsMoreSleep"]   = { "base:NeedsLessSleep" },
    ["base:NeedsLessSleep"]   = { "base:NeedsMoreSleep" },
    ["base:SlowHealer"]        = { "base:FastHealer" },
    ["base:SlowLearner"]       = { "base:FastLearner" },
    ["base:SlowReader"]        = { "base:FastReader", "base:Illiterate" },
    ["base:SpeedDemon"]        = { "base:SundayDriver" },
    ["base:SundayDriver"]      = { "base:SpeedDemon" },
    ["base:ThickSkinned"]      = { "base:ThinSkinned" },
    ["base:ThinSkinned"]       = { "base:ThickSkinned" },
    ["base:WeakStomach"]       = { "base:IronGut" },
}

-- ============================================================
-- LEGACY: v1.3.1 migration table. Maps pre-v1.3.1
-- UPPER_SNAKE_CASE trait IDs to ResourceLocation format.
-- Used by GetTraitDisplayName and the trait history guards.
-- Kept for pre-v1.3.1 saves; revisit removal in a later release.
-- ============================================================

BCR.TRAIT_ID_MIGRATION = {
    SPEED_DEMON      = "base:SpeedDemon",
    NIGHT_VISION     = "base:NightVision",
    DEXTROUS         = "base:Dextrous",
    FAST_READER      = "base:FastReader",
    INVENTIVE        = "base:Inventive",
    LIGHT_EATER      = "base:LightEater",
    LOW_THIRST       = "base:LowThirst",
    OUTDOORSMAN      = "base:Outdoorsman",
    NEEDS_LESS_SLEEP = "base:NeedsLessSleep",
    IRON_GUT         = "base:IronGut",
    ADRENALINE_JUNKIE= "base:AdrenalineJunkie",
    EAGLE_EYED       = "base:EagleEyed",
    GRACEFUL         = "base:Graceful",
    INCONSPICUOUS    = "base:Inconspicuous",
    NUTRITIONIST     = "base:Nutritionist",
    ORGANIZED        = "base:Organized",
    RESILIENT        = "base:Resilient",
    FAST_HEALER      = "base:FastHealer",
    FAST_LEARNER     = "base:FastLearner",
    KEEN_HEARING     = "base:KeenHearing",
    THICK_SKINNED    = "base:ThickSkinned",
    HIGH_THIRST      = "base:HighThirst",
    SUNDAY_DRIVER    = "base:SundayDriver",
    ALL_THUMBS       = "base:AllThumbs",
    CLUMSY           = "base:Clumsy",
    COWARDLY         = "base:Cowardly",
    SLOW_READER      = "base:SlowReader",
    SLOW_HEALER      = "base:SlowHealer",
    WEAK_STOMACH     = "base:WeakStomach",
    SMOKER           = "base:Smoker",
    AGORAPHOBIC      = "base:Agoraphobic",
    CLAUSTROPHOBIC   = "base:Claustrophobic",
    CONSPICUOUS      = "base:Conspicuous",
    HEARTY_APPETITE  = "base:HeartyAppetite",
    PACIFIST         = "base:Pacifist",
    PRONE_TO_ILLNESS = "base:ProneToIllness",
    NEEDS_MORE_SLEEP = "base:NeedsMoreSleep",
    ASTHMATIC        = "base:Asthmatic",
    HEMOPHOBIC       = "base:Hemophobic",
    DISORGANIZED     = "base:Disorganized",
    SLOW_LEARNER     = "base:SlowLearner",
    ILLITERATE       = "base:Illiterate",
    THIN_SKINNED     = "base:ThinSkinned",
}

-- ============================================================
-- RARITY TIERS
-- ============================================================

BCR.RarityTiers = {
    common    = { maxCost = 2,  color = { 0.80, 0.80, 0.80 } },
    uncommon  = { maxCost = 4,  color = { 0.60, 1.00, 0.20 } },
    rare      = { maxCost = 6,  color = { 1.00, 0.60, 0.20 } },
    -- maxCost = 99 is a sentinel for "no upper bound"
    veryRare  = { maxCost = 99, color = { 0.80, 0.30, 1.00 } },
}

-- ============================================================
-- EXTENSIBILITY -- third-party addon trait registration
-- ============================================================

BCR.CustomPositiveTraits = BCR.CustomPositiveTraits or {}
BCR.CustomNegativeTraits = BCR.CustomNegativeTraits or {}
BCR.CustomTraitSources = BCR.CustomTraitSources or {}
BCR.CustomTraitNamespaces = BCR.CustomTraitNamespaces or {}

-- ============================================================
-- COST NORMALIZATION -- used by addon registration. BCR lists
-- store positive (earnable) traits with negative costs and
-- negative (removable) traits with positive costs. The engine
-- uses the opposite sign convention, so costs can be derived
-- from the engine and repaired automatically.
-- ============================================================

function BCR.GetEngineTraitCost(traitId)
    local trait = BCR.GetTraitUserdata(traitId)
    if not trait then return nil end
    local ok, cost = pcall(function()
        local def = CharacterTraitDefinition.getCharacterTraitDefinition(trait)
        if def then return def:getCost() end
        return nil
    end)
    if ok and type(cost) == "number" then
        return math.abs(cost)
    end
    return nil
end

-- kind: "earnable" for the positive list (costs are stored negative),
--       "removable" for the negative list (costs are stored positive).
-- Returns cost, repairCode where repairCode is "engine", "sign" or nil.
function BCR.NormalizeTraitCost(traitId, cost, kind)
    local isEarnable = kind == "earnable"
    if type(cost) ~= "number" then
        local engineCost = BCR.GetEngineTraitCost(traitId)
        if engineCost == nil then return nil, nil end
        if isEarnable then
            return -engineCost, "engine"
        end
        return engineCost, "engine"
    end
    if (isEarnable and cost > 0) or (not isEarnable and cost < 0) then
        return -cost, "sign"
    end
    return cost, nil
end

-- Addon log line: [BCR] [Addon] "Source" -- message
local function logAddon(sourceName, message)
    print("[BCR] [Addon] \"" .. tostring(sourceName) .. "\" -- " .. tostring(message))
end

-- True when the value is nil or a table.
local function isTableOrNil(value)
    return value == nil or type(value) == "table"
end

-- Registers one entry into the custom lists and updates the counters.
-- kind: "earnable" for the positive list, "removable" for the negative list.
local function tryRegisterOneTrait(state, sourceName, sandboxNamespace, entry, kind)
    local traitId = entry.id
    if not traitId then
        logAddon(sourceName, "trait entry missing id, skipped")
        state.rejected = state.rejected + 1
        return
    end
    if not BCR.GetTraitUserdata(traitId) then
        logAddon(sourceName, tostring(traitId) .. " not a valid CharacterTrait, skipped")
        state.rejected = state.rejected + 1
        return
    end
    if BCR.CustomTraitSources[traitId] then
        logAddon(sourceName, tostring(traitId) .. " already registered by \"" .. tostring(BCR.CustomTraitSources[traitId]) .. "\", skipped")
        state.rejected = state.rejected + 1
        return
    end

    local cost, repair = BCR.NormalizeTraitCost(traitId, entry.cost, kind)
    if cost == nil then
        logAddon(sourceName, tostring(traitId) .. " has no numeric cost and no engine cost, skipped")
        state.rejected = state.rejected + 1
        return
    end
    if repair == "engine" then
        logAddon(sourceName, traitId .. " has no numeric cost; using engine cost " .. tostring(cost) .. " (auto-corrected)")
        state.corrected = state.corrected + 1
    elseif repair == "sign" then
        logAddon(sourceName, traitId .. " cost " .. tostring(entry.cost) .. " has the wrong sign for the " .. (kind == "earnable" and "positive" or "negative") .. " list; corrected to " .. tostring(cost) .. " (auto-corrected)")
        state.corrected = state.corrected + 1
    end

    local baseList = BCR.PositiveTraits
    local customList = BCR.CustomPositiveTraits
    if kind == "removable" then
        baseList = BCR.NegativeTraits
        customList = BCR.CustomNegativeTraits
    end
    local alreadyInBase = false
    for _, base in ipairs(baseList) do
        if base.id == traitId then alreadyInBase = true; break end
    end
    if alreadyInBase then
        logAddon(sourceName, traitId .. " is already a base BCR trait, skipped")
        state.rejected = state.rejected + 1
        return
    end

    table.insert(customList, { id = traitId, cost = cost })
    BCR.CustomTraitSources[traitId] = sourceName
    BCR.CustomTraitNamespaces[traitId] = sandboxNamespace
    if kind == "earnable" then
        state.registeredPos = state.registeredPos + 1
    else
        state.registeredNeg = state.registeredNeg + 1
    end
end

local function registerBatch(state, sourceName, sandboxNamespace, list, kind)
    if not list then return end
    for _, entry in ipairs(list) do
        tryRegisterOneTrait(state, sourceName, sandboxNamespace, entry, kind)
    end
end

-- Merges the addon's exclusion table into BCR.Exclusions. Iterates a copy:
-- an addon may pass BCR.Exclusions itself, and Lua 5.1 leaves pairs()
-- undefined when new keys are inserted during traversal.
local function mergeExclusions(sourceName, exclusions)
    if not exclusions then return end
    local source = {}
    for traitId, excludeList in pairs(exclusions) do
        source[traitId] = excludeList
    end
    for traitId, excludeList in pairs(source) do
        if type(traitId) == "string" and type(excludeList) == "table" then
            for _, excludedId in ipairs(excludeList) do
                if type(excludedId) ~= "string" or excludedId == "" then
                    logAddon(sourceName, "invalid exclusion entry in " .. traitId .. " (non-string or empty value)")
                else
                    if not BCR.Exclusions[traitId] then
                        BCR.Exclusions[traitId] = {}
                    end
                    local target = BCR.Exclusions[traitId]
                    local found = false
                    for _, e in ipairs(target) do
                        if e == excludedId then found = true; break end
                    end
                    if not found then
                        table.insert(target, excludedId)
                    end
                end
            end
        end
    end
end

-- "N positive, M negative" text (empty when nothing registered).
local function formatRegisteredPair(state)
    local parts = {}
    if state.registeredPos > 0 then table.insert(parts, state.registeredPos .. " positive") end
    if state.registeredNeg > 0 then table.insert(parts, state.registeredNeg .. " negative") end
    return table.concat(parts, ", ")
end

-- Load-log summary line.
local function formatRegistrationReport(state)
    if state.registeredPos + state.registeredNeg == 0 then
        return "nothing registered -- check messages above"
    end
    local statusStr = formatRegisteredPair(state)
    if state.corrected > 0 then
        statusStr = statusStr .. " (" .. state.corrected .. " auto-corrected)"
    end
    if state.rejected > 0 then
        statusStr = statusStr .. " (" .. state.rejected .. " rejected)"
    end
    return statusStr
end

-- Registers a third-party addon's traits and exclusions. Call from a
-- `shared/` file after BCR has loaded.
--
-- Returns the number of traits registered (0 when nothing registered),
-- or nil plus an error message when registration failed part-way.
function BCR.RegisterCustomTraits(sourceName, sandboxNamespace, positiveTraits, negativeTraits, exclusions)
    if type(sourceName) ~= "string" or sourceName == "" then
        print("[BCR] [Addon] RegisterCustomTraits: sourceName must be a non-empty string")
        return 0
    end
    if type(sandboxNamespace) ~= "string" or sandboxNamespace == "" then
        print("[BCR] [Addon] RegisterCustomTraits: sandboxNamespace must be a non-empty string for \"" .. sourceName .. "\"")
        return 0
    end
    if not isTableOrNil(positiveTraits) or not isTableOrNil(negativeTraits)
        or not isTableOrNil(exclusions) then
        logAddon(sourceName, "positiveTraits, negativeTraits and exclusions must be tables (or nil)")
        return 0
    end

    local state = {
        registeredPos = 0,
        registeredNeg = 0,
        rejected = 0,
        corrected = 0,
    }

    local ok, err = pcall(function()
        registerBatch(state, sourceName, sandboxNamespace, positiveTraits, "earnable")
        registerBatch(state, sourceName, sandboxNamespace, negativeTraits, "removable")
        mergeExclusions(sourceName, exclusions)
    end)

    -- Keep the merged pools consistent even after a partial failure.
    if state.registeredPos + state.registeredNeg > 0 then
        BCR.RebuildMergedTraits()
    end

    if not ok then
        logAddon(sourceName, "internal error during registration: " .. tostring(err))
        return nil, err
    end

    logAddon(sourceName, formatRegistrationReport(state))
    BCR.DebugPrintf("Addon", "RegisterCustomTraits: [%s] detail -- %s",
        tostring(sourceName), tostring(formatRegisteredPair(state)))
    return state.registeredPos + state.registeredNeg
end
