-- ============================================================
-- BodyCountRewards - Stats UI Module (Build 42.13.2)
-- 
-- Three-tab ISCollapsableWindow for player statistics:
--   - Tab 1 (Progress): Kill counter, progress bar, milestone roadmap
--   - Tab 2 (History): Chronological list of earned/removed traits
--   - Tab 3 (Catalog): All traits with status and drop chance %
-- 
-- Architecture:
--   BCRStatsWindow (ISCollapsableWindow)
--     - ISTabPanel
--          - BCRProgressPanel (custom ISPanel with cached drawing)
--          - ISRichTextPanel (history)
--          - ISRichTextPanel (catalog)
-- ============================================================

require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISPanel"
require "BCR_Shared"

BCR = BCR or {}


-- ===========================
-- UI CONFIGURATION

local UI_WIDTH = 520
local UI_HEIGHT = 550
local PADDING = 10
local TAB_CONTENT_OFFSET = 6

local COLORS = {
    -- Rarity tiers (match BCR.rarityColors but in 0-1 range with named keys)
    common = { r = 0.80, g = 0.80, b = 0.80 },
    uncommon = { r = 0.60, g = 1.00, b = 0.20 },
    rare = { r = 1.00, g = 0.60, b = 0.20 },
    veryRare = { r = 0.80, g = 0.30, b = 1.00 },

    -- Text roles
    sectionHead = { r = 1.00, g = 0.85, b = 0.40 },
    label = { r = 0.75, g = 0.75, b = 0.75 },
    value = { r = 1.00, g = 1.00, b = 1.00 },
    added = { r = 0.40, g = 1.00, b = 0.40 },
    removed = { r = 1.00, g = 0.45, b = 0.45 },
    empty = { r = 0.55, g = 0.55, b = 0.55 },
    disabled = { r = 0.40, g = 0.40, b = 0.40 },

    -- Progress bar
    barBg = { r = 0.15, g = 0.15, b = 0.15, a = 0.6 },
    barBorder = { r = 0.40, g = 0.40, b = 0.40, a = 0.6 },
    barFillLow = { r = 0.80, g = 0.30, b = 0.30 },
    barFillMid = { r = 0.90, g = 0.70, b = 0.20 },
    barFillHigh = { r = 0.30, g = 0.90, b = 0.40 },
}


-- ===========================
-- RICH TEXT HELPERS

local function colorTag(c)
    return string.format("<RGB:%.2f,%.2f,%.2f>", c.r, c.g, c.b)
end

local function rarityColor(rarity)
    return COLORS[rarity] or COLORS.common
end

local function formatNumber(n)
    local sep = getText("UI_BCR_ThousandSeparator")
    if not sep or sep == "UI_BCR_ThousandSeparator" then sep = "," end
    local formatted = tostring(math.floor(n))
    local k = 1
    while k > 0 do
        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1" .. sep .. "%2")
    end
    return formatted
end


-- ===========================
-- TAB 1: PROGRESS PANEL
-- Custom ISPanel using cached data (no per-frame recalculation)
-- Layout: Kill counter → Progress bar → Stats grid → Milestone roadmap

BCRProgressPanel = ISPanel:derive("BCRProgressPanel")

function BCRProgressPanel:new(x, y, w, h, parentWindow)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.parentWindow = parentWindow
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.cached = nil  -- Populated by updateContent(), drawn by prerender()
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

    ------------------------------------------------------------
    -- BRANCH: All rewards earned → show completion banner only
    ------------------------------------------------------------
    if d.allComplete then
        -- Show "All rewards earned!" as the primary heading
        -- (replaces Kill Counter, Progress Bar, Next Reward, Kills Remaining)
        self:drawText(
            getText("UI_BCR_AllComplete") or "All rewards earned!",
            x, y, 1.0, 0.85, 0.4, 1, UIFont.Medium
        )
        y = y + 36

        -- Total Rewards
        self:drawText(
            (getText("UI_BCR_TotalRewards") or "Total Rewards") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            tostring(d.rewardsGiven),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Total Zombie Kills (still useful info)
        self:drawText(
            (getText("UI_BCR_ZombieKills") or "Zombie Kills") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.kills),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Scaling Mode
        self:drawText(
            (getText("UI_BCR_ScalingMode") or "Scaling Mode") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.scalingLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Reward Priority
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
        --------------------------------------------------------
        -- NORMAL STATE: Kill Counter, Progress Bar, Stats
        --------------------------------------------------------

        -- Kill Counter (header + large number)
        self:drawText(
            getText("UI_BCR_ZombieKills") or "Zombie Kills",
            x, y, 1.0, 0.85, 0.4, 1, UIFont.Medium
        )
        y = y + 28

        self:drawText(formatNumber(d.kills), x + 4, y, 1, 1, 1, 1, UIFont.Large)
        y = y + 44

        -- Progress Bar (background → fill → border → label)
        local barX = x
        local barY = y
        local barW = contentWidth
        local barH = 22

        -- Background
        self:drawRect(barX, barY, barW, barH,
            COLORS.barBg.a, COLORS.barBg.r, COLORS.barBg.g, COLORS.barBg.b)

        -- Fill (color based on progress %)
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

        -- Border
        self:drawRectBorder(barX, barY, barW, barH,
            COLORS.barBorder.a, COLORS.barBorder.r, COLORS.barBorder.g, COLORS.barBorder.b)

        -- Centered label
        local progressLabel = formatNumber(d.progressCurrent) .. " / " .. formatNumber(d.progressMax)
        local labelW = getTextManager():MeasureStringX(UIFont.Small, progressLabel)
        local fontH = getTextManager():MeasureStringY(UIFont.Small, progressLabel)
        local textY = barY + math.floor((barH - fontH) / 2)
        self:drawText(progressLabel, barX + (barW - labelW) / 2, textY, 1, 1, 1, 1, UIFont.Small)

        y = barY + barH + 20

        -- Next Reward At
        self:drawText(
            (getText("UI_BCR_NextRewardAt") or "Next Reward at") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.nextMilestone) .. " " .. (getText("UI_BCR_Kills") or "kills"),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Kills Remaining
        self:drawText(
            (getText("UI_BCR_KillsRemaining") or "Kills Remaining") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            formatNumber(d.killsRemaining),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Total Rewards
        self:drawText(
            (getText("UI_BCR_TotalRewards") or "Total Rewards") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            tostring(d.rewardsGiven),
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Scaling Mode
        self:drawText(
            (getText("UI_BCR_ScalingMode") or "Scaling Mode") .. ":",
            x, y, COLORS.label.r, COLORS.label.g, COLORS.label.b, 1, UIFont.Small
        )
        self:drawText(
            d.scalingLabel,
            valX, y, COLORS.value.r, COLORS.value.g, COLORS.value.b, 1, UIFont.Small
        )
        y = y + lineH

        -- Reward Priority
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

    ------------------------------------------------------------
    -- SECTION: Milestone Roadmap (shown in both states)
    ------------------------------------------------------------
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

            -- [status] #number    kills
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



-- ===========================
-- MAIN WINDOW (ISCollapsableWindow with ISTabPanel)

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

    -- Tab panel fills window below title bar
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

    ------------------------------------------------------------
    -- TAB 1: Progress (custom BCRProgressPanel)
    ------------------------------------------------------------
    self.progressPanel = BCRProgressPanel:new(0, 0, contentW, contentH, self)
    self.progressPanel:initialise()
    self.progressPanel:setAnchorRight(true)
    self.progressPanel:setAnchorBottom(true)
    self.tabs:addView(getText("UI_BCR_TabProgress") or "Progress", self.progressPanel)

    ------------------------------------------------------------
    -- TAB 2: History (ISRichTextPanel, scrollable)
    ------------------------------------------------------------
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

    ------------------------------------------------------------
    -- TAB 3: Catalog (ISRichTextPanel, scrollable)
    ------------------------------------------------------------
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

function BCRStatsWindow:getBCRData()
    if not self.player then return nil end
    local modData = self.player:getModData()
    if not modData then return nil end
    return modData.BCR
end


-- ===========================
-- TAB 2: HISTORY CONTENT BUILDER
-- Renders chronological list of trait changes (newest first)

function BCRStatsWindow:buildHistoryText(bcrData)
    local text = ""
    local history = bcrData.traitHistory or {}

    if #history == 0 then
        text = text .. colorTag(COLORS.empty)
        text = text .. (getText("UI_BCR_NoTraitsYet") or "No rewards yet. Time to rack up your count!")
        return text
    end

    -- Header
    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_EarnedRewards") or "Earned Rewards")
    text = text .. " <LINE> <TEXT> "

    -- Entries (reverse chronological)
    for i = #history, 1, -1 do
        local entry = history[i]
        local displayName = BCR.getTraitDisplayName(entry.trait) or entry.trait
        local rarity = entry.rarity or "common"
        local rarityLabel = getText("UI_BCR_Rarity_" .. rarity) or rarity
        local action = entry.action or "added"

        text = text .. "<INDENT:16>"

        -- +/- prefix with action color, rarity in same color
        if action == "added" then
            text = text .. colorTag(COLORS.added)
            text = text .. "+ " .. displayName .. " (" .. rarityLabel .. ")"
        else
            text = text .. colorTag(COLORS.removed)
            text = text .. "- " .. displayName .. " (" .. rarityLabel .. ")"
        end

        text = text .. " <LINE> "
    end

    return text
end


-- ===========================
-- TAB 3: CATALOG CONTENT BUILDER
-- Shows all traits with status: drop chance %, or reason unavailable

function BCRStatsWindow:buildCatalogText(bcrData, opts)
    local text = ""
    local player = self.player

    -- Legend
    text = text .. colorTag(COLORS.label)
    text = text .. (getText("UI_BCR_CatalogLegend") or "% = Chance to receive as next reward")
    text = text .. " <LINE> "

    ------------------------------------------------------------
    -- Build pools for probability calculation
    ------------------------------------------------------------
    local earnablePool = {}
    local earnableTotalWeight = 0
    if player and opts.givePositiveTraits then
        local pool = BCR.getEarnableTraits(player) or {}
        for _, entry in ipairs(pool) do
            earnablePool[entry.trait] = entry
            earnableTotalWeight = earnableTotalWeight + entry.weight
        end
    end

    local removablePool = {}
    local removableTotalWeight = 0
    if player and opts.removeNegativeTraits then
        local pool = BCR.getRemovableTraits(player) or {}
        for _, entry in ipairs(pool) do
            removablePool[entry.trait] = entry
            removableTotalWeight = removableTotalWeight + entry.weight
        end
    end

    -- History lookup for "already earned/removed" status
    local modGranted = {}
    local modRemoved = {}
    for _, h in ipairs(bcrData.traitHistory or {}) do
        if h.action == "added" then
            modGranted[h.trait] = true
        elseif h.action == "removed" then
            modRemoved[h.trait] = true
        end
    end

    ------------------------------------------------------------
    -- Trait line renderer (shows % or unavailable reason)
    ------------------------------------------------------------
    local function renderTraitLine(traitID, cost, poolLookup, totalWeight, isPositive)
        local line = ""
        local displayName = BCR.getTraitDisplayName(traitID) or traitID
        local rarity = BCR.getRarityTier(cost)
        local rarityLabel = getText("UI_BCR_Rarity_" .. rarity) or rarity
        local isInPool = poolLookup[traitID] ~= nil
        local isAllowed = BCR.isTraitAllowed(traitID)

        line = line .. " <INDENT:16> "

        -- Available: show drop chance %
        if isInPool and totalWeight > 0 then
            local weight = poolLookup[traitID].weight
            local chance = (weight / totalWeight) * 100
            line = line .. colorTag(rarityColor(rarity))
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
                        .. string.format("%.1f%% ", chance)

        -- Unavailable: show reason with proper formatting
        elseif not isAllowed then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusServerDisabled") or "Server Disabled")

        elseif isPositive and modGranted[traitID] then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusEarned") or "Already")

        elseif not isPositive and modRemoved[traitID] then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusRemoved") or "Already Removed")

        elseif isPositive and BCR.playerHasTrait(player, traitID) then
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            line = line .. (getText("UI_BCR_StatusOwned") or "Already Owned")

        else
            -- Mutual exclusion or other unavailability
            local hasConflict, blockerID = BCR.hasMutuallyExclusiveTrait(player, traitID)
            line = line .. colorTag(COLORS.disabled)
            line = line .. displayName .. " (" .. rarityLabel .. ") - "
            if hasConflict and blockerID then
                local blockerName = BCR.getTraitDisplayName(blockerID) or blockerID
                local conflictStr = getText("UI_BCR_StatusConflict") or "Conflicts with %1"
                line = line .. string.gsub(conflictStr, "%%1", blockerName)
            else
                line = line .. (getText("UI_BCR_StatusUnavailable") or "Unavailable")
            end
        end

        line = line .. " <LINE> "
        return line
    end


    ------------------------------------------------------------
    -- Positive Traits Section
    ------------------------------------------------------------
    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_CatalogPositive") or "Earnable Positive Traits")
    text = text .. " <LINE><TEXT> "

    if not opts.givePositiveTraits then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.disabled)
        text = text .. (getText("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        for _, entry in ipairs(BCR.PositiveTraitsList) do
            text = text .. renderTraitLine(entry.trait, entry.cost, earnablePool, earnableTotalWeight, true)
        end
    end

    text = text .. " <INDENT:0> <BR> "

    ------------------------------------------------------------
    -- Negative Traits Section (only shows relevant traits)
    ------------------------------------------------------------
    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getText("UI_BCR_CatalogNegative") or "Removable Negative Traits")
    text = text .. " <LINE><TEXT> "

    if not opts.removeNegativeTraits then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.disabled)
        text = text .. (getText("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        -- Only show traits player has or BCR already removed
        local hasRelevantTraits = false
        for _, entry in ipairs(BCR.NegativeTraitsList) do
            local isRelevant = BCR.playerHasTrait(player, entry.trait) or modRemoved[entry.trait]
            if isRelevant then
                hasRelevantTraits = true
                text = text .. renderTraitLine(entry.trait, entry.cost, removablePool, removableTotalWeight, false)
            end
        end

        -- No negative traits found: player was created without any
        if not hasRelevantTraits then
            text = text .. " <INDENT:16> " .. colorTag(COLORS.empty)
            text = text .. (getText("UI_BCR_NoNegativeTraits") or "No negative traits found. Character was created without any.")
            text = text .. " <LINE> "
        end
    end

    return text
end


-- ===========================
-- CONTENT REFRESH
-- Called once on open and when data changes (not per-frame)

function BCRStatsWindow:updateContent()
    local bcrData = self:getBCRData()
    local noDataMsg = colorTag(COLORS.empty) .. (getText("UI_BCR_NoData") or "No data available.")

    if not bcrData then
        self.progressPanel.cached = nil
        self.historyPanel.text = noDataMsg
        self.historyPanel:paginate()
        self.catalogPanel.text = noDataMsg
        self.catalogPanel:paginate()
        return
    end

    local opts = BCR.getSandboxOptions()

    ------------------------------------------------------------
    -- Calculate progress data for Tab 1
    ------------------------------------------------------------
    local kills = bcrData.kills or 0
    local rewardsGiven = bcrData.rewardsGiven or 0
    local nextMilestone = BCR.getKillsForMilestone(rewardsGiven + 1, opts)
    local prevMilestone = BCR.getKillsForMilestone(rewardsGiven, opts)

    local progress = 0
    if nextMilestone > prevMilestone then
        progress = math.min(1, (kills - prevMilestone) / (nextMilestone - prevMilestone))
    end

    -- Scaling label (includes factor for progressive mode)
    local scalingLabel
    if opts.MilestoneScaling == 2 then
        local factor = opts.ProgressiveScalingFactor or 1.0
        scalingLabel = (getText("UI_BCR_ScalingProgressive") or "Progressive")
            .. " (x" .. string.format("%.1f", factor) .. ")"
    else
        scalingLabel = getText("UI_BCR_ScalingLinear") or "Linear"
    end

    -- Reward priority label
    local rewardPriorityLabel
    if opts.rewardPriority == 2 then
        rewardPriorityLabel = getText("UI_BCR_PriorityLoseFirst") or "Remove Negative First"
    elseif opts.rewardPriority == 3 then
        rewardPriorityLabel = getText("UI_BCR_PriorityRandom") or "Random"
    else
        rewardPriorityLabel = getText("UI_BCR_PriorityGainFirst") or "Gain Positive First"
    end

    -- Milestone roadmap: last 2 completed + next 5 upcoming
    -- When all complete: only show last few completed milestones, stop at maximum
    local SHOW_PAST = 2
    local SHOW_FUTURE = 5
    local allComplete = not BCR.HasAvailableRewards(self.player)

    local msStart, msEnd

    if allComplete then
        -- All rewards earned: show only completed milestones, capped at rewardsGiven
        msStart = math.max(1, rewardsGiven - (SHOW_PAST + SHOW_FUTURE - 1))
        msEnd = rewardsGiven  -- Stop at last earned milestone (the maximum)
    else
        -- Normal: show past 2 + next 5
        msStart = math.max(1, rewardsGiven - SHOW_PAST + 1)
        msEnd = rewardsGiven + SHOW_FUTURE
    end

    local milestones = {}
    for m = msStart, msEnd do
        table.insert(milestones, {
            number = m,
            killsNeeded = BCR.getKillsForMilestone(m, opts),
            reached = m <= rewardsGiven,
            isCurrent = m == rewardsGiven + 1,
        })
    end

    -- Cache all progress data for drawing
    self.progressPanel.cached = {
        kills = kills,
        rewardsGiven = rewardsGiven,
        nextMilestone = nextMilestone,
        killsRemaining = math.max(0, nextMilestone - kills),
        progress = progress,
        progressCurrent = kills - prevMilestone,
        progressMax = nextMilestone - prevMilestone,
        scalingLabel = scalingLabel,
        rewardPriorityLabel = rewardPriorityLabel,
        milestones = milestones,
        allComplete = allComplete,
    }

    ------------------------------------------------------------
    -- Build rich text for Tab 2 & Tab 3
    ------------------------------------------------------------
    self.historyPanel.text = self:buildHistoryText(bcrData)
    self.historyPanel:paginate()

    self.catalogPanel.text = self:buildCatalogText(bcrData, opts)
    self.catalogPanel:paginate()
end


-- ===========================
-- WINDOW LIFECYCLE

function BCRStatsWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    BCR.statsWindow = nil
end

function BCRStatsWindow:prerender()
    ISCollapsableWindow.prerender(self)
end

function BCRStatsWindow:render()
    ISCollapsableWindow.render(self)
end


-- ===========================
-- PUBLIC API

function BCR.showStatsWindow(player)
    if BCR.statsWindow and BCR.statsWindow:isVisible() then
        BCR.statsWindow:close()
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

    BCR.statsWindow = window
end

function BCR.refreshStatsWindow()
    if BCR.statsWindow and BCR.statsWindow:isVisible() then
        BCR.statsWindow:updateContent()
    end
end
