-- ============================================================
-- BodyCountRewards v1.4.0 -- BCRConfig (Build 42.21+)
-- Constants, sandbox option cache, debug flag. No game logic here.
-- ============================================================

BCR = BCR or {}

-- ============================================================
-- CONSTANTS
-- ============================================================

BCR.PRIORITY_POSITIVE_FIRST = 1
BCR.PRIORITY_NEGATIVE_FIRST = 2
BCR.PRIORITY_RANDOM = 3
BCR.MODULE_NAME = "BCR"
BCR.MAX_NOTIFICATION_QUEUE = 8
BCR.DEFAULT_BODY_COUNT = 1000
BCR.DEFAULT_PROGRESSIVE_FACTOR = 0.5
BCR.NOTIFICATION_DELAY_TICKS = 200
BCR.MAX_BATCH_REWARDS = 64
BCR.MAX_TRAIT_HISTORY = 1000
BCR.REWARD_REQUEST_COOLDOWN_SECONDS = 1
BCR.SCALING_LINEAR = 1
BCR.SCALING_PROGRESSIVE = 2
BCR.SECONDS_PER_HOUR = 3600
BCR.RARITY_UNKNOWN = "unknown"

-- ============================================================
-- RUNTIME STATE
-- ============================================================

BCR.opts = nil
BCR.DEBUG = false

-- ============================================================
-- DISPLAY NAME OVERRIDES -- PZ trait names that don't follow the
-- UI_trait_<PascalCase> convention
-- ============================================================

BCR.DISPLAY_OVERRIDES = {
    ["base:NeedsLessSleep"] = "UI_trait_LessSleep",
    ["base:NeedsMoreSleep"] = "UI_trait_MoreSleep",
    ["base:Dextrous"]       = "UI_trait_Dexterous",
}

-- ============================================================
-- FUNCTIONS
-- ============================================================

function BCR.DebugPrint(module, message)
    if not BCR.DEBUG then return end
    if message == nil then
        message = module
        module = "Core"
    end
    print("[BCR] [" .. tostring(module) .. "] " .. tostring(message))
end

-- Printf-style debug print: the message is only built when debug is on.
function BCR.DebugPrintf(module, fmt, ...)
    if not BCR.DEBUG then return end
    BCR.DebugPrint(module, string.format(fmt, ...))
end

function BCR.GetOpts()
    if not BCR.opts then
        BCR.RefreshConfig()
    end
    return BCR.opts
end

function BCR.RefreshConfig()
    -- NOTE: In-game sandbox key migration is not possible. The engine
    -- (SandboxOptions.load) discards save-file options that are not
    -- declared in the current sandbox-options.txt, so keys from older
    -- mod versions never reach SandboxVars here. Keys must never be
    -- renamed after shipping. Saves upgrading from pre-1.3.0 (the
    -- misspelled "grandMissedOpportunities" key) reset to defaults.
    local sandboxVars = SandboxVars.BCR or {}
    BCR.opts = {
        bodyCount                = sandboxVars.BodyCount or BCR.DEFAULT_BODY_COUNT,
        enablePositive           = sandboxVars.enablePositiveTraits ~= false,
        enableNegative           = sandboxVars.enableNegativeTraits ~= false,
        rewardPriority           = sandboxVars.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST,
        grantMissedOpportunities = sandboxVars.grantMissedOpportunities == true,
        restoreMissingTraits     = sandboxVars.restoreMissingTraits == true,
        milestoneScaling         = sandboxVars.MilestoneScaling or BCR.SCALING_LINEAR,
        progressiveScalingFactor = sandboxVars.ProgressiveScalingFactor or BCR.DEFAULT_PROGRESSIVE_FACTOR,
    }
    BCR.DEBUG = sandboxVars.enableDebugLogging == true
end

function BCR.IsTraitAllowed(id)
    if type(id) ~= "string" then return true end
    local key = "allow_" .. string.gsub(id, ":", "_")
    local namespace = BCR.CustomTraitNamespaces and BCR.CustomTraitNamespaces[id]
    if namespace then
        local sandboxVars = SandboxVars[namespace]
        if sandboxVars and sandboxVars[key] == false then
            BCR.DebugPrintf("Sandbox", "Trait blocked by sandbox [%s]: %s (key=%s, value=%s)",
                tostring(namespace), tostring(id), tostring(key), tostring(sandboxVars[key]))
            return false
        end
        return true
    end
    local sandboxVars = SandboxVars.BCR or {}
    if sandboxVars[key] == false then
        BCR.DebugPrintf("Sandbox", "Trait blocked by sandbox: %s (key=%s, value=%s)",
            tostring(id), tostring(key), tostring(sandboxVars[key]))
        return false
    end
    return true
end
