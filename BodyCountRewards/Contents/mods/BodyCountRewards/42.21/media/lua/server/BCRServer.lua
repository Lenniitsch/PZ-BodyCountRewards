-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRServer (Build 42.21+)
-- Reward processor, milestone validation, batch logic,
-- MP commands, SP direct path, kill sync, anti-cheat.
-- ============================================================

if isClient() and not isServer() then return end

require "BCRCore"

BCR = BCR or {}

-- ============================================================
-- PRIVATE HELPERS
-- ============================================================

local function getZombieKillsSafe(player)
    if not player then return nil end
    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok then
        BCR.DebugPrintf("Server", "getZombieKills failed: %s", tostring(kills))
        return nil
    end
    return kills or 0
end

local function getWorldAgeHoursSafe()
    local ok, result = pcall(function()
        local gt = getGameTime()
        return gt and gt:getWorldAgeHours() or 0
    end)
    if ok then return result or 0 end
    BCR.DebugPrintf("Server", "getWorldAgeHours failed: %s", tostring(result))
    return 0
end

local function validateMilestone(player, bcrData, opts)
    if not player or not bcrData or not opts then
        return false, 0
    end
    local missed = BCR.GetMissedMilestoneCount(bcrData, bcrData.kills, opts)
    if missed <= 0 then
        return false, 0
    end
    if missed > 1 and not opts.grantMissedOpportunities then
        return true, 1
    end
    return true, missed
end

local function recordTraitHistory(bcrData, reward)
    if not bcrData or not reward then return end
    if not bcrData.traitHistory then
        bcrData.traitHistory = {}
    end
    table.insert(bcrData.traitHistory, {
        id = reward.id,
        action = reward.action,
        rarity = reward.rarity,
        timestamp = getWorldAgeHoursSafe(),
        source = BCR.CustomTraitSources and BCR.CustomTraitSources[reward.id],
    })
    -- Bound the history so the per-trait scans stay cheap on long saves.
    if #bcrData.traitHistory > BCR.MAX_TRAIT_HISTORY then
        table.remove(bcrData.traitHistory, 1)
    end
end

-- ============================================================
-- TRAIT STATE RECONCILIATION -- server-authoritative. Compares
-- BCR's own grant history against the player's live trait state
-- and repairs mismatches.
-- ============================================================

local function findTraitEntry(traitId)
    for _, entry in ipairs(BCR.MergedPositiveTraits) do
        if entry.id == traitId then return entry end
    end
    for _, entry in ipairs(BCR.MergedNegativeTraits) do
        if entry.id == traitId then return entry end
    end
    return nil
end

function BCR.ReconcileTraitState(player, bcrData, opts)
    if not player or not bcrData or not opts then return false end
    -- Run everywhere except pure MP clients. SP has isServer() == false
    -- and isClient() == false, so the old `not isServer()` guard made
    -- this dead in singleplayer.
    if isClient() and not isServer() then return false end

    local changed = false

    local allTraitIds = {}
    for _, entry in ipairs(BCR.MergedPositiveTraits) do
        if entry.id then allTraitIds[entry.id] = true end
    end
    for _, entry in ipairs(BCR.MergedNegativeTraits) do
        if entry.id then allTraitIds[entry.id] = true end
    end

    for traitId in pairs(allTraitIds) do
        local last = BCR.GetLastHistoryAction(bcrData.traitHistory, traitId)
        local has = BCR.PlayerHasTrait(player, traitId)
        if has == nil then
            BCR.DebugPrintf("Server", "ReconcileTraitState: engine state unreadable for %s -- skipping", tostring(traitId))
        elseif has == true and last == nil then
            -- Starting or externally gained trait -- record a baseline
            -- entry so it can never be granted again. (Baseline entries
            -- are hidden in the history UI.)
            recordTraitHistory(bcrData, { id = traitId, action = "baseline", rarity = BCR.RARITY_UNKNOWN })
            changed = true
        elseif has == true and (last == "removed" or last == "lost") then
            -- Admin or another mod re-granted a previously removed/lost trait
            recordTraitHistory(bcrData, { id = traitId, action = "added", rarity = BCR.RARITY_UNKNOWN })
            changed = true
        elseif has == false and (last == "added" or last == "baseline") then
            -- History says owned but the trait is missing.
            -- (last == "removed"/"lost" are terminal states and can
            -- never reach this branch.)
            local entry = findTraitEntry(traitId)
            local restored = false
            if opts.restoreMissingTraits and BCR.IsTraitAllowed(traitId) and entry then
                restored = BCR.AddTrait(player, entry)
            end
            if restored then
                recordTraitHistory(bcrData, {
                    id = traitId,
                    action = "added",
                    rarity = entry and BCR.GetRarity(entry.cost) or BCR.RARITY_UNKNOWN,
                })
                changed = true
            elseif not opts.restoreMissingTraits then
                recordTraitHistory(bcrData, {
                    id = traitId,
                    action = "lost",
                    rarity = entry and BCR.GetRarity(entry.cost) or BCR.RARITY_UNKNOWN,
                })
                changed = true
            else
                BCR.DebugPrintf("Server", "ReconcileTraitState: restore failed/blocked for %s -- will retry on next check", tostring(traitId))
            end
        end
    end

    if changed and isServer() then
        local txOk, txErr = pcall(function() player:transmitModData() end)
        if not txOk then
            BCR.DebugPrintf("Server", "transmitModData failed: %s", tostring(txErr))
        end
    end
    return changed
end

local function buildAndApplyReward(player, earnablePool, removablePool, opts, appliedThisBatch)
    if not player or not opts then return nil end

    local filteredEarnable = BCR.FilterPoolByExclusion(earnablePool, appliedThisBatch)
    local filteredRemovable = BCR.FilterPoolByExclusion(removablePool, appliedThisBatch)

    local candidates = {}
    local priority = opts.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST

    if priority == BCR.PRIORITY_RANDOM then
        priority = ZombRand(2) == 1 and BCR.PRIORITY_POSITIVE_FIRST or BCR.PRIORITY_NEGATIVE_FIRST
    end

    local firstChoice, secondChoice
    if priority == BCR.PRIORITY_POSITIVE_FIRST then
        firstChoice = { pool = filteredEarnable, action = "added", enabled = opts.enablePositive ~= false }
        secondChoice = { pool = filteredRemovable, action = "removed", enabled = opts.enableNegative ~= false }
    else
        firstChoice = { pool = filteredRemovable, action = "removed", enabled = opts.enableNegative ~= false }
        secondChoice = { pool = filteredEarnable, action = "added", enabled = opts.enablePositive ~= false }
    end

    for _, choice in ipairs({ firstChoice, secondChoice }) do
        if choice.enabled then
            local selected = BCR.WeightedRandomSelect(choice.pool)
            if selected then
                local success = false
                if choice.action == "added" then
                    success = BCR.AddTrait(player, selected)
                else
                    success = BCR.RemoveTrait(player, selected)
                end
                if success then
                    return {
                        id = selected.id,
                        displayName = BCR.GetTraitDisplayName(selected.id),
                        action = choice.action,
                        rarity = selected.rarity,
                        color = BCR.GetRarityColor(selected.cost),
                        cost = selected.cost,
                    }
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- REWARD BATCH -- shared by the SP direct path and the MP command
-- handler. Returns the list of applied rewards.
-- ============================================================

local function applyRewardBatch(player, bcrData, opts, rewardsToGive)
    local results = {}
    local appliedThisBatch = {}
    local earnablePool = BCR.BuildEarnablePool(player, nil)
    local removablePool = BCR.BuildRemovablePool(player, nil)
    for _ = 1, rewardsToGive do
        local applied = buildAndApplyReward(player, earnablePool, removablePool, opts, appliedThisBatch)
        if not applied then
            break
        end
        appliedThisBatch[applied.id] = true
        bcrData.rewardsGiven = (bcrData.rewardsGiven or 0) + 1
        recordTraitHistory(bcrData, applied)
        table.insert(results, applied)
    end
    BCR.ConsumeWithheldMilestones(bcrData, #results, opts)
    return results
end

-- ============================================================
-- MP KILL SYNC -- server-side kill counter is authoritative in MP
-- (zombie simulation runs on the server). Client-reported numbers
-- are ignored.
-- ============================================================

-- The engine counter always wins: stored ModData is client-writable and
-- must never raise the kill count above what the server simulated.
function BCR.SyncAuthoritativeKills(player, bcrData)
    if not bcrData then return 0 end
    local serverKills = getZombieKillsSafe(player) or 0
    bcrData.kills = serverKills
    return serverKills
end

-- ============================================================
-- RETROACTIVE REWARDS WITHHOLDING -- while the option is off,
-- every load moves whatever is still owed into the withheld pool.
-- Withheld milestones are not granted; switching the option on
-- releases them. Returns true when the pool grew.
-- ============================================================

function BCR.CaptureWithheldBaseline(player, bcrData, opts)
    if not bcrData or not opts then return false end
    if opts.grantMissedOpportunities then return false end
    local kills = getZombieKillsSafe(player) or 0
    local reached = BCR.GetMilestonesAtKills(kills, opts)
    local rewarded = bcrData.rewardsGiven or 0
    local withheld = bcrData.withheldMilestones or 0
    local owed = reached - rewarded - withheld
    if owed <= 0 then return false end
    bcrData.withheldMilestones = withheld + owed
    return true
end

-- ============================================================
-- SP DIRECT PATH
-- ============================================================

function BCR.ProcessRewardDirect(player)
    if not player then return nil end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then
        print("[BCR] [Server] ProcessRewardDirect: no ModData")
        return nil
    end
    local opts = BCR.GetOpts()
    local canClaim, missedCount = validateMilestone(player, bcrData, opts)
    if not canClaim then return nil end
    BCR.ReconcileTraitState(player, bcrData, opts)
    local results = applyRewardBatch(player, bcrData, opts, math.min(missedCount, BCR.MAX_BATCH_REWARDS))
    if #results > 0 then
        if isServer() then
            local txOk, txErr = pcall(function() player:transmitModData() end)
            if not txOk then
                BCR.DebugPrintf("Server", "transmitModData failed: %s", tostring(txErr))
            end
        end
    end
    return results
end

-- ============================================================
-- MP HANDLERS
-- ============================================================

local function handleRequestReward(player, args)
    if not player or not args then return end
    local ok, username = pcall(function() return tostring(player:getUsername()) end)
    local who = ok and username or "unknown"
    BCR.DebugPrintf("Server", "RequestReward received from: %s", who)
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then
        sendServerCommand(player, BCR.MODULE_NAME, "RewardError", { reason = "no_moddata" })
        return
    end
    local opts = BCR.GetOpts()

    -- Rate limit: the client paces its requests at ~1.5s, so a 1-second
    -- cooldown only blocks spam, never legit flow. A silent return is
    -- safe -- the client re-requests on its next pending tick.
    local now = getWorldAgeHoursSafe()
    local previousRequest = bcrData.lastRewardRequest
    -- Only rate-limit on a clock that moved forward: a rollback, a new world,
    -- or an unreadable clock must not lock the player out of rewards.
    if previousRequest and now > previousRequest
        and (now - previousRequest) * BCR.SECONDS_PER_HOUR < BCR.REWARD_REQUEST_COOLDOWN_SECONDS then
        return
    end
    bcrData.lastRewardRequest = now

    if not opts.enablePositive and not opts.enableNegative then
        print("[BCR] [Server] Both trait rewards are disabled in sandbox options")
        sendServerCommand(player, BCR.MODULE_NAME, "RewardError", {
            reason = "rewards_disabled",
        })
        return
    end

    BCR.SyncAuthoritativeKills(player, bcrData)
    local canClaim, missedCount = validateMilestone(player, bcrData, opts)
    if not canClaim then
        -- Nothing owed right now (for example a withheld backlog).
        -- Report it as a normal empty batch so the client stops asking
        -- without logging an error.
        sendServerCommand(player, BCR.MODULE_NAME, "RewardBatchComplete", {
            totalGranted = 0,
            remainingMilestones = 0,
            rewardsGiven = bcrData.rewardsGiven or 0,
            withheldMilestones = bcrData.withheldMilestones,
        })
        return
    end
    BCR.ReconcileTraitState(player, bcrData, opts)
    local results = applyRewardBatch(player, bcrData, opts, math.min(missedCount, BCR.MAX_BATCH_REWARDS))
    local totalGranted = #results
    for _, applied in ipairs(results) do
        print(string.format(
            "[BCR] [Server] Reward granted to %s: %s (%s) - %s",
            who, applied.id, applied.action, applied.rarity
        ))
        -- Send identity and action only: the client resolves the display
        -- name and colors locally, so each player sees their own language.
        sendServerCommand(player, BCR.MODULE_NAME, "RewardGranted", {
            id = applied.id,
            action = applied.action,
        })
    end
    local remainingMilestones = BCR.GetMissedMilestoneCount(bcrData, bcrData.kills or 0, opts)
    if isServer() then
        local txOk, txErr = pcall(function() player:transmitModData() end)
        if not txOk then
            BCR.DebugPrintf("Server", "transmitModData failed: %s", tostring(txErr))
        end
    end
    sendServerCommand(player, BCR.MODULE_NAME, "RewardBatchComplete", {
        totalGranted = totalGranted,
        remainingMilestones = remainingMilestones,
        rewardsGiven = bcrData.rewardsGiven or 0,
        withheldMilestones = bcrData.withheldMilestones,
    })
end

-- MP clients announce themselves once per session so the server can
-- capture the withheld baseline before the first kill. The reply
-- carries the authoritative values for the client mirror.
local function handlePlayerReady(player)
    if not player then return end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end
    local opts = BCR.GetOpts()
    BCR.SyncAuthoritativeKills(player, bcrData)
    BCR.CaptureWithheldBaseline(player, bcrData, opts)
    if isServer() then
        local txOk, txErr = pcall(function() player:transmitModData() end)
        if not txOk then
            BCR.DebugPrintf("Server", "transmitModData failed: %s", tostring(txErr))
        end
    end
    sendServerCommand(player, BCR.MODULE_NAME, "PlayerSync", {
        kills = bcrData.kills or 0,
        rewardsGiven = bcrData.rewardsGiven or 0,
        withheldMilestones = bcrData.withheldMilestones,
    })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= BCR.MODULE_NAME then return end
    if command == "RequestReward" then
        local ok, err = pcall(handleRequestReward, player, args)
        if not ok then
            print("[BCR] [Server] RequestReward error: " .. tostring(err))
        end
    elseif command == "PlayerReady" then
        local ok, err = pcall(handlePlayerReady, player)
        if not ok then
            print("[BCR] [Server] PlayerReady error: " .. tostring(err))
        end
    end
end)
