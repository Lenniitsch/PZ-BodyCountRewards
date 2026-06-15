-- ============================================================
-- BodyCountRewards v1.3.0 -- BCRModOptions (Build 42.19+)
-- Per-user UI preferences (showContextMenu toggle).
-- Returns config table. Nil-guarded PZAPI.ModOptions integration.
-- ============================================================

local config = { showContextMenu = true }

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create("BodyCountRewards",
        getText("UI_BCR_MenuTitle") or "Body Count Rewards")
    options:addTickBox("showContextMenu",
        getText("UI_BCR_Option_ShowMenu") or "Show Context Menu", true,
        getText("UI_BCR_Option_ShowMenu_tooltip") or "When enabled, right-clicking shows Body Count Rewards progress in the context menu.")
    options.apply = function(self)
        for k, v in pairs(self.dict) do
            if v.type and v.type ~= "button" then
                config[k] = v:getValue()
            end
        end
    end
    Events.OnMainMenuEnter.Add(function()
        if options then options:apply() end
    end)
end

return config
