-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRData (Build 42.19+)
-- Pure data tables. No functions. No logic. Edit trait lists here.
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
-- MUTUAL EXCLUSIONS -- symmetric (A excludes B ⇔ B excludes A)
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
-- RARITY TIERS
-- ============================================================

BCR.RarityTiers = {
    common    = { maxCost = 2,  color = { 0.80, 0.80, 0.80 } },
    uncommon  = { maxCost = 4,  color = { 0.60, 1.00, 0.20 } },
    rare      = { maxCost = 6,  color = { 1.00, 0.60, 0.20 } },
    veryRare  = { maxCost = 99, color = { 0.80, 0.30, 1.00 } },
}

-- ============================================================
-- EXTENSIBILITY -- third-party addon trait registration
-- ============================================================

BCR.CustomPositiveTraits = BCR.CustomPositiveTraits or {}
BCR.CustomNegativeTraits = BCR.CustomNegativeTraits or {}
BCR.CustomTraitSources = BCR.CustomTraitSources or {}
BCR.CustomTraitNamespaces = BCR.CustomTraitNamespaces or {}

function BCR.RegisterCustomTraits(sourceName, sandboxNamespace, positiveTraits, negativeTraits, exclusions)
    if not sourceName then
        print("[BCR] RegisterCustomTraits: missing sourceName")
        return 0
    end
    if not sandboxNamespace then
        print("[BCR] RegisterCustomTraits: missing sandboxNamespace for \"" .. tostring(sourceName) .. "\"")
        return 0
    end
    local registeredPos = 0
    local registeredNeg = 0
    local rejected = 0

    local function registerBatch(list, isPositive)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if not traitId then
                print("[BCR] \"" .. sourceName .. "\" -- trait entry missing id, skipped")
                rejected = rejected + 1
            elseif type(entry.cost) ~= "number" then
                print("[BCR] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " has no numeric cost, skipped")
                rejected = rejected + 1
            elseif isPositive and entry.cost > 0 then
                print("[BCR] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " positive trait with positive cost " .. tostring(entry.cost) .. " (expected negative); registered anyway")
            elseif not isPositive and entry.cost < 0 then
                print("[BCR] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " negative trait with negative cost " .. tostring(entry.cost) .. " (expected positive); registered anyway")
            elseif not BCR.GetTraitUserdata(traitId) then
                print("[BCR] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " not a valid CharacterTrait, skipped")
                rejected = rejected + 1
            elseif BCR.CustomTraitSources[traitId] then
                print("[BCR] \"" .. sourceName .. "\" -- " .. tostring(traitId) .. " already registered by \"" .. tostring(BCR.CustomTraitSources[traitId]) .. "\", skipped")
                rejected = rejected + 1
            else
                local alreadyInBase = false
                if isPositive then
                    for _, b in ipairs(BCR.PositiveTraits) do
                        if b.id == traitId then alreadyInBase = true; break end
                    end
                    if not alreadyInBase then
                        table.insert(BCR.CustomPositiveTraits, { id = traitId, cost = entry.cost })
                    end
                else
                    for _, b in ipairs(BCR.NegativeTraits) do
                        if b.id == traitId then alreadyInBase = true; break end
                    end
                    if not alreadyInBase then
                        table.insert(BCR.CustomNegativeTraits, { id = traitId, cost = entry.cost })
                    end
                end
                if alreadyInBase then
                    print("[BCR] \"" .. sourceName .. "\" -- " .. traitId .. " is already a base BCR trait, skipped")
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

    local function mergeExclusions()
        if not exclusions then return end
        for traitId, excludeList in pairs(exclusions) do
            if type(traitId) == "string" and type(excludeList) == "table" then
                for _, excludedId in ipairs(excludeList) do
                    if type(excludedId) ~= "string" or excludedId == "" then
                        print("[BCR] \"" .. sourceName .. "\" -- invalid exclusion entry in " .. traitId .. " (non-string or empty value)")
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
        print("[BCR] \"" .. sourceName .. "\" -- internal error during registration: " .. tostring(err))
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
        if rejected > 0 then
            statusStr = statusStr .. " (" .. rejected .. " rejected)"
        end
    end

    print("[BCR] \"" .. sourceName .. "\" -- " .. statusStr)
    BCR.DebugPrint("RegisterCustomTraits: [" .. sourceName .. "] detail -- " .. registeredStr)
    if totalRegistered > 0 then
        BCR.RebuildMergedTraits()
    end
    return totalRegistered
end
