-- ============================================================
-- BodyCountRewards v1.3.0 — BCRStatsUI (Build 42.19+)
-- Stats window: ISCollapsableWindow with 3 tabs
-- (progress, history, catalog).
-- ============================================================

require "BCRCore"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISPanel"

BCR = BCR or {}

-- ============================================================
-- LOCAL STATE
-- ============================================================

local statsWindow = nil
local UI_WIDTH = 520
local UI_HEIGHT = 550
local PADDING = 10
local TAB_CONTENT_OFFSET = 6

-- ============================================================
-- COLORS (named keys for clarity)
-- ============================================================

local COLORS = {
    common = { r = 0.80, g = 0.80, b = 0.80 },
    uncommon = { r = 0.60, g = 1.00, b = 0.20 },
    rare = { r = 1.00, g = 0.60, b = 0.20 },
    veryRare = { r = 0.80, g = 0.30, b = 1.00 },
    sectionHead = { r = 1.00, g = 0.85, b = 0.40 },
    label = { r = 0.75, g = 0.75, b = 0.75 },
    value = { r = 1.00, g = 1.00, b = 1.00 },
    added = { r = 0.40, g = 1.00, b = 0.40 },
    removed = { r = 1.00, g = 0.45, b = 0.45 },
    empty = { r = 0.55, g = 0.55, b = 0.55 },
    disabled = { r = 0.40, g = 0.40, b = 0.40 },
    barBg = { r = 0.15, g = 0.15, b = 0.15, a = 0.6 },
    barBorder = { r = 0.40, g = 0.40, b = 0.40, a = 0.6 },
    barFillLow = { r = 0.80, g = 0.30, b = 0.30 },
    barFillMid = { r = 0.90, g = 0.70, b = 0.20 },
    barFillHigh = { r = 0.30, g = 0.90, b = 0.40 },
}

-- ============================================================
-- HELPERS
-- ============================================================

local function colorTag(color)
    return string.format("<RGB:%.2f,%.2f,%.2f>", color.r, color.g, color.b)
end

local function rarityColor(rarity)
    return COLORS[rarity] or COLORS.common
end

local function getBCRData(player)
    if not player then return nil end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or not modData then return nil end
    return modData.BCR
end

local function formatNumber(number)
    if not number then return "0" end
    local sep = getText("UI_BCR_ThousandSeparator")
    if not sep or sep == "UI_BCR_ThousandSeparator" then sep = "," end
    local formatted = tostring(math.floor(number))
    local k = 1
    while k > 0 do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
    end
    return formatted
end

-- ============================================================
-- BCRProgressPanel — ISPanel subclass with dirty-flag prerender
-- ============================================================

BCRProgressPanel = ISPanel:derive("BCRProgressPanel")

function BCRProgressPanel:new(x, y, w, h, parentWindow)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.parentWindow = parentWindow
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.cached = nil
    o.player = parentWindow.player
    return o
end

function BCRProgressPanel:initialise()
    ISPanel.initialise(self)
end

function BCRProgressPanel:prerender()
    ISPanel.prerender(self)
    self:drawProgressContent()
end

function BCRProgressPanel:drawProgressContent()
    local d = self.cached
    if not d then
        self:drawText(
            getText("UI_BCR_NoData") or "No data available.",
            PADDING, PADDING + TAB_CONTENT_OFFSET,
            0.55, 0.55, 0.55, 1, UIFont.Medium
        )
        return
    end

    local x = PADDING
    local y = PADDING + TAB_CONTENT_OFFSET
    local contentWidth = self.width - (PADDING * 2)
    local lineH = 24
    local valX = x + 190

    if d.allComplete then
        self:drawText(
            getText("UI_BCR_AllComplete") or "All rewards earned!",
            x, y, 1.0, 0.85, 0.4, 1, UIFont.Medium
        )
        y = y + 36

        self:drawText(
            (getText("UI_BCR_TotalRewards") or "Total Rewards") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            tostring(d.rewardsGiven),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_ZombieKills") or "Zombie Kills") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.kills),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_ScalingMode") or "Scaling Mode") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.scalingLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_RewardPriority") or "Reward Priority") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.rewardPriorityLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH
    else
        self:drawText(
            getText("UI_BCR_ZombieKills") or "Zombie Kills",
            x, y, 1.0, 0.85, 0.4, 1, UIFont.Medium
        )
        y = y + 28

        self:drawText(formatNumber(d.kills), x + 4, y, 1, 1, 1, 1, UIFont.Large)
        y = y + 44

        local barX = x
        local barY = y
        local barW = contentWidth
        local barH = 22

        self:drawRect(barX, barY, barW, barH,
            COLORS.barBg.a, COLORS.barBg.r, COLORS.barBg.g, COLORS.barBg.b)

        local fillW = math.floor(barW * d.progress)
        if fillW > 0 then
            local fc
            if d.progress >= 0.75 then
                fc = COLORS.barFillHigh
            elseif d.progress >= 0.35 then
                fc = COLORS.barFillMid
            else
                fc = COLORS.barFillLow
            end
            self:drawRect(barX, barY, fillW, barH, 0.85, fc.r, fc.g, fc.b)
        end

        self:drawRectBorder(barX, barY, barW, barH,
            COLORS.barBorder.a, COLORS.barBorder.r, COLORS.barBorder.g, COLORS.barBorder.b)

        local progressLabel = formatNumber(d.progressCurrent) .. " / " .. formatNumber(d.progressMax)
        local labelW = getTextManager():MeasureStringX(UIFont.Small, progressLabel)
        local fontH = getTextManager():MeasureStringY(UIFont.Small, progressLabel)
        local textY = barY + math.floor((barH - fontH) / 2)
        self:drawText(progressLabel, barX + (barW - labelW) / 2, textY, 1, 1, 1, 1, UIFont.Small)

        y = barY + barH + 20

        self:drawText(
            (getText("UI_BCR_NextRewardAt") or "Next Reward at") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.nextMilestone) .. " " .. (getText("UI_BCR_Kills") or "kills"),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_KillsRemaining") or "Kills Remaining") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.killsRemaining),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_TotalRewards") or "Total Rewards") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            tostring(d.rewardsGiven),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_ScalingMode") or "Scaling Mode") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.scalingLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        self:drawText(
            (getText("UI_BCR_RewardPriority") or "Reward Priority") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.rewardPriorityLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH
    end

    if d.milestones and #d.milestones > 0 then
        y = y + 16
        self:drawText(
            getText("UI_BCR_MilestoneRoadmap") or "Milestone Roadmap",
            x, y,
            COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1,
            UIFont.Medium
        )
        y = y + 30

        local msLabelX = x + 28
        local msKillsX = valX

        for _, ms in ipairs(d.milestones) do
            local prefix, cr, cg, cb
            if ms.reached then
                prefix = getText("UI_BCR_MilestoneReached") or "[x]"
                cr, cg, cb = COLORS.added.r, COLORS.added.g, COLORS.added.b
            elseif ms.isCurrent then
                prefix = getText("UI_BCR_MilestoneCurrent") or "[>]"
                cr, cg, cb = COLORS.value.r, COLORS.value.g, COLORS.value.b
            else
                prefix = getText("UI_BCR_MilestoneFuture") or "[ ]"
                cr, cg, cb = COLORS.label.r, COLORS.label.g, COLORS.label.b
            end

            self:drawText(prefix, x, y, cr, cg, cb, 1, UIFont.Small)
            self:drawText("#" .. tostring(ms.number), msLabelX, y, cr, cg, cb, 1, UIFont.Small)
            self:drawText(
                formatNumber(ms.killsNeeded) .. " " .. (getText("UI_BCR_Kills") or "kills"),
                msKillsX, y, cr, cg, cb, 1, UIFont.Small
            )
            y = y + lineH
        end
    end
end

-- ============================================================
-- BCRStatsWindow — ISCollapsableWindow subclass
-- ============================================================

BCRStatsWindow = ISCollapsableWindow:derive("BCRStatsWindow")

function BCRStatsWindow:new(x, y, w, h, player)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title = getText("UI_BCR_StatsTitle") or "Performance Review"
    o.resizable = false
    o.player = player
    return o
end

function BCRStatsWindow:initialise()
    ISCollapsableWindow.initialise(self)
end

function BCRStatsWindow:createChildren()
    ISCollapsableWindow.createChildren(self)

    local tabX = 0
    local tabY = self:titleBarHeight()
    local tabW = self.width
    local tabH = self.height - tabY

    self.tabs = ISTabPanel:new(tabX, tabY, tabW, tabH)
    self.tabs:initialise()
    self.tabs:setAnchorRight(true)
    self.tabs:setAnchorBottom(true)
    self:addChild(self.tabs)

    local contentW = tabW
    local contentH = tabH - self.tabs.tabHeight

    self.progressPanel = BCRProgressPanel:new(0, 0, contentW, contentH, self)
    self.progressPanel:initialise()
    self.progressPanel:setAnchorRight(true)
    self.progressPanel:setAnchorBottom(true)
    self.tabs:addView(getText("UI_BCR_TabProgress") or "Progress", self.progressPanel)

    self.historyPanel = ISRichTextPanel:new(0, 0, contentW, contentH)
    self.historyPanel:initialise()
    self.historyPanel.autosetheight = false
    self.historyPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.historyPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.historyPanel.marginLeft = PADDING
    self.historyPanel.marginTop = PADDING
    self.historyPanel.marginRight = PADDING
    self.historyPanel.clip = true
    self.historyPanel:addScrollBars()
    self.historyPanel:setScrollChildren(true)
    self.historyPanel:setAnchorRight(true)
    self.historyPanel:setAnchorBottom(true)
    self.tabs:addView(getText("UI_BCR_TabHistory") or "History", self.historyPanel)

    self.catalogPanel = ISRichTextPanel:new(0, 0, contentW, contentH)
    self.catalogPanel:initialise()
    self.catalogPanel.autosetheight = false
    self.catalogPanel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    self.catalogPanel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    self.catalogPanel.marginLeft = PADDING
    self.catalogPanel.marginTop = PADDING
    self.catalogPanel.marginRight = PADDING
    self.catalogPanel.clip = true
    self.catalogPanel:addScrollBars()
    self.catalogPanel:setScrollChildren(true)
    self.catalogPanel:setAnchorRight(true)
    self.catalogPanel:setAnchorBottom(true)
    self.tabs:addView(getText("UI_BCR_TabCatalog") or "Catalog", self.catalogPanel)
end

function BCRStatsWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    statsWindow = nil
end

function BCRStatsWindow:prerender()
    ISCollapsableWindow.prerender(self)
end

-- ============================================================
-- TAB 2: HISTORY CONTENT
-- ============================================================

function BCRStatsWindow:updateHistory()
    local bcrData = getBCRData(self.player)
    local text = ""
    local history = bcrData and bcrData.traitHistory or {}
    local count = 0
    for _ in pairs(history) do count = count + 1 end

    if count == 0 then
        text = text .. colorTag(COLORS.empty)
        text = text .. (getText("UI_BCR_NoTraitsYet") or "No rewards yet. Time to rack up your count!")
        self.historyPanel.text = text
        self.historyPanel:paginate()
        return
    end

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_EarnedRewards") or "Earned Rewards")
    text = text .. " <LINE> <TEXT> "

    for i = count, 1, -1 do
        local entry = history[i]
        local displayName = BCR.GetTraitDisplayName(entry.id) or entry.id
        local rarity = entry.rarity or "common"
        local rarityLabel = getText("UI_BCR_Rarity_" .. rarity) or rarity

        text = text .. "<INDENT:16>"
        if entry.action == "added" then
            text = text .. colorTag(COLORS.added)
            text = text .. "+ " .. displayName .. " (" .. rarityLabel .. ")"
        else
            text = text .. colorTag(COLORS.removed)
            text = text .. "- " .. displayName .. " (" .. rarityLabel .. ")"
        end
        text = text .. " <LINE> "
    end

    self.historyPanel.text = text
    self.historyPanel:paginate()
end

-- ============================================================
-- TAB 3: CATALOG CONTENT
-- ============================================================

function BCRStatsWindow:updateCatalog()
    local bcrData = getBCRData(self.player)
    local opts = BCR.opts
    if not opts then
        BCR.RefreshConfig()
        opts = BCR.opts
    end

    local earnablePool = {}
    if self.player and opts.enablePositive ~= false then
        local pool = BCR.BuildEarnablePool(self.player) or {}
        for _, entry in ipairs(pool) do
            earnablePool[entry.id] = entry
        end
    end

    local removablePool = {}
    if self.player and opts.enableNegative ~= false then
        local pool = BCR.BuildRemovablePool(self.player) or {}
        for _, entry in ipairs(pool) do
            removablePool[entry.id] = entry
        end
    end

    local modGranted = {}
    local modRemoved = {}
    for _, h in ipairs(bcrData and bcrData.traitHistory or {}) do
        if h.action == "added" then
            modGranted[h.id] = true
        elseif h.action == "removed" then
            modRemoved[h.id] = true
        end
    end

    local function renderTraitLine(traitId, cost, poolLookup, isPositive)
        local line = ""
        local displayName = BCR.GetTraitDisplayName(traitId) or traitId
        local rarity = BCR.GetRarity(cost)
        local rarityLabel = getText("UI_BCR_Rarity_" .. rarity) or rarity
        local isInPool = poolLookup[traitId] ~= nil
        local isAllowed = BCR.IsTraitAllowed(traitId)

        line = line .. " <INDENT:16> "

        if isInPool then
            line = line .. colorTag(rarityColor(rarity))
            line = line .. displayName .. " (" .. rarityLabel .. ")"
        elseif not isAllowed then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusServerDisabled") or "Server Disabled")
        elseif isPositive and modGranted[traitId] then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusEarned") or "Already Earned")
        elseif not isPositive and modRemoved[traitId] then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusRemoved") or "Already Removed")
        elseif isPositive and BCR.PlayerHasTrait(self.player, traitId) then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusOwned") or "Already Owned")
        else
            local hasConflict, blockerId = BCR.HasMutuallyExclusiveTrait(self.player, traitId)
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            if hasConflict and blockerId then
                local blockerName = BCR.GetTraitDisplayName(blockerId) or blockerId
                line = line .. getText("UI_BCR_StatusConflict", blockerName)
            else
                line = line .. (getText("UI_BCR_StatusUnavailable") or "Unavailable")
            end
        end

        line = line .. " <LINE> "
        return line
    end

    local text = ""

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_CatalogPositive") or "Earnable Positive Traits")
    text = text .. " <LINE><TEXT> "

    if opts.enablePositive == false then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.disabled)
        text = text .. (getText("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        for _, entry in ipairs(BCR.PositiveTraits) do
            local traitId = entry.id
            text = text .. renderTraitLine(traitId, entry.cost, earnablePool, true)
        end
    end

    text = text .. " <INDENT:0> <BR> "

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_CatalogNegative") or "Removable Negative Traits")
    text = text .. " <LINE><TEXT> "

    if opts.enableNegative == false then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.disabled)
        text = text .. (getText("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        local hasRelevantTraits = false
        for _, entry in ipairs(BCR.NegativeTraits) do
            local traitId = entry.id
            local isRelevant = BCR.PlayerHasTrait(self.player, traitId) or modRemoved[traitId]
            if isRelevant then
                hasRelevantTraits = true
                text = text .. renderTraitLine(traitId, entry.cost, removablePool, false)
            end
        end

        if not hasRelevantTraits then
            text = text .. " <INDENT:16> " .. colorTag(COLORS.empty)
            text = text .. (getText("UI_BCR_NoNegativeTraits") or "No negative traits found. Character was created without any.")
            text = text .. " <LINE> "
        end
    end

    self.catalogPanel.text = text
    self.catalogPanel:paginate()
end

-- ============================================================
-- PROGRESS DATA COMPUTATION
-- ============================================================

function BCRStatsWindow:updateProgress()
    local bcrData = getBCRData(self.player)
    if not bcrData then
        self.progressPanel.cached = nil
        return
    end

    BCR.RefreshConfig()
    local opts = BCR.opts
    if not opts then return end

    local ok, kills = pcall(function() return self.player:getZombieKills() end)
    if not ok then kills = 0 end
    local killsNum = kills or 0
    local rewardsGiven = bcrData.rewardsGiven or 0
    local nextMilestone = BCR.GetKillsForMilestone(rewardsGiven + 1, opts)
    local prevMilestone = BCR.GetKillsForMilestone(rewardsGiven, opts)

    local progress = 0
    if nextMilestone > prevMilestone then
        progress = math.min(1, (killsNum - prevMilestone) / (nextMilestone - prevMilestone))
    end

    local scalingLabel
    if opts.milestoneScaling == 2 then
        local factor = opts.progressiveScalingFactor or 1.0
        scalingLabel = (getText("UI_BCR_ScalingProgressive") or "Progressive")
            .. " (x" .. string.format("%.1f", factor) .. ")"
    else
        scalingLabel = getText("UI_BCR_ScalingLinear") or "Linear"
    end

    local rewardPriorityLabel
    if opts.rewardPriority == 2 then
        rewardPriorityLabel = getText("UI_BCR_PriorityLoseFirst") or "Remove Negative First"
    elseif opts.rewardPriority == 3 then
        rewardPriorityLabel = getText("UI_BCR_PriorityRandom") or "Random"
    else
        rewardPriorityLabel = getText("UI_BCR_PriorityGainFirst") or "Gain Positive First"
    end

    local allComplete = not BCR.HasAvailableRewards(self.player)

    local MILESTONE_PAST_COUNT = 2
    local MILESTONE_FUTURE_COUNT = 5
    local msStart, msEnd

    if allComplete then
        msStart = math.max(1, rewardsGiven - (MILESTONE_PAST_COUNT + MILESTONE_FUTURE_COUNT - 1))
        msEnd = rewardsGiven
    else
        local earnableCount = 0
        local earnable = BCR.BuildEarnablePool(self.player, nil)
        if earnable then
            for _ in ipairs(earnable) do earnableCount = earnableCount + 1 end
        end
        local removableCount = 0
        local removable = BCR.BuildRemovablePool(self.player, nil)
        if removable then
            for _ in ipairs(removable) do removableCount = removableCount + 1 end
        end
        local rewardsLeft = earnableCount + removableCount
        msStart = math.max(1, rewardsGiven - MILESTONE_PAST_COUNT + 1)
        msEnd = math.min(rewardsGiven + MILESTONE_FUTURE_COUNT, rewardsGiven + rewardsLeft)
    end

    local milestones = {}
    for m = msStart, msEnd do
        table.insert(milestones, {
            number = m,
            killsNeeded = BCR.GetKillsForMilestone(m, opts),
            reached = m <= rewardsGiven,
            isCurrent = m == rewardsGiven + 1,
        })
    end

    self.progressPanel.cached = {
        kills = killsNum,
        rewardsGiven = rewardsGiven,
        nextMilestone = nextMilestone,
        killsRemaining = math.max(0, nextMilestone - killsNum),
        progress = progress,
        progressCurrent = killsNum - prevMilestone,
        progressMax = nextMilestone - prevMilestone,
        scalingLabel = scalingLabel,
        rewardPriorityLabel = rewardPriorityLabel,
        milestones = milestones,
        allComplete = allComplete,
    }
end

-- ============================================================
-- CONTENT REFRESH
-- ============================================================

function BCRStatsWindow:updateContent()
    self:updateProgress()
    self:updateHistory()
    self:updateCatalog()
end

-- ============================================================
-- PUBLIC API
-- ============================================================

function BCR.ShowStatsWindow(player)
    if not player then return end
    if statsWindow and statsWindow:isVisible() then
        statsWindow:close()
        return
    end

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x = (sw - UI_WIDTH) / 2
    local y = (sh - UI_HEIGHT) / 2

    local window = BCRStatsWindow:new(x, y, UI_WIDTH, UI_HEIGHT, player)
    window:initialise()
    window:addToUIManager()
    window:setVisible(true)
    window:updateContent()

    statsWindow = window
end

function BCR.RefreshStatsWindow()
    if statsWindow and statsWindow:isVisible() then
        statsWindow:updateContent()
    end
end
