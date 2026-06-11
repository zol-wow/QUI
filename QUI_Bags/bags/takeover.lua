---------------------------------------------------------------------------
-- Bags takeover: FULL REPLACEMENT of the Blizzard bag UI entry points.
-- While active, all ten bag globals (ToggleAllBags / OpenAllBags /
-- CloseAllBags / ToggleBackpack / ToggleBag / OpenBag / CloseBag /
-- OpenBackpack / CloseBackpack / OpenAllBagsMatchingContext) are swapped
-- for ours; Blizzard's bodies never run.
--
-- Why hooks were rejected: Blizzard's ToggleBackpack internally calls the
-- GLOBAL ToggleBag(0) and CloseAllBags, so a hook design that lets the
-- original body run intercepts the nested calls too and double-fires on a
-- single B press. A hooked CloseAllBags also returns nil, so ESC's
-- CloseAllWindows chain thinks nothing closed and opens the Game Menu on
-- the same press. Caller analysis proved every caller (key bindings,
-- securecall sites, Blizzard-internal calls) resolves these names at call
-- time with zero captured references — swapping the globals is safe and
-- removes the root cause outright.
--
-- Container frames 1-6 + combined are Hide()-d FIRST (OnHide bookkeeping
-- runs while still under the real parent, so their shown flags and
-- IsBagOpen consumers stay truthful), then reparented to a hidden holder.
-- CloseAllBags mirrors Blizzard's FRAME_THAT_OPENED_BAGS semantics via
-- openedByFrameName (a programmatic close only succeeds when the same
-- frame opened the bags) and returns whether anything actually closed.
-- Revert restores the original globals and parents.
-- Taint-clean: no secure paths touched, no hooksecurefunc anywhere.
---------------------------------------------------------------------------
-- luacheck: globals ToggleAllBags OpenAllBags CloseAllBags ToggleBackpack ToggleBag OpenBag CloseBag OpenBackpack CloseBackpack OpenAllBagsMatchingContext
-- luacheck: read globals ContainerFrame_AllowedToOpenBags
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Takeover = {}
Bags.Takeover = Takeover

local active = false
local originals = nil          -- pre-QUI globals (re-captured on EVERY Apply)
local originalParents = {}     -- frame → parent
local hiddenHolder = nil
local openedByFrameName = nil  -- Blizzard's FRAME_THAT_OPENED_BAGS analog

local CONTAINER_FRAMES = {
    "ContainerFrame1", "ContainerFrame2", "ContainerFrame3",
    "ContainerFrame4", "ContainerFrame5", "ContainerFrame6",
    "ContainerFrameCombinedBags",
}

function Takeover.IsActive()
    return active
end

local function AllowedToOpen()
    if type(ContainerFrame_AllowedToOpenBags) == "function" then
        return ContainerFrame_AllowedToOpenBags()
    end
    return true
end

local function OurOpenAllBags(frame, forceUpdate)
    if not AllowedToOpen() then return end
    if Bags.BagWindow.IsShown() then
        if forceUpdate and Bags.BagWindow.Refresh then Bags.BagWindow.Refresh() end
        return -- already open: do NOT re-record the opener (Blizzard parity)
    end
    if frame and Bags.AutoOpen and not Bags.AutoOpen.ShouldOpenFor(frame) then
        return -- programmatic open suppressed by user policy
    end
    openedByFrameName = frame and frame.GetName and frame:GetName() or nil
    Bags.BagWindow.Show()
end

local function OurCloseAllBags(frame, forceUpdate) -- luacheck: no unused args
    -- Blizzard parity: a programmatic close only succeeds when the SAME frame
    -- opened the bags; manual closes (frame == nil) always succeed.
    if frame and frame.GetName then
        local name = frame:GetName()
        if name ~= openedByFrameName then return false end
    end
    local wasShown = Bags.BagWindow.IsShown()
    openedByFrameName = nil
    Bags.BagWindow.Hide()
    return wasShown -- CloseAllWindows/ESC chain needs truth (Game Menu gate)
end

local function OurToggleAllBags()
    if Bags.BagWindow.IsShown() then
        OurCloseAllBags()
    else
        OurOpenAllBags()
    end
end

-- One unified window: every per-bag entry point maps onto the all-bags ops.
local function OurOpenBag() OurOpenAllBags() end
local function OurCloseBag() return OurCloseAllBags() end
local function OurOpenBackpack() OurOpenAllBags() end
local function OurCloseBackpack() return OurCloseAllBags() end
local function OurToggleBag() OurToggleAllBags() end
local function OurToggleBackpack() OurToggleAllBags() end

-- ContainerFrame.lua's OpenAllBagsMatchingContext (used by
-- ItemButtonUtil.OpenAndFilterBags for keystone/enchant/item-upgrade UIs)
-- bypasses OpenAllBags, so it gets its own replacement.
local function OurOpenAllBagsMatchingContext(frame)
    -- Blizzard returns the number of bags opened; ItemButtonUtil uses it to
    -- decide whether to close bags when the context frame hides.
    if Bags.BagWindow.IsShown() then return 0 end
    OurOpenAllBags(frame)
    return Bags.BagWindow.IsShown() and 1 or 0
end

-- The ten replacement globals, keyed by global name (drives Apply/Revert).
local OURS = {
    ToggleAllBags = OurToggleAllBags,
    OpenAllBags = OurOpenAllBags,
    CloseAllBags = OurCloseAllBags,
    ToggleBackpack = OurToggleBackpack,
    ToggleBag = OurToggleBag,
    OpenBag = OurOpenBag,
    CloseBag = OurCloseBag,
    OpenBackpack = OurOpenBackpack,
    CloseBackpack = OurCloseBackpack,
    OpenAllBagsMatchingContext = OurOpenAllBagsMatchingContext,
}

function Takeover.Apply()
    if active then return end
    active = true

    if not hiddenHolder then
        hiddenHolder = CreateFrame("Frame")
        -- Children anchored to the holder still get resolved rects — some
        -- Blizzard code paths want one even on a hidden frame.
        hiddenHolder:SetSize(1, 1)
        hiddenHolder:SetPoint("BOTTOMRIGHT")
        hiddenHolder:Hide()
    end
    for _, name in ipairs(CONTAINER_FRAMES) do
        local frame = _G[name]
        if frame then
            -- Hide FIRST: clears any pre-takeover shown flag while still
            -- under the real parent, so OnHide bookkeeping runs and
            -- IsBagOpen consumers don't go stale (no zombie frames later).
            frame:Hide()
            originalParents[frame] = frame:GetParent()
            frame:SetParent(hiddenHolder)
        end
    end

    -- originals = whatever is global RIGHT NOW (possibly another addon's).
    -- Re-captured on every Apply: after an enable→disable cycle a different
    -- addon may have taken ownership while we were inactive — restoring a
    -- first-ever snapshot would silently steal the globals back from it.
    originals = {}
    for name, ourFn in pairs(OURS) do
        originals[name] = _G[name]
        _G[name] = ourFn
    end
end

function Takeover.Revert()
    if not active then return end

    if originals then
        -- Restore ONLY the globals that still point at our wrappers: a
        -- global some other addon overwrote while we were active has a
        -- newer owner — clobbering it with our pre-QUI snapshot would
        -- break that addon. The snapshot dies with the cycle.
        for name, ourFn in pairs(OURS) do
            if _G[name] == ourFn then
                _G[name] = originals[name]
            end
        end
        originals = nil
    end
    for frame, parent in pairs(originalParents) do
        frame:Hide() -- defensive: hand Blizzard back a clean hidden frame
        frame:SetParent(parent)
        originalParents[frame] = nil
    end
    openedByFrameName = nil
    active = false
end
