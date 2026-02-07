-- ============================================================
-- BodyCountRewards - Server Module (Build 42.13.2)
-- 
-- Authoritative game state and trait manipulation:
--   - Validates milestone requests from clients
--   - Applies trait add/remove operations
--   - Persists ModData (kills, rewards, history)
--   - Handles MP commands and SP direct processing
-- ============================================================

if isClient() and not isServer() then return end

require "BCR_Shared"

BCR = BCR or {} 
local ModuleName = "BCR" 


-- ===========================
-- HELPER FUNCTIONS

local function ensureModData(player)
    local modData = player:getModData()
    if not modData.BCR then
        modData.BCR = {
            kills = 0,
            rewardsGiven = 0,
            traitHistory = {},
        }
        BCR.DebugPrint("[Server] Initialized ModData for player: " .. tostring(player:getUsername()))
    end
    if not modData.BCR.traitHistory then
        modData.BCR.traitHistory = {}
    end
    return modData.BCR
end


-- ===========================
-- MILESTONE VALIDATION

local function validateMilestone(player, bcrData, opts)
    local killsRequired = BCR.getKillsForMilestone(bcrData.rewardsGiven + 1, opts)
    local kills = bcrData.kills

    if kills < killsRequired then
        BCR.DebugPrint(string.format(
            "[Server] Milestone validation FAILED for %s: kills=%d, required=%d",
            tostring(player:getUsername()), kills, killsRequired
        ))
        return false, 0
    end

    local milestonesEarned = BCR.getMilestonesAtKills(kills, opts)
    local missedRewards = milestonesEarned - bcrData.rewardsGiven

    BCR.DebugPrint(string.format(
        "[Server] Milestone validation for %s: kills=%d, required=%d, earned=%d, missed=%d",
        tostring(player:getUsername()), kills, killsRequired, milestonesEarned, missedRewards
    ))

    return true, math.max(0, missedRewards)
end


-- ===========================
-- TRAIT POOL BUILDING

local function buildTraitPools(player, opts)
    local earnablePool = {}
    local removablePool = {}
    
    if opts.givePositiveTraits then
        local success, result = pcall(BCR.getEarnableTraits, player)
        if success and result then
            earnablePool = result
        else
            BCR.DebugPrint("[Server] Error getting earnable traits: " .. tostring(result))
        end
    end
    
    if opts.removeNegativeTraits then
        local success, result = pcall(BCR.getRemovableTraits, player)
        if success and result then
            removablePool = result
        else
            BCR.DebugPrint("[Server] Error getting removable traits: " .. tostring(result))
        end
    end
    
    return earnablePool, removablePool
end


-- ===========================
-- REWARD SELECTION AND APPLICATION

local function selectAndApplyReward(player, earnablePool, removablePool, opts)
    local selected = nil
    local action = nil
    local success = false
    
    local tryPositiveFirst = true
    
    if opts.rewardPriority == BCR.PRIORITY_NEGATIVE_FIRST then
        -- Remove negative traits before adding positive ones
        tryPositiveFirst = false
    elseif opts.rewardPriority == BCR.PRIORITY_RANDOM then
        -- 50/50 coin flip each reward
        tryPositiveFirst = (ZombRand(2) == 0)
        BCR.DebugPrint("[Server] Random priority roll: " .. (tryPositiveFirst and "positive" or "negative") .. " first")
    end
    
    local attempts = {}
    if tryPositiveFirst then
        if #earnablePool > 0 then table.insert(attempts, { pool = earnablePool, action = "added", type = "positive" }) end
        if #removablePool > 0 then table.insert(attempts, { pool = removablePool, action = "removed", type = "negative" }) end
    else
        if #removablePool > 0 then table.insert(attempts, { pool = removablePool, action = "removed", type = "negative" }) end
        if #earnablePool > 0 then table.insert(attempts, { pool = earnablePool, action = "added", type = "positive" }) end
    end
    
    for _, attempt in ipairs(attempts) do
        selected = BCR.weightedRandomSelect(attempt.pool)
        if selected then
            BCR.DebugPrint("[Server] Selected " .. attempt.type .. " trait: " .. selected.trait)
            
            local applySuccess, applyResult
            if attempt.action == "added" then
                applySuccess, applyResult = pcall(BCR.addTraitToPlayer, player, selected)
            else
                applySuccess, applyResult = pcall(BCR.removeTraitFromPlayer, player, selected)
            end
            
            if applySuccess and applyResult then
                action = attempt.action
                success = true
                BCR.DebugPrint("[Server] Successfully " .. action .. " trait: " .. selected.trait)
                break
            else
                BCR.DebugPrint("[Server] Failed to apply trait: " .. tostring(applyResult))
                selected = nil
            end
        end
    end
    
    if success and selected and action then
        return {
            trait = selected.trait,
            displayName = BCR.getTraitDisplayName(selected.trait),
            action = action,
            rarity = selected.rarity,
            color = BCR.getRarityColor(selected.cost),
        }
    end
    
    return nil
end


-- ===========================
-- REWARD REQUEST HANDLER (MP)

local function handleRequestReward(player, args)
    BCR.DebugPrint("[Server] RequestReward received from: " .. tostring(player:getUsername()))
    
    local opts = BCR.getSandboxOptions()
    
    if not opts.givePositiveTraits and not opts.removeNegativeTraits then
        BCR.DebugPrint("[Server] Both trait rewards are disabled in sandbox options")
        sendServerCommand(player, ModuleName, "RewardError", {
            reason = "Rewards are disabled in server settings",
        })
        return
    end
    
    local bcrData = ensureModData(player)
    
    -- Use best available kill count: ModData, client report, or server API
    local reportedKills = (args and type(args.kills) == "number") and math.floor(args.kills) or 0
    local serverKills = player:getZombieKills() or 0
    local bestKills = math.max(bcrData.kills, reportedKills, serverKills)
    
    if bestKills > bcrData.kills then
        BCR.DebugPrint(string.format(
            "[Server] Updated kills during reward request: %d -> %d (reported=%d, server=%d)",
            bcrData.kills, bestKills, reportedKills, serverKills
        ))
        bcrData.kills = bestKills
    end
    
    local isValid, missedRewards = validateMilestone(player, bcrData, opts)
    
    if not isValid then
        BCR.DebugPrint("[Server] Invalid reward request - milestone not reached")
        sendServerCommand(player, ModuleName, "RewardError", {
            reason = "Milestone not reached",
        })
        return
    end

    local rewardsToGive = 1
    if opts.grandMissedOpportunities and missedRewards > 1 then
        rewardsToGive = missedRewards
        BCR.DebugPrint(string.format(
            "[Server] Grand missed opportunities: granting %d rewards",
            rewardsToGive
        ))
    end
    
    local totalGranted = 0
    for i = 1, rewardsToGive do
        -- Rebuild pools each iteration since player traits change after each reward
        local earnablePool, removablePool = buildTraitPools(player, opts)
        
        if #earnablePool == 0 and #removablePool == 0 then
            BCR.DebugPrint("[Server] No traits available for reward")
            if totalGranted == 0 then
                sendServerCommand(player, ModuleName, "NoRewardAvailable", {
                    reason = "All traits have been earned or removed",
                })
            end
            break
        end
        
        local result = selectAndApplyReward(player, earnablePool, removablePool, opts)
        
        if result then
            bcrData.rewardsGiven = bcrData.rewardsGiven + 1
            
            -- History stored server-side to persist via transmitModData()
            if not bcrData.traitHistory then
                bcrData.traitHistory = {}
            end
            table.insert(bcrData.traitHistory, {
                trait = result.trait,
                action = result.action,
                rarity = result.rarity,
                timestamp = getGameTime():getWorldAgeHours(),
            })
            
            if isServer() then
                player:transmitModData()
            end
            
            totalGranted = totalGranted + 1
            
            BCR.DebugPrint(string.format(
                "[Server] Reward granted to %s: %s (%s) - %s",
                tostring(player:getUsername()),
                result.trait,
                result.action,
                result.rarity
            ))
            
            sendServerCommand(player, ModuleName, "RewardGranted", {
                trait = result.trait,
                displayName = result.displayName,
                action = result.action,
                rarity = result.rarity,
                color = result.color,
            })

        else
            BCR.DebugPrint("[Server] Failed to apply any reward")
            if totalGranted == 0 then
                sendServerCommand(player, ModuleName, "RewardError", {
                    reason = "Failed to apply trait reward",
                })
            end
            break
        end
    end
    
    local milestonesEarned = BCR.getMilestonesAtKills(bcrData.kills, opts)
    local remainingMilestones = milestonesEarned - bcrData.rewardsGiven
    
    sendServerCommand(player, ModuleName, "RewardBatchComplete", {
        totalGranted = totalGranted,
        remainingMilestones = remainingMilestones,
    })
    
    BCR.DebugPrint(string.format(
        "[Server] Reward processing complete for %s: %d rewards granted, %d milestones remaining",
        tostring(player:getUsername()), totalGranted, remainingMilestones
    ))
end


-- ===========================
-- KILL SYNC HANDLER

local function handleSyncKills(player, args)
    if not args or type(args.kills) ~= "number" then
        BCR.DebugPrint("[Server] SyncKills received with invalid args")
        return
    end
    
    local bcrData = ensureModData(player)
    local newKills = math.floor(args.kills)
    
    -- Prefer server-side kill count if higher (anti-cheat measure)
    local serverKills = player:getZombieKills()
    if serverKills and serverKills > newKills then
        BCR.DebugPrint(string.format(
            "[Server] Server kill count (%d) higher than client report (%d) - using server value",
            serverKills, newKills
        ))
        newKills = serverKills
    end
    
    -- Never allow kill count to decrease (prevents exploits)
    if newKills < bcrData.kills then
        BCR.DebugPrint(string.format(
            "[Server] SyncKills REJECTED for %s: attempt to decrease kills (%d -> %d)",
            tostring(player:getUsername()), bcrData.kills, newKills
        ))
        return
    end
    
    local oldKills = bcrData.kills
    bcrData.kills = newKills
    
    if isServer() then
        player:transmitModData()
    end
    
    BCR.DebugPrint(string.format(
        "[Server] SyncKills for %s: %d -> %d",
        tostring(player:getUsername()), oldKills, newKills
    ))
    
    sendServerCommand(player, ModuleName, "KillsSynced", {
        kills = bcrData.kills,
        rewardsGiven = bcrData.rewardsGiven,
    })
end


-- ===========================
-- EVENT HANDLERS

local function onClientCommand(module, command, player, args)
    if module ~= ModuleName then return end
    
    BCR.DebugPrint("[Server] Received command: " .. command .. " from: " .. tostring(player:getUsername()))
    
    if command == "RequestReward" then
        handleRequestReward(player, args)
    elseif command == "SyncKills" then
        handleSyncKills(player, args)
    end
end


-- ===========================
-- SINGLEPLAYER DIRECT PROCESSING

function BCR.ProcessRewardDirect(player)
    if not player then return nil end
    
    local opts = BCR.getSandboxOptions()
    local bcrData = ensureModData(player)
    
    local isValid, missedRewards = validateMilestone(player, bcrData, opts)
    if not isValid then return nil end
    
    local earnablePool, removablePool = buildTraitPools(player, opts)
    if #earnablePool == 0 and #removablePool == 0 then return nil end
    
    local result = selectAndApplyReward(player, earnablePool, removablePool, opts)
    if result then
        bcrData.rewardsGiven = bcrData.rewardsGiven + 1
        
        if not bcrData.traitHistory then
            bcrData.traitHistory = {}
        end
        table.insert(bcrData.traitHistory, {
            trait = result.trait,
            action = result.action,
            rarity = result.rarity,
            timestamp = getGameTime():getWorldAgeHours(),
        })
    end
    
    return result
end


-- ===========================
-- EVENT REGISTRATION

Events.OnClientCommand.Add(onClientCommand)
