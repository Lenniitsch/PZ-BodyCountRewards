-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRServer (Build 42.19+)
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
    if not ok then return nil end
    return kills or 0
end

local function getWorldAgeHoursSafe()
    local ok, result = pcall(function()
        local gt = getGameTime()
        return gt and gt:getWorldAgeHours() or 0
    end)
    if ok then return result or 0 end
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

local function recordTraitHistory(bcrData, result)
    if not bcrData or not result then return end
    if not bcrData.traitHistory then
        bcrData.traitHistory = {}
    end
    table.insert(bcrData.traitHistory, {
        id = result.id,
        action = result.action,
        rarity = result.rarity,
        timestamp = getWorldAgeHoursSafe(),
        source = BCR.CustomTraitSources and BCR.CustomTraitSources[result.id],
    })
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
            BCR.DebugPrint("Server", "ReconcileTraitState: engine state unreadable for " .. tostring(traitId) .. " -- skipping")
        elseif has == true and last == nil then
            -- Starting or externally gained trait -- record a baseline
            -- entry so it can never be granted again. (Baseline entries
            -- are hidden in the history UI.)
            recordTraitHistory(bcrData, { id = traitId, action = "baseline", rarity = "unknown" })
            changed = true
        elseif has == true and (last == "removed" or last == "lost") then
            -- Admin or another mod re-granted a previously removed/lost trait
            recordTraitHistory(bcrData, { id = traitId, action = "added", rarity = "unknown" })
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
                    rarity = entry and BCR.GetRarity(entry.cost) or "unknown",
                })
                changed = true
            elseif not opts.restoreMissingTraits then
                recordTraitHistory(bcrData, {
                    id = traitId,
                    action = "lost",
                    rarity = entry and BCR.GetRarity(entry.cost) or "unknown",
                })
                changed = true
            else
                BCR.DebugPrint("Server", "ReconcileTraitState: restore failed/blocked for " .. tostring(traitId) .. " -- will retry on next check")
            end
        end
    end

    if changed and isServer() then
        pcall(function() player:transmitModData() end)
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
    return results
end

-- ============================================================
-- MP KILL SYNC -- server-side kill counter is authoritative in MP
-- (zombie simulation runs on the server). Client-reported numbers
-- are ignored.
-- ============================================================

local function syncAuthoritativeKills(player, bcrData)
    local serverKills = getZombieKillsSafe(player) or 0
    if serverKills > (bcrData.kills or 0) then
        bcrData.kills = serverKills
    end
    return bcrData.kills
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
            pcall(function() player:transmitModData() end)
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
    BCR.DebugPrint("Server", "RequestReward received from: " .. who)
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then
        sendServerCommand(player, "BCR", "RewardError", { reason = "no_moddata" })
        return
    end
    local opts = BCR.GetOpts()

    -- Rate limit: the client paces its requests at ~1.5s, so a 1-second
    -- cooldown only blocks spam, never legit flow. A silent return is
    -- safe -- the client re-requests on its next pending tick.
    local now = getWorldAgeHoursSafe()
    if bcrData.lastRewardRequest and (now - bcrData.lastRewardRequest) * 3600 < BCR.REWARD_REQUEST_COOLDOWN_SECONDS then
        return
    end
    bcrData.lastRewardRequest = now

    if not opts.enablePositive and not opts.enableNegative then
        print("[BCR] [Server] Both trait rewards are disabled in sandbox options")
        sendServerCommand(player, "BCR", "RewardError", {
            reason = "rewards_disabled",
        })
        return
    end

    syncAuthoritativeKills(player, bcrData)
    local canClaim, missedCount = validateMilestone(player, bcrData, opts)
    if not canClaim then
        sendServerCommand(player, "BCR", "RewardError", {
            reason = "Milestone not reached",
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
        sendServerCommand(player, "BCR", "RewardGranted", {
            id = applied.id,
            displayName = applied.displayName,
            action = applied.action,
            rarity = applied.rarity,
            color = applied.color,
        })
    end
    local milestonesEarned = BCR.GetMilestonesAtKills(bcrData.kills or 0, opts)
    local remainingMilestones = math.max(0, milestonesEarned - (bcrData.rewardsGiven or 0))
    if isServer() then
        pcall(function() player:transmitModData() end)
    end
    sendServerCommand(player, "BCR", "RewardBatchComplete", {
        totalGranted = totalGranted,
        remainingMilestones = remainingMilestones,
        rewardsGiven = bcrData.rewardsGiven or 0,
    })
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "BCR" then return end
    if command == "RequestReward" then
        local ok, err = pcall(handleRequestReward, player, args)
        if not ok then
            print("[BCR] [Server] RequestReward error: " .. tostring(err))
        end
    end
end)
