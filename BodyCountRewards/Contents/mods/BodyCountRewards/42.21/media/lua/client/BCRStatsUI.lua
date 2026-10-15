-- ============================================================
-- BodyCountRewards v1.3.4 -- BCRStatsUI (Build 42.19+)
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
local LINE_H = 24
local VAL_X_OFFSET = 190
local MILESTONE_PAST_COUNT = 2
local MILESTONE_FUTURE_COUNT = 5

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

-- ============================================================
-- BCRProgressPanel -- ISPanel subclass with dirty-flag prerender
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

function BCRProgressPanel:drawStatRow(label, value, x, y)
    local valX = x + VAL_X_OFFSET
    self:drawText(label, x, y, COLORS.dim.r, COLORS.dim.g, COLORS.dim.b, 1, UIFont.Small)
    self:drawText(value, valX, y, COLORS.text.r, COLORS.text.g, COLORS.text.b, 1, UIFont.Small)
    return y + LINE_H
end

function BCRProgressPanel:drawProgressContent()
    local data = self.cached
    if not data then
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

    if data.allComplete then
        self:drawText(
            getTextOrNull("UI_BCR_AllComplete") or "All rewards earned!",
            x, y, COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1, UIFont.Medium
        )
        y = y + HEADER_GAP

        y = self:drawStatRow((getTextOrNull("UI_BCR_TotalRewards") or "Total Rewards") .. ":", tostring(data.rewardsGiven), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ZombieKills") or "Zombie Kills") .. ":", formatNumber(data.kills), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ScalingMode") or "Scaling Mode") .. ":", data.scalingLabel, x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_RewardPriority") or "Reward Priority") .. ":", data.rewardPriorityLabel, x, y)
    else
        self:drawText(
            getTextOrNull("UI_BCR_ZombieKills") or "Zombie Kills",
            x, y, COLORS.sectionHead.r, COLORS.sectionHead.g, COLORS.sectionHead.b, 1, UIFont.Medium
        )
        y = y + SECTION_HEAD_GAP

        self:drawText(formatNumber(data.kills), x + KILLS_INSET, y, COLORS.plainWhite.r, COLORS.plainWhite.g, COLORS.plainWhite.b, 1, UIFont.Large)
        y = y + BIG_NUMBER_GAP

        local barX = x
        local barY = y
        local barW = contentWidth
        local barH = BAR_HEIGHT

        self:drawRect(barX, barY, barW, barH,
            COLORS.barBg.a, COLORS.barBg.r, COLORS.barBg.g, COLORS.barBg.b)

        local fillW = math.floor(barW * data.progress)
        if fillW > 0 then
            local fillColor
            if data.progress >= BAR_HIGH_THRESHOLD then
                fillColor = COLORS.barFillHigh
            elseif data.progress >= BAR_MID_THRESHOLD then
                fillColor = COLORS.barFillMid
            else
                fillColor = COLORS.barFillLow
            end
            self:drawRect(barX, barY, fillW, barH, BAR_FILL_ALPHA, fillColor.r, fillColor.g, fillColor.b)
        end

        self:drawRectBorder(barX, barY, barW, barH,
            COLORS.barBorder.a, COLORS.barBorder.r, COLORS.barBorder.g, COLORS.barBorder.b)

        local progressLabel = formatNumber(data.progressCurrent) .. " / " .. formatNumber(data.progressMax)
        local labelW = getTextManager():MeasureStringX(UIFont.Small, progressLabel)
        local fontH = getTextManager():MeasureStringY(UIFont.Small, progressLabel)
        local textY = barY + math.floor((barH - fontH) / 2)
        self:drawText(progressLabel, barX + (barW - labelW) / 2, textY, COLORS.plainWhite.r, COLORS.plainWhite.g, COLORS.plainWhite.b, 1, UIFont.Small)

        y = barY + barH + BAR_BOTTOM_GAP

        y = self:drawStatRow((getTextOrNull("UI_BCR_NextRewardAt") or "Next Reward at") .. ":", formatNumber(data.nextMilestone) .. " " .. (getTextOrNull("UI_BCR_Kills") or "kills"), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_KillsRemaining") or "Kills Remaining") .. ":", formatNumber(data.killsRemaining), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_TotalRewards") or "Total Rewards") .. ":", tostring(data.rewardsGiven), x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_ScalingMode") or "Scaling Mode") .. ":", data.scalingLabel, x, y)
        y = self:drawStatRow((getTextOrNull("UI_BCR_RewardPriority") or "Reward Priority") .. ":", data.rewardPriorityLabel, x, y)
    end

    if data.milestones and #data.milestones > 0 then
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

        for _, ms in ipairs(data.milestones) do
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

function BCRStatsWindow:initialise()
    ISCollapsableWindow.initialise(self)
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
            local displayName = BCR.GetTraitDisplayName(traitId) or traitId
            local rarity = entry.rarity or "common"
            local rarityKey = "UI_BCR_Rarity_" .. rarity
            local rarityLabel = getText(rarityKey)
            if not rarityLabel or rarityLabel == rarityKey then
                rarityLabel = rarity
            end
            local sourceStr = ""
            if entry.source then
                sourceStr = " | Added by: " .. entry.source
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

function BCRStatsWindow:updateCatalog()
    local bcrData = getBCRData(self.player)
    local opts = BCR.GetOpts()

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

    -- Last history action per trait -- "last action wins", mirroring
    -- the pool guards, so status labels never go stale.
    local lastByTrait = {}
    for _, h in ipairs(bcrData and bcrData.traitHistory or {}) do
        if h and h.id and h.action then
            lastByTrait[h.id] = h.action
        end
    end

    local function renderTraitLine(traitId, cost, poolLookup, isPositive)
        local line = ""
        local displayName = BCR.GetTraitDisplayName(traitId) or traitId
        local rarity = BCR.GetRarity(cost)
        local rarityKey = "UI_BCR_Rarity_" .. rarity
        local rarityLabel = getText(rarityKey)
        if not rarityLabel or rarityLabel == rarityKey then
            rarityLabel = rarity
        end
        local isInPool = poolLookup[traitId] ~= nil
        local isAllowed = BCR.IsTraitAllowed(traitId)

        if isInPool then
            line = line .. " <INDENT:16> " .. colorTag(rarityColor(rarity))
            line = line .. "- " .. displayName .. " | " .. rarityLabel
            line = line .. " <LINE> "
            return line
        end

        local statusReason
        if not isAllowed then
            statusReason = getTextOrNull("UI_BCR_StatusServerDisabled") or "Disabled"
        elseif lastByTrait[traitId] == "removed" then
            statusReason = getTextOrNull("UI_BCR_StatusRemoved") or "Removed"
        elseif lastByTrait[traitId] == "added" or BCR.PlayerHasTrait(self.player, traitId) then
            statusReason = getTextOrNull("UI_BCR_StatusEarned") or "Earned"
        else
            local hasConflict, blockerId = BCR.HasMutuallyExclusiveTrait(self.player, traitId)
            if isPositive and hasConflict and blockerId then
                local blockerName = BCR.GetTraitDisplayName(blockerId) or blockerId
                statusReason = getText("UI_BCR_StatusConflict", blockerName)
            else
                statusReason = getTextOrNull("UI_BCR_StatusUnavailable") or "Unavailable"
            end
        end

        line = line .. " <INDENT:16> " .. colorTag(COLORS.dim)
        line = line .. "- " .. displayName .. " | " .. rarityLabel .. " | " .. statusReason
        line = line .. " <LINE> "
        return line
    end

    local function sortByCost(t)
        if not t then return nil end
        local sorted = {}
        for _, v in ipairs(t) do
            table.insert(sorted, v)
        end
        table.sort(sorted, function(a, b)
            local ca = math.abs(a.cost or 0)
            local cb = math.abs(b.cost or 0)
            if ca ~= cb then return ca < cb end
            local na = BCR.GetTraitDisplayName(a.id) or a.id
            local nb = BCR.GetTraitDisplayName(b.id) or b.id
            return na < nb
        end)
        return sorted
    end

    local function renderCustomSection(list, poolLookup, isPositive, filterFn)
        if not list or #list == 0 then return "" end
        local grouped = {}
        for _, entry in ipairs(list) do
            if not filterFn or filterFn(entry) then
                local source = BCR.CustomTraitSources and BCR.CustomTraitSources[entry.id] or ""
                if not grouped[source] then
                    grouped[source] = {}
                end
                table.insert(grouped[source], entry)
            end
        end
        local sources = {}
        for source in pairs(grouped) do
            table.insert(sources, source)
        end
        table.sort(sources)
        for _, source in ipairs(sources) do
            grouped[source] = sortByCost(grouped[source])
        end
        local sectionText = ""
        for _, source in ipairs(sources) do
            local group = grouped[source]
            local label
            if #group > 1 then
                label = getTextOrNull("UI_BCR_AddedByPlural") or "Traits added by:"
            else
                label = getTextOrNull("UI_BCR_AddedBySingular") or "Trait added by:"
            end
            sectionText = sectionText .. " <LINE> " .. colorTag(COLORS.text) .. label .. " \"" .. source .. "\" <LINE> "
            for _, entry in ipairs(group) do
                sectionText = sectionText .. renderTraitLine(entry.id, entry.cost, poolLookup, isPositive)
            end
        end
        return sectionText
    end

    local text = ""

    local sortedPositive = sortByCost(BCR.PositiveTraits)
    local sortedNegative = sortByCost(BCR.NegativeTraits)

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getTextOrNull("UI_BCR_CatalogPositive") or "Earnable Positive Traits")
    text = text .. " <LINE><TEXT> "

    if opts.enablePositive == false then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.dim)
        text = text .. (getTextOrNull("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        for _, entry in ipairs(sortedPositive) do
            text = text .. renderTraitLine(entry.id, entry.cost, earnablePool, true)
        end
        text = text .. renderCustomSection(BCR.CustomPositiveTraits, earnablePool, true)
    end

    text = text .. " <INDENT:0> <BR> "

    text = text .. colorTag(COLORS.sectionHead)
    text = text .. " <H2> " .. (getTextOrNull("UI_BCR_CatalogNegative") or "Removable Negative Traits")
    text = text .. " <LINE><TEXT> "

    if opts.enableNegative == false then
        text = text .. " <INDENT:16> " .. colorTag(COLORS.dim)
        text = text .. (getTextOrNull("UI_BCR_CategoryDisabled") or "Disabled in server settings")
        text = text .. " <LINE> "
    else
        local hasRelevantTraits = false
        for _, entry in ipairs(sortedNegative) do
            local traitId = entry.id
            if BCR.PlayerHasTrait(self.player, traitId) or lastByTrait[traitId] == "removed" then
                hasRelevantTraits = true
                text = text .. renderTraitLine(traitId, entry.cost, removablePool, false)
            end
        end
        if BCR.CustomNegativeTraits and #BCR.CustomNegativeTraits > 0 then
            local customText = renderCustomSection(BCR.CustomNegativeTraits, removablePool, false,
                function(entry)
                    return BCR.PlayerHasTrait(self.player, entry.id) or lastByTrait[entry.id] == "removed"
                end)
            if customText ~= "" then
                hasRelevantTraits = true
                text = text .. customText
            end
        end

        if not hasRelevantTraits then
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
    local answered = BCR.GetAnsweredMilestones(bcrData)
    local nextMilestone = BCR.GetKillsForMilestone(answered + 1, opts)
    local prevMilestone = BCR.GetKillsForMilestone(answered, opts)

    local progress = 0
    if nextMilestone > prevMilestone then
        progress = math.max(0, math.min(1, (killsNum - prevMilestone) / (nextMilestone - prevMilestone)))
    end

    local scalingLabel
    if opts.milestoneScaling == 2 then
        local factor = opts.progressiveScalingFactor or BCR.DEFAULT_PROGRESSIVE_FACTOR
        scalingLabel = (getTextOrNull("UI_BCR_ScalingProgressive") or "Progressive")
            .. " (x" .. formatFloatLocaleSafe(factor, 1) .. ")"
    else
        scalingLabel = getTextOrNull("UI_BCR_ScalingLinear") or "Linear"
    end

    local rewardPriorityLabel
    if opts.rewardPriority == 2 then
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityLoseFirst") or "Remove Negative First"
    elseif opts.rewardPriority == 3 then
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityRandom") or "Random"
    else
        rewardPriorityLabel = getTextOrNull("UI_BCR_PriorityGainFirst") or "Gain Positive First"
    end

    local allComplete = not BCR.HasAvailableRewards(self.player)

    local msStart, msEnd

    if allComplete then
        msStart = math.max(1, answered - (MILESTONE_PAST_COUNT + MILESTONE_FUTURE_COUNT - 1))
        msEnd = answered
    else
        local earnableCount = (BCR.PositiveTraits and #BCR.PositiveTraits or 0) + (BCR.CustomPositiveTraits and #BCR.CustomPositiveTraits or 0)
        local removableCount = (BCR.NegativeTraits and #BCR.NegativeTraits or 0) + (BCR.CustomNegativeTraits and #BCR.CustomNegativeTraits or 0)
        local rewardsLeft = earnableCount + removableCount
        msStart = math.max(1, answered - MILESTONE_PAST_COUNT + 1)
        msEnd = math.min(answered + MILESTONE_FUTURE_COUNT, answered + rewardsLeft)
    end

    local milestones = {}
    for m = msStart, msEnd do
        table.insert(milestones, {
            number = m,
            killsNeeded = BCR.GetKillsForMilestone(m, opts),
            reached = m <= answered,
            isCurrent = m == answered + 1,
        })
    end

    self.progressPanel.cached = {
        kills = killsNum,
        rewardsGiven = rewardsGiven,
        nextMilestone = nextMilestone,
        killsRemaining = math.max(0, nextMilestone - killsNum),
        progress = progress,
        progressCurrent = math.max(0, killsNum - prevMilestone),
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
    -- Track the window before the first content build, so a build error
    -- cannot orphan it in the UI manager.
    statsWindow = window
    local ok, err = pcall(function() window:updateContent() end)
    if not ok then
        print("[BCR] [Client] ShowStatsWindow updateContent error: " .. tostring(err))
    end
end

function BCR.RefreshStatsWindow()
    if statsWindow and statsWindow:isVisible() then
        local ok, err = pcall(function() statsWindow:updateContent() end)
        if not ok then
            print("[BCR] [Client] RefreshStatsWindow error: " .. tostring(err))
        end
    end
end

-- Closes and forgets the stats window. Called on player creation so a
-- window left open across a save load cannot keep the old player.
function BCR.CloseStatsWindow()
    local window = statsWindow
    if not window then return end
    statsWindow = nil
    pcall(function() window:setVisible(false) end)
    pcall(function() window:removeFromUIManager() end)
end
