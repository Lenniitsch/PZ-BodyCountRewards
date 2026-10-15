-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRStatsUI (Build 42.21+)
-- Stats window: ISCollapsableWindow with 3 tabs
-- (progress, history, catalog).
-- ============================================================

require "BCRCore"
require "BCRStatsData"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISTabPanel"
require "ISUI/ISRichTextPanel"
require "ISUI/ISPanel"

BCR = BCR or {}

-- ============================================================
-- LOCAL STATE
-- ============================================================

local statsWindow = nil
local statsDirty = false
local UI_WIDTH = 520
local UI_HEIGHT = 550
local PADDING = 10
local TAB_CONTENT_OFFSET = 6
local LINE_H = 24
local VAL_X_OFFSET = 190
local VALUE_GAP = 8

-- Layout constants (progress panel)
local HEADER_GAP = 36
local SECTION_HEAD_GAP = 28
local BIG_NUMBER_GAP = 44
local BAR_HEIGHT = 22
local BAR_BOTTOM_GAP = 20
local SECTION_GAP = 16
local ROADMAP_HEAD_GAP = 30
local MS_NUMBER_X = 28
local KILLS_INSET = 4
local BAR_HIGH_THRESHOLD = 0.75
local BAR_MID_THRESHOLD = 0.35
local BAR_FILL_ALPHA = 0.85

-- ============================================================
-- COLORS (named keys for clarity)
-- ============================================================

local COLORS = {
    text = { r = 0.85, g = 0.85, b = 0.85 },
    dim = { r = 0.55, g = 0.55, b = 0.55 },
    sectionHead = { r = 1.00, g = 0.85, b = 0.40 },
    bright = {
        common = { r = 0.55, g = 0.65, b = 0.70 },
        uncommon = { r = 0.50, g = 1.00, b = 0.15 },
        rare = { r = 1.00, g = 0.55, b = 0.15 },
        veryRare = { r = 0.75, g = 0.25, b = 1.00 },
    },
    empty = { r = 0.55, g = 0.55, b = 0.55 },
    gainGreen = { r = 0.40, g = 1.00, b = 0.40 },
    lossRed = { r = 1.00, g = 0.40, b = 0.40 },
    plainWhite = { r = 1.00, g = 1.00, b = 1.00 },
    barBg = { r = 0.15, g = 0.15, b = 0.15, a = 0.6 },
    barBorder = { r = 0.40, g = 0.40, b = 0.40, a = 0.6 },
    barFillLow = { r = 0.80, g = 0.30, b = 0.30 },
    barFillMid = { r = 0.90, g = 0.70, b = 0.20 },
    barFillHigh = { r = 0.30, g = 0.90, b = 0.40 },
}

-- ============================================================
-- HELPERS
-- ============================================================

local function formatFloatLocaleSafe(value, decimals)
    local pattern = "%." .. tostring(decimals or 1) .. "f"
    -- Kahlua's string.format can use the JVM default locale (comma
    -- decimal separator in some locales) -- normalize to a dot.
    local formatted = string.format(pattern, value)
    return string.gsub(formatted, ",", ".")
end

local function colorTag(color)
    return string.format(
        "<RGB:%s,%s,%s>",
        formatFloatLocaleSafe(color.r, 2),
        formatFloatLocaleSafe(color.g, 2),
        formatFloatLocaleSafe(color.b, 2)
    )
end

local function rarityColor(rarity)
    return (COLORS.bright[rarity] or COLORS.bright.common)
end

local function getRarityLabel(rarity)
    return getTextOrNull("UI_BCR_Rarity_" .. tostring(rarity)) or tostring(rarity)
end

-- ISRichTextPanel parses any "<...>" token as a command; escape dynamic
-- (addon/ModData) values so they always render as plain text.
local function escapeRichText(text)
    if type(text) ~= "string" then return text end
    text = string.gsub(text, "<", "&lt;")
    return (string.gsub(text, ">", "&gt;"))
end

local function getBCRData(player)
    -- Route through EnsureModData so the UI never reads an
    -- unnormalized/corrupt ModData table.
    return BCR.EnsureModData(player)
end

local function formatNumber(value)
    if not value then return "0" end
    local sep = getTextOrNull("UI_BCR_ThousandSeparator") or ","
    if sep == "" then sep = "," end
    -- Keep the literal separator for the leading-separator strip below;
    -- `sep` itself becomes pattern-escaped for the gsub replacement.
    local literalSep = sep
    sep = sep:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
    local intPart = tostring(math.floor(value))
    local sign = ""
    if string.sub(intPart, 1, 1) == "-" then
        sign = "-"
        intPart = string.sub(intPart, 2)
    end
    local reversed = string.reverse(intPart)
    local grouped = string.gsub(reversed, "(%d%d%d)", "%1" .. sep)
    grouped = string.reverse(grouped)
    if string.sub(grouped, 1, #literalSep) == literalSep then
        grouped = string.sub(grouped, #literalSep + 1)
    end
    return sign .. grouped
end

-- Trims text with an ellipsis so it fits maxWidth in UIFont.Small.
-- Never splits a UTF-8 multi-byte sequence.
local function ellipsizeToWidth(text, maxWidth)
    if getTextManager():MeasureStringX(UIFont.Small, text) <= maxWidth then
        return text
    end
    local ellipsis = "..."
    local ellipsisWidth = getTextManager():MeasureStringX(UIFont.Small, ellipsis)
    local limit = #text
    while limit > 0 do
        local candidate = string.sub(text, 1, limit)
        if getTextManager():MeasureStringX(UIFont.Small, candidate) + ellipsisWidth <= maxWidth then
            break
        end
        limit = limit - 1
    end
    while limit > 0 do
        local nextByte = string.byte(text, limit + 1)
        if nextByte and nextByte >= 128 and nextByte < 192 then
            limit = limit - 1
        else
            break
        end
    end
    return string.sub(text, 1, limit) .. ellipsis
end

-- ============================================================
-- BCRProgressPanel -- draws the cached snapshot each frame; the
-- expensive data recompute is event-gated, not per-frame.
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

function BCRProgressPanel:prerender()
    ISPanel.prerender(self)
    self:drawProgressContent()
end

function BCRProgressPanel:drawStatRow(label, value, x, y)
    local valX = x + VAL_X_OFFSET
    label = ellipsizeToWidth(label, VAL_X_OFFSET - VALUE_GAP)
    self:drawText(label, x, y, COLORS.dim.r, COLORS.dim.g, COLORS.dim.b, 1, UIFont.Small)
    self:drawText(value, valX, y, COLORS.text.r, COLORS.text.g, COLORS.text.b, 1, UIFont.Small)
    return y + LINE_H
end

function BCRProgressPanel:drawProgressContent()
    local progress = self.cached
    if not progress then
        self:drawText(
            getTextOrNull("UI_BCR_NoData") or "No data available.",
            PADDING, PADDING + TAB_CONTENT_OFFSET,
            COLORS.empty.r, COLORS.empty.g, COLORS.empty.b, 1, UIFont.Medium
        )
        return
    end

    local x = PADDING
    local y = PADDING + TAB_CONTENT_OFFSET
    local contentWidth = self.width - (PADDING * 2)

    if progress.allComplete then
        self:drawText(
            getTextOrNull("UI_BCR_AllComplete") or "All rewards earned!",
            x, y, COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1, UIFont.Medium
        )
        y = y + HEADER_GAP

        y = self:drawStatRow((getTextOrNull("UI_BCR_TotalRewards") or "Total Rewards") .. ":", tostring(progress.rewardsGiven), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ZombieKills") or "Zombie Kills") .. ":", formatNumber(progress.kills), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ScalingMode") or "Scaling Mode") .. ":", progress.scalingLabel, x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_RewardPriority") or "Reward Priority") .. ":", progress.rewardPriorityLabel, x, y)
    else
        self:drawText(
            getTextOrNull("UI_BCR_ZombieKills") or "Zombie Kills",
            x, y, COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1, UIFont.Medium
        )
        y = y + SECTION_HEAD_GAP

        self:drawText(formatNumber(progress.kills), x + KILLS_INSET, y, COLORS.plainWhite.r, COLORS.plainWhite.g, COLORS.plainWhite.b, 1, UIFont.Large)
        y = y + BIG_NUMBER_GAP

        local barX = x
        local barY = y
        local barW = contentWidth
        local barH = BAR_HEIGHT

        self:drawRect(barX, barY, barW, barH,
            COLORS.barBg.a, COLORS.barBg.r, COLORS.barBg.g, COLORS.barBg.b)

        local fillW = math.floor(barW * progress.progress)
        if fillW > 0 then
            local fillColor
            if progress.progress >= BAR_HIGH_THRESHOLD then
                fillColor = COLORS.barFillHigh
            elseif progress.progress >= BAR_MID_THRESHOLD then
                fillColor = COLORS.barFillMid
            else
                fillColor = COLORS.barFillLow
            end
            self:drawRect(barX, barY, fillW, barH, BAR_FILL_ALPHA, fillColor.r, fillColor.g, fillColor.b)
        end

        self:drawRectBorder(barX, barY, barW, barH,
            COLORS.barBorder.a, COLORS.barBorder.r, COLORS.barBorder.g, COLORS.barBorder.b)

        local progressLabel = formatNumber(progress.progressCurrent) .. " / " .. formatNumber(progress.progressMax)
        local labelW = getTextManager():MeasureStringX(UIFont.Small, progressLabel)
        local fontH = getTextManager():MeasureStringY(UIFont.Small, progressLabel)
        local textY = barY + math.floor((barH - fontH) / 2)
        self:drawText(progressLabel, barX + (barW - labelW) / 2, textY, COLORS.plainWhite.r, COLORS.plainWhite.g, COLORS.plainWhite.b, 1, UIFont.Small)

        y = barY + barH + BAR_BOTTOM_GAP

        y = self:drawStatRow((getTextOrNull("UI_BCR_NextRewardAt") or "Next Reward at") .. ":", formatNumber(progress.nextMilestone) .. " " .. (getTextOrNull("UI_BCR_Kills") or "kills"), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_KillsRemaining") or "Kills Remaining") .. ":", formatNumber(progress.killsRemaining), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_TotalRewards") or "Total Rewards") .. ":", tostring(progress.rewardsGiven), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ScalingMode") or "Scaling Mode") .. ":", progress.scalingLabel, x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_RewardPriority") or "Reward Priority") .. ":", progress.rewardPriorityLabel, x, y)
    end

    if progress.milestones and #progress.milestones > 0 then
        y = y + SECTION_GAP
        self:drawText(
            getTextOrNull("UI_BCR_MilestoneRoadmap") or "Milestone Roadmap",
            x, y,
            COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1,
            UIFont.Medium
        )
        y = y + ROADMAP_HEAD_GAP

        local msLabelX = x + MS_NUMBER_X
        local msKillsX = x + VAL_X_OFFSET

        for _, ms in ipairs(progress.milestones) do
            local prefix, cr, cg, cb
            if ms.reached then
                prefix = getTextOrNull("UI_BCR_MilestoneReached") or "[x]"
                cr, cg, cb = COLORS.gainGreen.r, COLORS.gainGreen.g, COLORS.gainGreen.b
            elseif ms.isCurrent then
                prefix = getTextOrNull("UI_BCR_MilestoneCurrent") or "[>]"
                cr, cg, cb = COLORS.text.r, COLORS.text.g, COLORS.text.b
            else
                prefix = getTextOrNull("UI_BCR_MilestoneFuture") or "[ ]"
                cr, cg, cb = COLORS.dim.r, COLORS.dim.g, COLORS.dim.b
            end

            self:drawText(prefix, x, y, cr, cg, cb, 1, UIFont.Small)
            self:drawText("#" .. tostring(ms.number), msLabelX, y, cr, cg, cb, 1, UIFont.Small)
            self:drawText(
                formatNumber(ms.killsNeeded) .. " " .. (getTextOrNull("UI_BCR_Kills") or "kills"),
                msKillsX, y, cr, cg, cb, 1, UIFont.Small
            )
            y = y + LINE_H
        end
    end
end

-- ============================================================
-- BCRStatsWindow -- ISCollapsableWindow subclass
-- ============================================================

BCRStatsWindow = ISCollapsableWindow:derive("BCRStatsWindow")

function BCRStatsWindow:new(x, y, w, h, player)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.title = getTextOrNull("UI_BCR_StatsTitle") or "Performance Review"
    o.resizable = false
    o.player = player
    return o
end

local function createRichTextPanel(w, h)
    local panel = ISRichTextPanel:new(0, 0, w, h)
    panel:initialise()
    panel.autosetheight = false
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    panel.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    panel.marginLeft = PADDING
    panel.marginTop = PADDING
    panel.marginRight = PADDING
    panel.clip = true
    panel:addScrollBars()
    panel:setScrollChildren(true)
    panel:setAnchorRight(true)
    panel:setAnchorBottom(true)
    return panel
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
    self.tabs:addView(getTextOrNull("UI_BCR_TabProgress") or "Progress", self.progressPanel)

    self.historyPanel = createRichTextPanel(contentW, contentH)
    self.tabs:addView(getTextOrNull("UI_BCR_TabHistory") or "History", self.historyPanel)

    self.catalogPanel = createRichTextPanel(contentW, contentH)
    self.tabs:addView(getTextOrNull("UI_BCR_TabCatalog") or "Catalog", self.catalogPanel)
end

function BCRStatsWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    statsWindow = nil
end

-- ============================================================
-- TAB 2: HISTORY CONTENT
-- ============================================================

function BCRStatsWindow:updateHistory()
    local bcrData = getBCRData(self.player)
    local text = ""
    local history = bcrData and bcrData.traitHistory or {}
    local visibleCount = 0
    for i = 1, #history do
        local entry = history[i]
        if entry and entry.action ~= "baseline" then
            visibleCount = visibleCount + 1
        end
    end

    if visibleCount == 0 then
        text = text .. colorTag(COLORS.empty)
        text = text .. (getTextOrNull("UI_BCR_NoTraitsYet") or "No rewards yet. Time to rack up your count!")
        self.historyPanel.text = text
        self.historyPanel:paginate()
        return
    end

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getTextOrNull("UI_BCR_EarnedRewards") or "Earned Rewards")
    text = text .. " <LINE> <TEXT> "

    for i = #history, 1, -1 do
        local entry = history[i]
        if entry and entry.action ~= "baseline" then
            local traitId = entry.id or entry.trait
            local displayName = escapeRichText(BCR.GetTraitDisplayName(traitId) or traitId)
            local rarityLabel = getRarityLabel(entry.rarity or "common")

            local sourceStr = ""
            if entry.source then
                local sourceLabel
                if entry.action == "added" then
                    sourceLabel = getTextOrNull("UI_BCR_HistoryAddedBy") or "Added by"
                else
                    sourceLabel = getTextOrNull("UI_BCR_HistoryProvidedBy") or "Provided by"
                end
                sourceStr = " | " .. sourceLabel .. ": " .. escapeRichText(entry.source)
            end

            text = text .. "<INDENT:16>"
            if entry.action == "added" then
                text = text .. colorTag(COLORS.gainGreen)
                text = text .. "+ " .. displayName .. " | " .. rarityLabel .. sourceStr
            else
                text = text .. colorTag(COLORS.lossRed)
                text = text .. "- " .. displayName .. " | " .. rarityLabel .. sourceStr
            end
            text = text .. " <LINE> "
        end
    end

    self.historyPanel.text = text
    self.historyPanel:paginate()
end

-- ============================================================
-- TAB 3: CATALOG CONTENT
-- ============================================================

function BCRStatsWindow:updateCatalog(catalog)
    if not catalog then
        self.catalogPanel.text = getTextOrNull("UI_BCR_NoData") or "No data available."
        self.catalogPanel:paginate()
        return
    end

    local function renderTraitLine(entry)
        local line = ""
        local displayName = escapeRichText(BCR.GetTraitDisplayName(entry.id) or entry.id)
        local rarityLabel = getRarityLabel(entry.rarity)

        if entry.status == "earnable" then
            line = line .. " <INDENT:16> " .. colorTag(rarityColor(entry.rarity))
            line = line .. "- " .. displayName .. " | " .. rarityLabel
            line = line .. " <LINE> "
            return line
        end

        local statusReason
        if entry.status == "conflict" then
            local blockerName = escapeRichText(BCR.GetTraitDisplayName(entry.blockerId) or entry.blockerId)
            statusReason = getText("UI_BCR_StatusConflict", blockerName)
        elseif entry.status == "disabled" then
            statusReason = getTextOrNull("UI_BCR_StatusServerDisabled") or "Disabled"
        elseif entry.status == "removed" then
            statusReason = getTextOrNull("UI_BCR_StatusRemoved") or "Removed"
        elseif entry.status == "earned" then
            statusReason = getTextOrNull("UI_BCR_StatusEarned") or "Earned"
        else
            statusReason = getTextOrNull("UI_BCR_StatusUnavailable") or "Unavailable"
        end

        line = line .. " <INDENT:16> " .. colorTag(COLORS.dim)
        line = line .. "- " .. displayName .. " | " .. rarityLabel .. " | " .. statusReason
        line = line .. " <LINE> "
        return line
    end

    local function renderCustomSections(sections)
        local sectionText = ""
        for _, section in ipairs(sections or {}) do
            local group = section.entries
            local label
            if #group > 1 then
                label = getTextOrNull("UI_BCR_AddedByPlural") or "Traits added by:"
            else
                label = getTextOrNull("UI_BCR_AddedBySingular") or "Trait added by:"
            end
            sectionText = sectionText .. " <LINE> " .. colorTag(COLORS.text) .. label .. " \"" .. escapeRichText(section.source) .. "\" <LINE> "
            for _, entry in ipairs(group) do
                sectionText = sectionText .. renderTraitLine(entry)
            end
        end
        return sectionText
    end

    local text = ""

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getTextOrNull("UI_BCR_CatalogPositive") or "Earnable Positive Traits")
    text = text .. " <LINE><TEXT> "

    if catalog.positiveDisabled then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.dim)
        text = text .. (getTextOrNull("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        for _, entry in ipairs(catalog.positive) do
            text = text .. renderTraitLine(entry)
        end
        text = text .. renderCustomSections(catalog.customPositive)
    end

    text = text .. " <INDENT:0> <BR> "

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getTextOrNull("UI_BCR_CatalogNegative") or "Removable Negative Traits")
    text = text .. " <LINE><TEXT> "

    if catalog.negativeDisabled then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.dim)
        text = text .. (getTextOrNull("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        for _, entry in ipairs(catalog.negative) do
            text = text .. renderTraitLine(entry)
        end
        text = text .. renderCustomSections(catalog.customNegative)
        if not catalog.hasRelevantNegative then
            text = text .. " <INDENT:16> " .. colorTag(COLORS.empty)
            text = text .. (getTextOrNull("UI_BCR_NoNegativeTraits") or "No negative traits found. Character was created without any.")
            text = text .. " <LINE> "
        end
    end

    self.catalogPanel.text = text
    self.catalogPanel:paginate()
end

-- ============================================================
-- PROGRESS DATA COMPUTATION
-- ============================================================

function BCRStatsWindow:updateProgress(view)
    if not view then
        self.progressPanel.cached = nil
        return
    end

    local scalingLabel
    if view.scalingCode == "progressive" then
        scalingLabel = (getTextOrNull("UI_BCR_ScalingProgressive") or "Progressive")
            .. " (x" .. formatFloatLocaleSafe(view.scalingFactor, 1) .. ")"
    else
        scalingLabel = getTextOrNull("UI_BCR_ScalingLinear") or "Linear"
    end

    local rewardPriorityLabel
    if view.priorityCode == BCR.PRIORITY_NEGATIVE_FIRST then
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityLoseFirst") or "Remove Negative First"
    elseif view.priorityCode == BCR.PRIORITY_RANDOM then
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityRandom") or "Random"
    else
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityGainFirst") or "Gain Positive First"
    end

    self.progressPanel.cached = {
        kills = view.kills,
        rewardsGiven = view.rewardsGiven,
        nextMilestone = view.nextMilestone,
        killsRemaining = view.killsRemaining,
        progress = view.progressFraction,
        progressCurrent = view.progressCurrent,
        progressMax = view.progressMax,
        scalingLabel = scalingLabel,
        rewardPriorityLabel = rewardPriorityLabel,
        milestones = view.milestones,
        allComplete = view.allComplete,
    }
end

-- ============================================================
-- CONTENT REFRESH
-- ============================================================

function BCRStatsWindow:updateContent()
    local view = BCR.BuildStatsView(self.player)
    self:updateProgress(view and view.progress)
    self:updateHistory()
    self:updateCatalog(view and view.catalog)
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
    -- Track the window before the first content build, so a build error
    -- cannot orphan it in the UI manager.
    statsWindow = window
    local ok, err = pcall(function() window:updateContent() end)
    if not ok then
        print("[BCR] [Client] ShowStatsWindow updateContent error: " .. tostring(err))
    end
    statsDirty = false
end

-- Requests a refresh; the update tick performs at most one rebuild per tick.
function BCR.RefreshStatsWindow()
    statsDirty = true
end

-- Drains the dirty flag and rebuilds the window. Called from the update tick.
function BCR.FlushStatsWindow()
    if not statsDirty then return end
    statsDirty = false
    if statsWindow and statsWindow:isVisible() then
        local ok, err = pcall(function() statsWindow:updateContent() end)
        if not ok then
            print("[BCR] [Client] FlushStatsWindow error: " .. tostring(err))
        end
    end
end

-- Closes and forgets the stats window. Called on player creation so a
-- window left open across a save load cannot keep the old player.
function BCR.CloseStatsWindow()
    local window = statsWindow
    statsDirty = false
    if not window then return end
    statsWindow = nil
    pcall(function() window:setVisible(false) end)
    pcall(function() window:removeFromUIManager() end)
end
