-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRCore (Build 42.19+)
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

function BCR.GetTraitUserdata(traitId)
    if not traitId or traitId == "" then
        return nil
    end
    local cached = traitUserdataCache[traitId]
    if cached ~= nil then return cached end
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

function BCR.PlayerHasTrait(player, traitId)
    if not player then return nil end
    local traitObj = BCR.GetTraitUserdata(traitId)
    if not traitObj then return nil end
    local ok, result = pcall(function() return player:hasTrait(traitObj) end)
    if not ok then return nil end
    return result
end

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

function BCR.GetPlayerTraitsList(player)
    if not player then return nil end
    local ok, traits = pcall(function() return player:getCharacterTraits() end)
    if not ok or not traits then return nil end
    local ok2, knownTraits = pcall(function() return traits:getKnownTraits() end)
    if not ok2 or not knownTraits then return nil end
    local result = {}
    local ok3, size = pcall(function() return knownTraits:size() end)
    if not ok3 then return result end
    for i = 0, size - 1 do
        local ok4, trait = pcall(function() return knownTraits:get(i) end)
        if ok4 and trait then
            table.insert(result, tostring(trait))
        end
    end
    return result
end

-- ============================================================
-- TRAIT MODIFICATION -- unified internal function
-- ============================================================

local function canModifyTraits()
    return (not isClient() and not isServer()) or isServer()
end

local function modifyTrait(player, traitEntry, action)
    if not player or not traitEntry then return false end
    if not canModifyTraits() then
        BCR.DebugPrint("modifyTrait: cannot modify traits in this context")
        return false
    end
    local traitId = traitEntry.id
    if not traitId then return false end
    local traitObj = traitEntry.traitUserdata or BCR.GetTraitUserdata(traitId)
    if not traitObj then
        BCR.DebugPrint("modifyTrait: no userdata for " .. tostring(traitId))
        return false
    end

    if action == "add" then
        local has = BCR.PlayerHasTrait(player, traitId)
        if has ~= false then
            BCR.DebugPrint("modifyTrait: cannot add " .. traitId .. " (has=" .. tostring(has) .. ")")
            return false
        end
        local blocked, blockerId = BCR.HasMutuallyExclusiveTrait(player, traitId)
        if blocked then
            BCR.DebugPrint("modifyTrait: cannot add " .. traitId .. " (blocked by " .. tostring(blockerId) .. ")")
            return false
        end
    elseif action == "remove" then
        local has = BCR.PlayerHasTrait(player, traitId)
        if has ~= true then
            BCR.DebugPrint("modifyTrait: cannot remove " .. traitId .. " (has=" .. tostring(has) .. ")")
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
        BCR.DebugPrint("modifyTrait: " .. action .. " failed for " .. traitId .. ": " .. tostring(err))
        return false
    end
    return true
end

function BCR.AddTrait(player, traitEntry)
    return modifyTrait(player, traitEntry, "add")
end

function BCR.RemoveTrait(player, traitEntry)
    return modifyTrait(player, traitEntry, "remove")
end

-- ============================================================
-- WEIGHTED SELECTION
-- ============================================================

function BCR.GetRarity(cost)
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
    return math.max(1, (BCR.MAX_WEIGHT_COST - math.abs(cost)) + 1)
end

function BCR.WeightedRandomSelect(pool)
    if not pool then return nil end
    local empty = true
    for _ in pairs(pool) do empty = false; break end
    if empty then return nil end
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        totalWeight = totalWeight + (entry.weight or 1)
    end
    if totalWeight <= 0 then
        local count = #pool
        return pool[ZombRand(count) + 1]
    end
    local roll = ZombRand(totalWeight)
    local cumulative = 0
    for _, entry in ipairs(pool) do
        cumulative = cumulative + (entry.weight or 1)
        if roll < cumulative then
            return entry
        end
    end
    return pool[#pool]
end

-- ============================================================
-- POOL BUILDING
-- ============================================================

BCR.MergedPositiveTraits = BCR.PositiveTraits
BCR.MergedNegativeTraits = BCR.NegativeTraits

local function mergeTraitTables(base, custom)
    if not custom then return base end
    if #custom == 0 then return base end
    local merged = {}
    for _, v in ipairs(base) do
        table.insert(merged, v)
    end
    for _, v in ipairs(custom) do
        table.insert(merged, v)
    end
    return merged
end

function BCR.RebuildMergedTraits()
    BCR.MergedPositiveTraits = mergeTraitTables(BCR.PositiveTraits, BCR.CustomPositiveTraits)
    BCR.MergedNegativeTraits = mergeTraitTables(BCR.NegativeTraits, BCR.CustomNegativeTraits)
end

function BCR.BuildEarnablePool(player, customTraits)
    if not player then return nil end
    local allTraits = BCR.MergedPositiveTraits
    if customTraits then
        allTraits = mergeTraitTables(allTraits, customTraits)
    end
    local pool = {}
    for _, entry in ipairs(allTraits) do
        local traitId = entry.id
        if traitId then
            if BCR.IsTraitAllowed(traitId) then
                local has = BCR.PlayerHasTrait(player, traitId)
                if has == false then
                    local blocked = BCR.HasMutuallyExclusiveTrait(player, traitId)
                    if not blocked then
                        local traitObj = BCR.GetTraitUserdata(traitId)
                        if traitObj then
                            local cost = entry.cost or 0
                            local rarity = BCR.GetRarity(cost)
                            local weight = BCR.CalculateWeight(cost)
                            table.insert(pool, {
                                id = traitId,
                                traitUserdata = traitObj,
                                cost = cost,
                                rarity = rarity,
                                weight = weight,
                            })
                        end
                    end
                end
            end
        end
    end
    return pool
end

function BCR.BuildRemovablePool(player, customTraits)
    if not player then return nil end
    local allTraits = BCR.MergedNegativeTraits
    if customTraits then
        allTraits = mergeTraitTables(allTraits, customTraits)
    end
    local pool = {}
    for _, entry in ipairs(allTraits) do
        local traitId = entry.id
        if traitId then
            if BCR.IsTraitAllowed(traitId) then
                if BCR.PlayerHasTrait(player, traitId) == true then
                    local traitObj = BCR.GetTraitUserdata(traitId)
                    if traitObj then
                        local cost = entry.cost or 0
                        local rarity = BCR.GetRarity(cost)
                        local weight = BCR.CalculateWeight(cost)
                        table.insert(pool, {
                            id = traitId,
                            traitUserdata = traitObj,
                            cost = cost,
                            rarity = rarity,
                            weight = weight,
                        })
                    end
                end
            end
        end
    end
    return pool
end

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
    if milestone <= 0 then return 0 end
    local bc = opts.bodyCount or 1000
    if opts.milestoneScaling == 2 then
        local factor = opts.progressiveScalingFactor or 0.5
        if factor > 0 then
            return math.floor(bc * (milestone + factor * milestone * (milestone - 1) / 2))
        end
    end
    return milestone * bc
end

function BCR.GetMilestonesAtKills(kills, opts)
    if kills <= 0 then return 0 end
    local bc = opts.bodyCount or 1000
    if bc <= 0 then return 0 end
    if opts.milestoneScaling == 2 then
        local factor = opts.progressiveScalingFactor or 0.5
        if factor > 0 then
            local a = factor * bc / 2
            local b = bc * (1 - factor / 2)
            local c = -kills
            local discriminant = b * b - 4 * a * c
            if discriminant < 0 then return 0 end
            local root = math.floor((-b + math.sqrt(discriminant)) / (2 * a))
            return math.max(0, root)
        end
    end
    return math.floor(kills / bc)
end

-- ============================================================
-- DISPLAY NAMES
-- ============================================================

function BCR.GetTraitDisplayName(traitId)
    if not traitId then return "Unknown" end
    local override = BCR.DISPLAY_OVERRIDES[traitId]
    if override then
        local text = getText(override)
        if text and text ~= override then return text end
    end
    local colonPos = string.find(traitId, ":")
    local path = colonPos and string.sub(traitId, colonPos + 1) or nil
    if not path then
        local newId = BCR.TRAIT_ID_MIGRATION and BCR.TRAIT_ID_MIGRATION[traitId]
        if newId then
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
    end
    local readable = string.gsub(path, "([a-z])([A-Z])", "%1 %2")
    return readable ~= "" and readable or "Unknown"
end

-- ============================================================
-- MODDATA
-- ============================================================

function BCR.EnsureModData(player)
    if not player then return nil end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or not modData then return nil end
    if not modData.BCR then
        modData.BCR = {
            kills = 0,
            rewardsGiven = 0,
            traitHistory = {},
        }
    end
    if not modData.BCR.traitHistory then
        modData.BCR.traitHistory = {}
    end
    return modData.BCR
end

-- ============================================================
-- AVAILABILITY
-- ============================================================

function BCR.HasAvailableRewards(player)
    if not player then return false end
    local opts = BCR.opts
    if not opts then
        BCR.RefreshConfig()
        opts = BCR.opts
    end
    local earnableCount = 0
    local removableCount = 0
    if opts.enablePositive ~= false then
        local earnable = BCR.BuildEarnablePool(player, nil)
        if earnable then
            for _ in ipairs(earnable) do earnableCount = earnableCount + 1 end
        end
    end
    if opts.enableNegative ~= false then
        local removable = BCR.BuildRemovablePool(player, nil)
        if removable then
            for _ in ipairs(removable) do removableCount = removableCount + 1 end
        end
    end
    return earnableCount > 0 or removableCount > 0
end

-- ============================================================
-- THIRD-PARTY TRAIT TESTS
-- ============================================================

function BCR_RunThirdPartyTests()
    local passed, failed = 0, 0

    local function ok(msg, condition)
        if condition then
            passed = passed + 1
            print("[BCR ThirdPartyTest] PASS: " .. msg)
        else
            failed = failed + 1
            print("[BCR ThirdPartyTest] FAIL: " .. msg)
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
        print("[BCR ThirdPartyTest] No third-party traits registered.")
        return true
    end

    print("[BCR ThirdPartyTest] ===== Checking " .. tostring(positiveCount) ..
        " custom positive, " .. tostring(negativeCount) .. " custom negative trait(s) =====")

    local sources = {}

    local function testTraitList(list, label)
        if not list then return end
        for _, entry in ipairs(list) do
            local traitId = entry.id
            if not traitId then
                failed = failed + 1
                print("[BCR ThirdPartyTest] FAIL: " .. label .. " entry missing id")
            else
                local source = BCR.CustomTraitSources and BCR.CustomTraitSources[traitId]
                local ns = BCR.CustomTraitNamespaces and BCR.CustomTraitNamespaces[traitId]
                local userdata = BCR.GetTraitUserdata(traitId)

                if not source then
                    failed = failed + 1
                    print("[BCR ThirdPartyTest] FAIL: " .. traitId .. " missing source")
                else
                    sources[source] = true
                end

                if not ns then
                    failed = failed + 1
                    print("[BCR ThirdPartyTest] FAIL: " .. traitId .. " missing sandbox namespace")
                end

                if not userdata then
                    failed = failed + 1
                    print("[BCR ThirdPartyTest] FAIL: " .. traitId .. " does not resolve via CharacterTrait")
                end

                if source and ns and userdata then
                    passed = passed + 1
                    print("[BCR ThirdPartyTest] OK: " .. traitId .. " (source=\"" .. source .. "\", ns=\"" .. ns .. "\")")
                end
            end
        end
    end

    testTraitList(BCR.CustomPositiveTraits, "positive")
    testTraitList(BCR.CustomNegativeTraits, "negative")

    ok("BCR.Exclusions exists and is a table",
        BCR.Exclusions ~= nil and type(BCR.Exclusions) == "table")

    local sourceList = {}
    for s, _ in pairs(sources) do table.insert(sourceList, "\"" .. s .. "\"") end
    print("[BCR ThirdPartyTest] Active addon(s): " .. table.concat(sourceList, ", "))

    print("[BCR ThirdPartyTest] ===== " .. tostring(passed) .. " passed, " ..
        tostring(failed) .. " failed =====")
    return failed == 0
end

BCR.RunThirdPartyTests = BCR_RunThirdPartyTests
