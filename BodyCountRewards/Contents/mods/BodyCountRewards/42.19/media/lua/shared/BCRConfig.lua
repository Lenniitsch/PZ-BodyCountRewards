-- ============================================================
-- BodyCountRewards v1.3.0 — BCRConfig (Build 42.19+)
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

-- ============================================================
-- RUNTIME STATE
-- ============================================================

BCR.opts = nil
BCR.DEBUG = false

-- ============================================================
-- DISPLAY NAME OVERRIDES — PZ trait names that don't follow the
-- UI_trait_<PascalCase> convention
-- ============================================================

BCR.DISPLAY_OVERRIDES = {
    NEEDS_LESS_SLEEP = "UI_trait_LessSleep",
    NEEDS_MORE_SLEEP = "UI_trait_MoreSleep",
    DEXTROUS         = "UI_trait_Dexterous",
}

-- ============================================================
-- FUNCTIONS
-- ============================================================

function BCR.DebugPrint(message)
    if BCR.DEBUG then print("[BCR] " .. tostring(message)) end
end

function BCR.RefreshConfig()
    local sv = SandboxVars.BCR or {}
    BCR.opts = {
        bodyCount                = sv.BodyCount or 1000,
        enablePositive           = sv.enablePositiveTraits ~= false,
        enableNegative           = sv.enableNegativeTraits ~= false,
        rewardPriority           = sv.rewardPriority or BCR.PRIORITY_POSITIVE_FIRST,
        grantMissedOpportunities = sv.grantMissedOpportunities == true,
        milestoneScaling         = sv.MilestoneScaling or 1,
        progressiveScalingFactor = sv.ProgressiveScalingFactor or 0.5,
    }
    BCR.DEBUG = sv.enableDebugLogging == true
end

function BCR.IsTraitAllowed(id)
    local sv = SandboxVars.BCR or {}
    local key = "allow_" .. id
    if sv[key] == false then
        BCR.DebugPrint("Trait blocked by sandbox: " .. id)
        return false
    end
    return true
end
