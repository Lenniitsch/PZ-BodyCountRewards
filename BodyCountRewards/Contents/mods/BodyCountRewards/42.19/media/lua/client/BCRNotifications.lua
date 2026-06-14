-- ============================================================
-- BodyCountRewards v1.3.0 — BCRNotifications (Build 42.19+)
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
local NOTIFICATION_DELAY_TICKS = 200

-- ============================================================
-- PUBLIC FUNCTIONS
-- ============================================================

function BCR.EnqueueNotification(result)
    if not result then return end
    if #notificationQueue >= BCR.MAX_NOTIFICATION_QUEUE then
        notificationQueue = {
            {
                id = "BATCH",
                displayName = getText("UI_BCR_BatchRewards") or (tostring(#notificationQueue + 1) .. " rewards"),
                action = "batch",
                rarity = "common",
                color = { 1, 1, 1 },
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
            if notificationTimer >= NOTIFICATION_DELAY_TICKS then
                isShowingNotification = false
                notificationTimer = 0
            end
        end
        return
    end
    if isShowingNotification then
        notificationTimer = notificationTimer + 1
        if notificationTimer >= NOTIFICATION_DELAY_TICKS then
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
    BCR.DebugPrint(string.format("[Client] Showing notification (%d remaining)", #notificationQueue))
    local action = result.action or "added"
    local displayName = result.displayName or BCR.GetTraitDisplayName(result.id) or "Unknown"
    if action == "added" then
        local text = getText("UI_BCR_Gained") or "Gained: "
        HaloTextHelper.addTextWithArrow(player, text .. displayName, true, 0, 255, 0)
    elseif action == "removed" then
        local text = getText("UI_BCR_Lost") or "Lost: "
        HaloTextHelper.addTextWithArrow(player, text .. displayName, true, 255, 165, 0)
    elseif action == "batch" then
        HaloTextHelper.addText(player, displayName, "", 200, 200, 200)
    end
end

function BCR.ShowFinalMessage(player)
    if not player then return end
    local text = getText("UI_BCR_AllRewardsGranted") or "All rewards granted!"
    HaloTextHelper.addText(player, text, "", 255, 255, 255)
end
