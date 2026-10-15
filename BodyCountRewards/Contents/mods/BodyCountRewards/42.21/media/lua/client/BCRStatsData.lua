-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRStatsData (Build 42.21+)
-- Data layer for the stats window and the status menu. Builds the
-- progress snapshot and the trait catalog as plain tables: ids,
-- costs, rarity tiers and status codes only. No translated text,
-- no UI. BCRStatsUI renders these tables.
-- ============================================================

require "BCRCore"
require "BCRData"

BCR = BCR or {}

-- Milestone roadmap window around the current answer count.
local MILESTONE_PAST_COUNT = 2
local MILESTONE_FUTURE_COUNT = 5

-- Catalog status codes (rendered by BCRStatsUI):
--   "earnable"    -- the trait is in the grantable pool
--   "disabled"    -- blocked by a sandbox toggle
--   "removed"     -- last history action was a removal
--   "earned"      -- owned (history or live state)
--   "conflict"    -- a mutually exclusive trait is owned (blockerId set)
--   "unavailable" -- none of the above

local function sortEntriesByCost(list)
    local sorted = {}
    for _, entry in ipairs(list) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b)
        local ca = math.abs(a.cost or 0)
        local cb = math.abs(b.cost or 0)
        if ca ~= cb then return ca < cb end
        -- id tie-break: ASCII-stable, independent of the active language
        return (a.id or "") < (b.id or "")
    end)
    return sorted
end

-- One catalog row: identity, cost, rarity tier and a status code.
local function buildStatusEntry(player, entry, poolLookup, isEarnable, lastByTrait)
    local traitId = entry.id
    local status
    local blockerId
    if poolLookup[traitId] then
        status = "earnable"
    elseif not BCR.IsTraitAllowed(traitId) then
        status = "disabled"
    elseif lastByTrait[traitId] == "removed" then
        status = "removed"
    elseif lastByTrait[traitId] == "added" or BCR.PlayerHasTrait(player, traitId) then
        status = "earned"
    else
        local hasConflict, blocker = BCR.HasMutuallyExclusiveTrait(player, traitId)
        if isEarnable and hasConflict and blocker then
            status = "conflict"
            blockerId = blocker
        else
            status = "unavailable"
        end
    end
    return {
        id = traitId,
        cost = entry.cost,
        rarity = BCR.GetRarity(entry.cost),
        status = status,
        blockerId = blockerId,
    }
end

local function buildStatusEntries(player, list, poolLookup, isEarnable, lastByTrait, filterFn)
    local out = {}
    for _, entry in ipairs(list or {}) do
        if not filterFn or filterFn(entry) then
            table.insert(out, buildStatusEntry(player, entry, poolLookup, isEarnable, lastByTrait))
        end
    end
    return sortEntriesByCost(out)
end

-- Custom traits grouped by addon source, sorted like the base lists.
local function buildCustomSections(player, list, poolLookup, isEarnable, lastByTrait, filterFn)
    local grouped = {}
    for _, entry in ipairs(list or {}) do
        if not filterFn or filterFn(entry) then
            local source = BCR.CustomTraitSources and BCR.CustomTraitSources[entry.id] or ""
            if not grouped[source] then
                grouped[source] = {}
            end
            table.insert(grouped[source], buildStatusEntry(player, entry, poolLookup, isEarnable, lastByTrait))
        end
    end
    local sections = {}
    for source, entries in pairs(grouped) do
        table.insert(sections, { source = source, entries = sortEntriesByCost(entries) })
    end
    table.sort(sections, function(a, b) return a.source < b.source end)
    return sections
end

local function buildProgress(player, bcrData, opts, earnableList, removableList)
    local ok, kills = pcall(function() return player:getZombieKills() end)
    if not ok then
        BCR.DebugPrint("Client", "BuildStatsView: getZombieKills failed")
        kills = 0
    end
    local killsNum = kills or 0
    local rewardsGiven = bcrData.rewardsGiven or 0
    local answered = BCR.GetAnsweredMilestones(bcrData)
    local nextMilestone = BCR.GetKillsForMilestone(answered + 1, opts)
    local prevMilestone = BCR.GetKillsForMilestone(answered, opts)

    local progressFraction = 0
    if nextMilestone > prevMilestone then
        progressFraction = math.max(0, math.min(1, (killsNum - prevMilestone) / (nextMilestone - prevMilestone)))
    end

    -- Pool sizes respect the sandbox toggles and the player's live state.
    local poolSize = #(earnableList or {}) + #(removableList or {})
    local allComplete = poolSize == 0

    local msStart, msEnd
    if allComplete then
        msStart = math.max(1, answered - (MILESTONE_PAST_COUNT + MILESTONE_FUTURE_COUNT - 1))
        msEnd = answered
    else
        msStart = math.max(1, answered - MILESTONE_PAST_COUNT + 1)
        msEnd = math.min(answered + MILESTONE_FUTURE_COUNT, answered + poolSize)
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

    return {
        kills = killsNum,
        rewardsGiven = rewardsGiven,
        answered = answered,
        nextMilestone = nextMilestone,
        killsRemaining = math.max(0, nextMilestone - killsNum),
        progressFraction = progressFraction,
        progressCurrent = math.max(0, killsNum - prevMilestone),
        progressMax = nextMilestone - prevMilestone,
        scalingCode = (opts.milestoneScaling == BCR.SCALING_PROGRESSIVE) and "progressive" or "linear",
        scalingFactor = opts.progressiveScalingFactor or BCR.DEFAULT_PROGRESSIVE_FACTOR,
        priorityCode = opts.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST,
        poolSize = poolSize,
        allComplete = allComplete,
        milestones = milestones,
    }
end

local function buildCatalog(player, opts, lastByTrait, earnablePool, removablePool)
    local positiveDisabled = (opts.enablePositive == false)
    local negativeDisabled = (opts.enableNegative == false)

    local positive = {}
    local customPositive = {}
    if not positiveDisabled then
        positive = buildStatusEntries(player, BCR.PositiveTraits, earnablePool, true, lastByTrait, nil)
        customPositive = buildCustomSections(player, BCR.CustomPositiveTraits, earnablePool, true, lastByTrait, nil)
    end

    local negative = {}
    local customNegative = {}
    local hasRelevantNegative = false
    if not negativeDisabled then
        -- The negative tab lists only traits the player owns or already
        -- lost: unowned negatives are not actionable.
        local function isRelevant(entry)
            return BCR.PlayerHasTrait(player, entry.id) == true or lastByTrait[entry.id] == "removed"
        end
        negative = buildStatusEntries(player, BCR.NegativeTraits, removablePool, false, lastByTrait, isRelevant)
        customNegative = buildCustomSections(player, BCR.CustomNegativeTraits, removablePool, false, lastByTrait, isRelevant)
        hasRelevantNegative = #negative > 0 or #customNegative > 0
    end

    return {
        positiveDisabled = positiveDisabled,
        negativeDisabled = negativeDisabled,
        positive = positive,
        negative = negative,
        customPositive = customPositive,
        customNegative = customNegative,
        hasRelevantNegative = hasRelevantNegative,
    }
end

-- Builds both view models in one pass. The reward pools are built once and
-- shared by both tabs. Returns nil when the player or the options are not
-- available; progress is nil when ModData cannot be read.
function BCR.BuildStatsView(player)
    if not player then return nil end
    BCR.RefreshConfig()
    local opts = BCR.opts
    if not opts then return nil end

    local bcrData = BCR.EnsureModData(player)

    -- Last history action per trait -- "last action wins", mirroring
    -- the pool guards, so status labels never go stale.
    local lastByTrait = {}
    for _, h in ipairs(bcrData and bcrData.traitHistory or {}) do
        if h and h.id and h.action then
            lastByTrait[h.id] = h.action
        end
    end

    local earnableList, removableList
    if opts.enablePositive ~= false then
        earnableList = BCR.BuildEarnablePool(player) or {}
    end
    if opts.enableNegative ~= false then
        removableList = BCR.BuildRemovablePool(player) or {}
    end

    local earnablePool = {}
    for _, entry in ipairs(earnableList or {}) do
        earnablePool[entry.id] = true
    end
    local removablePool = {}
    for _, entry in ipairs(removableList or {}) do
        removablePool[entry.id] = true
    end

    local progress
    if bcrData then
        progress = buildProgress(player, bcrData, opts, earnableList, removableList)
    end
    local catalog = buildCatalog(player, opts, lastByTrait, earnablePool, removablePool)

    return {
        progress = progress,
        catalog = catalog,
    }
end
