-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRData (Build 42.19+)
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
-- TEMPORARY: v1.3.1 migration table. Maps pre-v1.3.1
-- UPPER_SNAKE_CASE trait IDs to ResourceLocation format.
-- Used by GetTraitDisplayName (history fallback) and
-- RefreshConfig (sandbox key migration).
-- Remove after a few releases when old saves cycle out.
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

function BCR.NormalizeTraitCost(traitId, cost, isPositive)
    if type(cost) ~= "number" then
        local engineCost = BCR.GetEngineTraitCost(traitId)
        if engineCost == nil then return nil, nil end
        if isPositive then
            return -engineCost, "engine"
        end
        return engineCost, "engine"
    end
    if (isPositive and cost > 0) or (not isPositive and cost < 0) then
        return -cost, "sign"
    end
    return cost, nil
end

function BCR.RegisterCustomTraits(sourceName, sandboxNamespace, positiveTraits, negativeTraits, exclusions)
    if not sourceName then
        print("[BCR] [Addon] RegisterCustomTraits: missing sourceName")
        return 0
    end
    if not sandboxNamespace then
        print("[BCR] [Addon] RegisterCustomTraits: missing sandboxNamespace for \"" .. tostring(sourceName) .. "\"")
        return 0
    end
    local registeredPos = 0
    local registeredNeg = 0
    local rejected = 0
    local corrected = 0

    local function registerBatch(list, isPositive)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if not traitId then
                print("[BCR] [Addon] \"" .. sourceName .. "\" -- trait entry missing id, skipped")
                rejected = rejected + 1
            elseif not BCR.GetTraitUserdata(traitId) then
                print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " not a valid CharacterTrait, skipped")
                rejected = rejected + 1
            elseif BCR.CustomTraitSources[traitId] then
                print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " already registered by \"" .. tostring(BCR.CustomTraitSources[traitId]) .. "\", skipped")
                rejected = rejected + 1
            else
                local cost, repair = BCR.NormalizeTraitCost(traitId, entry.cost, isPositive)
                if cost == nil then
                    print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " has no numeric cost and no engine cost, skipped")
                    rejected = rejected + 1
                else
                    if repair == "engine" then
                        print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. traitId .. " has no numeric cost; using engine cost " .. tostring(cost) .. " (auto-corrected)")
                        corrected = corrected + 1
                    elseif repair == "sign" then
                        print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. traitId .. " cost " .. tostring(entry.cost) .. " has the wrong sign for the " .. (isPositive and "positive" or "negative") .. " list; corrected to " .. tostring(cost) .. " (auto-corrected)")
                        corrected = corrected + 1
                    end
                    local alreadyInBase = false
                    if isPositive then
                        for _, b in ipairs(BCR.PositiveTraits) do
                            if b.id == traitId then alreadyInBase = true; break end
                        end
                        if not alreadyInBase then
                            table.insert(BCR.CustomPositiveTraits, { id = traitId, cost = cost })
                        end
                    else
                        for _, b in ipairs(BCR.NegativeTraits) do
                            if b.id == traitId then alreadyInBase = true; break end
                        end
                        if not alreadyInBase then
                            table.insert(BCR.CustomNegativeTraits, { id = traitId, cost = cost })
                        end
                    end
                    if alreadyInBase then
                        print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. traitId .. " is already a base BCR trait, skipped")
                        rejected = rejected + 1
                    else
                        BCR.CustomTraitSources[traitId] = sourceName
                        BCR.CustomTraitNamespaces[traitId] = sandboxNamespace
                        if isPositive then
                            registeredPos = registeredPos + 1
                        else
                            registeredNeg = registeredNeg + 1
                        end
                    end
                end
            end
        end
    end

    local function mergeExclusions()
        if not exclusions then return end
        -- Copy first: an addon may pass BCR.Exclusions itself, and Lua 5.1
        -- leaves pairs() undefined when new keys are inserted during traversal.
        local source = {}
        for traitId, excludeList in pairs(exclusions) do
            source[traitId] = excludeList
        end
        for traitId, excludeList in pairs(source) do
            if type(traitId) == "string" and type(excludeList) == "table" then
                for _, excludedId in ipairs(excludeList) do
                    if type(excludedId) ~= "string" or excludedId == "" then
                        print("[BCR] [Addon] \"" .. sourceName .. "\" -- invalid exclusion entry in " .. traitId .. " (non-string or empty value)")
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

    local ok, err = pcall(function()
        registerBatch(positiveTraits, true)
        registerBatch(negativeTraits, false)
        mergeExclusions()
    end)
    if not ok then
        print("[BCR] [Addon] \"" .. sourceName .. "\" -- internal error during registration: " .. tostring(err))
        return registeredPos + registeredNeg
    end

    local totalRegistered = registeredPos + registeredNeg
    local parts = {}
    if registeredPos > 0 then table.insert(parts, registeredPos .. " positive") end
    if registeredNeg > 0 then table.insert(parts, registeredNeg .. " negative") end
    local registeredStr = table.concat(parts, ", ")

    local statusStr
    if totalRegistered == 0 then
        statusStr = "nothing registered -- check messages above"
    else
        statusStr = registeredStr
        if corrected > 0 then
            statusStr = statusStr .. " (" .. corrected .. " auto-corrected)"
        end
        if rejected > 0 then
            statusStr = statusStr .. " (" .. rejected .. " rejected)"
        end
    end

    print("[BCR] [Addon] \"" .. sourceName .. "\" -- " .. statusStr)
    BCR.DebugPrint("Addon", "RegisterCustomTraits: [" .. sourceName .. "] detail -- " .. registeredStr)
    if totalRegistered > 0 then
        BCR.RebuildMergedTraits()
    end
    return totalRegistered
end
