-- ============================================================
-- BodyCountRewards - Client Module (Build 42.13.2)
-- 
-- Player-facing tracking and UI:
--   - Monitors zombie kills and detects milestones
--   - Syncs state with server (MP) or calls server directly (SP)
--   - Queues and displays halo text notifications
--   - Provides context menu and stats window access
-- ============================================================

require "BCR_Shared"
require "BCR_StatsUI"

BCR = BCR or {}
local ModuleName = "BCR"


-- ===========================
-- CONFIGURATION

local PENDING_REWARD_DELAY_TICKS = 90   -- ~1.5 seconds between auto-claims
local NOTIFICATION_DELAY_TICKS = 200    -- ~3.3 seconds between staggered notifications


-- ===========================
-- STATE VARIABLES

local lastKnownKills = 0
local pendingRewardsCount = 0
local pendingRewardTimer = 0
local isProcessingPendingRewards = false
local currentTick = 0
local hasShownAllTraitsMessage = false
local shouldShowFinalMessage = false
local showFinalMessageTimer = 0
local rewardsExhausted = false
local notificationQueue = {}
local notificationTimer = 0
local isShowingNotification = false


-- ===========================
-- HELPER FUNCTIONS

local function getLocalPlayer()
    return getSpecificPlayer(0)
end

local function ensureClientModData(player)
    if not player then return nil end
    local modData = player:getModData()
    if not modData.BCR then
        modData.BCR = {
            kills = 0,
            rewardsGiven = 0,
            traitHistory = {},
        }
        BCR.DebugPrint("[Client] Initialized ModData for player")
    end
    if not modData.BCR.traitHistory then
        modData.BCR.traitHistory = {}
    end
    return modData.BCR
end

-- Sync threshold scales with BodyCount (10%, clamped 10-100)
local function getSyncThreshold(opts)
    local threshold = math.floor(opts.BodyCount * 0.1)
    return math.max(10, math.min(threshold, 100))
end


-- ===========================
-- KILL TRACKING

local function getCurrentKills(player)
    if not player then return 0 end
    
    local success, kills = pcall(function()
        return player:getZombieKills()
    end)
    
    if success and kills then
        return kills
    end
    
    BCR.DebugPrint("[Client] Warning: Could not read zombie kills")
    return 0
end


-- ===========================
-- MILESTONE LOGIC

local function getNextMilestone(bcrData, opts)
    return BCR.getKillsForMilestone(bcrData.rewardsGiven + 1, opts)
end

local function getKillsUntilMilestone(kills, bcrData, opts)
    local nextMilestone = getNextMilestone(bcrData, opts)
    return math.max(0, nextMilestone - kills)
end

local function hasMilestoneBeenReached(kills, bcrData, opts)
    return kills >= getNextMilestone(bcrData, opts)
end

local function getMissedMilestones(kills, bcrData, opts)
    local milestonesEarned = BCR.getMilestonesAtKills(kills, opts)
    local missed = milestonesEarned - bcrData.rewardsGiven
    return math.max(0, missed)
end

local function isNearMilestone(kills, bcrData, opts)
    local threshold = getSyncThreshold(opts)
    local remaining = getKillsUntilMilestone(kills, bcrData, opts)
    return remaining <= threshold and remaining > 0
end


-- ===========================
-- KILL SYNC (MP only)

local function syncKillsToServer(player, kills)
    if BCR.isSinglePlayer() then return end
    BCR.DebugPrint("[Client] Syncing kills to server: " .. kills)
    sendClientCommand(player, ModuleName, "SyncKills", { kills = kills })
end


-- ===========================
-- UI: HALO TEXT NOTIFICATION

local function showRewardNotification(player, result)
    if not player or not result then return end
    
    local actionText
    local displayName = BCR.getTraitDisplayName(result.trait)
    
    if result.action == "added" then
        actionText = getText("UI_BCR_Gained") or "Gained"
        local text = actionText .. ": " .. displayName
        HaloTextHelper.addTextWithArrow(player, text, true, 0, 255, 0)
    else
        actionText = getText("UI_BCR_Lost") or "Lost"
        local text = actionText .. ": " .. displayName
        HaloTextHelper.addTextWithArrow(player, text, true, 255, 165, 0)
    end
    
    BCR.DebugPrint("[Client] Notification: " .. actionText .. " - " .. displayName)
end

local function showInfoNotification(player, text)
    if not player or not text then return end
    HaloTextHelper.addText(player, text, "", 255, 255, 255)
end


-- ===========================
-- REWARD REQUEST

local function requestReward(player, bcrData)
    if not player then 
        BCR.DebugPrint("[Client] requestReward called with nil player")
        return 
    end
    
    BCR.DebugPrint("[Client] Requesting reward...")
    
    if BCR.isSinglePlayer() then
        local result = BCR.ProcessRewardDirect(player)
        
        if result then
            table.insert(notificationQueue, {
                trait = result.trait,
                displayName = BCR.getTraitDisplayName(result.trait),
                action = result.action,
                rarity = result.rarity,
                color = BCR.getRarityColor(result.cost or 0),
            })
            
            BCR.refreshStatsWindow()
            BCR.DebugPrint("[Client] SP Reward granted: " .. result.trait .. " (" .. result.action .. ")")
            
            if not hasShownAllTraitsMessage and not BCR.HasAvailableRewards(player) then
                BCR.DebugPrint("[Client] No more rewards available - scheduling final message")
                rewardsExhausted = true
                shouldShowFinalMessage = true
                showFinalMessageTimer = 0
            end
        else
            BCR.DebugPrint("[Client] SP Reward failed or no traits available")
            
            if not BCR.HasAvailableRewards(player) and not hasShownAllTraitsMessage then
                shouldShowFinalMessage = true
                showFinalMessageTimer = 0
            end
        end
    else
        local currentKills = getCurrentKills(player)
        BCR.DebugPrint("[Client] Sending reward request to server with kills: " .. currentKills)
        sendClientCommand(player, ModuleName, "RequestReward", { kills = currentKills })
    end
end


-- ===========================
-- PENDING REWARDS PROCESSING

local function processPendingReward()
    if pendingRewardsCount <= 0 then
        isProcessingPendingRewards = false
        return
    end
    
    local player = getLocalPlayer()
    if not player then return end
    
    local bcrData = ensureClientModData(player)
    if not bcrData then return end
    
    isProcessingPendingRewards = true
    pendingRewardsCount = pendingRewardsCount - 1
    
    BCR.DebugPrint("[Client] Auto-claiming pending reward (" .. pendingRewardsCount .. " remaining)")
    requestReward(player, bcrData)
    
    pendingRewardTimer = 0
    
    if pendingRewardsCount <= 0 then
        isProcessingPendingRewards = false
    end
end


-- ===========================
-- MAIN UPDATE HANDLER 

local function BCR_OnPlayerUpdate(player)
    if not player then return end
    if player:isDead() then return end
    
    currentTick = currentTick + 1
    
    local bcrData = ensureClientModData(player)
    if not bcrData then return end
    
    -- All rewards exhausted - only track kills for display
    if hasShownAllTraitsMessage then
        bcrData.kills = getCurrentKills(player)
        return
    end
    
    local opts = BCR.getSandboxOptions()
    local currentKills = getCurrentKills(player)
    
    bcrData.kills = currentKills
    
    if currentKills > lastKnownKills then
        local newKills = currentKills - lastKnownKills
        lastKnownKills = currentKills
        
        BCR.DebugPrint("[Client] +" .. newKills .. " kill(s) - Total: " .. currentKills)
        
        -- Check milestone before syncing to avoid unnecessary server calls
        if hasMilestoneBeenReached(currentKills, bcrData, opts) then
            
            if rewardsExhausted then
                BCR.DebugPrint("[Client] Milestone reached but rewards exhausted - skipping")
                if not BCR.isSinglePlayer() then
                    syncKillsToServer(player, currentKills)
                end
            else
                BCR.DebugPrint("[Client] Milestone reached at " .. currentKills .. " kills!")
                syncKillsToServer(player, currentKills)
                
                if BCR.isSinglePlayer() then
                    local missedRewards = getMissedMilestones(currentKills, bcrData, opts)
                    if missedRewards > 1 then
                        BCR.DebugPrint("[Client] Found " .. missedRewards .. " milestones to claim")
                        pendingRewardsCount = missedRewards
                        pendingRewardTimer = PENDING_REWARD_DELAY_TICKS
                        local msg = missedRewards .. " " .. (getText("UI_BCR_PendingRewards") or "rewards earned!")
                        showInfoNotification(player, msg)
                    else
                        requestReward(player, bcrData)
                    end
                else
                    requestReward(player, bcrData)
                end
            end
            
        elseif isNearMilestone(currentKills, bcrData, opts) then
            BCR.DebugPrint("[Client] Near milestone - syncing")
            syncKillsToServer(player, currentKills)
        end
    end
    
    -- Process pending rewards with delay
    if pendingRewardsCount > 0 then
        pendingRewardTimer = pendingRewardTimer + 1
        if pendingRewardTimer >= PENDING_REWARD_DELAY_TICKS then
            processPendingReward()
        end
    end

    -- Drain notification queue one at a time with delay between each
    if #notificationQueue > 0 then
        if not isShowingNotification then
            -- First notification in a batch: show immediately
            isShowingNotification = true
            notificationTimer = 0
            local first = table.remove(notificationQueue, 1)
            showRewardNotification(player, first)
            BCR.DebugPrint("[Client] Showing notification (" .. #notificationQueue .. " remaining)")
        else
            -- Subsequent notifications: enforce delay between each
            notificationTimer = notificationTimer + 1
            if notificationTimer >= NOTIFICATION_DELAY_TICKS then
                notificationTimer = 0
                local next = table.remove(notificationQueue, 1)
                showRewardNotification(player, next)
                BCR.DebugPrint("[Client] Showing queued notification (" .. #notificationQueue .. " remaining)")
            end
        end
    else
        -- Queue empty: keep cooldown running before allowing immediate display again
        if isShowingNotification then
            notificationTimer = notificationTimer + 1
            if notificationTimer >= NOTIFICATION_DELAY_TICKS then
                isShowingNotification = false
                notificationTimer = 0
                BCR.DebugPrint("[Client] Notification cooldown complete")
            end
        end
    end

    
    -- Delayed final message after all rewards granted
    if shouldShowFinalMessage then
        showFinalMessageTimer = showFinalMessageTimer + 1
        if showFinalMessageTimer >= PENDING_REWARD_DELAY_TICKS then
            showInfoNotification(player, getText("UI_BCR_AllRewardsGranted"))
            shouldShowFinalMessage = false
            hasShownAllTraitsMessage = true
            BCR.DebugPrint("[Client] Final message shown - no more reward processing")
        end
    end
end


-- ===========================
-- SERVER COMMAND HANDLERS (MP)

local function onServerCommand(module, command, args)
    if module ~= ModuleName then return end
    
    local player = getLocalPlayer()
    if not player then return end
    
    local bcrData = ensureClientModData(player)
    
    BCR.DebugPrint("[Client] Server command: " .. tostring(command))
    
    if command == "RewardGranted" then
        table.insert(notificationQueue, {
            trait = args.trait,
            displayName = args.displayName,
            action = args.action,
            rarity = args.rarity,
            color = args.color,
        })
        BCR.DebugPrint("[Client] Queued notification (" .. #notificationQueue .. " in queue)")
        
        BCR.refreshStatsWindow()
         
    elseif command == "RewardBatchComplete" then
        local totalGranted = args.totalGranted or 0
        local remaining = args.remainingMilestones or 0
        
        BCR.DebugPrint("[Client] Batch complete: " .. totalGranted .. " granted, " .. remaining .. " milestones remaining")
        
        if totalGranted > 1 then
            local msg = totalGranted .. " " .. (getText("UI_BCR_PendingRewards") or "rewards earned!")
            showInfoNotification(player, msg)
        end
        
        if remaining > 0 then
            pendingRewardsCount = remaining
            pendingRewardTimer = 0
            isProcessingPendingRewards = true
            BCR.DebugPrint("[Client] Server reports " .. remaining .. " milestones remaining - queuing follow-up requests")
        else
            pendingRewardsCount = 0
            isProcessingPendingRewards = false
            BCR.DebugPrint("[Client] Server reports all milestones handled")
        end
        
        if not hasShownAllTraitsMessage and not BCR.HasAvailableRewards(player) then
            rewardsExhausted = true
            shouldShowFinalMessage = true
            showFinalMessageTimer = 0
        end
        
    elseif command == "StateSync" then
        if args.kills ~= nil then 
            bcrData.kills = args.kills 
        end
        if args.rewardsGiven ~= nil then 
            bcrData.rewardsGiven = args.rewardsGiven 
        end
        BCR.DebugPrint("[Client] State synced - kills: " .. bcrData.kills .. ", rewards: " .. bcrData.rewardsGiven)
        
    elseif command == "KillsSynced" then
        if args.kills ~= nil then 
            bcrData.kills = args.kills
            -- Align lastKnownKills when server corrected upward to prevent phantom kill detection
            if args.kills > lastKnownKills then
                lastKnownKills = args.kills
            end
        end
        if args.rewardsGiven ~= nil then 
            bcrData.rewardsGiven = args.rewardsGiven 
        end
        
    elseif command == "PendingRewards" then
        local count = args.count or 0
        if count > 0 then
            pendingRewardsCount = count
            pendingRewardTimer = PENDING_REWARD_DELAY_TICKS
            BCR.DebugPrint("[Client] " .. count .. " pending rewards to claim")
            showInfoNotification(player, count .. " " .. (getText("UI_BCR_PendingRewards") or "rewards pending!"))
        end
        
    elseif command == "RewardError" then
        BCR.DebugPrint("[Client] Reward error: " .. tostring(args.reason))
        -- Clear pending queue on server denial
        pendingRewardsCount = 0
        isProcessingPendingRewards = false
        
    elseif command == "NoRewardAvailable" then
        BCR.DebugPrint("[Client] No rewards available: " .. tostring(args.reason))
        pendingRewardsCount = 0
        isProcessingPendingRewards = false
    end
end


-- ===========================
-- STATS WINDOW BRIDGE

function BCR.openStatsWindow(player)
    if not player then
        player = getLocalPlayer()
    end
    if not player then return end

    BCR.showStatsWindow(player)
end


-- ===========================
-- RIGHT-CLICK CONTEXT MENU

local function onFillWorldObjectContextMenu(playerNum, context, worldObjects, test)
    if test then return true end
    
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    
    local bcrData = ensureClientModData(player)
    local opts = BCR.getSandboxOptions()
    local currentKills = getCurrentKills(player)
    
    local bcrOption = context:addOption(
        getText("UI_BCR_MenuTitle") or "Body Count Rewards", 
        nil, 
        nil
    )
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(bcrOption, subMenu)
    
    subMenu:addOption(
        getText("UI_BCR_ViewStats") or "View Stats",
        player,
        BCR.openStatsWindow
    )
       
    if hasShownAllTraitsMessage or not BCR.HasAvailableRewards(player) then
        local exhaustedText = getText("UI_BCR_AllRewardsGranted") or "All rewards granted!"
        local exhaustedOption = subMenu:addOption(exhaustedText, nil, nil)
        exhaustedOption.notAvailable = true
    else
        local nextMilestone = getNextMilestone(bcrData, opts)
        local killsRemaining = getKillsUntilMilestone(currentKills, bcrData, opts)
        
        local progressText = (getText("UI_BCR_Progress") or "Progress") .. ": " 
            .. currentKills .. " / " .. nextMilestone
        local progressOption = subMenu:addOption(progressText, nil, nil)
        progressOption.notAvailable = true

        local remainingText = (getText("UI_BCR_NextReward") or "Next reward") .. ": "
            .. killsRemaining .. " " .. (getText("UI_BCR_Kills") or "kills")
        local remainingOption = subMenu:addOption(remainingText, nil, nil)
        remainingOption.notAvailable = true
    end
end


-- ===========================
-- PLAYER CREATION

local function onCreatePlayer(playerNum, player)
    if not player then return end
    
    BCR.DebugPrint("[Client] Player created - initializing BCR")
    
    -- Reset state for new character
    lastKnownKills = 0
    pendingRewardsCount = 0
    pendingRewardTimer = 0
    isProcessingPendingRewards = false
    hasShownAllTraitsMessage = false 
    shouldShowFinalMessage = false 
    showFinalMessageTimer = 0
    rewardsExhausted = false
    notificationQueue = {}
    notificationTimer = 0
    
    ensureClientModData(player)
    lastKnownKills = getCurrentKills(player)
end


-- ===========================
-- EVENT REGISTRATION

Events.OnPlayerUpdate.Add(function(player)
    pcall(function() BCR_OnPlayerUpdate(player) end)
end)

Events.OnServerCommand.Add(onServerCommand)
Events.OnFillWorldObjectContextMenu.Add(onFillWorldObjectContextMenu)
Events.OnCreatePlayer.Add(onCreatePlayer)
