local ADDON_NAME, ns = ...

local function RefreshAuraSurfaces()
    if ns.QUI_RefreshGroupFrameAuras then ns.QUI_RefreshGroupFrameAuras() end
    if ns.QUI_RefreshUnitFrameAuras then ns.QUI_RefreshUnitFrameAuras() end
    if ns.QUI_RefreshBuffBorderAuras then ns.QUI_RefreshBuffBorderAuras() end
end

if CreateFrame then
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    f:SetScript("OnEvent", function(_, _, arg1)
        if arg1 == "player" or arg1 == nil then
            local pins = ns.Settings and ns.Settings.Pins
            if pins and type(pins.HandleProfileFeatureSpecChanged) == "function" then
                pins:HandleProfileFeatureSpecChanged()
            end
            RefreshAuraSurfaces()
        end
    end)
end
