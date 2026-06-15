-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRTests (Build 42.19+)
-- Unit tests, 10 suites. Run in-game: BCRRunTests()
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

local function assertTrue(cond, msg)
    if cond then
        passed = passed + 1
        print("[BCR Tests]   PASS: [" .. currentSuite .. "] " .. (msg or "assertTrue"))
    else
        failed = failed + 1
        table.insert(failures, "[" .. currentSuite .. "] " .. (msg or "assertion failed"))
        print("[BCR Tests]   FAIL: [" .. currentSuite .. "] " .. (msg or "assertion failed"))
    end
end

local function assertFalse(cond, msg)
    assertTrue(not cond, msg)
end

local function assertEqual(expected, actual, msg)
    if expected == actual then
        passed = passed + 1
        print("[BCR Tests]   PASS: [" .. currentSuite .. "] " .. (msg or "assertEqual"))
        return
    end
    failed = failed + 1
    local detail = (msg or "assertEqual failed")
        .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")"
    table.insert(failures, "[" .. currentSuite .. "] " .. detail)
    print("[BCR Tests]   FAIL: [" .. currentSuite .. "] " .. (msg or "assertEqual failed")
        .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")")
end

local function assertNotNil(val, msg)
    if val ~= nil then
        passed = passed + 1
        print("[BCR Tests]   PASS: [" .. currentSuite .. "] " .. (msg or "assertNotNil"))
    else
        failed = failed + 1
        table.insert(failures, "[" .. currentSuite .. "] " .. (msg or "expected non-nil, got nil"))
        print("[BCR Tests]   FAIL: [" .. currentSuite .. "] " .. (msg or "expected non-nil, got nil"))
    end
end

local function assertNotEqual(expected, val, msg)
    if expected ~= val then
        passed = passed + 1
        print("[BCR Tests]   PASS: [" .. currentSuite .. "] " .. (msg or "assertNotEqual"))
    else
        failed = failed + 1
        table.insert(failures, "[" .. currentSuite .. "] " .. (msg or "values should differ"))
        print("[BCR Tests]   FAIL: [" .. currentSuite .. "] " .. (msg or "values should differ"))
    end
end

local function assertType(expectedType, val, msg)
    if type(val) == expectedType then
        passed = passed + 1
        print("[BCR Tests]   PASS: [" .. currentSuite .. "] " .. (msg or "type check"))
    else
        failed = failed + 1
        local detail = (msg or "type check failed")
            .. " (expected " .. expectedType .. ", got " .. type(val) .. ")"
        table.insert(failures, "[" .. currentSuite .. "] " .. detail)
        print("[BCR Tests]   FAIL: [" .. currentSuite .. "] " .. (msg or "type check failed")
            .. " (expected " .. expectedType .. ", got " .. type(val) .. ")")
    end
end

local function skipSuite(reason)
    skipped = skipped + 1
    print("[BCR Tests]   SKIP: [" .. currentSuite .. "] " .. reason)
end

local function runSuite(name, fn)
    currentSuite = name
    print("[BCR Tests] ========================================")
    print("[BCR Tests] SUITE: " .. name)
    print("[BCR Tests] ========================================")
    local ok, err = pcall(fn)
    if not ok then
        print("[BCR Tests] Suite '" .. name .. "' crashed: " .. tostring(err))
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

    local resolvedCount = 0
    for _, traitId in ipairs(allTraitIds) do
        local userdata = BCR.GetTraitUserdata(traitId)
        assertNotNil(userdata, traitId .. " should resolve to userdata")
        if userdata then resolvedCount = resolvedCount + 1 end
    end
    assertEqual(43, resolvedCount, "All 43 traits should resolve")

    for _, traitId in ipairs(allTraitIds) do
        local a = BCR.GetTraitUserdata(traitId)
        local b = BCR.GetTraitUserdata(traitId)
        assertEqual(a, b, traitId .. " cache should return same object")
    end

    local unknown = BCR.GetTraitUserdata("FAKE_TRAIT_XYZ")
    assertTrue(unknown == nil or unknown == false, "Unknown trait -> nil/false")

    assertTrue(BCR.GetTraitUserdata(nil) == nil or BCR.GetTraitUserdata(nil) == false,
        "Nil input -> nil/false")
    assertTrue(BCR.GetTraitUserdata("") == nil or BCR.GetTraitUserdata("") == false,
        "Empty string -> nil/false")
end

-- ============================================================
-- SUITE 2: RARITY & WEIGHT
-- ============================================================

local function suiteRarityWeight()
    assertEqual("common",   BCR.GetRarity(0),  "Cost 0 is common")
    assertEqual("common",   BCR.GetRarity(1))
    assertEqual("common",   BCR.GetRarity(2),  "Boundary: 2 = common")
    assertEqual("uncommon", BCR.GetRarity(3),  "Boundary: 3 = uncommon")
    assertEqual("uncommon", BCR.GetRarity(4),  "Boundary: 4 = uncommon")
    assertEqual("rare",     BCR.GetRarity(5),  "Boundary: 5 = rare")
    assertEqual("rare",     BCR.GetRarity(6),  "Boundary: 6 = rare")
    assertEqual("veryRare", BCR.GetRarity(7),  "Boundary: 7 = veryRare")
    assertEqual("veryRare", BCR.GetRarity(99))

    assertEqual(BCR.GetRarity(4), BCR.GetRarity(-4), "Abs cost 4 same tier")
    assertEqual(BCR.GetRarity(6), BCR.GetRarity(-6))
    assertEqual(BCR.GetRarity(8), BCR.GetRarity(-8))

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
    for traitA, excludedList in pairs(BCR.Exclusions) do
        for _, traitB in ipairs(excludedList) do
            local reverseExclusions = BCR.Exclusions[traitB]
            assertNotNil(reverseExclusions,
                traitB .. " must have exclusions (missing reverse of " .. traitA .. ")")
            local found = false
            for _, excludedId in ipairs(reverseExclusions or {}) do
                if excludedId == traitA then found = true; break end
            end
            assertTrue(found, traitB .. " must exclude " .. traitA)
        end
    end

    for traitId, excludedList in pairs(BCR.Exclusions) do
        for _, excludedId in ipairs(excludedList) do
            assertNotEqual(traitId, excludedId, traitId .. " must not exclude itself")
        end
    end

    local allIds = {}
    for _, e in ipairs(BCR.PositiveTraits) do allIds[e.id] = true end
    for _, e in ipairs(BCR.NegativeTraits) do allIds[e.id] = true end
    if BCR.CustomPositiveTraits then
        for _, e in ipairs(BCR.CustomPositiveTraits) do allIds[e.id] = true end
    end
    if BCR.CustomNegativeTraits then
        for _, e in ipairs(BCR.CustomNegativeTraits) do allIds[e.id] = true end
    end
    for _, excludedList in pairs(BCR.Exclusions) do
        for _, excludedId in ipairs(excludedList) do
            assertTrue(allIds[excludedId], excludedId .. " in exclusion must be a real trait")
        end
    end

    for _, excludedList in pairs(BCR.Exclusions) do
        local seen = {}
        for _, id in ipairs(excludedList) do
            assertFalse(seen[id], "Duplicate in exclusion list: " .. id)
            seen[id] = true
        end
    end
end

-- ============================================================
-- SUITE 4: WEIGHTED SELECTION
-- ============================================================

local function suiteWeightedSelection()
    assertTrue(BCR.WeightedRandomSelect(nil) == nil, "Nil pool -> nil")
    assertTrue(BCR.WeightedRandomSelect({}) == nil, "Empty pool -> nil")

    local single = { id = "ONLY", traitUserdata = nil, cost = 1, rarity = "common", weight = 1 }
    for _ = 1, 5 do
        local sel = BCR.WeightedRandomSelect({ single })
        assertEqual(single.id, sel.id, "Single-entry always returned")
    end

    local light = { id = "LIGHT", weight = 9 }
    local heavy = { id = "HEAVY", weight = 1 }
    local pool = { light, heavy }
    local counts = { LIGHT = 0, HEAVY = 0 }
    for _ = 1, 200 do
        local result = BCR.WeightedRandomSelect(pool)
        assertNotNil(result, "Must return entry from valid pool")
        counts[result.id] = (counts[result.id] or 0) + 1
    end
    assertTrue(counts.LIGHT > counts.HEAVY,
        "Higher weight selected more (L=" .. counts.LIGHT .. " H=" .. counts.HEAVY .. ")")
    assertTrue(counts.HEAVY > 0, "Lower weight appears at least once in 200 trials")

    local zeroPool = { { id = "A", weight = 0 }, { id = "B", weight = 0 } }
    for _ = 1, 10 do
        local sel = BCR.WeightedRandomSelect(zeroPool)
        assertNotNil(sel, "Zero-weight returns entry via fallback")
        assertTrue(sel.id == "A" or sel.id == "B")
    end

    local sel = BCR.WeightedRandomSelect({ { id = "ZERO", weight = 0 } })
    assertNotNil(sel, "Single zero-weight -> fallback")
    assertEqual("ZERO", sel.id)
end

-- ============================================================
-- SUITE 5: DISPLAY NAMES
-- ============================================================

local function suiteDisplayNames()
    local overrides = { "base:NeedsLessSleep", "base:NeedsMoreSleep", "base:Dextrous" }
    for _, tid in ipairs(overrides) do
        local name = BCR.GetTraitDisplayName(tid)
        assertNotNil(name, tid .. " override name not nil")
        assertTrue(#name > 0, tid .. " override name not empty")
        assertNotEqual(tid, name, tid .. " override name differs from raw ID")
        assertFalse(string.find(name, "_"), tid .. " override name no underscores: " .. name)
    end

    local allIds = {}
    for _, e in ipairs(BCR.PositiveTraits) do table.insert(allIds, e.id) end
    for _, e in ipairs(BCR.NegativeTraits) do table.insert(allIds, e.id) end
    for _, tid in ipairs(allIds) do
        local name = BCR.GetTraitDisplayName(tid)
        assertNotNil(name, tid .. " name not nil")
        assertTrue(#name > 0, tid .. " name not empty")
        assertNotEqual(tid, name, tid .. " name differs from ID")
    end

    assertEqual("Unknown", BCR.GetTraitDisplayName(nil), "Nil -> 'Unknown'")
    assertNotNil(BCR.GetTraitDisplayName(""), "Empty string -> not nil")

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

    local seen = {}
    for _, e in ipairs(BCR.PositiveTraits) do
        assertFalse(seen[e.id], "Duplicate positive: " .. e.id)
        seen[e.id] = true
    end
    seen = {}
    for _, e in ipairs(BCR.NegativeTraits) do
        assertFalse(seen[e.id], "Duplicate negative: " .. e.id)
        seen[e.id] = true
    end
    local negIds = {}
    for _, e in ipairs(BCR.NegativeTraits) do negIds[e.id] = true end
    for _, e in ipairs(BCR.PositiveTraits) do
        assertFalse(negIds[e.id], e.id .. " not in both lists")
    end

    for _, e in ipairs(BCR.PositiveTraits) do
        assertTrue(e.cost < 0, e.id .. " positive cost < 0, got " .. e.cost)
    end
    for _, e in ipairs(BCR.NegativeTraits) do
        assertTrue(e.cost > 0, e.id .. " negative cost > 0, got " .. e.cost)
    end

    assertFalse(BCR.HasAvailableRewards(nil), "nil -> false")
    assertTrue(BCR.EnsureModData(nil) == nil, "nil -> nil ModData")
    assertTrue(BCR.PlayerHasTrait(nil, "base:SpeedDemon") == nil, "nil -> nil hasTrait")

    -- Exclusions count check (informational, won't fail on count mismatch unless it's 0)
    local exCount = 0
    for _ in pairs(BCR.Exclusions) do exCount = exCount + 1 end
    assertTrue(exCount > 0, "Exclusions must have entries")
end

-- ============================================================
-- SUITE 7: CONFIG & DEBUG
-- ============================================================

local function suiteConfigDebug()
    assertEqual(1, BCR.PRIORITY_POSITIVE_FIRST)
    assertEqual(2, BCR.PRIORITY_NEGATIVE_FIRST)
    assertEqual(3, BCR.PRIORITY_RANDOM)
    assertEqual("BCR", BCR.MODULE_NAME)
    assertEqual(8, BCR.MAX_NOTIFICATION_QUEUE)
    assertEqual("boolean", type(BCR.DEBUG))

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
    assertNotNil(BCR.FilterPoolByExclusion(nil, {}), "Nil pool -> empty table (not nil)")
    assertNotNil(BCR.FilterPoolByExclusion(nil, nil), "Nil pool + nil exclude -> empty table")

    local pool = {
        { id = "A", traitUserdata = nil, cost = 1, rarity = "common", weight = 1 },
        { id = "B", traitUserdata = nil, cost = 2, rarity = "common", weight = 2 },
        { id = "C", traitUserdata = nil, cost = 3, rarity = "uncommon", weight = 1 },
    }
    assertEqual(3, #BCR.FilterPoolByExclusion(pool, nil), "Nil exclude -> full pool")
    assertEqual(3, #BCR.FilterPoolByExclusion(pool, {}), "Empty exclude -> full pool")

    local f1 = BCR.FilterPoolByExclusion(pool, { A = true })
    assertEqual(2, #f1, "Exclude A -> 2 entries")
    for _, e in ipairs(f1) do assertNotEqual("A", e.id) end

    local f2 = BCR.FilterPoolByExclusion(pool, { A = true, C = true })
    assertEqual(1, #f2, "Exclude A+C -> 1 entry")
    assertEqual("B", f2[1].id)

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
    assertEqual(1000, BCR.GetKillsForMilestone(1, linear))
    assertEqual(2000, BCR.GetKillsForMilestone(2, linear))
    assertEqual(5000, BCR.GetKillsForMilestone(5, linear))

    -- Round-trip invariant
    for n = 1, 10 do
        local kills = BCR.GetKillsForMilestone(n, linear)
        local m = BCR.GetMilestonesAtKills(kills, linear)
        assertTrue(m >= n, "Linear round-trip n=" .. n .. " kills=" .. kills .. " m=" .. m)
    end

    assertEqual(0, BCR.GetMilestonesAtKills(999, linear))
    assertEqual(1, BCR.GetMilestonesAtKills(1000, linear))
    assertEqual(1, BCR.GetMilestonesAtKills(1999, linear))
    assertEqual(2, BCR.GetMilestonesAtKills(2000, linear))

    assertEqual(0, BCR.GetKillsForMilestone(0, linear))
    assertEqual(0, BCR.GetKillsForMilestone(-5, linear))
    assertEqual(0, BCR.GetMilestonesAtKills(0, linear))
    assertEqual(0, BCR.GetMilestonesAtKills(-100, linear))

    local zeroBC = { bodyCount = 0, milestoneScaling = 1 }
    assertEqual(0, BCR.GetKillsForMilestone(1, zeroBC))
    assertEqual(0, BCR.GetMilestonesAtKills(5000, zeroBC))

    local progZero = { bodyCount = 1000, milestoneScaling = 2, progressiveScalingFactor = 0 }
    assertEqual(BCR.GetKillsForMilestone(3, linear), BCR.GetKillsForMilestone(3, progZero),
        "Factor 0 progressive = linear")

    local prog = { bodyCount = 1000, milestoneScaling = 2, progressiveScalingFactor = 0.5 }
    assertEqual(1000, BCR.GetKillsForMilestone(1, prog))
    assertEqual(2500, BCR.GetKillsForMilestone(2, prog))
    assertEqual(4500, BCR.GetKillsForMilestone(3, prog))
    assertEqual(7000, BCR.GetKillsForMilestone(4, prog))

    local prev = 0
    for n = 1, 5 do
        local cur = BCR.GetKillsForMilestone(n, prog)
        assertTrue(cur > prev, "Progressive monotonic n=" .. n)
        prev = cur
    end

    for n = 1, 8 do
        local kills = BCR.GetKillsForMilestone(n, prog)
        local m = BCR.GetMilestonesAtKills(kills, prog)
        assertTrue(m >= n, "Progressive round-trip n=" .. n .. " kills=" .. kills .. " m=" .. m)
    end
end

-- ============================================================
-- SUITE 10: ADD / REMOVE (needs player)
-- ============================================================

local function suiteAddRemove()
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    local speedEntry = { id = "base:SpeedDemon", cost = -1 }
    BCR.RemoveTrait(player, speedEntry)

    assertTrue(BCR.AddTrait(player, speedEntry), "Add base:SpeedDemon")
    assertFalse(BCR.AddTrait(player, speedEntry), "Duplicate add fails")
    assertTrue(BCR.RemoveTrait(player, speedEntry), "Remove base:SpeedDemon")
    assertFalse(BCR.RemoveTrait(player, speedEntry), "Remove absent fails")

    assertFalse(BCR.AddTrait(nil, speedEntry), "nil player -> false")
    assertFalse(BCR.RemoveTrait(nil, speedEntry), "nil player -> false")
    assertFalse(BCR.AddTrait(player, nil), "nil entry -> false")
    assertFalse(BCR.RemoveTrait(player, nil), "nil entry -> false")

    -- Entry with no .id field
    assertFalse(BCR.AddTrait(player, { cost = -1 }), "No id/trait field -> false")
    assertFalse(BCR.RemoveTrait(player, { cost = 2 }), "No id/trait field -> false")

    -- Bogus trait ID (won't resolve to userdata)
    assertFalse(BCR.AddTrait(player, { id = "NOT_A_REAL_TRAIT" }),
        "Bogus ID -> add fails")
    assertFalse(BCR.RemoveTrait(player, { id = "NOT_A_REAL_TRAIT" }),
        "Bogus ID -> remove fails")

    assertTrue(BCR.AddTrait(player, { id = "base:SpeedDemon" }),
        "Re-add after remove-absent cycle should succeed")
    BCR.RemoveTrait(player, speedEntry)
end

-- ============================================================
-- SUITE 11: EXCLUSIONS (needs player)
-- ============================================================

local function suiteExclusions()
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    local adrEntry = { id = "base:AdrenalineJunkie", cost = -4 }
    local agoEntry = { id = "base:Agoraphobic", cost = 4 }
    BCR.RemoveTrait(player, adrEntry)
    BCR.RemoveTrait(player, agoEntry)

    assertTrue(BCR.AddTrait(player, adrEntry), "Add base:AdrenalineJunkie")
    assertFalse(BCR.AddTrait(player, agoEntry), "base:Agoraphobic blocked")

    local blocked, blocker = BCR.HasMutuallyExclusiveTrait(player, "base:Agoraphobic")
    assertTrue(blocked, "base:Agoraphobic is blocked")
    assertEqual("base:AdrenalineJunkie", blocker)

    -- Non-excluded trait
    assertFalse(BCR.HasMutuallyExclusiveTrait(player, "base:Smoker"), "base:Smoker not blocked")

    -- Nil player
    assertFalse(BCR.HasMutuallyExclusiveTrait(nil, "base:SpeedDemon"), "nil -> false")

    -- Nonexistent trait
    assertFalse(BCR.HasMutuallyExclusiveTrait(player, "FAKETRAIT_XYZ"),
        "Nonexistent trait -> false")

    BCR.RemoveTrait(player, adrEntry)
    local braveEntry = { id = "base:Brave", cost = -4 }
    local hadBrave = BCR.PlayerHasTrait(player, "base:Brave")
    BCR.RemoveTrait(player, braveEntry)
    assertTrue(BCR.AddTrait(player, agoEntry), "base:Agoraphobic addable after removal")
    assertFalse(BCR.AddTrait(player, adrEntry), "ADRENALINE blocked by base:Agoraphobic (symmetry)")

    BCR.RemoveTrait(player, agoEntry)
    BCR.RemoveTrait(player, adrEntry)
    if hadBrave == true then BCR.AddTrait(player, braveEntry) end

    -- 3-way: base:FastReader
    local frEntry = { id = "base:FastReader", cost = -2 }
    local srEntry = { id = "base:SlowReader", cost = 2 }
    local illEntry = { id = "base:Illiterate", cost = 10 }
    BCR.RemoveTrait(player, frEntry)
    BCR.RemoveTrait(player, srEntry)
    BCR.RemoveTrait(player, illEntry)

    assertTrue(BCR.AddTrait(player, frEntry), "Add base:FastReader")
    assertFalse(BCR.AddTrait(player, srEntry), "base:SlowReader blocked")
    assertFalse(BCR.AddTrait(player, illEntry), "base:Illiterate blocked")
    BCR.RemoveTrait(player, frEntry)
end

-- ============================================================
-- SUITE 12: POOL BUILDING & PLAYER STATE (needs player)
-- ============================================================

local function suitePoolBuildingPlayerState()
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()

    -- === BuildEarnablePool ===
    assertTrue(BCR.BuildEarnablePool(nil) == nil, "nil player -> nil earnable")
    assertTrue(BCR.BuildRemovablePool(nil) == nil, "nil player -> nil removable")

    local earnable = BCR.BuildEarnablePool(player)
    assertNotNil(earnable, "Earnable pool not nil")
    local eCount = 0
    for _ in ipairs(earnable) do eCount = eCount + 1 end
    assertTrue(eCount > 0, "Earnable pool has entries")

    for _, entry in ipairs(earnable) do
        assertNotNil(entry.id)
        assertType("string", entry.id, entry.id .. " .id string")
        assertNotNil(entry.traitUserdata, entry.id .. " .traitUserdata")
        assertNotNil(entry.cost)
        assertType("number", entry.cost, entry.id .. " .cost number")
        assertTrue(entry.cost < 0, entry.id .. " cost negative, got " .. entry.cost)
        assertNotNil(entry.rarity)
        assertNotNil(entry.weight)
        assertTrue(entry.weight >= 1, entry.id .. " weight >= 1, got " .. entry.weight)
    end

    -- === BuildRemovablePool ===
    local removable = BCR.BuildRemovablePool(player)
    assertNotNil(removable, "Removable pool not nil")
    for _, entry in ipairs(removable) do
        assertTrue(entry.cost > 0, entry.id .. " cost positive")
        assertEqual(true, BCR.PlayerHasTrait(player, entry.id),
            entry.id .. " must be owned")
    end

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
    for _, tid in ipairs(traitList) do
        assertType("string", tid, "Trait list entry must be string, got " .. type(tid))
        listCount = listCount + 1
    end
    -- Player should have at least their profession traits
    assertTrue(listCount > 0, "Player should have some traits")

    assertTrue(BCR.GetPlayerTraitsList(nil) == nil, "nil player -> nil traits list")

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
end

-- ============================================================
-- SUITE 13: CATCH-UP / PROCESS REWARD (needs player + SP)
-- ============================================================

local function suiteCatchUpProcessReward()
    if not isClient() and not isServer() then
        -- SP mode
    else
        skipSuite("Needs SP mode (both client and server loaded)")
        return
    end
    if not hasPlayer() then
        skipSuite("Needs player in-game. Run from SP world console.")
        return
    end
    local player = getPlayerForTests()
    local bcrData = BCR.EnsureModData(player)
    assertNotNil(bcrData, "Should have ModData")

    -- Test: ProcessRewardDirect with nil player
    assertTrue(BCR.ProcessRewardDirect(nil) == nil, "nil player -> nil")

    -- Test: ProcessRewardDirect returns nil when no milestone reached
    local originalKills = bcrData.kills
    local originalRewardsGiven = bcrData.rewardsGiven
    bcrData.rewardsGiven = 99
    bcrData.kills = 999
    local result = BCR.ProcessRewardDirect(player)
    assertTrue(result == nil,
        "No reward when kills < BodyCount and rewardsGiven already high")
    if originalKills ~= nil then bcrData.kills = originalKills end
    if originalRewardsGiven ~= nil then bcrData.rewardsGiven = originalRewardsGiven end

    -- Test: With very high kills and 0 rewards, ensure ProcessRewardDirect
    -- returns a reward with correct shape (if a rewardable trait exists)
    bcrData.rewardsGiven = 0
    bcrData.kills = 50000
    result = BCR.ProcessRewardDirect(player)
    -- Restore regardless
    if originalKills ~= nil then bcrData.kills = originalKills end
    if originalRewardsGiven ~= nil then bcrData.rewardsGiven = originalRewardsGiven end
    -- If no reward returned (all traits already owned/blocked), that's valid
    if result ~= nil and type(result) == "table" and #result > 0 then
        local first = result[1]
        assertNotNil(first.id, "Result.id")
        assertNotNil(first.displayName, "Result.displayName")
        assertTrue(first.action == "added" or first.action == "removed",
            "Action is added/removed, got " .. tostring(first.action))
        assertNotNil(first.rarity, "Result.rarity")
        assertNotNil(first.color, "Result.color")
        assertEqual(3, #first.color, "Color {r,g,b}")
        assertNotNil(first.cost, "Result.cost")
    end
end

-- ============================================================
-- SUITE 14: NOTIFICATION QUEUE
-- ============================================================

local function suiteNotificationQueue()
    local ok1, err1 = pcall(BCR.EnqueueNotification, nil)
    assertTrue(ok1, "EnqueueNotification(nil) does not crash")

    local sample = {
        id = "base:SpeedDemon",
        displayName = "Speed Demon",
        action = "added",
        rarity = "common",
        color = { 0.8, 0.8, 0.8 },
    }
    local ok2, err2 = pcall(BCR.EnqueueNotification, sample)
    assertTrue(ok2, "EnqueueNotification(valid) does not crash")

    for i = 1, BCR.MAX_NOTIFICATION_QUEUE + 5 do
        local ok3, _ = pcall(BCR.EnqueueNotification, {
            id = "T" .. tostring(i),
            displayName = "Test " .. tostring(i),
            action = "added",
            rarity = "common",
            color = { 1, 1, 1 },
        })
        assertTrue(ok3, "EnqueueNotification overflow entry " .. i .. " does not crash")
    end

    local ok4, _ = pcall(BCR.UpdateNotifications, nil)
    assertTrue(ok4, "UpdateNotifications(nil) does not crash")

    local ok5, _ = pcall(BCR.ShowFinalMessage, nil)
    assertTrue(ok5, "ShowFinalMessage(nil) does not crash")
end

-- ============================================================
-- PUBLIC ENTRY POINT
-- ============================================================

function BCRRunTests()
    passed = 0
    failed = 0
    skipped = 0
    failures = {}

    runSuite("Trait Registry", suiteTraitRegistry)
    runSuite("Rarity & Weight", suiteRarityWeight)
    runSuite("Mutual Exclusion", suiteMutualExclusion)
    runSuite("Weighted Selection", suiteWeightedSelection)
    runSuite("Display Names", suiteDisplayNames)
    runSuite("Data Integrity", suiteDataIntegrity)
    runSuite("Config & Debug", suiteConfigDebug)
    runSuite("Filter Pool", suiteFilterPool)
    runSuite("Milestone Math", suiteMilestoneMath)
    runSuite("Add / Remove", suiteAddRemove)
    runSuite("Exclusions", suiteExclusions)
    runSuite("Pool Building & Player State", suitePoolBuildingPlayerState)
    runSuite("Catch-Up / Process Reward", suiteCatchUpProcessReward)
    runSuite("Notification Queue", suiteNotificationQueue)

    local total = passed + failed
    print("========================================")
    print(string.format("[BCR Tests] Total: %d | Passed: %d | Failed: %d | Skipped: %d",
        total, passed, failed, skipped))
    if #failures > 0 then
        print("----------------------------------------")
        print("[BCR Tests] FAILURES (" .. #failures .. "):")
        for _, msg in ipairs(failures) do
            print("  " .. msg)
        end
    end
    print("========================================")
end
