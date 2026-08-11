local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local TakeoverShared = {}
Bags.TakeoverShared = TakeoverShared

function TakeoverShared.MakeHiddenHolder()
    local holder = CreateFrame("Frame")
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOMRIGHT")
    holder:Hide()
    return holder
end
