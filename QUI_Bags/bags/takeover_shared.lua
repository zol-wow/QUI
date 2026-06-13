---------------------------------------------------------------------------
-- Bags takeover: shared construction helpers.
--
-- Loads before the takeover files (takeover / bank_takeover / guild_takeover)
-- so each can build its hidden reparent holder without re-defining the block.
-- Behavior is identical to the per-file copies this replaced.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local TakeoverShared = {}
Bags.TakeoverShared = TakeoverShared

--- Create the offscreen holder a takeover reparents suppressed Blizzard
--- frames onto. Hidden, 1×1, anchored BOTTOMRIGHT.
function TakeoverShared.MakeHiddenHolder()
    local holder = CreateFrame("Frame")
    -- Children anchored to the holder still get resolved rects — some
    -- Blizzard code paths want one even on a hidden frame.
    holder:SetSize(1, 1)
    holder:SetPoint("BOTTOMRIGHT")
    holder:Hide()
    return holder
end
