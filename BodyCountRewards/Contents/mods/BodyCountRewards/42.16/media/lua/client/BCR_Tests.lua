-- ============================================================
-- BCR_Test.lua - Unit Tests for BodyCountRewards (Build 42.13+)
-- File: media/lua/client/BCR_Test.lua
--
-- Run in-game via debug console: BCR_RunTests()
-- Requires: BCR_Shared.lua loaded, active singleplayer game
-- ============================================================

require "BCR_Shared"

BCR = BCR or {}

-- ============================================================
-- MINI TEST FRAMEWORK
-- ============================================================

local TestRunner = {
    passed = 0,
    failed = 0,
    skipped = 0,
    errors = {},
    currentSuite = "",
}

local function logLine(msg)
    print("[BCR_Test] " .. msg)
end

local function startSuite(name)
    TestRunner.currentSuite = name
    logLine("====================================")
    logLine("SUITE: " .. name)
    logLine("====================================")
end

local function assert_true(condition, testName)
    local label = TestRunner.currentSuite .. " > " .. testName
    if condition then
        TestRunner.passed = TestRunner.passed + 1
        logLine("  PASS: " .. label)
    else
        TestRunner.failed = TestRunner.failed + 1
        table.insert(TestRunner.errors, label)
        logLine("  FAIL: " .. label)
    end
end

local function assert_false(condition, testName)
    assert_true(not condition, testName)
end

local function assert_equal(expected, actual, testName)
    local label = TestRunner.currentSuite .. " > " .. testName
    if expected == actual then
        TestRunner.passed = TestRunner.passed + 1
        logLine("  PASS: " .. label)
    else
        TestRunner.failed = TestRunner.failed + 1
        table.insert(TestRunner.errors, label .. " (expected=" .. tostring(expected) .. ", got=" .. tostring(actual) .. ")")
        logLine("  FAIL: " .. label .. " (expected=" .. tostring(expected) .. ", got=" .. tostring(actual) .. ")")
    end
end

local function assert_not_nil(value, testName)
    assert_true(value ~= nil, testName)
end

local function assert_nil(value, testName)
    assert_true(value == nil, testName)
end

local function skip(testName, reason)
    TestRunner.skipped = TestRunner.skipped + 1
    logLine("  SKIP: " .. TestRunner.currentSuite .. " > " .. testName .. " (" .. reason .. ")")
end

local function printSummary()
    logLine("")
    logLine("############################################")
    logLine("# TEST RESULTS SUMMARY")
    logLine("############################################")
    logLine("#  PASSED:  " .. TestRunner.passed)
    logLine("#  FAILED:  " .. TestRunner.failed)
    logLine("#  SKIPPED: " .. TestRunner.skipped)
    logLine("#  TOTAL:   " .. (TestRunner.passed + TestRunner.failed + TestRunner.skipped))
    logLine("############################################")

    if TestRunner.failed > 0 then
        logLine("")
        logLine("FAILURES:")
        for i, err in ipairs(TestRunner.errors) do
            logLine("  " .. i .. ") " .. err)
        end
    else
        logLine("")
        logLine("ALL TESTS PASSED!")
    end
    logLine("")
end

local function resetRunner()
    TestRunner.passed = 0
    TestRunner.failed = 0
    TestRunner.skipped = 0
    TestRunner.errors = {}
    TestRunner.currentSuite = ""
end


-- ============================================================
-- SUITE 1: TRAIT REGISTRY RESOLUTION
-- Verify every trait in PositiveTraitsList and NegativeTraitsList
-- can be resolved via BCR.getTraitUserdata()
-- ============================================================

local function testTraitRegistryResolution()
    startSuite("Trait Registry Resolution")

    logLine("  -- Positive Traits (" .. #BCR.PositiveTraitsList .. ") --")
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        local ud = BCR.getTraitUserdata(entry.trait)
        assert_not_nil(ud, "Resolve positive trait: " .. entry.trait)
    end

    logLine("  -- Negative Traits (" .. #BCR.NegativeTraitsList .. ") --")
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        local ud = BCR.getTraitUserdata(entry.trait)
        assert_not_nil(ud, "Resolve negative trait: " .. entry.trait)
    end

    -- Edge case: non-existent trait should return nil
    local bogus = BCR.getTraitUserdata("TOTALLY_FAKE_TRAIT_XYZ")
    assert_nil(bogus, "Non-existent trait returns nil")

    -- Edge case: nil input
    local nilResult = BCR.getTraitUserdata(nil)
    assert_nil(nilResult, "nil input returns nil")
end


-- ============================================================
-- SUITE 2: RARITY & WEIGHT CALCULATIONS
-- Verify getRarityTier, calculateWeight, getRarityColor
-- ============================================================

local function testRarityAndWeight()
    startSuite("Rarity and Weight Calculations")

    -- Rarity tiers
    assert_equal("common",   BCR.getRarityTier(-1),  "Cost -1 = common")
    assert_equal("common",   BCR.getRarityTier(-2),  "Cost -2 = common")
    assert_equal("common",   BCR.getRarityTier(1),   "Cost +1 = common")
    assert_equal("common",   BCR.getRarityTier(2),   "Cost +2 = common")
    assert_equal("uncommon", BCR.getRarityTier(-3),  "Cost -3 = uncommon")
    assert_equal("uncommon", BCR.getRarityTier(-4),  "Cost -4 = uncommon")
    assert_equal("uncommon", BCR.getRarityTier(4),   "Cost +4 = uncommon")
    assert_equal("rare",     BCR.getRarityTier(-5),  "Cost -5 = rare")
    assert_equal("rare",     BCR.getRarityTier(-6),  "Cost -6 = rare")
    assert_equal("rare",     BCR.getRarityTier(6),   "Cost +6 = rare")
    assert_equal("veryRare", BCR.getRarityTier(-8),  "Cost -8 = veryRare")
    assert_equal("veryRare", BCR.getRarityTier(8),   "Cost +8 = veryRare")
    assert_equal("common",   BCR.getRarityTier(0),   "Cost 0 = common")
    assert_equal("common",   BCR.getRarityTier(nil), "Cost nil = common")

    -- Weight formula: max(1, (8 - |cost|) + 1)
    assert_equal(8, BCR.calculateWeight(-1),  "Weight for cost -1 = 8")
    assert_equal(7, BCR.calculateWeight(-2),  "Weight for cost -2 = 7")
    assert_equal(5, BCR.calculateWeight(-4),  "Weight for cost -4 = 5")
    assert_equal(3, BCR.calculateWeight(-6),  "Weight for cost -6 = 3")
    assert_equal(1, BCR.calculateWeight(-8),  "Weight for cost -8 = 1")
    assert_equal(8, BCR.calculateWeight(1),   "Weight for cost +1 = 8")
    assert_equal(1, BCR.calculateWeight(8),   "Weight for cost +8 = 1")
    assert_equal(9, BCR.calculateWeight(0),   "Weight for cost 0 = 9")
    assert_equal(9, BCR.calculateWeight(nil), "Weight for cost nil = 9")

    -- Rarity colors should return a table with 3 values (RGB)
    for _, cost in ipairs({-1, -4, -6, -8}) do
        local color = BCR.getRarityColor(cost)
        assert_not_nil(color, "getRarityColor returns value for cost " .. cost)
        assert_equal(3, #color, "Color table has 3 components for cost " .. cost)
    end

    -- Verify weight decreases as cost increases (inverse relationship)
    local prevWeight = 999
    for _, absCost in ipairs({1, 2, 3, 4, 5, 6, 7, 8}) do
        local w = BCR.calculateWeight(absCost)
        assert_true(w <= prevWeight, "Weight decreases: cost " .. absCost .. " weight " .. w .. " <= " .. prevWeight)
        prevWeight = w
    end
end


-- ============================================================
-- SUITE 3: MUTUALLY EXCLUSIVE TRAIT VALIDATION
-- Verify the exclusion table is symmetric and complete
-- ============================================================

local function testMutualExclusions()
    startSuite("Mutually Exclusive Trait Validation")

    local mexTable = BCR.MutuallyExclusiveTraits

    -- Symmetry check: if A excludes B, then B must exclude A
    local asymmetric = {}
    for traitA, exclusions in pairs(mexTable) do
        for _, traitB in ipairs(exclusions) do
            local reverseList = mexTable[traitB]
            if not reverseList then
                table.insert(asymmetric, traitB .. " has no exclusion entry but is excluded by " .. traitA)
            else
                local found = false
                for _, rev in ipairs(reverseList) do
                    if rev == traitA then found = true; break end
                end
                if not found then
                    table.insert(asymmetric, traitA .. " excludes " .. traitB .. " but " .. traitB .. " does not exclude " .. traitA)
                end
            end
        end
    end

    assert_equal(0, #asymmetric, "All mutual exclusions are symmetric")
    if #asymmetric > 0 then
        for _, msg in ipairs(asymmetric) do
            logLine("    WARNING: " .. msg)
        end
    end

    -- Verify no trait excludes itself
    for traitA, exclusions in pairs(mexTable) do
        local selfExclude = false
        for _, ex in ipairs(exclusions) do
            if ex == traitA then selfExclude = true; break end
        end
        assert_false(selfExclude, traitA .. " does not exclude itself")
    end

    -- Verify all excluded traits exist in our trait lists
    local allTraits = {}
    for _, entry in ipairs(BCR.PositiveTraitsList) do allTraits[entry.trait] = true end
    for _, entry in ipairs(BCR.NegativeTraitsList) do allTraits[entry.trait] = true end

    for traitA, exclusions in pairs(mexTable) do
        for _, traitB in ipairs(exclusions) do
            -- Both sides should be either in our lists or a vanilla-only trait (like BRAVE)
            if not allTraits[traitA] and not allTraits[traitB] then
                logLine("    INFO: Exclusion pair " .. traitA .. " <-> " .. traitB .. " - neither in BCR trait lists (vanilla-only)")
            end
        end
    end
end


-- ============================================================
-- SUITE 4: WEIGHTED RANDOM SELECTION
-- Verify distribution and edge cases
-- ============================================================

local function testWeightedRandomSelection()
    startSuite("Weighted Random Selection")

    -- Empty pool should return nil
    local emptyResult = BCR.weightedRandomSelect({})
    assert_nil(emptyResult, "Empty pool returns nil")

    -- nil pool should return nil
    local nilResult = BCR.weightedRandomSelect(nil)
    assert_nil(nilResult, "nil pool returns nil")

    -- Single entry pool should always return that entry
    local singlePool = {{ trait = "TEST_SINGLE", weight = 5, cost = -2, rarity = "common" }}
    local singleResult = BCR.weightedRandomSelect(singlePool)
    assert_not_nil(singleResult, "Single-entry pool returns a result")
    assert_equal("TEST_SINGLE", singleResult.trait, "Single-entry pool returns correct trait")

    -- Multi-entry pool: run many iterations and verify distribution is plausible
    local multiPool = {
        { trait = "HIGH_WEIGHT", weight = 90, cost = -1, rarity = "common" },
        { trait = "LOW_WEIGHT",  weight = 10, cost = -8, rarity = "veryRare" },
    }

    local counts = { HIGH_WEIGHT = 0, LOW_WEIGHT = 0 }
    local iterations = 1000

    for i = 1, iterations do
        local pick = BCR.weightedRandomSelect(multiPool)
        if pick and counts[pick.trait] ~= nil then
            counts[pick.trait] = counts[pick.trait] + 1
        end
    end

    -- HIGH_WEIGHT (90%) should be picked significantly more than LOW_WEIGHT (10%)
    assert_true(counts.HIGH_WEIGHT > counts.LOW_WEIGHT,
        "High weight picked more often (" .. counts.HIGH_WEIGHT .. " vs " .. counts.LOW_WEIGHT .. ")")

    -- HIGH_WEIGHT should be at least 60% of total (generous margin for RNG)
    local highPct = (counts.HIGH_WEIGHT / iterations) * 100
    assert_true(highPct > 60,
        "High weight is >60%% of picks (actual: " .. string.format("%.1f", highPct) .. "%%)")

    -- All zero weights: should still return something (fallback to random index)
    local zeroPool = {
        { trait = "ZERO_A", weight = 0, cost = -1, rarity = "common" },
        { trait = "ZERO_B", weight = 0, cost = -2, rarity = "common" },
    }
    local zeroResult = BCR.weightedRandomSelect(zeroPool)
    assert_not_nil(zeroResult, "Zero-weight pool returns a result via fallback")
end


-- ============================================================
-- SUITE 5: ADD & REMOVE TRAITS ON PLAYER
-- Tests real trait application and removal on the current player
-- ============================================================

local function testAddRemoveTraits(player)
    startSuite("Add and Remove Traits")

    if not player then
        skip("All add/remove tests", "No player available")
        return
    end

    -- Pick a positive trait the player likely doesn't have
    local testPositive = nil
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        if not BCR.playerHasTrait(player, entry.trait) and not BCR.hasMutuallyExclusiveTrait(player, entry.trait) then
            local ud = BCR.getTraitUserdata(entry.trait)
            if ud then
                testPositive = { trait = entry.trait, traitUserdata = ud, cost = entry.cost }
                break
            end
        end
    end

    -- Pick a negative trait the player likely doesn't have (for add then remove test)
    local testNegative = nil
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        if not BCR.playerHasTrait(player, entry.trait) and not BCR.hasMutuallyExclusiveTrait(player, entry.trait) then
            local ud = BCR.getTraitUserdata(entry.trait)
            if ud then
                testNegative = { trait = entry.trait, traitUserdata = ud, cost = entry.cost }
                break
            end
        end
    end

    -- TEST: Add a positive trait
    if testPositive then
        logLine("  Testing with positive trait: " .. testPositive.trait)

        local addOk = BCR.addTraitToPlayer(player, testPositive)
        assert_true(addOk, "Add positive trait: " .. testPositive.trait)

        local hasTrait = BCR.playerHasTrait(player, testPositive.trait)
        assert_true(hasTrait, "Player now has: " .. testPositive.trait)

        -- TEST: Adding same trait again should fail
        local addAgain = BCR.addTraitToPlayer(player, testPositive)
        assert_false(addAgain, "Adding duplicate trait fails: " .. testPositive.trait)

        -- TEST: Remove the trait we just added (cleanup)
        local removeOk = BCR.removeTraitFromPlayer(player, testPositive)
        assert_true(removeOk, "Remove positive trait: " .. testPositive.trait)

        local hasAfterRemove = BCR.playerHasTrait(player, testPositive.trait)
        assert_false(hasAfterRemove, "Player no longer has: " .. testPositive.trait)

        -- TEST: Removing a trait the player doesn't have should fail
        local removeAgain = BCR.removeTraitFromPlayer(player, testPositive)
        assert_false(removeAgain, "Removing absent trait fails: " .. testPositive.trait)
    else
        skip("Add/remove positive trait", "No eligible positive trait found")
    end

    -- TEST: Add then remove a negative trait
    if testNegative then
        logLine("  Testing with negative trait: " .. testNegative.trait)

        local addOk = BCR.addTraitToPlayer(player, testNegative)
        assert_true(addOk, "Add negative trait: " .. testNegative.trait)

        local hasTrait = BCR.playerHasTrait(player, testNegative.trait)
        assert_true(hasTrait, "Player now has: " .. testNegative.trait)

        local removeOk = BCR.removeTraitFromPlayer(player, testNegative)
        assert_true(removeOk, "Remove negative trait: " .. testNegative.trait)

        local hasAfterRemove = BCR.playerHasTrait(player, testNegative.trait)
        assert_false(hasAfterRemove, "Player no longer has: " .. testNegative.trait)
    else
        skip("Add/remove negative trait", "No eligible negative trait found")
    end

    -- TEST: Add with nil player
    if testPositive then
        local nilPlayerResult = BCR.addTraitToPlayer(nil, testPositive)
        assert_false(nilPlayerResult, "addTraitToPlayer with nil player returns false")

        local nilPlayerRemove = BCR.removeTraitFromPlayer(nil, testPositive)
        assert_false(nilPlayerRemove, "removeTraitFromPlayer with nil player returns false")
    end
end


-- ============================================================
-- SUITE 6: MUTUAL EXCLUSION ENFORCEMENT
-- Add a trait, verify its mutually exclusive partner is blocked
-- ============================================================

local function testMutualExclusionEnforcement(player)
    startSuite("Mutual Exclusion Enforcement")

    if not player then
        skip("All mutual exclusion tests", "No player available")
        return
    end

    -- Define test pairs: {traitToAdd, traitThatShouldBeBlocked}
    local testPairs = {
        { "ORGANIZED",     "DISORGANIZED" },
        { "FAST_HEALER",   "SLOW_HEALER" },
        { "THICK_SKINNED", "THIN_SKINNED" },
        { "GRACEFUL",      "CLUMSY" },
        { "FAST_READER",   "ILLITERATE" },
        { "SPEED_DEMON",   "SUNDAY_DRIVER" },
    }

    -- Track modifications for best-effort cleanup if suite crashes
    local activeEntry = nil

    for _, pair in ipairs(testPairs) do
        local traitA = pair[1]
        local traitB = pair[2]
        local udA = BCR.getTraitUserdata(traitA)
        local udB = BCR.getTraitUserdata(traitB)

        if not udA or not udB then
            skip(traitA .. " <-> " .. traitB, "Could not resolve trait userdata")
        else
            local hadA = BCR.playerHasTrait(player, traitA)
            local hadB = BCR.playerHasTrait(player, traitB)

            if hadA or hadB then
                skip(traitA .. " <-> " .. traitB, "Player already has one of the pair")
            else
                -- Add traitA
                local entryA = { trait = traitA, traitUserdata = udA }
                BCR.addTraitToPlayer(player, entryA)
                activeEntry = entryA

                -- Forward: traitA blocks traitB
                local blocked = BCR.hasMutuallyExclusiveTrait(player, traitB)
                assert_true(blocked, traitB .. " is blocked when " .. traitA .. " is active")

                local earnablePool = BCR.getEarnableTraits(player)
                local foundBlocked = false
                for _, e in ipairs(earnablePool) do
                    if e.trait == traitB then foundBlocked = true; break end
                end
                assert_false(foundBlocked, traitB .. " is NOT in earnable pool when " .. traitA .. " is active")

                -- Cleanup: remove traitA
                BCR.removeTraitFromPlayer(player, entryA)
                activeEntry = nil

                -- Reverse: add traitB, verify it blocks traitA
                local entryB = { trait = traitB, traitUserdata = udB }
                BCR.addTraitToPlayer(player, entryB)
                activeEntry = entryB

                local blockedRev = BCR.hasMutuallyExclusiveTrait(player, traitA)
                assert_true(blockedRev, traitA .. " is blocked when " .. traitB .. " is active (reverse)")

                local earnablePoolB = BCR.getEarnableTraits(player)
                local foundBlockedRev = false
                for _, e in ipairs(earnablePoolB) do
                    if e.trait == traitA then foundBlockedRev = true; break end
                end
                assert_false(foundBlockedRev, traitA .. " is NOT in earnable pool when " .. traitB .. " is active (reverse)")

                -- Cleanup: remove traitB
                BCR.removeTraitFromPlayer(player, entryB)
                activeEntry = nil
            end
        end
    end

    -- 3-way exclusion: FAST_READER blocks both ILLITERATE and SLOW_READER
    local udFast = BCR.getTraitUserdata("FAST_READER")
    if udFast and not BCR.playerHasTrait(player, "FAST_READER")
            and not BCR.playerHasTrait(player, "ILLITERATE")
            and not BCR.playerHasTrait(player, "SLOW_READER") then
        local entryFast = { trait = "FAST_READER", traitUserdata = udFast }
        BCR.addTraitToPlayer(player, entryFast)
        activeEntry = entryFast

        local blockedIll = BCR.hasMutuallyExclusiveTrait(player, "ILLITERATE")
        local blockedSlow = BCR.hasMutuallyExclusiveTrait(player, "SLOW_READER")
        assert_true(blockedIll, "ILLITERATE is blocked when FAST_READER is active")
        assert_true(blockedSlow, "SLOW_READER is blocked when FAST_READER is active")

        local pool = BCR.getEarnableTraits(player)
        for _, e in ipairs(pool) do
            assert_false(e.trait == "ILLITERATE", "ILLITERATE not in earnable pool with FAST_READER")
            assert_false(e.trait == "SLOW_READER", "SLOW_READER not in earnable pool with FAST_READER")
        end

        BCR.removeTraitFromPlayer(player, entryFast)
        activeEntry = nil
    else
        skip("3-way FAST_READER exclusion", "Preconditions not met")
    end

    -- Best-effort cleanup in case an intermediate assertion failed
    if activeEntry then
        logLine("  CLEANUP: Removing leftover trait: " .. activeEntry.trait)
        BCR.removeTraitFromPlayer(player, activeEntry)
    end
end


-- ============================================================
-- SUITE 7: TRAIT POOL BUILDING
-- Verify getEarnableTraits and getRemovableTraits return correct pools
-- ============================================================

local function testTraitPoolBuilding(player)
    startSuite("Trait Pool Building")

    if not player then
        skip("All pool tests", "No player available")
        return
    end

    -- Earnable pool should have entries
    local earnablePool = BCR.getEarnableTraits(player)
    assert_not_nil(earnablePool, "getEarnableTraits returns a table")
    assert_true(type(earnablePool) == "table", "Earnable pool is a table")

    logLine("  Earnable pool size: " .. #earnablePool)

    -- Each entry in pool should have required fields
    if #earnablePool > 0 then
        local first = earnablePool[1]
        assert_not_nil(first.trait, "Pool entry has 'trait' field")
        assert_not_nil(first.traitUserdata, "Pool entry has 'traitUserdata' field")
        assert_not_nil(first.cost, "Pool entry has 'cost' field")
        assert_not_nil(first.rarity, "Pool entry has 'rarity' field")
        assert_not_nil(first.weight, "Pool entry has 'weight' field")
    end

    -- No earnable trait should already be owned by the player
    for _, entry in ipairs(earnablePool) do
        local alreadyHas = BCR.playerHasTrait(player, entry.trait)
        assert_false(alreadyHas, "Earnable trait " .. entry.trait .. " is NOT already owned")
    end

    -- Removable pool: add a negative trait, then check it appears
    local testNeg = nil
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        if not BCR.playerHasTrait(player, entry.trait) then
            local ud = BCR.getTraitUserdata(entry.trait)
            if ud then
                testNeg = { trait = entry.trait, traitUserdata = ud, cost = entry.cost }
                break
            end
        end
    end

    if testNeg then
        -- Add negative trait so it appears in removable pool
        BCR.addTraitToPlayer(player, testNeg)

        local removablePool = BCR.getRemovableTraits(player)
        local foundInPool = false
        for _, entry in ipairs(removablePool) do
            if entry.trait == testNeg.trait then foundInPool = true; break end
        end
        assert_true(foundInPool, testNeg.trait .. " appears in removable pool after being added")

        -- Cleanup
        BCR.removeTraitFromPlayer(player, testNeg)

        -- After removal, it should no longer be in removable pool
        local poolAfter = BCR.getRemovableTraits(player)
        local stillInPool = false
        for _, entry in ipairs(poolAfter) do
            if entry.trait == testNeg.trait then stillInPool = true; break end
        end
        assert_false(stillInPool, testNeg.trait .. " no longer in removable pool after removal")
    else
        skip("Removable pool test", "No eligible negative trait for test")
    end

    -- Nil player should return empty table
    local nilPool = BCR.getEarnableTraits(nil)
    assert_equal(0, #nilPool, "getEarnableTraits(nil) returns empty table")

    local nilRemovable = BCR.getRemovableTraits(nil)
    assert_equal(0, #nilRemovable, "getRemovableTraits(nil) returns empty table")
end


-- ============================================================
-- SUITE 8: MILESTONE CATCH-UP (ProcessRewardDirect)
-- Verify milestone validation and reward granting in singleplayer
-- ============================================================

local function testMilestoneCatchUp(player)
    startSuite("Milestone Catch-Up (ProcessRewardDirect)")

    if not player then
        skip("All milestone tests", "No player available")
        return
    end

    if not BCR.isSinglePlayer() then
        skip("All milestone tests", "Only runs in singleplayer")
        return
    end

    if not BCR.ProcessRewardDirect then
        skip("All milestone tests", "ProcessRewardDirect not available (load BCR_Server.lua)")
        return
    end

    -- Save original ModData so we can restore it
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or not modData then
        skip("All milestone tests", "Could not access player ModData")
        return
    end
    local originalBCR = nil
    if modData.BCR then
        -- Deep-copy traitHistory entries too (shallow per-entry is fine)
        local origHistory = {}
        if modData.BCR.traitHistory then
            for _, h in ipairs(modData.BCR.traitHistory) do
                table.insert(origHistory, { trait = h.trait, action = h.action, rarity = h.rarity, timestamp = h.timestamp })
            end
        end
        originalBCR = {
            kills = modData.BCR.kills,
            rewardsGiven = modData.BCR.rewardsGiven,
            traitHistory = origHistory,
        }
    end

    local opts = BCR.getSandboxOptions()
    local bodyCount = opts.BodyCount

    logLine("  BodyCount setting: " .. bodyCount)

    -- TEST: Not enough kills = no reward
    modData.BCR = { kills = 0, rewardsGiven = 0 }
    local noKillResult = BCR.ProcessRewardDirect(player)
    assert_nil(noKillResult, "0 kills = no reward")

    -- TEST: Exactly at first milestone = reward granted
    modData.BCR = { kills = bodyCount, rewardsGiven = 0 }
    local firstReward = BCR.ProcessRewardDirect(player)
    assert_not_nil(firstReward, "Kills = BodyCount gives reward")

    if firstReward then
        assert_not_nil(firstReward.trait, "Reward has 'trait' field")
        assert_not_nil(firstReward.action, "Reward has 'action' field")
        assert_not_nil(firstReward.rarity, "Reward has 'rarity' field")
        assert_not_nil(firstReward.displayName, "Reward has 'displayName' field")
        assert_not_nil(firstReward.color, "Reward has 'color' field")

        -- Verify action is either "added" or "removed"
        assert_true(
            firstReward.action == "added" or firstReward.action == "removed",
            "Action is 'added' or 'removed' (got: " .. tostring(firstReward.action) .. ")"
        )

        logLine("  First reward: " .. firstReward.trait .. " (" .. firstReward.action .. ")")

        -- Cleanup: undo the reward so it doesn't persist
        local ud = BCR.getTraitUserdata(firstReward.trait)
        if ud then
            local cleanupEntry = { trait = firstReward.trait, traitUserdata = ud }
            if firstReward.action == "added" then
                BCR.removeTraitFromPlayer(player, cleanupEntry)
            else
                BCR.addTraitToPlayer(player, cleanupEntry)
            end
        end
    end

    -- TEST: Already claimed = no duplicate
    modData.BCR = { kills = bodyCount, rewardsGiven = 1 }
    local dupResult = BCR.ProcessRewardDirect(player)
    assert_nil(dupResult, "Already claimed milestone = no reward")

    -- TEST: Multiple milestones reached (3x BodyCount, 0 claimed)
    modData.BCR = { kills = bodyCount * 3, rewardsGiven = 0 }
    local multiResult = BCR.ProcessRewardDirect(player)
    assert_not_nil(multiResult, "3x BodyCount with 0 claimed gives reward")

    -- Cleanup: undo multi result
    if multiResult then
        local ud = BCR.getTraitUserdata(multiResult.trait)
        if ud then
            local cleanupEntry = { trait = multiResult.trait, traitUserdata = ud }
            if multiResult.action == "added" then
                BCR.removeTraitFromPlayer(player, cleanupEntry)
            else
                BCR.addTraitToPlayer(player, cleanupEntry)
            end
        end
    end

    -- TEST: Just below milestone = no reward
    modData.BCR = { kills = bodyCount - 1, rewardsGiven = 0 }
    local belowResult = BCR.ProcessRewardDirect(player)
    assert_nil(belowResult, (bodyCount - 1) .. " kills (1 below milestone) = no reward")

    -- Restore original ModData (including traitHistory)
    if originalBCR then
        modData.BCR = originalBCR
    else
        modData.BCR = { kills = 0, rewardsGiven = 0, traitHistory = {} }
    end

    logLine("  ModData restored to original state")
end


-- ============================================================
-- SUITE 9: DISPLAY NAME RESOLUTION
-- Verify getTraitDisplayName returns non-empty strings
-- ============================================================

local function testDisplayNames()
    startSuite("Display Name Resolution")

    -- Test all positive traits
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        local name = BCR.getTraitDisplayName(entry.trait)
        assert_not_nil(name, "Display name exists for: " .. entry.trait)
        assert_true(type(name) == "string" and #name > 0,
            "Display name is non-empty string for: " .. entry.trait .. " (got: '" .. tostring(name) .. "')")
    end

    -- Test all negative traits
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        local name = BCR.getTraitDisplayName(entry.trait)
        assert_not_nil(name, "Display name exists for: " .. entry.trait)
        assert_true(type(name) == "string" and #name > 0,
            "Display name is non-empty string for: " .. entry.trait .. " (got: '" .. tostring(name) .. "')")
    end

    -- Edge cases
    local nilName = BCR.getTraitDisplayName(nil)
    assert_equal("Unknown", nilName, "nil trait returns 'Unknown'")

    local fakeName = BCR.getTraitDisplayName("TOTALLY_FAKE_TRAIT")
    assert_not_nil(fakeName, "Fake trait still returns a fallback name")
    assert_true(#fakeName > 0, "Fake trait fallback is non-empty")
end


-- ============================================================
-- SUITE: SANDBOX OPTIONS
-- ============================================================

local function testSandboxOptions()
    startSuite("Sandbox Options")

    local opts = BCR.getSandboxOptions()
    assert_not_nil(opts, "getSandboxOptions returns a table")
    assert_true(type(opts.BodyCount) == "number", "BodyCount is a number")
    assert_true(opts.BodyCount >= 2, "BodyCount >= 2")
    assert_true(type(opts.givePositiveTraits) == "boolean", "givePositiveTraits is boolean")
    assert_true(type(opts.removeNegativeTraits) == "boolean", "removeNegativeTraits is boolean")
    assert_true(type(opts.grandMissedOpportunities) == "boolean", "grandMissedOpportunities is boolean")
    assert_true(type(opts.MilestoneScaling) == "number", "MilestoneScaling is a number")
    assert_true(opts.MilestoneScaling == 1 or opts.MilestoneScaling == 2, "MilestoneScaling is 1 or 2")

    -- isTraitAllowed: known traits should be allowed by default
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        assert_true(BCR.isTraitAllowed(entry.trait), "Trait allowed: " .. entry.trait)
    end
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        assert_true(BCR.isTraitAllowed(entry.trait), "Trait allowed: " .. entry.trait)
    end

    -- Fake trait still passes (no sandbox block defined)
    assert_true(BCR.isTraitAllowed("TOTALLY_FAKE_TRAIT_XYZ"), "Fake trait allowed (no block defined)")

    -- Priority values
    assert_equal(1, BCR.PRIORITY_POSITIVE_FIRST, "PRIORITY_POSITIVE_FIRST = 1")
    assert_equal(2, BCR.PRIORITY_NEGATIVE_FIRST, "PRIORITY_NEGATIVE_FIRST = 2")
    assert_equal(3, BCR.PRIORITY_RANDOM, "PRIORITY_RANDOM = 3")
end


-- ============================================================
-- SUITE: FILTER POOL BY EXCLUSION
-- ============================================================

local function testFilterPoolByExclusion()
    startSuite("Filter Pool By Exclusion")

    -- nil pool returns empty table
    local nilResult = BCR.filterPoolByExclusion(nil, {})
    assert_not_nil(nilResult, "nil pool returns a table")
    assert_equal(0, #nilResult, "nil pool returns empty table")

    -- Empty pool returns empty table
    local emptyResult = BCR.filterPoolByExclusion({}, { A = true })
    assert_equal(0, #emptyResult, "Empty pool returns empty table")

    -- nil excludeSet returns pool unchanged
    local pool = {
        { trait = "A", weight = 1 },
        { trait = "B", weight = 2 },
    }
    local noFilter = BCR.filterPoolByExclusion(pool, nil)
    assert_equal(2, #noFilter, "nil excludeSet returns full pool")

    -- Empty excludeSet returns pool unchanged
    local emptyFilter = BCR.filterPoolByExclusion(pool, {})
    assert_equal(2, #emptyFilter, "Empty excludeSet returns full pool")

    -- Single exclusion
    local singleExclude = BCR.filterPoolByExclusion(pool, { A = true })
    assert_equal(1, #singleExclude, "Single exclusion removes 1 entry")
    assert_equal("B", singleExclude[1].trait, "Remaining entry is 'B'")

    -- All excluded
    local fullExclude = BCR.filterPoolByExclusion(pool, { A = true, B = true })
    assert_equal(0, #fullExclude, "All excluded returns empty pool")
end


-- ============================================================
-- SUITE: MILESTONE MATH EDGE CASES
-- ============================================================

local function testMilestoneEdgeCases()
    startSuite("Milestone Math Edge Cases")

    local linearOpts  = { BodyCount = 100, MilestoneScaling = 1 }
    local progOpts    = { BodyCount = 100, MilestoneScaling = 2, ProgressiveScalingFactor = 0.5 }
    local defaultOpts = { BodyCount = 100 }  -- MilestoneScaling defaults to 1

    -- getKillsForMilestone edge cases
    assert_equal(0, BCR.getKillsForMilestone(0, linearOpts), "Milestone 0 = 0 kills")
    assert_equal(0, BCR.getKillsForMilestone(-1, linearOpts), "Negative milestone = 0 kills")
    assert_equal(100, BCR.getKillsForMilestone(1, linearOpts), "Milestone 1 = 100 kills (linear)")
    assert_equal(200, BCR.getKillsForMilestone(2, linearOpts), "Milestone 2 = 200 kills (linear)")

    -- Progressive scaling (factor 0.5)
    local m1 = BCR.getKillsForMilestone(1, progOpts)
    local m2 = BCR.getKillsForMilestone(2, progOpts)
    local m3 = BCR.getKillsForMilestone(3, progOpts)
    assert_equal(100, m1, "Progressive milestone 1 = 100")
    assert_true(m2 > 200, "Progressive milestone 2 > linear (" .. m2 .. " > 200)")
    assert_true(m3 > m2 + (m2 - m1), "Progressive gap grows: (" .. m1 .. " → " .. m2 .. " → " .. m3 .. ")")

    -- getMilestonesAtKills edge cases
    assert_equal(0, BCR.getMilestonesAtKills(0, linearOpts), "0 kills = 0 milestones")
    assert_equal(0, BCR.getMilestonesAtKills(-1, linearOpts), "Negative kills = 0 milestones")
    assert_equal(1, BCR.getMilestonesAtKills(100, linearOpts), "100 kills = 1 milestone")
    assert_equal(5, BCR.getMilestonesAtKills(500, linearOpts), "500 kills = 5 milestones")
    assert_equal(5, BCR.getMilestonesAtKills(599, linearOpts), "599 kills = 5 milestones (floor)")

    -- BodyCount = 0 safety
    local zeroOpts = { BodyCount = 0 }
    assert_equal(0, BCR.getKillsForMilestone(1, zeroOpts), "BodyCount 0 → milestone requires 0 kills")
    assert_equal(0, BCR.getMilestonesAtKills(1000, zeroOpts), "BodyCount 0 → 0 milestones")

    -- Missing scaling defaults to linear
    assert_equal(300, BCR.getKillsForMilestone(3, defaultOpts), "Missing MilestoneScaling defaults to linear")

    -- Progressive with factor 0
    local zeroFactorOpts = { BodyCount = 100, MilestoneScaling = 2, ProgressiveScalingFactor = 0 }
    assert_equal(200, BCR.getKillsForMilestone(2, zeroFactorOpts), "Progressive factor 0 → linear")

    -- Negative factor should behave like 0
    local negFactorOpts = { BodyCount = 100, MilestoneScaling = 2, ProgressiveScalingFactor = -1 }
    assert_equal(200, BCR.getKillsForMilestone(2, negFactorOpts), "Negative progressive factor → linear")
end


-- ============================================================
-- SUITE 10: DATA INTEGRITY CHECKS
-- Cross-validate trait lists for consistency
-- ============================================================

local function testDataIntegrity()
    startSuite("Data Integrity Checks")

    -- No duplicate traits in positive list
    local seenPositive = {}
    local dupsPositive = 0
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        if seenPositive[entry.trait] then
            dupsPositive = dupsPositive + 1
            logLine("    DUPLICATE positive: " .. entry.trait)
        end
        seenPositive[entry.trait] = true
    end
    assert_equal(0, dupsPositive, "No duplicate entries in PositiveTraitsList")

    -- No duplicate traits in negative list
    local seenNegative = {}
    local dupsNegative = 0
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        if seenNegative[entry.trait] then
            dupsNegative = dupsNegative + 1
            logLine("    DUPLICATE negative: " .. entry.trait)
        end
        seenNegative[entry.trait] = true
    end
    assert_equal(0, dupsNegative, "No duplicate entries in NegativeTraitsList")

    -- No trait appears in BOTH lists
    local overlap = 0
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        if seenNegative[entry.trait] then
            overlap = overlap + 1
            logLine("    OVERLAP: " .. entry.trait .. " in both lists!")
        end
    end
    assert_equal(0, overlap, "No trait appears in both positive and negative lists")

    -- All positive traits have negative costs
    for _, entry in ipairs(BCR.PositiveTraitsList) do
        assert_true(entry.cost < 0, "Positive trait " .. entry.trait .. " has negative cost (" .. entry.cost .. ")")
    end

    -- All negative traits have positive costs
    for _, entry in ipairs(BCR.NegativeTraitsList) do
        assert_true(entry.cost > 0, "Negative trait " .. entry.trait .. " has positive cost (" .. entry.cost .. ")")
    end

    -- Expected counts
    assert_equal(21, #BCR.PositiveTraitsList, "PositiveTraitsList has 21 entries")
    assert_equal(22, #BCR.NegativeTraitsList, "NegativeTraitsList has 22 entries")

    -- HasAvailableRewards with nil should return false
    local nilAvail = BCR.HasAvailableRewards(nil)
    assert_false(nilAvail, "HasAvailableRewards(nil) returns false")
end


-- ============================================================
-- MAIN TEST RUNNER
-- ============================================================

function BCR_RunTests()
    resetRunner()

    logLine("")
    logLine("############################################")
    logLine("# BCR UNIT TESTS - Build 42.13+")
    logLine("# Starting test run...")
    logLine("############################################")
    logLine("")

    -- Get the current player (singleplayer only)
    local player = nil
    local ok, p = pcall(function() return getPlayer and getPlayer() or nil end)
    if ok then player = p end
    if not player then
        logLine("WARNING: No player found. Player-dependent tests will be skipped.")
        logLine("         Run these tests from an active singleplayer game.")
        logLine("")
    end

    -- Run a suite in protected mode — one suite crash won't kill the run
    local function runSuite(name, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then
            logLine("  SUITE CRASHED: " .. name .. " — " .. tostring(err))
            TestRunner.failed = TestRunner.failed + 1
            table.insert(TestRunner.errors, name .. " crashed: " .. tostring(err))
        end
    end

    runSuite("Trait Registry Resolution", testTraitRegistryResolution)
    runSuite("Rarity and Weight Calculations", testRarityAndWeight)
    runSuite("Mutually Exclusive Trait Validation", testMutualExclusions)
    runSuite("Weighted Random Selection", testWeightedRandomSelection)
    runSuite("Display Name Resolution", testDisplayNames)
    runSuite("Data Integrity Checks", testDataIntegrity)
    runSuite("Sandbox Options", testSandboxOptions)
    runSuite("Filter Pool By Exclusion", testFilterPoolByExclusion)
    runSuite("Milestone Math Edge Cases", testMilestoneEdgeCases)
    runSuite("Add and Remove Traits", testAddRemoveTraits, player)
    runSuite("Mutual Exclusion Enforcement", testMutualExclusionEnforcement, player)
    runSuite("Trait Pool Building", testTraitPoolBuilding, player)
    runSuite("Milestone Catch-Up", testMilestoneCatchUp, player)

    if TestRunner.failed > 0 then
        logLine("")
        logLine("NOTE: Some tests failed. If mutation tests failed, the player may be in")
        logLine("      a modified state. Restart the game to get a clean character.")
    end

    printSummary()

    return TestRunner.failed == 0
end


-- ============================================================
-- AUTO-RUN HINT
-- ============================================================

print("[BCR_Test] Test module loaded. Type BCR_RunTests() in the debug console to execute all tests.")
