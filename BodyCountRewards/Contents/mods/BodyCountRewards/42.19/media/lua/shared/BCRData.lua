-- ============================================================
-- BodyCountRewards v1.3.0 — BCRData (Build 42.19+)
-- Pure data tables. No functions. No logic. Edit trait lists here.
-- ============================================================

BCR = BCR or {}

-- ============================================================
-- CONSTANTS
-- ============================================================

BCR.MAX_WEIGHT_COST = 8

-- ============================================================
-- POSITIVE TRAITS — earnable (cost = negative number)
-- ============================================================

BCR.PositiveTraits = {
    { id = "SPEED_DEMON",      cost = -1 },
    { id = "NIGHT_VISION",     cost = -3 },
    { id = "DEXTROUS",         cost = -2 },
    { id = "FAST_READER",      cost = -2 },
    { id = "INVENTIVE",        cost = -2 },
    { id = "LIGHT_EATER",      cost = -2 },
    { id = "LOW_THIRST",       cost = -2 },
    { id = "OUTDOORSMAN",      cost = -2 },
    { id = "NEEDS_LESS_SLEEP", cost = -3 },
    { id = "IRON_GUT",         cost = -2 },
    { id = "ADRENALINE_JUNKIE",cost = -4 },
    { id = "EAGLE_EYED",       cost = -4 },
    { id = "GRACEFUL",         cost = -4 },
    { id = "INCONSPICUOUS",    cost = -4 },
    { id = "NUTRITIONIST",     cost = -2 },
    { id = "ORGANIZED",        cost = -4 },
    { id = "RESILIENT",        cost = -4 },
    { id = "FAST_HEALER",      cost = -6 },
    { id = "FAST_LEARNER",     cost = -6 },
    { id = "KEEN_HEARING",     cost = -6 },
    { id = "THICK_SKINNED",    cost = -8 },
}

-- ============================================================
-- NEGATIVE TRAITS — removable (cost = positive number)
-- ============================================================

BCR.NegativeTraits = {
    { id = "HIGH_THIRST",      cost = 2 },
    { id = "SUNDAY_DRIVER",    cost = 1 },
    { id = "ALL_THUMBS",       cost = 2 },
    { id = "CLUMSY",           cost = 2 },
    { id = "COWARDLY",         cost = 2 },
    { id = "SLOW_READER",      cost = 2 },
    { id = "SLOW_HEALER",      cost = 3 },
    { id = "WEAK_STOMACH",     cost = 2 },
    { id = "SMOKER",           cost = 3 },
    { id = "AGORAPHOBIC",      cost = 4 },
    { id = "CLAUSTROPHOBIC",   cost = 4 },
    { id = "CONSPICUOUS",      cost = 4 },
    { id = "HEARTY_APPETITE",  cost = 4 },
    { id = "PACIFIST",         cost = 5 },
    { id = "PRONE_TO_ILLNESS", cost = 4 },
    { id = "NEEDS_MORE_SLEEP", cost = 4 },
    { id = "ASTHMATIC",        cost = 5 },
    { id = "HEMOPHOBIC",       cost = 5 },
    { id = "DISORGANIZED",     cost = 6 },
    { id = "SLOW_LEARNER",     cost = 6 },
    { id = "ILLITERATE",       cost = 10 },
    { id = "THIN_SKINNED",     cost = 8 },
}

-- ============================================================
-- MUTUAL EXCLUSIONS — symmetric (A excludes B ⇔ B excludes A)
-- ============================================================

BCR.Exclusions = {
    ["ADRENALINE_JUNKIE"]  = { "AGORAPHOBIC", "CLAUSTROPHOBIC", "COWARDLY" },
    ["AGORAPHOBIC"]        = { "ADRENALINE_JUNKIE", "CLAUSTROPHOBIC" },
    ["ALL_THUMBS"]         = { "DEXTROUS" },
    ["CLAUSTROPHOBIC"]     = { "ADRENALINE_JUNKIE", "AGORAPHOBIC" },
    ["CLUMSY"]             = { "GRACEFUL" },
    ["CONSPICUOUS"]        = { "INCONSPICUOUS" },
    ["COWARDLY"]           = { "ADRENALINE_JUNKIE" },
    ["DEXTROUS"]           = { "ALL_THUMBS" },
    ["DISORGANIZED"]       = { "ORGANIZED" },
    ["FAST_HEALER"]        = { "SLOW_HEALER" },
    ["FAST_LEARNER"]       = { "SLOW_LEARNER" },
    ["FAST_READER"]        = { "ILLITERATE", "SLOW_READER" },
    ["GRACEFUL"]           = { "CLUMSY" },
    ["HEARTY_APPETITE"]    = { "LIGHT_EATER" },
    ["HIGH_THIRST"]        = { "LOW_THIRST" },
    ["ILLITERATE"]         = { "FAST_READER", "SLOW_READER" },
    ["INCONSPICUOUS"]      = { "CONSPICUOUS" },
    ["IRON_GUT"]           = { "WEAK_STOMACH" },
    ["LIGHT_EATER"]        = { "HEARTY_APPETITE" },
    ["LOW_THIRST"]         = { "HIGH_THIRST" },
    ["ORGANIZED"]          = { "DISORGANIZED" },
    ["PRONE_TO_ILLNESS"]   = { "RESILIENT" },
    ["RESILIENT"]          = { "PRONE_TO_ILLNESS" },
    ["NEEDS_MORE_SLEEP"]   = { "NEEDS_LESS_SLEEP" },
    ["NEEDS_LESS_SLEEP"]   = { "NEEDS_MORE_SLEEP" },
    ["SLOW_HEALER"]        = { "FAST_HEALER" },
    ["SLOW_LEARNER"]       = { "FAST_LEARNER" },
    ["SLOW_READER"]        = { "FAST_READER", "ILLITERATE" },
    ["SPEED_DEMON"]        = { "SUNDAY_DRIVER" },
    ["SUNDAY_DRIVER"]      = { "SPEED_DEMON" },
    ["THICK_SKINNED"]      = { "THIN_SKINNED" },
    ["THIN_SKINNED"]       = { "THICK_SKINNED" },
    ["WEAK_STOMACH"]       = { "IRON_GUT" },
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
-- EXTENSIBILITY — third-party addon trait registration
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
                print("[BCR] \"" .. sourceName .. "\" — trait entry missing id, skipped")
                rejected = rejected + 1
            elseif type(entry.cost) ~= "number" then
                print("[BCR] \"" .. sourceName .. "\" — " .. tostring(traitId) .. " has no numeric cost, skipped")
                rejected = rejected + 1
            elseif isPositive and entry.cost > 0 then
                print("[BCR] \"" .. sourceName .. "\" — " .. tostring(traitId) .. " positive trait with positive cost " .. tostring(entry.cost) .. " (expected negative); registered anyway")
            elseif not isPositive and entry.cost < 0 then
                print("[BCR] \"" .. sourceName .. "\" — " .. tostring(traitId) .. " negative trait with negative cost " .. tostring(entry.cost) .. " (expected positive); registered anyway")
            elseif not BCR.GetTraitUserdata(traitId) then
                print("[BCR] \"" .. sourceName .. "\" — " .. tostring(traitId) .. " not a valid CharacterTrait, skipped")
                rejected = rejected + 1
            elseif BCR.CustomTraitSources[traitId] then
                print("[BCR] \"" .. sourceName .. "\" — " .. tostring(traitId) .. " already registered by \"" .. tostring(BCR.CustomTraitSources[traitId]) .. "\", skipped")
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
                    print("[BCR] \"" .. sourceName .. "\" — " .. traitId .. " is already a base BCR trait, skipped")
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
                        print("[BCR] \"" .. sourceName .. "\" — invalid exclusion entry in " .. traitId .. " (non-string or empty value)")
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
    return totalRegistered
end
