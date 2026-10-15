-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRNotifications (Build 42.19+)
-- Notification queue, staggering, halo text display.
-- ============================================================

require "BCRCore"

BCR = BCR or {}

-- ============================================================
-- LOCAL STATE
-- ============================================================

local notificationQueue = {}
local notificationTimer = 0
local isShowingNotification = false

local HALO_COLORS = {
    gained = { 0, 255, 0 },
    lost   = { 255, 165, 0 },
    batch  = { 200, 200, 200 },
    final  = { 255, 255, 255 },
}

-- ============================================================
-- PUBLIC FUNCTIONS
-- ============================================================

function BCR.EnqueueNotification(result)
    if type(result) ~= "table" then return end
    if #notificationQueue >= BCR.MAX_NOTIFICATION_QUEUE then
        -- The summary replaces the queued entries; the incoming reward takes
        -- its own slot, so count only what is collapsed.
        local batchedCount = #notificationQueue
        local label = getTextOrNull("UI_BCR_BatchRewards")
        if not label then
            label = tostring(batchedCount) .. " rewards"
        end
        notificationQueue = {
            {
                displayName = label,
                action = "batch",
            }
        }
    end
    table.insert(notificationQueue, result)
end

function BCR.UpdateNotifications(player)
    if not player then return end
    if #notificationQueue == 0 then
        if isShowingNotification then
            notificationTimer = notificationTimer + 1
            if notificationTimer >= BCR.NOTIFICATION_DELAY_TICKS then
                isShowingNotification = false
                notificationTimer = 0
            end
        end
        return
    end
    if isShowingNotification then
        notificationTimer = notificationTimer + 1
        if notificationTimer >= BCR.NOTIFICATION_DELAY_TICKS then
            isShowingNotification = false
            notificationTimer = 0
        else
            return
        end
    end
    local result = notificationQueue[1]
    table.remove(notificationQueue, 1)
    if not result then
        isShowingNotification = false
        return
    end
    isShowingNotification = true
    notificationTimer = 0
    BCR.DebugPrint("Client", string.format("Showing notification (%d remaining)", #notificationQueue))
    local action = result.action or "added"
    local displayName = result.displayName or BCR.GetTraitDisplayName(result.id) or "Unknown"
    if action == "added" then
        local actionText = getTextOrNull("UI_BCR_Gained") or "Gained"
        local text = actionText .. ": " .. displayName
        HaloTextHelper.addTextWithArrow(player, text, true, HALO_COLORS.gained[1], HALO_COLORS.gained[2], HALO_COLORS.gained[3])
    elseif action == "removed" then
        local actionText = getTextOrNull("UI_BCR_Lost") or "Lost"
        local text = actionText .. ": " .. displayName
        HaloTextHelper.addTextWithArrow(player, text, true, HALO_COLORS.lost[1], HALO_COLORS.lost[2], HALO_COLORS.lost[3])
    elseif action == "batch" then
        HaloTextHelper.addText(player, displayName, "", HALO_COLORS.batch[1], HALO_COLORS.batch[2], HALO_COLORS.batch[3])
    end
end

function BCR.ShowFinalMessage(player)
    if not player then return end
    local text = getTextOrNull("UI_BCR_AllRewardsGranted") or "All rewards granted!"
    HaloTextHelper.addText(player, text, "", HALO_COLORS.final[1], HALO_COLORS.final[2], HALO_COLORS.final[3])
end

-- Clears queued notifications and display state. Called on player
-- creation and after tests so stale entries never leak forward.
function BCR.ResetNotifications()
    notificationQueue = {}
    notificationTimer = 0
    isShowingNotification = false
end
