-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRClient (Build 42.19+)
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
local MP_REQUEST_TIMEOUT_TICKS = 300
local REEXHAUST_CHECK_TICKS = 60
local MAX_PENDING_STALLS = 3
local PLAYER_READY_MAX_ATTEMPTS = 3
local PLAYER_READY_RETRY_TICKS = 60

-- ============================================================
-- STATE VARIABLES
-- ============================================================

local lastKnownKills = 0
local pendingRewardsCount = 0
local pendingRewardTimer = 0
local isPendingRequestInFlight = false
local pendingRequestTimer = 0
local hasShownAllTraitsMessage = false
local shouldShowFinalMessage = false
local showFinalMessageTimer = 0
local rewardsExhausted = false
local pendingStallCount = 0
local reexhaustTimer = 0
local needsPlayerReady = false
local playerReadyAttempts = 0
local playerReadyTimer = 0

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
    pendingRequestTimer = 0
    hasShownAllTraitsMessage = false
    shouldShowFinalMessage = false
    showFinalMessageTimer = 0
    rewardsExhausted = false
    pendingStallCount = 0
    reexhaustTimer = 0
    needsPlayerReady = false
    playerReadyAttempts = 0
    playerReadyTimer = 0
    -- Clear UI state that belongs to the previous session.
    if BCR.ResetNotifications then BCR.ResetNotifications() end
    if BCR.CloseStatsWindow then BCR.CloseStatsWindow() end
end

local function countMissedMilestones(bcrData, opts)
    if not opts then return 0 end
    local player = getLocalPlayer()
    if not player then return 0 end
    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok or not kills then return 0 end
    return BCR.GetMissedMilestoneCount(bcrData, kills, opts)
end

-- Arms the pending drain when rewards are already owed at load time
-- (for example a released withheld pool after a late option flip).
local function seedPendingRewards(player, bcrData)
    if not player or not bcrData or not BCR.opts then return end
    if hasShownAllTraitsMessage then return end
    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok or not kills then return end
    local missed = BCR.GetMissedMilestoneCount(bcrData, kills, BCR.opts)
    if missed > 0 then
        pendingRewardsCount = missed
        pendingRewardTimer = 0
    end
end

local function tryReexhaust(player)
    if hasShownAllTraitsMessage and BCR.HasAvailableRewards(player) then
        BCR.DebugPrint("Client", "Re-exhaust check: rewards available again -- resuming")
        hasShownAllTraitsMessage = false
        rewardsExhausted = false
    end
end

local function scheduleFinalMessage()
    rewardsExhausted = true
    shouldShowFinalMessage = true
    showFinalMessageTimer = 0
end

local function sendRequestCommand(player, kills)
    isPendingRequestInFlight = true
    pendingRequestTimer = 0
    local ok = pcall(function() sendClientCommand(player, "BCR", "RequestReward", { kills = kills }) end)
    if not ok then
        isPendingRequestInFlight = false
    end
end

-- ============================================================
-- EVENT HANDLERS
-- ============================================================

local function BCR_OnCreatePlayer(playerNum, player)
    BCR.RefreshConfig()
    if not player then return end

    BCR.DebugPrint("Client", "Player created - initializing BCR")

    resetState()

    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end

    if BCR.opts and BCR.ReconcileTraitState then
        local recOk, recErr = pcall(BCR.ReconcileTraitState, player, bcrData, BCR.opts)
        if not recOk then
            BCR.DebugPrint("Client", "ReconcileTraitState failed: " .. tostring(recErr))
        end
    end

    local ok, kills = pcall(function() return player:getZombieKills() end)
    local rewardsGiven = bcrData.rewardsGiven or 0
    if ok and kills then
        if bcrData.kills == 0 and kills > 0 then
            bcrData.kills = kills
        end
    end
    -- Seed the tick baseline so the first update does not report the whole
    -- lifetime kill count as new kills.
    lastKnownKills = bcrData.kills or 0

    local traitCount = bcrData.traitHistory and #bcrData.traitHistory or 0
    BCR.DebugPrint("Client", string.format(
        "onCreatePlayer: kills=%d, rewardsGiven=%d, traits=%d",
        (ok and kills) or 0, rewardsGiven, traitCount
    ))

    if not BCR.HasAvailableRewards(player) then
        hasShownAllTraitsMessage = true
        BCR.DebugPrint("Client", "onCreatePlayer: all rewards exhausted -- skipping future processing")
    end

    if isSinglePlayer() then
        -- Same VM as the server module: capture the withheld baseline and
        -- drain anything already owed without waiting for the next kill.
        if BCR.CaptureWithheldBaseline and BCR.opts then
            pcall(BCR.CaptureWithheldBaseline, player, bcrData, BCR.opts)
        end
        seedPendingRewards(player, bcrData)
    else
        -- MP: announce this session to the server (retried from OnPlayerUpdate).
        needsPlayerReady = true
    end
end

local function requestReward(player, bcrData)
    if not player then
        BCR.DebugPrint("Client", "requestReward called with nil player")
        return
    end
    BCR.DebugPrint("Client", "Requesting reward")
    local ok, results = pcall(BCR.ProcessRewardDirect, player)
    if not ok or type(results) ~= "table" or #results == 0 then
        if not ok then
            BCR.DebugPrint("Client", "SP reward request error: " .. tostring(results))
        else
            BCR.DebugPrint("Client", "SP reward skipped: nothing granted")
        end
        if not hasShownAllTraitsMessage and not BCR.HasAvailableRewards(player) then
            BCR.DebugPrint("Client", "No more rewards available - scheduling final message")
            scheduleFinalMessage()
        end
        return
    end
    for _, result in ipairs(results) do
        BCR.EnqueueNotification(result)
        BCR.DebugPrint("Client", "SP Reward granted: " .. tostring(result.id) .. " (" .. tostring(result.action) .. ")")
    end
    BCR.RefreshStatsWindow()
    if not hasShownAllTraitsMessage and not BCR.HasAvailableRewards(player) then
        BCR.DebugPrint("Client", "No more rewards available - scheduling final message")
        scheduleFinalMessage()
    end
end

local function BCR_OnPlayerUpdate(player)
    if not player then return end
    if player:isDead() then return end
    if isPendingRequestInFlight and not isSinglePlayer() then
        pendingRequestTimer = pendingRequestTimer + 1
        if pendingRequestTimer >= MP_REQUEST_TIMEOUT_TICKS then
            -- Clear only the in-flight flag: the pending count stays armed so
            -- the retry loop re-sends instead of waiting for the next kill.
            BCR.DebugPrint("Client", "MP request timed out -- retrying")
            isPendingRequestInFlight = false
            pendingRequestTimer = 0
        end
    end
    if needsPlayerReady then
        playerReadyTimer = playerReadyTimer + 1
        if playerReadyAttempts == 0 or playerReadyTimer >= PLAYER_READY_RETRY_TICKS then
            playerReadyTimer = 0
            playerReadyAttempts = playerReadyAttempts + 1
            local sent = pcall(function()
                sendClientCommand(player, "BCR", "PlayerReady", {})
            end)
            if not sent or playerReadyAttempts >= PLAYER_READY_MAX_ATTEMPTS then
                needsPlayerReady = false
            end
        end
    end
    if hasShownAllTraitsMessage then
        BCR.UpdateNotifications(player)
        reexhaustTimer = reexhaustTimer + 1
        if reexhaustTimer >= REEXHAUST_CHECK_TICKS then
            reexhaustTimer = 0
            tryReexhaust(player)
        end
        if hasShownAllTraitsMessage then return end
    end
    if BCR.opts == nil then
        BCR.RefreshConfig()
    end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end
    local ok, currentKills = pcall(function() return player:getZombieKills() end)
    if not ok or not currentKills then return end
    if currentKills > lastKnownKills then
        bcrData.kills = currentKills
        local newKills = currentKills - lastKnownKills
        BCR.DebugPrint("Client", string.format("+%d kill(s) - Total: %d", newKills, currentKills))
        if BCR.GetMissedMilestoneCount(bcrData, currentKills, BCR.opts) > 0 and not rewardsExhausted then
            BCR.DebugPrint("Client", "Milestone reached: " .. currentKills .. " kills")
            if isSinglePlayer() then
                local missed = countMissedMilestones(bcrData, BCR.opts)
                if missed > 1 then
                    BCR.DebugPrint("Client", "Found " .. missed .. " milestones to claim")
                    pendingRewardsCount = missed
                    pendingRewardTimer = 0
                    local msg = missed .. " " .. (getText("UI_BCR_PendingRewards") or "rewards earned!")
                    HaloTextHelper.addText(player, msg, "", 255, 255, 255)
                else
                    if not isPendingRequestInFlight then
                        isPendingRequestInFlight = true
                        local reqOk, reqErr = pcall(requestReward, player, bcrData)
                        isPendingRequestInFlight = false
                        if not reqOk then
                            BCR.DebugPrint("Client", "requestReward error: " .. tostring(reqErr))
                        end
                    end
                end
            else
                if not isPendingRequestInFlight then
                    sendRequestCommand(player, currentKills)
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
                local ok, results = pcall(BCR.ProcessRewardDirect, player)
                if not ok or type(results) ~= "table" or #results == 0 then
                    isPendingRequestInFlight = false
                    if not ok then
                        BCR.DebugPrint("Client", "OnPlayerUpdate: ProcessRewardDirect error: " .. tostring(results))
                    else
                        BCR.DebugPrint("Client", "OnPlayerUpdate: ProcessRewardDirect granted nothing")
                    end
                    if not BCR.HasAvailableRewards(player) then
                        scheduleFinalMessage()
                        pendingRewardsCount = 0
                    else
                        pendingStallCount = pendingStallCount + 1
                        if pendingStallCount >= MAX_PENDING_STALLS then
                            BCR.DebugPrint("Client", "Stalled on empty ProcessRewardDirect -- aborting pending loop")
                            pendingRewardsCount = 0
                            pendingStallCount = 0
                        end
                    end
                    -- Do not recompute the count here: keep it for a retry,
                    -- or keep the zero that stops the loop (exhausted/stalled).
                else
                    isPendingRequestInFlight = false
                    pendingStallCount = 0
                    for _, result in ipairs(results) do
                        BCR.EnqueueNotification(result)
                    end
                    BCR.RefreshStatsWindow()
                    if not BCR.HasAvailableRewards(player) then
                        scheduleFinalMessage()
                        pendingRewardsCount = 0
                    else
                        pendingRewardsCount = countMissedMilestones(bcrData, BCR.opts)
                    end
                end
            elseif not isSinglePlayer() and not isPendingRequestInFlight then
                local freshKills = currentKills
                local ok2, refreshedKills = pcall(function() return player:getZombieKills() end)
                if ok2 and refreshedKills then freshKills = refreshedKills end
                sendRequestCommand(player, freshKills)
            end
        end
    end
    BCR.UpdateNotifications(player)
    if shouldShowFinalMessage then
        showFinalMessageTimer = showFinalMessageTimer + 1
        if showFinalMessageTimer >= BCR.NOTIFICATION_DELAY_TICKS then
            BCR.ShowFinalMessage(player)
            shouldShowFinalMessage = false
            showFinalMessageTimer = 0
            hasShownAllTraitsMessage = true
            BCR.DebugPrint("Client", "Final message shown - no more reward processing")
        end
    end
    lastKnownKills = currentKills
end

local function BCR_OnServerCommand(module, command, args)
    if module ~= "BCR" then return end
    if not args then return end
    local player = getLocalPlayer()
    if not player then return end
    local bcrData = BCR.EnsureModData(player)
    if not bcrData then return end
    if command == "RewardGranted" then
        BCR.DebugPrint("Client", "Server command: RewardGranted")
        bcrData.rewardsGiven = (bcrData.rewardsGiven or 0) + 1
        BCR.EnqueueNotification(args)
        BCR.RefreshStatsWindow()
    elseif command == "RewardBatchComplete" then
        isPendingRequestInFlight = false
        pendingRequestTimer = 0
        local totalGranted = type(args.totalGranted) == "number"
            and math.max(0, math.floor(args.totalGranted)) or 0
        local remainingMilestones = type(args.remainingMilestones) == "number"
            and math.max(0, math.floor(args.remainingMilestones)) or nil
        local serverRewardsGiven = type(args.rewardsGiven) == "number"
            and math.max(0, math.floor(args.rewardsGiven)) or nil
        local serverWithheld = type(args.withheldMilestones) == "number"
            and math.max(0, math.floor(args.withheldMilestones)) or nil
        if remainingMilestones then
            pendingRewardsCount = remainingMilestones
        end
        BCR.DebugPrint("Client", string.format(
            "Batch complete: %d granted, %d milestones remaining",
            totalGranted, remainingMilestones or 0
        ))
        if serverRewardsGiven and serverRewardsGiven > (bcrData.rewardsGiven or 0) then
            bcrData.rewardsGiven = serverRewardsGiven
        end
        if serverWithheld then
            bcrData.withheldMilestones = serverWithheld
        end
        if totalGranted == 0 and pendingRewardsCount > 0 then
            -- Server granted nothing -- either the pools are exhausted or
            -- a pick failed transiently. Retry a few times, then stop so
            -- the client does not ping-pong the server forever.
            pendingStallCount = pendingStallCount + 1
            if pendingStallCount >= MAX_PENDING_STALLS then
                BCR.DebugPrint("Client", "Server granted nothing " .. MAX_PENDING_STALLS .. " times in a row -- stopping re-requests")
                pendingRewardsCount = 0
                pendingStallCount = 0
            end
        else
            pendingStallCount = 0
        end
        if not BCR.HasAvailableRewards(player) then
            scheduleFinalMessage()
        end
    elseif command == "PlayerSync" then
        needsPlayerReady = false
        playerReadyAttempts = 0
        playerReadyTimer = 0
        if type(args.kills) == "number" and args.kills >= 0 then
            bcrData.kills = args.kills
        end
        if type(args.rewardsGiven) == "number" and args.rewardsGiven >= 0 then
            bcrData.rewardsGiven = args.rewardsGiven
        end
        if type(args.withheldMilestones) == "number" and args.withheldMilestones >= 0 then
            bcrData.withheldMilestones = args.withheldMilestones
        end
        BCR.DebugPrint("Client", "Player sync received")
        seedPendingRewards(player, bcrData)
    elseif command == "RewardError" then
        print("[BCR] [Client] Reward error: " .. tostring(args.reason))
        isPendingRequestInFlight = false
        pendingRequestTimer = 0
        pendingRewardsCount = 0
    end
end

local function BCR_OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
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

    tryReexhaust(player)

    if hasShownAllTraitsMessage or not BCR.HasAvailableRewards(player) then
        local exhaustedText = getText("UI_BCR_AllRewardsGranted") or "All rewards granted!"
        local exhaustedOption = subMenu:addOption(exhaustedText, nil, nil)
        exhaustedOption.notAvailable = true
    else
        local answered = bcrData and BCR.GetAnsweredMilestones(bcrData) or 0
        local nextMilestone = BCR.GetKillsForMilestone(answered + 1, opts)
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
    if not ok then print("[BCR] [Client] OnCreatePlayer error: " .. tostring(err)) end
end)

Events.OnPlayerUpdate.Add(function(player)
    local ok, err = pcall(function() BCR_OnPlayerUpdate(player) end)
    if not ok then print("[BCR] [Client] OnPlayerUpdate error: " .. tostring(err)) end
end)

Events.OnServerCommand.Add(function(module, command, args)
    local ok, err = pcall(function() BCR_OnServerCommand(module, command, args) end)
    if not ok then print("[BCR] [Client] OnServerCommand error: " .. tostring(err)) end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldObjects, test)
    local ok, err = pcall(function() BCR_OnFillWorldObjectContextMenu(playerNum, context, worldObjects, test) end)
    if not ok then print("[BCR] [Client] OnFillWorldObjectContextMenu error: " .. tostring(err)) end
end)
