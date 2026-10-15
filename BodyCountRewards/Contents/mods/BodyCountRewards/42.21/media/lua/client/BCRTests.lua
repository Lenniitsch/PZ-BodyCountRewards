-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRTests (Build 42.19+)
-- Unit tests, 15 suites. Run in-game: BCRRunTests()
-- ============================================================

require "BCRCore"
require "BCRNotifications"
require "BCRStatsUI"

BCR = BCR or {}

-- ============================================================
-- TEST FRAMEWORK
-- ============================================================

local passed = 0
local failed = 0
local skipped = 0
local currentSuite = ""
local failures = {}
local suiteIndex = 0
local suiteTotal = 0

local function assertTrue(cond, msg)
    if cond then
        passed = passed + 1
        print("[BCR] [Tests] PASS: " .. (msg or "assertTrue"))
    else
        failed = failed + 1
        local detail = msg or "assertion failed"
        table.insert(failures, "[" .. currentSuite .. "] " .. detail)
        print("[BCR] [Tests] FAIL: [" .. currentSuite .. "] " .. detail)
    end
end

local function assertFalse(cond, msg)
    assertTrue(not cond, msg)
end

local function assertEqual(expected, actual, msg)
    if expected == actual then
        passed = passed + 1
        print("[BCR] [Tests] PASS: " .. (msg or "assertEqual"))
        return
    end
    failed = failed + 1
    local detail = (msg or "assertEqual failed")
        .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
    table.insert(failures, "[" .. currentSuite .. "] " .. detail)
    print("[BCR] [Tests] FAIL: [" .. currentSuite .. "] " .. detail)
end

local function assertNotNil(value, msg)
    if value ~= nil then
        passed = passed + 1
        print("[BCR] [Tests] PASS: " .. (msg or "assertNotNil"))
    else
        failed = failed + 1
        local detail = msg or "expected non-nil, got nil"
        table.insert(failures, "[" .. currentSuite .. "] " .. detail)
        print("[BCR] [Tests] FAIL: [" .. currentSuite .. "] " .. detail)
    end
end

local function assertNotEqual(expected, actual, msg)
    if expected ~= actual then
        passed = passed + 1
        print("[BCR] [Tests] PASS: " .. (msg or "assertNotEqual"))
    else
        failed = failed + 1
        local detail = msg or "values should differ"
        table.insert(failures, "[" .. currentSuite .. "] " .. detail)
        print("[BCR] [Tests] FAIL: [" .. currentSuite .. "] " .. detail)
    end
end

local function assertType(expectedType, value, msg)
    if type(value) == expectedType then
        passed = passed + 1
        print("[BCR] [Tests] PASS: " .. (msg or "type check"))
    else
        failed = failed + 1
        local detail = (msg or "type check failed")
            .. " (expected " .. expectedType .. ", got " .. type(value) .. ")"
        table.insert(failures, "[" .. currentSuite .. "] " .. detail)
        print("[BCR] [Tests] FAIL: [" .. currentSuite .. "] " .. detail)
    end
end

local function skipSuite(reason)
    skipped = skipped + 1
    print("[BCR] [Tests] SKIP: " .. reason)
end

local function runSuite(name, fn)
    suiteIndex = suiteIndex + 1
    currentSuite = name
    print(string.format("[BCR] [Tests] === SUITE %d/%d: %s ===", suiteIndex, suiteTotal, name))
    local ok, err = pcall(fn)
    if not ok then
        print("[BCR] [Tests] *** SUITE CRASH [" .. name .. "]: " .. tostring(err))
        table.insert(failures, "[" .. name .. "] SUITE CRASH: " .. tostring(err))
        failed = failed + 1
    end
end

local function getPlayerForTests()
    local player = getSpecificPlayer(0)
    if not player then return nil end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or not modData then return nil end
    return player
end

local function hasPlayer()
    return getPlayerForTests() ~= nil
end

-- ============================================================
-- SUITE 1: TRAIT REGISTRY
-- ============================================================

local function suiteTraitRegistry()
    local allTraitIds = {}
    for _, entry in ipairs(BCR.PositiveTraits) do table.insert(allTraitIds, entry.id) end
    for _, entry in ipairs(BCR.NegativeTraits) do table.insert(allTraitIds, entry.id) end
    assertEqual(43, #allTraitIds, "Total trait count should be 43")

    local unresolved = {}
    for _, traitId in ipairs(allTraitIds) do
        if not BCR.GetTraitUserdata(traitId) then
            table.insert(unresolved, traitId)
        end
    end
    assertEqual(0, #unresolved, "All 43 traits resolve to userdata (missing: " .. table.concat(unresolved, ", ") .. ")")

    local cacheMisses = {}
    for _, traitId in ipairs(allTraitIds) do
        local a = BCR.GetTraitUserdata(traitId)
        local b = BCR.GetTraitUserdata(traitId)
        if a == nil or a ~= b then
            table.insert(cacheMisses, traitId)
        end
    end
    assertEqual(0, #cacheMisses, "Cache returns the same object (mismatches: " .. table.concat(cacheMisses, ", ") .. ")")

    local unknown = BCR.GetTraitUserdata("FAKE_TRAIT_XYZ")
    assertTrue(unknown == nil or unknown == false, "GetTraitUserdata(unknown id) -> nil/false")

    assertTrue(BCR.GetTraitUserdata(nil) == nil or BCR.GetTraitUserdata(nil) == false,
        "GetTraitUserdata(nil) -> nil/false")
    assertTrue(BCR.GetTraitUserdata("") == nil or BCR.GetTraitUserdata("") == false,
        "GetTraitUserdata(empty string) -> nil/false")

    -- Cost normalization used by addon registration
    local fixedCost, repairNote = BCR.NormalizeTraitCost("base:Brave", nil, true)
    assertTrue(fixedCost ~= nil and fixedCost < 0,
        "Missing cost filled from the engine, positive list (base:Brave -> " .. tostring(fixedCost) .. ")")
    assertEqual("engine", repairNote, "Engine repair is reported")
    fixedCost, repairNote = BCR.NormalizeTraitCost("base:Brave", 3, true)
    assertEqual(-3, fixedCost, "Wrong sign flipped for the positive list")
    assertEqual("sign", repairNote, "Sign repair is reported")
    fixedCost, repairNote = BCR.NormalizeTraitCost("base:AllThumbs", 2, false)
    assertEqual(2, fixedCost, "Correct sign kept for the negative list")
    assertEqual(nil, repairNote, "No repair note when the cost is fine")
    fixedCost, repairNote = BCR.NormalizeTraitCost("FAKE_TRAIT_XYZ", nil, true)
    assertEqual(nil, fixedCost, "Unknown trait without cost returns nil")

    -- Live engine registry must be readable and non-empty
    local dumpOk, dumpRows = pcall(BCR.DumpEngineTraits, true)
    local dumpCount = (dumpOk and type(dumpRows) == "table") and #dumpRows or 0
    assertTrue(dumpCount > 0, "Engine trait registry readable (got " .. tostring(dumpCount) .. " definitions)")
end

-- ============================================================
-- SUITE 2: RARITY & WEIGHT
-- ============================================================

local function suiteRarityWeight()
    assertEqual("common",   BCR.GetRarity(0),  "Cost 0 is common")
    assertEqual("common",   BCR.GetRarity(1),  "Cost 1 is common")
    assertEqual("common",   BCR.GetRarity(2),  "Boundary: 2 = common")
    assertEqual("uncommon", BCR.GetRarity(3),  "Boundary: 3 = uncommon")
    assertEqual("uncommon", BCR.GetRarity(4),  "Boundary: 4 = uncommon")
    assertEqual("rare",     BCR.GetRarity(5),  "Boundary: 5 = rare")
    assertEqual("rare",     BCR.GetRarity(6),  "Boundary: 6 = rare")
    assertEqual("veryRare", BCR.GetRarity(7),  "Boundary: 7 = veryRare")
    assertEqual("veryRare", BCR.GetRarity(99), "Cost 99 caps at veryRare")

    assertEqual(BCR.GetRarity(4), BCR.GetRarity(-4), "Abs cost 4 same tier")
    assertEqual(BCR.GetRarity(6), BCR.GetRarity(-6), "Abs cost 6 same tier")
    assertEqual(BCR.GetRarity(8), BCR.GetRarity(-8), "Abs cost 8 same tier")

    local w1 = BCR.CalculateWeight(1)
    local w4 = BCR.CalculateWeight(4)
    local w8 = BCR.CalculateWeight(8)
    assertTrue(w1 > w4, "Cost 1 weight > cost 4 weight")
    assertTrue(w4 > w8, "Cost 4 weight > cost 8 weight")
    assertEqual(BCR.MAX_WEIGHT_COST, w1, "Cost 1 = MAX_WEIGHT_COST")
    assertEqual(1, w8, "Cost 8 = 1")

    for _, c in ipairs({1, 2, 3, 4, 5, 6, 7, 8}) do
        assertEqual(BCR.CalculateWeight(c), BCR.CalculateWeight(-c),
            "Weight symmetric for cost +/-" .. c)
    end

    local cc = BCR.GetRarityColor(1)
    assertEqual(0.80, cc[1], "Common R=0.80")
    assertEqual(0.80, cc[2], "Common G=0.80")
    assertEqual(0.80, cc[3], "Common B=0.80")

    local rc = BCR.GetRarityColor(6)
    assertEqual(1.00, rc[1], "Rare R=1.00")
    assertEqual(0.60, rc[2], "Rare G=0.60")
    assertEqual(0.20, rc[3], "Rare B=0.20")

    local vc = BCR.GetRarityColor(10)
    assertEqual(0.80, vc[1], "VeryRare R=0.80")
    assertEqual(0.30, vc[2], "VeryRare G=0.30")
    assertEqual(1.00, vc[3], "VeryRare B=1.00")
end

-- ============================================================
-- SUITE 3: MUTUAL EXCLUSION
-- ============================================================

local function suiteMutualExclusion()
    local missingReverse, oneWay, selfExcluded, duplicates = {}, {}, {}, {}
    for traitA, excludedList in pairs(BCR.Exclusions) do
        local seen = {}
        for _, traitB in ipairs(excludedList) do
            if seen[traitB] then table.insert(duplicates, traitA .. " -> " .. traitB) end
            seen[traitB] = true
            if traitA == traitB then table.insert(selfExcluded, traitA) end
            local reverseExclusions = BCR.Exclusions[traitB]
            if reverseExclusions == nil then
                table.insert(missingReverse, traitA .. " -> " .. traitB)
            else
                local found = false
                for _, excludedId in ipairs(reverseExclusions) do
                    if excludedId == traitA then found = true; break end
                end
                if not found then table.insert(oneWay, traitA .. " -> " .. traitB) end
            end
        end
    end
    assertEqual(0, #missingReverse, "Exclusions declared on both traits (missing: " .. table.concat(missingReverse, ", ") .. ")")
    assertEqual(0, #oneWay, "Exclusions are mutual (one-way: " .. table.concat(oneWay, ", ") .. ")")
    assertEqual(0, #selfExcluded, "No trait excludes itself (" .. table.concat(selfExcluded, ", ") .. ")")
    assertEqual(0, #duplicates, "No duplicate exclusion entries (" .. table.concat(duplicates, ", ") .. ")")

    local allIds = {}
    for _, e in ipairs(BCR.PositiveTraits) do allIds[e.id] = true end
    for _, e in ipairs(BCR.NegativeTraits) do allIds[e.id] = true end
    if BCR.CustomPositiveTraits then
        for _, e in ipairs(BCR.CustomPositiveTraits) do allIds[e.id] = true end
    end
    if BCR.CustomNegativeTraits then
        for _, e in ipairs(BCR.CustomNegativeTraits) do allIds[e.id] = true end
    end
    local unknownTargets = {}
    for _, excludedList in pairs(BCR.Exclusions) do
        for _, excludedId in ipairs(excludedList) do
            if not allIds[excludedId] then table.insert(unknownTargets, excludedId) end
        end
    end
    assertEqual(0, #unknownTargets, "Exclusion targets are real traits (" .. table.concat(unknownTargets, ", ") .. ")")
end

-- ============================================================
-- SUITE 4: WEIGHTED SELECTION
-- ============================================================

local function suiteWeightedSelection()
    assertTrue(BCR.WeightedRandomSelect(nil) == nil, "WeightedRandomSelect(nil) -> nil")
    assertTrue(BCR.WeightedRandomSelect({}) == nil, "WeightedRandomSelect(empty table) -> nil")

    local single = { id = "ONLY", traitUserdata = nil, cost = 1, rarity = "common", weight = 1 }
    local singleOk = true
    for _ = 1, 5 do
        local sel = BCR.WeightedRandomSelect({ single })
        if not sel or sel.id ~= single.id then singleOk = false; break end
    end
    assertTrue(singleOk, "Single-entry pool always returns its only entry (5 draws)")

    local light = { id = "LIGHT", weight = 9 }
    local heavy = { id = "HEAVY", weight = 1 }
    local pool = { light, heavy }
    local counts = { LIGHT = 0, HEAVY = 0 }
    local allValid = true
    for _ = 1, 200 do
        local result = BCR.WeightedRandomSelect(pool)
        if not result then allValid = false; break end
        counts[result.id] = (counts[result.id] or 0) + 1
    end
    assertTrue(allValid, "All 200 weighted draws returned an entry")
    assertTrue(counts.LIGHT > counts.HEAVY,
        "Higher weight selected more (L=" .. counts.LIGHT .. " H=" .. counts.HEAVY .. ")")
    assertTrue(counts.HEAVY > 0, "Lower weight appears at least once in 200 trials")

    local zeroValid = true
    for _ = 1, 10 do
        local sel = BCR.WeightedRandomSelect({ { id = "A", weight = 0 }, { id = "B", weight = 0 } })
        if not sel or (sel.id ~= "A" and sel.id ~= "B") then zeroValid = false; break end
    end
    assertTrue(zeroValid, "Zero-weight pool falls back to a valid entry (10 draws)")

    local sel = BCR.WeightedRandomSelect({ { id = "ZERO", weight = 0 } })
    assertNotNil(sel, "Single zero-weight -> fallback")
    assertEqual("ZERO", sel.id, "Single zero-weight returns ZERO")

    -- Engine RNG sanity: ZombRand(n) must be an integer in [0, n-1]
    local badRoll = nil
    for _ = 1, 1000 do
        local r = ZombRand(5)
        if type(r) ~= "number" or r ~= math.floor(r) or r < 0 or r > 4 then
            badRoll = tostring(r)
            break
        end
    end
    assertTrue(badRoll == nil, "ZombRand(5) always integer 0..4 (got " .. tostring(badRoll) .. ")")

    -- ZombRand(2) coin must be ~50/50 (10k flips; +-5% is >10 sigma)
    local flips = 10000
    local ones = 0
    for _ = 1, flips do
        if ZombRand(2) == 1 then ones = ones + 1 end
    end
    local onesRatio = ones / flips
    assertTrue(onesRatio > 0.45 and onesRatio < 0.55,
        string.format("ZombRand(2) balanced: %d/%d (ratio %.3f)", ones, flips, onesRatio))

    -- Weighted pool 1:3 over 5k draws must honor the ratio (~25%)
    local ratioPool = { { id = "LOW", weight = 1 }, { id = "HIGH", weight = 3 } }
    local draws = 5000
    local lowCount = 0
    for _ = 1, draws do
        local pick = BCR.WeightedRandomSelect(ratioPool)
        if pick and pick.id == "LOW" then lowCount = lowCount + 1 end
    end
    local lowRatio = lowCount / draws
    assertTrue(lowRatio > 0.20 and lowRatio < 0.30,
        string.format("Weight 1:3 ratio honored: LOW %d/%d (ratio %.3f)", lowCount, draws, lowRatio))
end

-- ============================================================
-- SUITE 5: DISPLAY NAMES
-- ============================================================

local function suiteDisplayNames()
    local overrides = { "base:NeedsLessSleep", "base:NeedsMoreSleep", "base:Dextrous" }
    for _, tid in ipairs(overrides) do
        local name = BCR.GetTraitDisplayName(tid)
        assertTrue(name ~= nil and #name > 0 and name ~= tid and not string.find(name, "_"),
            tid .. " override name is translated (" .. tostring(name) .. ")")
    end

    local allIds = {}
    for _, e in ipairs(BCR.PositiveTraits) do table.insert(allIds, e.id) end
    for _, e in ipairs(BCR.NegativeTraits) do table.insert(allIds, e.id) end
    local badNames = {}
    for _, tid in ipairs(allIds) do
        local name = BCR.GetTraitDisplayName(tid)
        if name == nil or #name == 0 or name == tid then
            table.insert(badNames, tid)
        end
    end
    assertEqual(0, #badNames, "All traits have display names (bad: " .. table.concat(badNames, ", ") .. ")")

    assertEqual("Unknown", BCR.GetTraitDisplayName(nil), "GetTraitDisplayName(nil) -> 'Unknown'")
    assertEqual("Unknown", BCR.GetTraitDisplayName(""), "GetTraitDisplayName(empty string) -> 'Unknown'")

    local sd = BCR.GetTraitDisplayName("base:SpeedDemon")
    assertTrue(#sd > 0 and not string.find(sd, "base:SpeedDemon"),
        "base:SpeedDemon display is translated, not raw ID: " .. sd)
end

-- ============================================================
-- SUITE 6: DATA INTEGRITY
-- ============================================================

local function suiteDataIntegrity()
    local posCount, negCount = 0, 0
    for _ in ipairs(BCR.PositiveTraits) do posCount = posCount + 1 end
    for _ in ipairs(BCR.NegativeTraits) do negCount = negCount + 1 end
    assertEqual(21, posCount, "21 positive traits")
    assertEqual(22, negCount, "22 negative traits")

    local seen, duplicates = {}, {}
    for _, e in ipairs(BCR.PositiveTraits) do
        if seen[e.id] then table.insert(duplicates, e.id) end
        seen[e.id] = true
    end
    seen = {}
    for _, e in ipairs(BCR.NegativeTraits) do
        if seen[e.id] then table.insert(duplicates, e.id) end
        seen[e.id] = true
    end
    assertEqual(0, #duplicates, "No duplicate trait ids (" .. table.concat(duplicates, ", ") .. ")")

    local negIds, bothLists = {}, {}
    for _, e in ipairs(BCR.NegativeTraits) do negIds[e.id] = true end
    for _, e in ipairs(BCR.PositiveTraits) do
        if negIds[e.id] then table.insert(bothLists, e.id) end
    end
    assertEqual(0, #bothLists, "No trait in both lists (" .. table.concat(bothLists, ", ") .. ")")

    local badCost = {}
    for _, e in ipairs(BCR.PositiveTraits) do
        if not (e.cost < 0) then table.insert(badCost, e.id .. "=" .. tostring(e.cost)) end
    end
    for _, e in ipairs(BCR.NegativeTraits) do
        if not (e.cost > 0) then table.insert(badCost, e.id .. "=" .. tostring(e.cost)) end
    end
    assertEqual(0, #badCost, "Positive costs negative, negative costs positive (" .. table.concat(badCost, ", ") .. ")")

    assertFalse(BCR.HasAvailableRewards(nil), "HasAvailableRewards(nil player) -> false")
    assertTrue(BCR.EnsureModData(nil) == nil, "EnsureModData(nil player) -> nil")
    assertTrue(BCR.PlayerHasTrait(nil, "base:SpeedDemon") == nil, "PlayerHasTrait(nil player) -> nil")

    -- Exclusions count check (informational, won't fail on count mismatch unless it's 0)
    local exCount = 0
    for _ in pairs(BCR.Exclusions) do exCount = exCount + 1 end
    assertTrue(exCount > 0, "Exclusions must have entries")
end

-- ============================================================
-- SUITE 7: CONFIG & DEBUG
-- ============================================================

local function suiteConfigDebug()
    assertEqual(1, BCR.PRIORITY_POSITIVE_FIRST, "PRIORITY_POSITIVE_FIRST is 1")
    assertEqual(2, BCR.PRIORITY_NEGATIVE_FIRST, "PRIORITY_NEGATIVE_FIRST is 2")
    assertEqual(3, BCR.PRIORITY_RANDOM, "PRIORITY_RANDOM is 3")
    assertEqual("BCR", BCR.MODULE_NAME, "Event module name is BCR")
    assertEqual(8, BCR.MAX_NOTIFICATION_QUEUE, "Notification queue cap is 8")
    assertEqual("boolean", type(BCR.DEBUG), "BCR.DEBUG is boolean")

    local oldOpts = BCR.opts
    BCR.RefreshConfig()
    assertNotNil(BCR.opts, "opts set after RefreshConfig")
    local requiredFields = {
        "bodyCount", "enablePositive", "enableNegative", "rewardPriority",
        "grantMissedOpportunities", "milestoneScaling", "progressiveScalingFactor"
    }
    for _, f in ipairs(requiredFields) do
        assertNotNil(BCR.opts[f], "opts." .. f .. " must exist")
    end
    assertTrue(BCR.opts.bodyCount > 0, "BodyCount > 0")
    assertTrue(BCR.opts.bodyCount <= 10000, "BodyCount <= 10000")
    assertType("boolean", BCR.opts.enablePositive, "enablePositive bool")
    assertType("boolean", BCR.opts.enableNegative, "enableNegative bool")
    assertType("boolean", BCR.opts.grantMissedOpportunities, "grantMissed bool")
    assertType("number", BCR.opts.progressiveScalingFactor, "PSF number")
    if oldOpts then BCR.opts = oldOpts end

    -- DebugPrint must not crash with any input type
    local oldDebug = BCR.DEBUG
    BCR.DEBUG = false
    BCR.DebugPrint("hello")
    BCR.DebugPrint(42)
    BCR.DebugPrint(nil)
    BCR.DebugPrint({ a = 1 })
    BCR.DEBUG = true
    BCR.DebugPrint("with debug on")
    BCR.DebugPrint(nil)
    BCR.DEBUG = oldDebug

    assertType("boolean", BCR.IsTraitAllowed("base:SpeedDemon"), "IsTraitAllowed returns bool")
    -- Bogus ID should still return a boolean (nil SandboxVars means default true)
    local bogus = BCR.IsTraitAllowed("NOT_A_REAL_TRAIT_12345")
    assertTrue(bogus == true or bogus == false, "IsTraitAllowed returns bool for bogus")
end

-- ============================================================
-- SUITE 8: FILTER POOL
-- ============================================================

local function suiteFilterPool()
    assertNotNil(BCR.FilterPoolByExclusion(nil, {}), "FilterPoolByExclusion(nil, {}) -> empty table")
    assertNotNil(BCR.FilterPoolByExclusion(nil, nil), "FilterPoolByExclusion(nil, nil) -> empty table")

    local pool = {
        { id = "A", traitUserdata = nil, cost = 1, rarity = "common", weight = 1 },
        { id = "B", traitUserdata = nil, cost = 2, rarity = "common", weight = 2 },
        { id = "C", traitUserdata = nil, cost = 3, rarity = "uncommon", weight = 1 },
    }
    assertEqual(3, #BCR.FilterPoolByExclusion(pool, nil), "Nil exclude -> full pool")
    assertEqual(3, #BCR.FilterPoolByExclusion(pool, {}), "Empty exclude -> full pool")

    local f1 = BCR.FilterPoolByExclusion(pool, { A = true })
    assertEqual(2, #f1, "Exclude A -> 2 entries")
    for _, e in ipairs(f1) do assertNotEqual("A", e.id, "Excluded A absent from result") end

    local f2 = BCR.FilterPoolByExclusion(pool, { A = true, C = true })
    assertEqual(1, #f2, "Exclude A+C -> 1 entry")
    assertEqual("B", f2[1].id, "Exclude A+C leaves only B")

    assertEqual(0, #BCR.FilterPoolByExclusion(pool, { A = true, B = true, C = true }),
        "All excluded -> empty")

    assertEqual(3, #BCR.FilterPoolByExclusion(pool, { Z = true }),
        "Exclude nonexistent Z -> unchanged")

    -- FilterPoolByExclusion checks excludeSet[id] == nil (excluded if key present, regardless of value)
    local f3 = BCR.FilterPoolByExclusion(pool, { A = false, B = true })
    assertEqual(1, #f3, "Falsy A still excluded (key presence matters)")
end

-- ============================================================
-- SUITE 9: MILESTONE MATH
-- ============================================================

local function suiteMilestoneMath()
    local linear = { bodyCount = 1000, milestoneScaling = 1, progressiveScalingFactor = 0.5 }
    assertEqual(1000, BCR.GetKillsForMilestone(1, linear), "Linear milestone 1")
    assertEqual(2000, BCR.GetKillsForMilestone(2, linear), "Linear milestone 2")
    assertEqual(5000, BCR.GetKillsForMilestone(5, linear), "Linear milestone 5")

    -- Round-trip invariant
    local rtFail = {}
    for n = 1, 10 do
        local kills = BCR.GetKillsForMilestone(n, linear)
        if BCR.GetMilestonesAtKills(kills, linear) < n then table.insert(rtFail, n) end
    end
    assertEqual(0, #rtFail, "Linear round-trip holds (bad n: " .. table.concat(rtFail, ", ") .. ")")

    assertEqual(0, BCR.GetMilestonesAtKills(999, linear), "999 kills -> 0 milestones")
    assertEqual(1, BCR.GetMilestonesAtKills(1000, linear), "1000 kills -> 1 milestone")
    assertEqual(1, BCR.GetMilestonesAtKills(1999, linear), "1999 kills -> 1 milestone")
    assertEqual(2, BCR.GetMilestonesAtKills(2000, linear), "2000 kills -> 2 milestones")

    assertEqual(0, BCR.GetKillsForMilestone(0, linear), "Milestone 0 -> 0 kills")
    assertEqual(0, BCR.GetKillsForMilestone(-5, linear), "Negative milestone -> 0 kills")
    assertEqual(0, BCR.GetMilestonesAtKills(0, linear), "0 kills -> 0 milestones")
    assertEqual(0, BCR.GetMilestonesAtKills(-100, linear), "Negative kills -> 0 milestones")

    local zeroBC = { bodyCount = 0, milestoneScaling = 1 }
    assertEqual(0, BCR.GetKillsForMilestone(1, zeroBC), "BodyCount 0 -> 0 kills")
    assertEqual(0, BCR.GetMilestonesAtKills(5000, zeroBC), "BodyCount 0 -> 0 milestones")

    local progZero = { bodyCount = 1000, milestoneScaling = 2, progressiveScalingFactor = 0 }
    assertEqual(BCR.GetKillsForMilestone(3, linear), BCR.GetKillsForMilestone(3, progZero),
        "Factor 0 progressive = linear")

    local prog = { bodyCount = 1000, milestoneScaling = 2, progressiveScalingFactor = 0.5 }
    assertEqual(1000, BCR.GetKillsForMilestone(1, prog), "Progressive milestone 1")
    assertEqual(2500, BCR.GetKillsForMilestone(2, prog), "Progressive milestone 2")
    assertEqual(4500, BCR.GetKillsForMilestone(3, prog), "Progressive milestone 3")
    assertEqual(7000, BCR.GetKillsForMilestone(4, prog), "Progressive milestone 4")

    local monotonic = true
    local prev = 0
    for n = 1, 5 do
        local cur = BCR.GetKillsForMilestone(n, prog)
        if cur <= prev then monotonic = false; break end
        prev = cur
    end
    assertTrue(monotonic, "Progressive milestones strictly increase")

    local progRtFail = {}
    for n = 1, 8 do
        local kills = BCR.GetKillsForMilestone(n, prog)
        if BCR.GetMilestonesAtKills(kills, prog) < n then table.insert(progRtFail, n) end
    end
    assertEqual(0, #progRtFail, "Progressive round-trip holds (bad n: " .. table.concat(progRtFail, ", ") .. ")")

    -- GetMissedMilestoneCount boundaries and clamping
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 3 }, 3999, linear),
        "No missed milestones below the next threshold")
    assertEqual(1, BCR.GetMissedMilestoneCount({ rewardsGiven = 3 }, 4000, linear),
        "One missed milestone when one is unclaimed")
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 5 }, 3000, linear),
        "Never negative when rewardsGiven exceeds milestones")
    assertEqual(0, BCR.GetMissedMilestoneCount(nil, 5000, linear),
        "Nil ModData -> 0")
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 0 }, 5000, nil),
        "Nil opts -> 0")

    -- Withheld milestones (retroactive rewards baseline)
    local offOpts = { bodyCount = 1000, milestoneScaling = 1, grantMissedOpportunities = false }
    local onOpts = { bodyCount = 1000, milestoneScaling = 1, grantMissedOpportunities = true }
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 0, withheldMilestones = 5 }, 5500, offOpts),
        "Withheld backlog is not owed while the option is off")
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 1, withheldMilestones = 5 }, 6500, offOpts),
        "Grants earned while off leave the withheld pool intact")
    assertEqual(1, BCR.GetMissedMilestoneCount({ rewardsGiven = 1, withheldMilestones = 5 }, 7000, offOpts),
        "The next crossing is owed while the option is off")
    assertEqual(5, BCR.GetMissedMilestoneCount({ rewardsGiven = 2, withheldMilestones = 5 }, 7000, onOpts),
        "Switching the option on releases the withheld milestones")
    assertEqual(0, BCR.GetMissedMilestoneCount({ rewardsGiven = 0, withheldMilestones = 99 }, 1000, offOpts),
        "Withheld never makes the count negative")

    assertEqual(7, BCR.GetAnsweredMilestones({ rewardsGiven = 2, withheldMilestones = 5 }),
        "Answered = granted + withheld")
    assertEqual(3, BCR.GetAnsweredMilestones({ rewardsGiven = 3 }),
        "Answered handles a missing withheld field")
    assertEqual(0, BCR.GetAnsweredMilestones(nil), "Answered(nil) -> 0")

    local fakeData = { rewardsGiven = 0, withheldMilestones = 3 }
    BCR.ConsumeWithheldMilestones(fakeData, 2, onOpts)
    assertEqual(1, fakeData.withheldMilestones, "Grants while on consume withheld milestones")
    BCR.ConsumeWithheldMilestones(fakeData, 5, onOpts)
    assertEqual(0, fakeData.withheldMilestones, "Withheld consumption clamps at zero")
    fakeData.withheldMilestones = 2
    BCR.ConsumeWithheldMilestones(fakeData, 1, offOpts)
    assertEqual(2, fakeData.withheldMilestones, "Grants while off do not consume the pool")
end

-- ============================================================
-- SUITE 10: ADD / REMOVE (needs player)
-- ============================================================

local function suiteAddRemove()
    if isClient() or isServer() then
        skipSuite("Needs SP mode (neither client nor server flag set)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    local speedEntry = { id = "base:NightVision", cost = -3 }
    local hadSpeed = BCR.PlayerHasTrait(player, "base:NightVision")
    BCR.RemoveTrait(player, speedEntry)

    assertTrue(BCR.AddTrait(player, speedEntry), "Add base:NightVision")
    assertFalse(BCR.AddTrait(player, speedEntry), "Duplicate add fails")
    assertTrue(BCR.RemoveTrait(player, speedEntry), "Remove base:NightVision")
    assertFalse(BCR.RemoveTrait(player, speedEntry), "Remove absent fails")

    assertFalse(BCR.AddTrait(nil, speedEntry), "AddTrait(nil player) -> false")
    assertFalse(BCR.RemoveTrait(nil, speedEntry), "RemoveTrait(nil player) -> false")
    assertFalse(BCR.AddTrait(player, nil), "AddTrait(nil entry) -> false")
    assertFalse(BCR.RemoveTrait(player, nil), "RemoveTrait(nil entry) -> false")

    -- Entry with no .id field
    assertFalse(BCR.AddTrait(player, { cost = -1 }), "AddTrait(entry without id) -> false")
    assertFalse(BCR.RemoveTrait(player, { cost = 2 }), "RemoveTrait(entry without id) -> false")

    -- Bogus trait ID (won't resolve to userdata)
    assertFalse(BCR.AddTrait(player, { id = "NOT_A_REAL_TRAIT" }),
        "Bogus ID -> add fails")
    assertFalse(BCR.RemoveTrait(player, { id = "NOT_A_REAL_TRAIT" }),
        "Bogus ID -> remove fails")

    assertTrue(BCR.AddTrait(player, { id = "base:NightVision" }),
        "Re-add after remove-absent cycle should succeed")

    -- Restore original trait state
    BCR.RemoveTrait(player, speedEntry)
    if hadSpeed ~= false then
        assertTrue(BCR.AddTrait(player, speedEntry), "Restore base:NightVision after suite")
    end
end

-- ============================================================
-- SUITE 11: EXCLUSIONS (needs player)
-- ============================================================

local function suiteExclusions()
    if isClient() or isServer() then
        skipSuite("Needs SP mode (neither client nor server flag set)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    local adrEntry = { id = "base:AdrenalineJunkie", cost = -4 }
    local agoEntry = { id = "base:Agoraphobic", cost = 4 }
    local braveEntry = { id = "base:Brave", cost = -4 }
    local frEntry = { id = "base:FastReader", cost = -2 }
    local srEntry = { id = "base:SlowReader", cost = 2 }
    local illEntry = { id = "base:Illiterate", cost = 10 }

    local hadAdr = BCR.PlayerHasTrait(player, "base:AdrenalineJunkie")
    local hadAgo = BCR.PlayerHasTrait(player, "base:Agoraphobic")
    local hadBrave = BCR.PlayerHasTrait(player, "base:Brave")
    local hadFr = BCR.PlayerHasTrait(player, "base:FastReader")
    local hadSr = BCR.PlayerHasTrait(player, "base:SlowReader")
    local hadIll = BCR.PlayerHasTrait(player, "base:Illiterate")

    BCR.RemoveTrait(player, adrEntry)
    BCR.RemoveTrait(player, agoEntry)

    assertTrue(BCR.AddTrait(player, adrEntry), "Add base:AdrenalineJunkie")
    assertFalse(BCR.AddTrait(player, agoEntry), "base:Agoraphobic blocked")

    local blocked, blocker = BCR.HasMutuallyExclusiveTrait(player, "base:Agoraphobic")
    assertTrue(blocked, "base:Agoraphobic is blocked")
    assertEqual("base:AdrenalineJunkie", blocker, "Blocker is base:AdrenalineJunkie")

    -- Non-excluded trait
    assertFalse(BCR.HasMutuallyExclusiveTrait(player, "base:Smoker"), "base:Smoker not blocked")

    -- Nil player
    assertFalse(BCR.HasMutuallyExclusiveTrait(nil, "base:SpeedDemon"), "HasMutuallyExclusiveTrait(nil player) -> false")

    -- Nonexistent trait
    assertFalse(BCR.HasMutuallyExclusiveTrait(player, "FAKETRAIT_XYZ"),
        "Nonexistent trait FAKETRAIT_XYZ -> false")

    BCR.RemoveTrait(player, adrEntry)
    BCR.RemoveTrait(player, braveEntry)
    assertTrue(BCR.AddTrait(player, agoEntry), "base:Agoraphobic addable after removal")
    assertFalse(BCR.AddTrait(player, adrEntry), "base:AdrenalineJunkie blocked by base:Agoraphobic (symmetry)")

    BCR.RemoveTrait(player, agoEntry)
    BCR.RemoveTrait(player, adrEntry)

    -- 3-way: base:FastReader
    BCR.RemoveTrait(player, frEntry)
    BCR.RemoveTrait(player, srEntry)
    BCR.RemoveTrait(player, illEntry)

    assertTrue(BCR.AddTrait(player, frEntry), "Add base:FastReader")
    assertFalse(BCR.AddTrait(player, srEntry), "base:SlowReader blocked")
    assertFalse(BCR.AddTrait(player, illEntry), "base:Illiterate blocked")

    -- Restore original trait state for every trait this suite touched
    BCR.RemoveTrait(player, adrEntry)
    BCR.RemoveTrait(player, agoEntry)
    BCR.RemoveTrait(player, braveEntry)
    BCR.RemoveTrait(player, frEntry)
    BCR.RemoveTrait(player, srEntry)
    BCR.RemoveTrait(player, illEntry)
    if hadAdr ~= false then assertTrue(BCR.AddTrait(player, adrEntry), "Restore base:AdrenalineJunkie") end
    if hadAgo ~= false then assertTrue(BCR.AddTrait(player, agoEntry), "Restore base:Agoraphobic") end
    if hadBrave ~= false then assertTrue(BCR.AddTrait(player, braveEntry), "Restore base:Brave") end
    if hadFr ~= false then assertTrue(BCR.AddTrait(player, frEntry), "Restore base:FastReader") end
    if hadSr ~= false then assertTrue(BCR.AddTrait(player, srEntry), "Restore base:SlowReader") end
    if hadIll ~= false then assertTrue(BCR.AddTrait(player, illEntry), "Restore base:Illiterate") end
end

-- ============================================================
-- SUITE 12: POOL BUILDING & PLAYER STATE (needs player)
-- ============================================================

local function suitePoolBuildingPlayerState()
    if isClient() or isServer() then
        skipSuite("Needs SP mode (neither client nor server flag set)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    -- === BuildEarnablePool ===
    assertTrue(BCR.BuildEarnablePool(nil) == nil, "BuildEarnablePool(nil) -> nil")
    assertTrue(BCR.BuildRemovablePool(nil) == nil, "BuildRemovablePool(nil) -> nil")

    local earnable = BCR.BuildEarnablePool(player)
    assertNotNil(earnable, "Earnable pool not nil")
    local eCount = 0
    for _ in ipairs(earnable) do eCount = eCount + 1 end
    assertTrue(eCount > 0, "Earnable pool has entries (" .. eCount .. ")")

    local badEarnable = {}
    for _, entry in ipairs(earnable) do
        if type(entry.id) ~= "string" or entry.traitUserdata == nil
            or type(entry.cost) ~= "number" or not (entry.cost < 0)
            or entry.rarity == nil or type(entry.weight) ~= "number" or entry.weight < 1 then
            table.insert(badEarnable, tostring(entry.id))
        end
    end
    assertEqual(0, #badEarnable, "Earnable entries well-formed (" .. table.concat(badEarnable, ", ") .. ")")

    -- === BuildRemovablePool ===
    local removable = BCR.BuildRemovablePool(player)
    assertNotNil(removable, "Removable pool not nil")
    local badRemovable = {}
    for _, entry in ipairs(removable) do
        if not (entry.cost > 0) or BCR.PlayerHasTrait(player, entry.id) ~= true then
            table.insert(badRemovable, tostring(entry.id))
        end
    end
    assertEqual(0, #badRemovable, "Removable entries owned with positive cost (" .. table.concat(badRemovable, ", ") .. ")")

    -- === Custom traits merge ===
    local custom = { { id = "base:Hemophobic", cost = -3 } }
    local e1 = BCR.BuildEarnablePool(player)
    local e2 = BCR.BuildEarnablePool(player, custom)
    local hasHemophobic = BCR.PlayerHasTrait(player, "base:Hemophobic")
    if hasHemophobic == true then
        assertEqual(#e1, #e2, "Custom already-owned trait excluded")
    else
        assertTrue(#e2 > #e1, "Custom trait adds entries (" .. #e2 .. " vs " .. #e1 .. ")")
    end

    local e3 = BCR.BuildEarnablePool(player, {})
    assertEqual(#e1, #e3, "Empty custom = nil custom")

    -- === HasAvailableRewards ===
    local hasAvailable = BCR.HasAvailableRewards(player)
    assertType("boolean", hasAvailable, "HasAvailableRewards returns bool")

    -- === PlayerHasTrait ===
    local hasResult = BCR.PlayerHasTrait(player, "base:SpeedDemon")
    assertTrue(hasResult == true or hasResult == false,
        "PlayerHasTrait returns true or false for valid player+trait, got " .. tostring(hasResult))

    -- === GetPlayerTraitsList ===
    local traitList = BCR.GetPlayerTraitsList(player)
    assertNotNil(traitList, "GetPlayerTraitsList returns table")
    assertType("table", traitList, "GetPlayerTraitsList returns table")
    local listCount = 0
    local nonStringEntries = 0
    for _, tid in ipairs(traitList) do
        if type(tid) ~= "string" then nonStringEntries = nonStringEntries + 1 end
        listCount = listCount + 1
    end
    assertEqual(0, nonStringEntries, "Trait list entries are strings")
    -- Player should have at least their profession traits
    assertTrue(listCount > 0, "Player should have some traits")

    assertTrue(BCR.GetPlayerTraitsList(nil) == nil, "GetPlayerTraitsList(nil player) -> nil")

    -- === EnsureModData ===
    local bcrData = BCR.EnsureModData(player)
    assertNotNil(bcrData, "EnsureModData returns table")
    assertType("table", bcrData, "EnsureModData returns table")
    assertType("number", bcrData.kills, ".kills is number")
    assertType("number", bcrData.rewardsGiven, ".rewardsGiven is number")
    assertType("table", bcrData.traitHistory, ".traitHistory is table")

    -- Repeated calls return same table
    local bcrData2 = BCR.EnsureModData(player)
    assertEqual(bcrData, bcrData2, "Repeated EnsureModData returns same table")

    -- === Regression: EnsureModData repairs corrupt fields ===
    local savedHistory = bcrData.traitHistory
    local savedKills = bcrData.kills
    local savedRewards = bcrData.rewardsGiven

    bcrData.traitHistory = "corrupt"
    local repaired = BCR.EnsureModData(player)
    assertType("table", repaired.traitHistory, "Corrupt traitHistory is replaced with a table")

    bcrData.kills = -5
    bcrData.rewardsGiven = -2
    repaired = BCR.EnsureModData(player)
    assertEqual(0, repaired.kills, "Negative kills are clamped to 0")
    assertEqual(0, repaired.rewardsGiven, "Negative rewardsGiven are clamped to 0")

    bcrData.traitHistory = savedHistory
    bcrData.kills = savedKills
    bcrData.rewardsGiven = savedRewards

    -- === Regression: server kill sync takes the engine value ===
    if BCR.SyncAuthoritativeKills then
        local okKills, engineKills = pcall(function() return player:getZombieKills() end)
        if okKills and type(engineKills) == "number" then
            local savedKills2 = bcrData.kills
            local okSync = pcall(function()
                bcrData.kills = engineKills + 500000
                BCR.SyncAuthoritativeKills(player, bcrData)
            end)
            local syncedKills = bcrData.kills
            bcrData.kills = savedKills2
            assertTrue(okSync, "SyncAuthoritativeKills does not error")
            assertEqual(engineKills, syncedKills,
                "SyncAuthoritativeKills replaces stored kills with the engine value")
        end
    end

    -- === Regression: withheld baseline capture (retroactive rewards) ===
    if BCR.CaptureWithheldBaseline then
        local okK3, engineKills3 = pcall(function() return player:getZombieKills() end)
        if okK3 and type(engineKills3) == "number" then
            local captureOpts = {
                bodyCount = 1000, milestoneScaling = 1,
                progressiveScalingFactor = 0.5, grantMissedOpportunities = false,
            }
            local expected = BCR.GetMilestonesAtKills(engineKills3, captureOpts)
            local savedWithheld = bcrData.withheldMilestones
            local savedRewards2 = bcrData.rewardsGiven

            bcrData.withheldMilestones = nil
            bcrData.rewardsGiven = 0
            local captured = BCR.CaptureWithheldBaseline(player, bcrData, captureOpts)
            local withheld = bcrData.withheldMilestones
            local capturedAgain = BCR.CaptureWithheldBaseline(player, bcrData, captureOpts)

            bcrData.withheldMilestones = nil
            local capturedOnOpts = BCR.CaptureWithheldBaseline(player, bcrData, { grantMissedOpportunities = true })

            bcrData.withheldMilestones = savedWithheld
            bcrData.rewardsGiven = savedRewards2

            assertTrue(captured, "First capture reports a change")
            assertEqual(expected, withheld, "Capture withholds reached-but-ungranted milestones")
            assertFalse(capturedAgain, "Capture is a one-time baseline")
            assertFalse(capturedOnOpts, "No capture while retroactive rewards are on")
        end
    end
end

-- ============================================================
-- SUITE 13: CATCH-UP / PROCESS REWARD (needs player + SP)
-- ============================================================

local function suiteCatchUpProcessReward()
    if isClient() or isServer() then
        skipSuite("Needs SP mode (neither client nor server flag set)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()
    local bcrData = BCR.EnsureModData(player)
    assertNotNil(bcrData, "Should have ModData")

    -- Snapshot live state so this destructive suite can restore it
    local originalKills = bcrData.kills
    local originalRewardsGiven = bcrData.rewardsGiven
    local originalWithheld = bcrData.withheldMilestones
    local historyCopy = {}
    for i, v in pairs(bcrData.traitHistory) do
        historyCopy[i] = v
    end
    local traitsBefore = {}
    local traitList = BCR.GetPlayerTraitsList(player)
    if traitList then
        for _, tid in ipairs(traitList) do
            traitsBefore[tid] = true
        end
    end

    -- Test: ProcessRewardDirect with nil player
    assertTrue(BCR.ProcessRewardDirect(nil) == nil, "ProcessRewardDirect(nil player) -> nil")

    -- Test: ProcessRewardDirect returns nil when no milestone reached
    local opts = BCR.GetOpts()
    bcrData.rewardsGiven = 99
    bcrData.kills = math.max(0, (opts.bodyCount or BCR.DEFAULT_BODY_COUNT) - 1)
    local result = BCR.ProcessRewardDirect(player)
    assertTrue(result == nil,
        "No reward when kills < BodyCount and rewardsGiven already high")

    -- Test: With very high kills and 0 rewards, a reward batch must be granted
    -- while any reward remains available.
    bcrData.rewardsGiven = 0
    bcrData.kills = 50000
    bcrData.withheldMilestones = 0
    local rewardsBefore = BCR.HasAvailableRewards(player)
    result = BCR.ProcessRewardDirect(player)
    local gotBatch = result ~= nil and type(result) == "table" and #result > 0
    assertTrue(gotBatch or not rewardsBefore,
        "Reward batch granted while rewards are available (got " .. tostring(result) .. ")")
    if gotBatch then
        assertTrue(#result <= BCR.MAX_BATCH_REWARDS,
            "Batch honors MAX_BATCH_REWARDS cap (" .. #result .. " <= " .. BCR.MAX_BATCH_REWARDS .. ")")
        local first = result[1]
        assertNotNil(first.id, "Reward result has an id")
        assertNotNil(first.displayName, "Reward result has a display name")
        assertTrue(first.action == "added" or first.action == "removed",
            "Reward result action is added/removed, got " .. tostring(first.action))
        assertNotNil(first.rarity, "Reward result has a rarity")
        assertNotNil(first.color, "Reward result has a color")
        assertEqual(3, #first.color, "Reward result color is {r,g,b}")
        assertNotNil(first.cost, "Reward result has a cost")

        -- Every granted trait is recorded in the history with its action
        local historyOk = true
        for _, granted in ipairs(result) do
            if BCR.GetLastHistoryAction(bcrData.traitHistory, granted.id) ~= granted.action then
                historyOk = false
                break
            end
        end
        assertTrue(historyOk, "Every granted trait is recorded in trait history")
    end

    -- Restore ModData fields
    bcrData.kills = originalKills
    bcrData.rewardsGiven = originalRewardsGiven
    bcrData.withheldMilestones = originalWithheld
    bcrData.traitHistory = historyCopy

    -- Restore trait changes the reward path may have applied
    local traitsAfter = {}
    traitList = BCR.GetPlayerTraitsList(player)
    if traitList then
        for _, tid in ipairs(traitList) do
            traitsAfter[tid] = true
        end
    end
    for tid in pairs(traitsAfter) do
        if not traitsBefore[tid] then
            assertTrue(BCR.RemoveTrait(player, { id = tid }), "Restore: remove test-granted " .. tid)
        end
    end
    for tid in pairs(traitsBefore) do
        if not traitsAfter[tid] then
            assertTrue(BCR.AddTrait(player, { id = tid }), "Restore: re-add original " .. tid)
        end
    end
end

-- ============================================================
-- SUITE 14: NOTIFICATION QUEUE
-- ============================================================

local function suiteNotificationQueue()
    local ok1 = pcall(BCR.EnqueueNotification, nil)
    assertTrue(ok1, "EnqueueNotification(nil) does not crash")

    local sample = {
        id = "base:SpeedDemon",
        displayName = "Speed Demon",
        action = "added",
        rarity = "common",
        color = { 0.8, 0.8, 0.8 },
    }
    local ok2 = pcall(BCR.EnqueueNotification, sample)
    assertTrue(ok2, "EnqueueNotification(valid) does not crash")

    local overflowOk = true
    for i = 1, BCR.MAX_NOTIFICATION_QUEUE + 5 do
        local ok3 = pcall(BCR.EnqueueNotification, {
            id = "T" .. tostring(i),
            displayName = "Test " .. tostring(i),
            action = "added",
            rarity = "common",
            color = { 1, 1, 1 },
        })
        if not ok3 then overflowOk = false; break end
    end
    assertTrue(overflowOk, "Queue overflow (" .. (BCR.MAX_NOTIFICATION_QUEUE + 5) .. " enqueues) does not crash")

    local ok4, _ = pcall(BCR.UpdateNotifications, nil)
    assertTrue(ok4, "UpdateNotifications(nil) does not crash")

    local ok5, _ = pcall(BCR.ShowFinalMessage, nil)
    assertTrue(ok5, "ShowFinalMessage(nil) does not crash")

    -- Leave no synthetic entries behind for the live update loop
    local ok6 = pcall(BCR.ResetNotifications)
    assertTrue(ok6, "ResetNotifications does not crash")
end

-- ============================================================
-- SUITE 15: TRAIT HISTORY & RECONCILIATION
-- ============================================================

local function suiteTraitHistoryReconciliation()
    -- === Pure part: GetLastHistoryAction ===
    local history = {
        { id = "base:SpeedDemon", action = "added" },
        { id = "base:NightVision", action = "added" },
        { id = "base:SpeedDemon", action = "lost" },
    }
    assertEqual("lost", BCR.GetLastHistoryAction(history, "base:SpeedDemon"),
        "Last action wins for base:SpeedDemon (superseded added)")
    assertEqual("added", BCR.GetLastHistoryAction(history, "base:NightVision"),
        "Single entry for base:NightVision returns its action")
    assertEqual(nil, BCR.GetLastHistoryAction(history, "base:NotInHistory"),
        "Unknown trait base:NotInHistory -> nil")
    assertEqual(nil, BCR.GetLastHistoryAction(nil, "base:SpeedDemon"),
        "GetLastHistoryAction(nil history) -> nil")
    assertEqual(nil, BCR.GetLastHistoryAction(history, nil),
        "GetLastHistoryAction(nil trait) -> nil")

    -- Legacy UPPER_SNAKE_CASE ids must match current ResourceLocation ids
    local legacyHistory = { { id = "NIGHT_VISION", action = "added" } }
    assertEqual("added", BCR.GetLastHistoryAction(legacyHistory, "base:NightVision"),
        "Legacy history id resolves to current id")
    assertEqual("added", BCR.GetLastHistoryAction(
        { { id = "base:NightVision", action = "added" } }, "NIGHT_VISION"),
        "Legacy query id resolves to current entry")

    if isClient() or isServer() then
        skipSuite("Needs SP mode (neither client nor server flag set)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()
    local bcrData = BCR.EnsureModData(player)
    assertNotNil(bcrData, "ModData present")

    -- Save real state for restoration
    local savedHistory = bcrData.traitHistory
    local savedRestore = BCR.opts and BCR.opts.restoreMissingTraits

    local nightEntry = { id = "base:NightVision", cost = -3 }
    local hadNight = BCR.PlayerHasTrait(player, "base:NightVision")

    -- === Test 1: baseline history entry excluded from earnable pool ===
    bcrData.traitHistory = { { id = "base:NightVision", action = "baseline" } }
    BCR.RemoveTrait(player, nightEntry)
    local earnable = BCR.BuildEarnablePool(player)
    local found = false
    for _, entry in ipairs(earnable) do
        if entry.id == "base:NightVision" then found = true end
    end
    assertFalse(found, "Baseline trait " .. nightEntry.id .. " excluded from earnable pool")

    -- === Test 2: history-added trait excluded from earnable pool ===
    bcrData.traitHistory = { { id = "base:NightVision", action = "added" } }
    earnable = BCR.BuildEarnablePool(player)
    found = false
    for _, entry in ipairs(earnable) do
        if entry.id == "base:NightVision" then found = true end
    end
    assertFalse(found, "History-added trait " .. nightEntry.id .. " excluded from earnable pool")

    -- === Test 3: lost trait is earnable again ===
    table.insert(bcrData.traitHistory, { id = "base:NightVision", action = "lost" })
    earnable = BCR.BuildEarnablePool(player)
    found = false
    for _, entry in ipairs(earnable) do
        if entry.id == "base:NightVision" then found = true end
    end
    assertTrue(found, "Lost trait " .. nightEntry.id .. " is earnable again")

    -- === Test 4: removed-history trait excluded from removable pool ===
    bcrData.traitHistory = {}
    local asthmaticEntry = { id = "base:Asthmatic", cost = 5 }
    local hadAsthmatic = BCR.PlayerHasTrait(player, "base:Asthmatic")
    BCR.AddTrait(player, asthmaticEntry)
    local removable = BCR.BuildRemovablePool(player)
    local inPool = false
    for _, entry in ipairs(removable) do
        if entry.id == "base:Asthmatic" then inPool = true end
    end
    assertTrue(inPool, "Owned negative trait " .. asthmaticEntry.id .. " is in removable pool")
    table.insert(bcrData.traitHistory, { id = "base:Asthmatic", action = "removed" })
    removable = BCR.BuildRemovablePool(player)
    inPool = false
    for _, entry in ipairs(removable) do
        if entry.id == "base:Asthmatic" then inPool = true end
    end
    assertFalse(inPool, "Removed-history trait " .. asthmaticEntry.id .. " excluded from removable pool")
    BCR.RemoveTrait(player, asthmaticEntry)
    if hadAsthmatic ~= false then BCR.AddTrait(player, asthmaticEntry) end

    -- === Test 5: reconcile records baseline for owned traits ===
    bcrData.traitHistory = {}
    BCR.opts.restoreMissingTraits = false
    BCR.AddTrait(player, nightEntry)
    local changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
    assertTrue(changed, "Reconcile records baseline (" .. nightEntry.id .. ")")
    assertEqual("baseline", BCR.GetLastHistoryAction(bcrData.traitHistory, "base:NightVision"),
        "Owned trait " .. nightEntry.id .. " gets a baseline history entry")

    -- === Test 5b: reconcile is idempotent ===
    changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
    assertFalse(changed, "Second reconcile is a no-op (" .. nightEntry.id .. ")")
    local nightCount = 0
    for _, h in ipairs(bcrData.traitHistory) do
        if h.id == "base:NightVision" then nightCount = nightCount + 1 end
    end
    assertEqual(1, nightCount, "No duplicate baseline entries for " .. nightEntry.id)

    -- === Test 6: missing + restore off -> marked lost ===
    BCR.RemoveTrait(player, nightEntry)
    changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
    assertTrue(changed, "Reconcile marks " .. nightEntry.id .. " lost")
    assertEqual("lost", BCR.GetLastHistoryAction(bcrData.traitHistory, "base:NightVision"),
        "Missing baseline trait (" .. nightEntry.id .. ") marked lost")

    -- === Test 7: missing + restore on -> re-applied ===
    BCR.opts.restoreMissingTraits = true
    bcrData.traitHistory = { { id = "base:NightVision", action = "baseline" } }
    changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
    assertTrue(changed, "Reconcile restores " .. nightEntry.id)
    assertEqual(true, BCR.PlayerHasTrait(player, "base:NightVision") == true,
        nightEntry.id .. " re-applied by restore")
    assertEqual("added", BCR.GetLastHistoryAction(bcrData.traitHistory, "base:NightVision"),
        "Restore records 'added' for " .. nightEntry.id)

    -- === Test 8: restore on + sandbox toggle off -> not re-applied, not lost ===
    BCR.RemoveTrait(player, nightEntry)
    if SandboxVars.BCR ~= nil then
        local sv = SandboxVars.BCR
        local savedAllow = sv.allow_base_NightVision
        sv.allow_base_NightVision = false
        assertEqual(false, BCR.IsTraitAllowed("base:NightVision"),
            "IsTraitAllowed false for base:NightVision while the sandbox toggle is off")
        bcrData.traitHistory = { { id = "base:NightVision", action = "baseline" } }
        changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
        assertEqual("baseline", BCR.GetLastHistoryAction(bcrData.traitHistory, "base:NightVision"),
            "Disabled " .. nightEntry.id .. ": no new history entry recorded (restore retries later)")
        local nightEntries = 0
        for _, h in ipairs(bcrData.traitHistory) do
            if h.id == "base:NightVision" then nightEntries = nightEntries + 1 end
        end
        assertEqual(1, nightEntries, "Disabled " .. nightEntry.id .. ": exactly one history entry")
        assertEqual(false, BCR.PlayerHasTrait(player, "base:NightVision") == true,
            nightEntry.id .. " NOT re-applied while disabled")
        if savedAllow ~= nil then
            sv.allow_base_NightVision = savedAllow
        else
            sv.allow_base_NightVision = nil
        end
    end

    -- === Test 9: reward-removed trait must not be restored or marked lost ===
    bcrData.traitHistory = {
        { id = "base:Asthmatic", action = "baseline" },
        { id = "base:Asthmatic", action = "removed" },
    }
    BCR.opts.restoreMissingTraits = true
    BCR.AddTrait(player, asthmaticEntry)
    BCR.RemoveTrait(player, asthmaticEntry)
    changed = BCR.ReconcileTraitState(player, bcrData, BCR.opts)
    assertEqual("removed", BCR.GetLastHistoryAction(bcrData.traitHistory, "base:Asthmatic"),
        "Reward-removed " .. asthmaticEntry.id .. " keeps last action removed")
    assertEqual(false, BCR.PlayerHasTrait(player, "base:Asthmatic") == true,
        "Reward-removed " .. asthmaticEntry.id .. " NOT restored even with restore on")
    if hadAsthmatic ~= false then BCR.AddTrait(player, asthmaticEntry) end

    -- === Restore state ===
    if hadNight ~= false then BCR.AddTrait(player, nightEntry) end
    bcrData.traitHistory = savedHistory
    if BCR.opts then
        BCR.opts.restoreMissingTraits = savedRestore
    end
end

-- ============================================================
-- PUBLIC ENTRY POINT
-- ============================================================

local testSuites = {
    { "Trait Registry", suiteTraitRegistry },
    { "Rarity & Weight", suiteRarityWeight },
    { "Mutual Exclusion", suiteMutualExclusion },
    { "Weighted Selection", suiteWeightedSelection },
    { "Display Names", suiteDisplayNames },
    { "Data Integrity", suiteDataIntegrity },
    { "Config & Debug", suiteConfigDebug },
    { "Filter Pool", suiteFilterPool },
    { "Milestone Math", suiteMilestoneMath },
    { "Add / Remove", suiteAddRemove },
    { "Exclusions", suiteExclusions },
    { "Pool Building & Player State", suitePoolBuildingPlayerState },
    { "Catch-Up / Process Reward", suiteCatchUpProcessReward },
    { "Notification Queue", suiteNotificationQueue },
    { "Trait History & Reconciliation", suiteTraitHistoryReconciliation },
}

-- ============================================================
-- RUN-LEVEL SAFETY NET -- some suites mutate live player state.
-- Snapshot before the run and restore afterwards, so a crashing
-- suite can never leave test values in the save.
-- ============================================================

local function snapshotPlayerState(player)
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return nil end
    local snapshot = {
        kills = bcrData.kills,
        rewardsGiven = bcrData.rewardsGiven,
        withheld = bcrData.withheldMilestones,
        history = {},
        traits = {},
        restoreMissingTraits = BCR.opts and BCR.opts.restoreMissingTraits,
        sandbox = {},
    }
    if type(bcrData.traitHistory) == "table" then
        for i, v in ipairs(bcrData.traitHistory) do
            snapshot.history[i] = v
        end
    end
    local traitList = BCR.GetPlayerTraitsList(player)
    if traitList then
        for _, tid in ipairs(traitList) do
            snapshot.traits[tid] = true
        end
    end
    local sandboxVars = SandboxVars and SandboxVars.BCR
    if type(sandboxVars) == "table" then
        for k, v in pairs(sandboxVars) do
            snapshot.sandbox[k] = v
        end
    end
    return snapshot
end

local function restorePlayerState(player, snapshot)
    local bcrData = BCR.EnsureModData(player)
    if bcrData then
        bcrData.kills = snapshot.kills
        bcrData.rewardsGiven = snapshot.rewardsGiven
        bcrData.withheldMilestones = snapshot.withheld
        local history = {}
        for i, v in ipairs(snapshot.history) do
            history[i] = v
        end
        bcrData.traitHistory = history
    end

    local traitsNow = {}
    local traitList = BCR.GetPlayerTraitsList(player)
    if traitList then
        for _, tid in ipairs(traitList) do
            traitsNow[tid] = true
        end
    end
    for tid in pairs(traitsNow) do
        if not snapshot.traits[tid] then
            BCR.RemoveTrait(player, { id = tid })
        end
    end
    for tid in pairs(snapshot.traits) do
        if not traitsNow[tid] then
            BCR.AddTrait(player, { id = tid })
        end
    end

    if BCR.opts then
        BCR.opts.restoreMissingTraits = snapshot.restoreMissingTraits
    end
    local sandboxVars = SandboxVars and SandboxVars.BCR
    if type(sandboxVars) == "table" then
        for k, v in pairs(snapshot.sandbox) do
            sandboxVars[k] = v
        end
    end
end

function BCRRunTests()
    passed = 0
    failed = 0
    skipped = 0
    failures = {}
    suiteIndex = 0
    suiteTotal = #testSuites

    local player = getPlayerForTests()
    local snapshot = player and snapshotPlayerState(player) or nil

    for _, s in ipairs(testSuites) do
        runSuite(s[1], s[2])
    end

    if snapshot then
        local okRestore, errRestore = pcall(restorePlayerState, player, snapshot)
        if not okRestore then
            print("[BCR] [Tests] State restore error: " .. tostring(errRestore))
        end
    end

    local total = passed + failed
    print("[BCR] [Tests] ========================================")
    print(string.format("[BCR] [Tests] Total: %d | Passed: %d | Failed: %d | Skipped: %d",
        total, passed, failed, skipped))
    if #failures > 0 then
        print("[BCR] [Tests] FAILURES (" .. #failures .. "):")
        for _, msg in ipairs(failures) do
            print("[BCR] [Tests]   " .. msg)
        end
    end
    print("[BCR] [Tests] ========================================")
end
