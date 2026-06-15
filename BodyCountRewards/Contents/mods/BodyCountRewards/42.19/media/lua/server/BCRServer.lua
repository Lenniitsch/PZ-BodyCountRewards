-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRServer (Build 42.19+)
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
    local kills = bcrData.kills or 0
    if not kills then return false, 0 end
    local milestonesAtKills = BCR.GetMilestonesAtKills(kills, opts)
    local currentRewards = bcrData.rewardsGiven or 0
    if milestonesAtKills <= currentRewards then
        return false, 0
    end
    local missed = milestonesAtKills - currentRewards
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
-- SP DIRECT PATH
-- ============================================================

function BCR.ProcessRewardDirect(player)
    if not player then return nil end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then
        print("[BCR] ProcessRewardDirect: no ModData")
        return nil
    end
    local opts = BCR.opts
    if not opts then
        BCR.RefreshConfig()
        opts = BCR.opts
    end
    local canClaim, missedCount = validateMilestone(player, bcrData, opts)
    if not canClaim then return nil end
    local rewardsToGive = missedCount
    local results = {}
    local appliedThisBatch = {}
    local earnablePool = BCR.BuildEarnablePool(player, nil)
    local removablePool = BCR.BuildRemovablePool(player, nil)
    for _ = 1, rewardsToGive do
        local applied = buildAndApplyReward(player, earnablePool, removablePool, opts, appliedThisBatch)
        if applied then
            appliedThisBatch[applied.id] = true
            bcrData.rewardsGiven = (bcrData.rewardsGiven or 0) + 1
            recordTraitHistory(bcrData, applied)
            table.insert(results, applied)
        end
    end
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
    BCR.DebugPrint("[Server] RequestReward received from: " .. who)
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then
        sendServerCommand(player, "BCR", "RewardError", { reason = "no_moddata" })
        return
    end
    local opts = BCR.opts
    if not opts then
        BCR.RefreshConfig()
        opts = BCR.opts
    end

    if not opts.enablePositive and not opts.enableNegative then
        print("[BCR] [Server] Both trait rewards are disabled in sandbox options")
        sendServerCommand(player, "BCR", "RewardError", {
            reason = "rewards_disabled",
        })
        return
    end

    local serverKills = getZombieKillsSafe(player) or 0
    local reportedKills = type(args.kills) == "number" and math.floor(args.kills) or 0
    local bestKills = math.max(bcrData.kills or 0, reportedKills, serverKills)
    if bestKills > (bcrData.kills or 0) then
        bcrData.kills = bestKills
    end
    local canClaim, missedCount = validateMilestone(player, bcrData, opts)
    if not canClaim then
        sendServerCommand(player, "BCR", "RewardError", {
            reason = "Milestone not reached",
        })
        return
    end
    local rewardsToGive = missedCount
    local appliedThisBatch = {}
    local totalGranted = 0
    local earnablePool = BCR.BuildEarnablePool(player, nil)
    local removablePool = BCR.BuildRemovablePool(player, nil)
    for _ = 1, rewardsToGive do
        local applied = buildAndApplyReward(player, earnablePool, removablePool, opts, appliedThisBatch)
        if applied then
            appliedThisBatch[applied.id] = true
            bcrData.rewardsGiven = (bcrData.rewardsGiven or 0) + 1
            recordTraitHistory(bcrData, applied)
            totalGranted = totalGranted + 1
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
    end
    local milestonesEarned = BCR.GetMilestonesAtKills(bcrData.kills or 0, opts)
    local remainingMilestones = milestonesEarned - (bcrData.rewardsGiven or 0)
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
        handleRequestReward(player, args)
    end
end)
