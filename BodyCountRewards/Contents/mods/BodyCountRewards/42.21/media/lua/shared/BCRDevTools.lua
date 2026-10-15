-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRDevTools (Build 42.21+)
-- Developer tools, shipped for in-game use:
--   BCRDumpTraits()          - engine trait registry dump
--   BCR.RunThirdPartyTests() - addon registration checks
-- Console commands only; not part of the runtime reward flow.
-- ============================================================

BCR = BCR or {}

-- ============================================================
-- ENGINE TRAIT DUMP -- iterates what the running game actually
-- holds (every character_trait_definition: vanilla + mods).
-- Run in-game: BCRDumpTraits()
-- ============================================================

-- Collects the engine trait registry as sorted rows: { id = ..., text = ... }.
function BCR.CollectEngineTraits()
    local rows = {}
    local defsOk, defs = pcall(function() return CharacterTraitDefinition.getTraits() end)
    if not defsOk or not defs then
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
    return rows
end

-- Prints the engine trait registry plus coverage checks. Run in-game: BCRDumpTraits().
function BCR.DumpEngineTraits()
    local rows = BCR.CollectEngineTraits()
    if #rows == 0 then
        print("[BCR] [Dump] Engine trait definitions unavailable in this context")
        return rows
    end

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
    BCR.DumpEngineTraits()
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
