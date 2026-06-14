-- ============================================================
-- BodyCountRewards v1.3.0 — BCRClient (Build 42.19+)
-- Update loop, kill tracking, reward requesting, context menu,
-- event registration.
-- ============================================================

require "BCRCore"
require "BCRNotifications"
require "BCRStatsUI"

local bcrModConfig = require "BCRModOptions"

BCR = BCR or {}

-- ============================================================
-- CONSTANTS
-- ============================================================

local PENDING_REWARD_DELAY_TICKS = 90
local NOTIFICATION_DELAY_TICKS = 200

-- ============================================================
-- STATE VARIABLES
-- ============================================================

local lastKnownKills = 0
local pendingRewardsCount = 0
local pendingRewardTimer = 0
local isPendingRequestInFlight = false
local hasShownAllTraitsMessage = false
local shouldShowFinalMessage = false
local showFinalMessageTimer = 0
local rewardsExhausted = false

-- ============================================================
-- HELPERS
-- ============================================================

local function isSinglePlayer()
    return not isClient() and not isServer()
end

local function getLocalPlayer()
    return getSpecificPlayer(0)
end

local function resetState()
    lastKnownKills = 0
    pendingRewardsCount = 0
    pendingRewardTimer = 0
    isPendingRequestInFlight = false
    hasShownAllTraitsMessage = false
    shouldShowFinalMessage = false
    showFinalMessageTimer = 0
    rewardsExhausted = false
end

local function countMissedMilestones(bcrData, opts)
    local player = getLocalPlayer()
    if not player then return 0 end
    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok then return 0 end
    local milestonesAtKills = BCR.GetMilestonesAtKills(kills, opts)
    local currentRewards = bcrData.rewardsGiven or 0
    return math.max(0, milestonesAtKills - currentRewards)
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

function BCR_OnCreatePlayer(playerNum, player)
    BCR.RefreshConfig()
    if not player then return end

    BCR.DebugPrint("[Client] Player created - initializing BCR")

    resetState()

    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end

    local ok, kills = pcall(function() return player:getZombieKills() end)
    local rewardsGiven = bcrData.rewardsGiven or 0
    if ok and kills then
        if bcrData.kills == 0 and kills > 0 then
            bcrData.kills = kills
        end
    end

    local traitCount = bcrData.traitHistory and #bcrData.traitHistory or 0
    BCR.DebugPrint(string.format(
        "[Client] onCreatePlayer: kills=%d, rewardsGiven=%d, traits=%d",
        kills or 0, rewardsGiven, traitCount
    ))

    if not BCR.HasAvailableRewards(player) then
        hasShownAllTraitsMessage = true
        BCR.DebugPrint("[Client] onCreatePlayer: all rewards exhausted — skipping future processing")
    end
end

local function requestReward(player, bcrData)
    if not player then
        BCR.DebugPrint("[Client] requestReward called with nil player")
        return
    end
    BCR.DebugPrint("[Client] Requesting reward...")
    local ok, result = pcall(BCR.ProcessRewardDirect, player)
    if not ok or not result then
        BCR.DebugPrint("[Client] SP Reward skipped: " .. tostring(result or ok))
        return
    end
    BCR.EnqueueNotification(result)
    BCR.RefreshStatsWindow()
    BCR.DebugPrint("[Client] SP Reward granted: " .. tostring(result.id) .. " (" .. tostring(result.action) .. ")")
    if not hasShownAllTraitsMessage and not BCR.HasAvailableRewards(player) then
        BCR.DebugPrint("[Client] No more rewards available - scheduling final message")
        rewardsExhausted = true
        shouldShowFinalMessage = true
        showFinalMessageTimer = 0
    end
end

function BCR_OnPlayerUpdate(player)
    if not player then return end
    if player:isDead() then return end
    if hasShownAllTraitsMessage then return end
    if BCR.opts == nil then
        BCR.RefreshConfig()
    end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end
    local ok, currentKills = pcall(function() return player:getZombieKills() end)
    if not ok then return end
    if lastKnownKills == nil then
        lastKnownKills = bcrData.kills or currentKills or 0
    end
    if currentKills > lastKnownKills then
        bcrData.kills = currentKills
        local newKills = currentKills - lastKnownKills
        BCR.DebugPrint(string.format("[Client] +%d kill(s) - Total: %d", newKills, currentKills))
        local milestonesAtKills = BCR.GetMilestonesAtKills(currentKills, BCR.opts)
        local currentRewards = bcrData.rewardsGiven or 0
        if milestonesAtKills > currentRewards and not rewardsExhausted then
            BCR.DebugPrint("[Client] Milestone reached at " .. currentKills .. " kills!")
            if isSinglePlayer() then
                local missed = countMissedMilestones(bcrData, BCR.opts)
                if missed > 1 then
                    BCR.DebugPrint("[Client] Found " .. missed .. " milestones to claim")
                    pendingRewardsCount = missed
                    pendingRewardTimer = 0
                    local msg = missed .. " " .. (getText("UI_BCR_PendingRewards") or "rewards earned!")
                    HaloTextHelper.addText(player, msg, "", 255, 255, 255)
                else
                    if not isPendingRequestInFlight then
                        isPendingRequestInFlight = true
                        requestReward(player, bcrData)
                        isPendingRequestInFlight = false
                    end
                end
            else
                if not isPendingRequestInFlight then
                    isPendingRequestInFlight = true
                    sendClientCommand(player, "BCR", "RequestReward", { kills = currentKills })
                end
            end
        end
    end
    if pendingRewardsCount > 0 then
        pendingRewardTimer = pendingRewardTimer + 1
        if pendingRewardTimer >= PENDING_REWARD_DELAY_TICKS then
            pendingRewardTimer = 0
            if isSinglePlayer() and not isPendingRequestInFlight then
                isPendingRequestInFlight = true
                pendingRewardsCount = pendingRewardsCount - 1
                local ok, result = pcall(BCR.ProcessRewardDirect, player)
                if not ok or not result then
                    pendingRewardsCount = pendingRewardsCount + 1
                    isPendingRequestInFlight = false
                    BCR.DebugPrint("OnPlayerUpdate: ProcessRewardDirect error: " .. tostring(result or ok))
                else
                    isPendingRequestInFlight = false
                    BCR.EnqueueNotification(result)
                    BCR.RefreshStatsWindow()
                    if not BCR.HasAvailableRewards(player) then
                        rewardsExhausted = true
                        shouldShowFinalMessage = true
                        showFinalMessageTimer = 0
                    end
                end
            elseif not isSinglePlayer() and not isPendingRequestInFlight then
                isPendingRequestInFlight = true
                sendClientCommand(player, "BCR", "RequestReward", { kills = currentKills })
            end
        end
    end
    BCR.UpdateNotifications(player)
    if shouldShowFinalMessage then
        showFinalMessageTimer = showFinalMessageTimer + 1
        if showFinalMessageTimer >= NOTIFICATION_DELAY_TICKS then
            BCR.ShowFinalMessage(player)
            shouldShowFinalMessage = false
            showFinalMessageTimer = 0
            hasShownAllTraitsMessage = true
            BCR.DebugPrint("[Client] Final message shown - no more reward processing")
        end
    end
    lastKnownKills = currentKills
end

function BCR_OnServerCommand(module, command, args)
    if module ~= "BCR" then return end
    local player = getLocalPlayer()
    if not player then return end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end
    if command == "RewardGranted" then
        BCR.DebugPrint("[Client] Server command: RewardGranted")
        bcrData.rewardsGiven = (bcrData.rewardsGiven or 0) + 1
        BCR.EnqueueNotification(args)
        BCR.RefreshStatsWindow()
        if not BCR.HasAvailableRewards(player) then
            rewardsExhausted = true
            shouldShowFinalMessage = true
            showFinalMessageTimer = 0
        end
    elseif command == "RewardBatchComplete" then
        isPendingRequestInFlight = false
        if args.remainingMilestones then
            pendingRewardsCount = args.remainingMilestones
        end
        BCR.DebugPrint(string.format(
            "[Client] Batch complete: %d granted, %d milestones remaining",
            args.totalGranted or 0, args.remainingMilestones or 0
        ))
        local rewardsGiven = args.rewardsGiven
        if rewardsGiven and rewardsGiven > (bcrData.rewardsGiven or 0) then
            bcrData.rewardsGiven = rewardsGiven
        end
    elseif command == "KillsSynced" then
        BCR.DebugPrint("[Client] Server command: KillsSynced")
        if args.kills then
            bcrData.kills = args.kills
            if args.kills > lastKnownKills then
                lastKnownKills = args.kills
            end
        end
        local rewardsGiven = args.rewardsGiven
        if rewardsGiven and rewardsGiven > (bcrData.rewardsGiven or 0) then
            bcrData.rewardsGiven = rewardsGiven
        end
    elseif command == "RewardError" then
        BCR.DebugPrint(string.format("[Client] Reward error: %s", tostring(args.reason)))
        isPendingRequestInFlight = false
        pendingRewardsCount = 0
    elseif command == "NoRewardAvailable" then
        BCR.DebugPrint(string.format("[Client] No rewards available: %s", tostring(args.reason)))
        isPendingRequestInFlight = false
        pendingRewardsCount = 0
    end
end

function BCR_OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return true end
    if not bcrModConfig.showContextMenu then return end

    local player = getSpecificPlayer(playerNum)
    if not player then return end

    local bcrData = BCR.EnsureModData(player)
    BCR.RefreshConfig()
    local opts = BCR.opts
    if not opts then return end

    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok then return end
    local currentKills = kills or 0

    local label = getText("UI_BCR_MenuTitle") or "Body Count Rewards"
    local bcrOption = context:addOption(label, nil, nil)
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(bcrOption, subMenu)

    subMenu:addOption(
        getText("UI_BCR_ViewStats") or "View Stats...",
        player,
        BCR.ShowStatsWindow
    )

    if hasShownAllTraitsMessage or not BCR.HasAvailableRewards(player) then
        local exhaustedText = getText("UI_BCR_AllRewardsGranted") or "All rewards granted!"
        local exhaustedOption = subMenu:addOption(exhaustedText, nil, nil)
        exhaustedOption.notAvailable = true
    else
        local rewardsGiven = bcrData and bcrData.rewardsGiven or 0
        local milestonesAtKills = BCR.GetMilestonesAtKills(currentKills, opts)
        local nextMilestone = BCR.GetKillsForMilestone(rewardsGiven + 1, opts)
        local killsRemaining = math.max(0, nextMilestone - currentKills)

        local progressText = (getText("UI_BCR_Progress") or "Progress") .. ": "
            .. tostring(currentKills) .. " / " .. tostring(nextMilestone)
        local progressOption = subMenu:addOption(progressText, nil, nil)
        progressOption.notAvailable = true

        local remainingText = (getText("UI_BCR_NextReward") or "Next reward") .. ": "
            .. tostring(killsRemaining) .. " " .. (getText("UI_BCR_Kills") or "kills")
        local remainingOption = subMenu:addOption(remainingText, nil, nil)
        remainingOption.notAvailable = true
    end
end

-- ============================================================
-- EVENT REGISTRATION
-- ============================================================

Events.OnCreatePlayer.Add(function(playerNum, player)
    local ok, err = pcall(function() BCR_OnCreatePlayer(playerNum, player) end)
    if not ok then BCR.DebugPrint("OnCreatePlayer error: " .. tostring(err)) end
end)

Events.OnPlayerUpdate.Add(function(player)
    local ok, err = pcall(function() BCR_OnPlayerUpdate(player) end)
    if not ok then BCR.DebugPrint("OnPlayerUpdate error: " .. tostring(err)) end
end)

Events.OnServerCommand.Add(function(module, command, args)
    local ok, err = pcall(function() BCR_OnServerCommand(module, command, args) end)
    if not ok then BCR.DebugPrint("OnServerCommand error: " .. tostring(err)) end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
    local ok, err = pcall(function() BCR_OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test) end)
    if not ok then BCR.DebugPrint("OnFillWorldObjectContextMenu error: " .. tostring(err)) end
end)
