---------------------------------------------------------------------------
-- Bags takeover: suppress the Blizzard bag UI WITHOUT replacing its secure
-- entry points.
--
-- Hook model (replaces the original global-swap design). The ten bag
-- globals stay Blizzard's: secure callers read them at call time and then
-- keep executing, so an addon-owned global taints the rest of the secure
-- execution — MailFrame_Show calls OpenAllBags(MailFrame) and the
-- RESTRICTED C_ChatInfo.PerformEmote four lines later (ADDON_ACTION_BLOCKED
-- at every mailbox), and UIParent's ENCHANT_SPELL_SELECTED handler calls
-- OpenAndFilterBags → OpenAllBagsMatchingContext then opens the character
-- frame. hooksecurefunc post-hooks run insecurely WITHOUT tainting the
-- caller, so Blizzard's bodies run for real — against container frames
-- parked under a hidden parent (shown flags flip, nothing renders) — and
-- the hooks mirror the open/close/toggle intent onto the QUI window.
--
-- Exception — ToggleAllBags IS still replaced: its secure callers (the
-- OPENALLBAGS "B" binding, the bag-bar buttons' OnClick in
-- MainMenuBarBagButtons.lua) do nothing protected after the call, so the
-- swap is taint-safe, and it keeps a plain B press from pointlessly
-- churning the hidden Blizzard frames.
--
-- Toggle de-dup: Blizzard's bodies nest by GLOBAL name (ToggleBackpack →
-- ToggleBag(0)/CloseAllBags; OpenAllBags → OpenBackpack → ToggleBackpack),
-- so one call can fire several hooks. Two guards:
--   * debugstack() filter — a toggle reached under OpenAllBags/CloseAllBags
--     belongs to the programmatic open/close path (the OpenAllBags hook or
--     the interaction-event sink owns it); a CloseAllBags reached under a
--     toggle belongs to that toggle.
--   * same-GetTime() debounce — nested toggle hooks fire within one frame;
--     the first one wins.
--
-- ESC: the QUI windows live in UISpecialFrames (views/chassis.lua).
-- CloseAllWindows runs CloseAllBags FIRST and the CloseSpecialWindows sweep
-- AFTER (UIParentPanelManager.lua) — the CloseAllBags hook must skip under
-- CloseAllWindows, or it hides the window before the sweep looks, the sweep
-- reports nothing closed, and ESC falls through to the Game Menu.
--
-- Container frames 1-6 + combined are Hide()-d FIRST (OnHide bookkeeping
-- runs while still under the real parent), then reparented to a hidden
-- holder. The reagent-bag frame tutorial is marked seen on Apply: it waits
-- for a bag-open it would anchor to the invisible frames.
--
-- Loot toasts: AlertFrameSystems' OnClick handlers call OpenBag(slot)
-- directly — a stack-filtered hook mirrors just those onto the window.
--
-- hooksecurefunc is permanent (no un-hook): hooks install once on the first
-- Apply and their bodies gate on `active`, so Revert leaves them inert.
---------------------------------------------------------------------------
-- luacheck: globals ToggleAllBags
-- luacheck: read globals ContainerFrame_AllowedToOpenBags debugstack
-- luacheck: read globals SetCVarBitfield LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags

local Takeover = {}
Bags.Takeover = Takeover

local active = false
local hooksInstalled = false
local originalToggleAllBags = nil -- pre-QUI global (re-captured on EVERY Apply)
local originalParents = {}        -- frame → parent
local hiddenHolder = nil
local openedByFrameName = nil     -- Blizzard's FRAME_THAT_OPENED_BAGS analog
local lastToggleTime = -1         -- same-frame toggle debounce

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

local function GetCallStack()
    return (debugstack and debugstack()) or ""
end

--- Programmatic open with Blizzard's FRAME_THAT_OPENED_BAGS parity: an
--- already-open window must NOT re-record the opener; a policy-suppressed
--- frame (autoopen) opens nothing. Shared by the OpenAllBags /
--- OpenAllBagsMatchingContext hooks, the manual toggle, and the bank/guild
--- takeovers (their name-carrying opener proxies).
function Takeover.OpenForFrame(frame, forceUpdate)
    if not active then return end
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

--- Programmatic close, opener-parity: a frame-carrying close only succeeds
--- when the SAME frame opened the window; manual closes (frame == nil)
--- always succeed. Returns whether anything closed (internal callers only —
--- the CloseAllBags hook cannot influence Blizzard's return value).
function Takeover.CloseForFrame(frame)
    if not active then return false end
    if frame and frame.GetName then
        local name = frame:GetName()
        if name ~= openedByFrameName then return false end
    end
    local wasShown = Bags.BagWindow.IsShown()
    openedByFrameName = nil
    Bags.BagWindow.Hide()
    return wasShown
end

-- Manual toggle, shared debounce. The ToggleAllBags replacement and the
-- ToggleBackpack/ToggleBag hooks all land here; nested hook firings within
-- one frame (ToggleBackpack → ToggleBag(0)) collapse to one window op.
local function ManualToggle()
    if not AllowedToOpen() then return end
    local now = GetTime and GetTime() or 0
    if now == lastToggleTime then return end
    lastToggleTime = now
    if Bags.BagWindow.IsShown() then
        Takeover.CloseForFrame()
    else
        Takeover.OpenForFrame()
    end
end

local function OurToggleAllBags()
    ManualToggle()
end

-- Post-hook for ToggleBackpack/ToggleBag: only DIRECT toggles (a keybind or
-- a bag-bar click) reach the window. A toggle nested under OpenAllBags or
-- CloseAllBags is the programmatic path's plumbing — its owner (the
-- OpenAllBags hook / the CloseAllBags hook / the interaction-event sink)
-- already mirrors it.
local function DirectToggleOnly()
    if not active then return end
    local stack = GetCallStack()
    if stack:match("OpenAllBags") or stack:match("CloseAllBags") then return end
    ManualToggle()
end

local function InstallHooks()
    if hooksInstalled or type(hooksecurefunc) ~= "function" then return end
    hooksInstalled = true

    hooksecurefunc("ToggleBackpack", DirectToggleOnly)
    hooksecurefunc("ToggleBag", DirectToggleOnly)

    hooksecurefunc("OpenAllBags", function(frame, forceUpdate)
        Takeover.OpenForFrame(frame, forceUpdate)
    end)

    -- ItemButtonUtil.OpenAndFilterBags (keystone socketing, enchanting,
    -- item-upgrade, soulbinds UIs) bypasses OpenAllBags. Blizzard's own
    -- return value (its hidden frames' open count) keeps driving the
    -- caller's closeBagsOnHide bookkeeping.
    hooksecurefunc("OpenAllBagsMatchingContext", function(frame)
        Takeover.OpenForFrame(frame)
    end)

    -- Loot-toast clicks (AlertFrameSystems.lua's OnClick handlers) call
    -- OpenBag(slot) to show the bag holding the won item — the only
    -- user-facing direct OpenBag caller. The filter keeps
    -- OpenAllBagsInternal's per-bag OpenBag(i) plumbing (already mirrored
    -- by the OpenAllBags hook) out.
    hooksecurefunc("OpenBag", function()
        if not active then return end
        if not GetCallStack():match("AlertFrameSystems") then return end
        Takeover.OpenForFrame() -- manual-style: no opener, no policy gate
    end)

    hooksecurefunc("CloseAllBags", function(frame)
        if not active then return end
        local stack = GetCallStack()
        -- Under CloseAllWindows the UISpecialFrames sweep owns the window
        -- (ESC truth — see header); under a toggle, DirectToggleOnly does.
        if stack:match("CloseAllWindows")
            or stack:match("ToggleBackpack") or stack:match("ToggleBag") then
            return
        end
        Takeover.CloseForFrame(frame)
    end)
end

function Takeover.Apply()
    if active then return end
    active = true

    if not hiddenHolder then
        hiddenHolder = Bags.TakeoverShared.MakeHiddenHolder()
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

    -- Re-captured on every Apply: after an enable→disable cycle a different
    -- addon may have taken ownership while we were inactive — restoring a
    -- first-ever snapshot would silently steal the global back from it.
    originalToggleAllBags = _G.ToggleAllBags
    _G.ToggleAllBags = OurToggleAllBags

    InstallHooks()

    -- The reagent-bag frame tutorial waits for a bag-open and anchors its
    -- HelpTips to the (now invisible) container frames — mark it seen so it
    -- never arms against frames the user can't see.
    if SetCVarBitfield and LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG then
        SetCVarBitfield("closedInfoFrames", LE_FRAME_TUTORIAL_EQUIP_REAGENT_BAG, true)
    end
end

function Takeover.Revert()
    if not active then return end

    -- Restore ONLY if the global still points at our wrapper: a global some
    -- other addon overwrote while we were active has a newer owner —
    -- clobbering it would break that addon. The snapshot dies with the cycle.
    if _G.ToggleAllBags == OurToggleAllBags then
        _G.ToggleAllBags = originalToggleAllBags
    end
    originalToggleAllBags = nil

    for frame, parent in pairs(originalParents) do
        frame:Hide() -- defensive: hand Blizzard back a clean hidden frame
        frame:SetParent(parent)
        originalParents[frame] = nil
    end
    openedByFrameName = nil
    active = false -- hooks go inert (hooksecurefunc has no un-hook)
end
