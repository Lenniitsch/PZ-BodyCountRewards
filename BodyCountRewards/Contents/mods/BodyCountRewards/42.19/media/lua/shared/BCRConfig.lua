-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRConfig (Build 42.19+)
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

function BCR.DebugPrint(message)
    if BCR.DEBUG then print("[BCR] " .. tostring(message)) end
end

function BCR.RefreshConfig()
    local sv = SandboxVars.BCR or {}
    if sv.allow_SPEED_DEMON ~= nil then
        local migrated = 0
        if BCR.TRAIT_ID_MIGRATION then
            for oldId, newId in pairs(BCR.TRAIT_ID_MIGRATION) do
                local oldKey = "allow_" .. oldId
                local newKey = "allow_" .. string.gsub(newId, ":", "_")
                if sv[oldKey] ~= nil and sv[newKey] == nil then
                    sv[newKey] = sv[oldKey]
                    migrated = migrated + 1
                end
            end
        end
        print("[BCR] v1.3.1: Migrated " .. tostring(migrated) .. " sandbox trait toggle(s) to new format. Verify in the Traits page if needed.")
    end
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
    local key = "allow_" .. string.gsub(id, ":", "_")
    local namespace = BCR.CustomTraitNamespaces and BCR.CustomTraitNamespaces[id]
    if namespace then
        local sv = SandboxVars[namespace]
        if sv and sv[key] == false then
            BCR.DebugPrint("Trait blocked by sandbox [" .. namespace .. "]: " .. id .. " (key=" .. key .. ", value=" .. tostring(sv[key]) .. ")")
            return false
        end
        return true
    end
    local sv = SandboxVars.BCR or {}
    if sv[key] == false then
        BCR.DebugPrint("Trait blocked by sandbox: " .. id .. " (key=" .. key .. ", value=" .. tostring(sv[key]) .. ")")
        return false
    end
    return true
end
