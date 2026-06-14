-- ============================================================
-- BodyCountRewards - ModOptions (Build 42.16)
-- Client-side per-user UI preferences via PZAPI.ModOptions
-- ============================================================

local config = { showContextMenu = true }

if PZAPI and PZAPI.ModOptions then
    local options = PZAPI.ModOptions:create("BodyCountRewards", getText("UI_BCR_MenuTitle") or "Body Count Rewards")

    options:addTickBox("showContextMenu",
        getText("UI_BCR_Option_ShowMenu") or "Show Context Menu",
        true,
        getText("UI_BCR_Option_ShowMenu_tooltip") or "When enabled, right-clicking shows Body Count Rewards progress in the context menu."
    )

    options.apply = function(self)
        for k, v in pairs(self.dict) do
            if v.type and v.type ~= "button" then
                config[k] = v:getValue()
            end
        end
    end

    Events.OnMainMenuEnter.Add(function()
        options:apply()
    end)
end

return config
