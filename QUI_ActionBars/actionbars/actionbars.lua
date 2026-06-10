local ADDON_NAME, ns = ...
local env = ns.ActionBarsEnv
env.ADDON_NAME = ADDON_NAME
env.ns = ns
env.SetChunkEnv(1, env)

--[[
    QUI Action Bars - Native Engine
    Creates native ActionButtonTemplate buttons (bar 1) or reparents
    Blizzard's existing buttons (bars 2-8) into QUI-owned containers.
    Buttons get native icon, cooldown, count, drag/pickup, and keybind
    behavior. QUI handles skinning, layout, fade, and empty slot hiding.
]]

ADDON_NAME, ns = ...
Helpers = ns.Helpers
GetCore = Helpers.GetCore
LSM = ns.LSM

-- Upvalue caching for hot-path performance
type = type
pairs = pairs
ipairs = ipairs
pcall = pcall
C_Timer = C_Timer
InCombatLockdown = InCombatLockdown

-- ADDON_LOADED safe window flag: during a combat /reload, InCombatLockdown()
-- returns true but protected calls are still allowed. This flag lets
-- initialization sub-functions bypass their combat guards.
inInitSafeWindow = false

---------------------------------------------------------------------------
-- MIDNIGHT (12.0+) DETECTION
---------------------------------------------------------------------------

IS_MIDNIGHT = select(4, GetBuildInfo()) >= 120000

-- LOCAL suppression of GetActionCount on Midnight (same approach as
-- action button addons).  Must be local — replacing the global taints every
-- Blizzard button that calls it, causing SetCooldown secret-value errors
-- on the hidden original MultiBar buttons we don't own.
GetActionCount = GetActionCount
if IS_MIDNIGHT then
    GetActionCount = function() return 0 end
end

---------------------------------------------------------------------------
-- CONSTANTS
---------------------------------------------------------------------------

-- In-housed textures (self-contained, no external dependencies)
TEXTURE_PATH = [[Interface\AddOns\QUI\assets\iconskin\]]
TEXTURES = {
    normal = TEXTURE_PATH .. "Normal",       -- Black border frame
    gloss = TEXTURE_PATH .. "Gloss",         -- ADD blend shine
    highlight = TEXTURE_PATH .. "Highlight", -- Hover state
    pushed = TEXTURE_PATH .. "Pushed",       -- Click state
    checked = TEXTURE_PATH .. "Checked",     -- Selected state
    flash = TEXTURE_PATH .. "Flash",         -- Ready flash
}

-- Icon texture coordinates (crop transparent edges)
ICON_TEXCOORD = {0.07, 0.93, 0.07, 0.93}

-- Blizzard's range indicator placeholder (to detect and hide)
RANGE_INDICATOR = RANGE_INDICATOR or "●"
VISUAL_REFRESH_DELAY = 0.05
WORLD_INITIAL_REFRESH_DELAY = 0.5

-- Bar frame name mappings (MainMenuBar was renamed to MainActionBar in Midnight 12.0)
BAR_FRAMES = {
    bar1 = "MainActionBar",
    bar2 = "MultiBarBottomLeft",
    bar3 = "MultiBarBottomRight",
    bar4 = "MultiBarRight",
    bar5 = "MultiBarLeft",
    bar6 = "MultiBar5",
    bar7 = "MultiBar6",
    bar8 = "MultiBar7",
    pet = "PetActionBar",
    stance = "StanceBar",
    -- Non-standard bars (special handling in GetBarButtons)
    microbar = "MicroMenuContainer",
    bags = "BagsBar",
    extraActionButton = "ExtraActionBarFrame",  -- Boss encounters, quests
    zoneAbility = "ZoneAbilityFrame",          -- Garrison, covenant, zone powers
}

-- Button name patterns for each bar
BUTTON_PATTERNS = {
    bar1 = "ActionButton%d",
    bar2 = "MultiBarBottomLeftButton%d",
    bar3 = "MultiBarBottomRightButton%d",
    bar4 = "MultiBarRightButton%d",
    bar5 = "MultiBarLeftButton%d",
    bar6 = "MultiBar5Button%d",
    bar7 = "MultiBar6Button%d",
    bar8 = "MultiBar7Button%d",
    pet = "PetActionButton%d",
    stance = "StanceButton%d",
}

-- Button counts per bar
BUTTON_COUNTS = {
    bar1 = 12, bar2 = 12, bar3 = 12, bar4 = 12, bar5 = 12,
    bar6 = 12, bar7 = 12, bar8 = 12, pet = 10, stance = 10,
}

BAR_ACTION_OFFSETS = {
    bar2 = 60,   -- slots 61-72
    bar3 = 48,   -- slots 49-60
    bar4 = 24,   -- slots 25-36
    bar5 = 36,   -- slots 37-48
    bar6 = 144,  -- slots 145-156
    bar7 = 156,  -- slots 157-168
    bar8 = 168,  -- slots 169-180
}

-- Binding command prefixes for LibKeyBound integration
BINDING_COMMANDS = {
    bar1 = "ACTIONBUTTON",           -- ACTIONBUTTON1-12
    bar2 = "MULTIACTIONBAR1BUTTON",  -- MULTIACTIONBAR1BUTTON1-12
    bar3 = "MULTIACTIONBAR2BUTTON",  -- MULTIACTIONBAR2BUTTON1-12
    bar4 = "MULTIACTIONBAR3BUTTON",  -- MULTIACTIONBAR3BUTTON1-12
    bar5 = "MULTIACTIONBAR4BUTTON",  -- MULTIACTIONBAR4BUTTON1-12
    bar6 = "MULTIACTIONBAR5BUTTON",  -- MULTIACTIONBAR5BUTTON1-12
    bar7 = "MULTIACTIONBAR6BUTTON",  -- MULTIACTIONBAR6BUTTON1-12
    bar8 = "MULTIACTIONBAR7BUTTON",  -- MULTIACTIONBAR7BUTTON1-12
    pet = "BONUSACTIONBUTTON",       -- BONUSACTIONBUTTON1-10
    stance = "SHAPESHIFTBUTTON",     -- SHAPESHIFTBUTTON1-10
}

-- Explicit micro button names (stable list, not dependent on GetChildren order)
MICRO_BUTTON_NAMES = {
    "CharacterMicroButton", "ProfessionMicroButton", "PlayerSpellsMicroButton",
    "AchievementMicroButton", "QuestLogMicroButton", "HousingMicroButton",
    "GuildMicroButton", "LFDMicroButton", "CollectionsMicroButton",
    "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton",
}

-- Standard action bar keys (bars 1-8, not pet/stance)
STANDARD_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8"}
STANDARD_BAR_KEY_SET = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
}

-- Bars that participate in the "Link Bars 1-8" mouseover group. Pet and
-- stance share the owned fade system and sit inside the bar cluster, so
-- they must show and hide with the linked group — otherwise they stay
-- faded while the surrounding bars light up.
LINKED_OWNED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "pet", "stance"}

-- All managed bar keys (includes pet/stance/microbar/bags which are reparented into owned containers)
ALL_MANAGED_BAR_KEYS = {"bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "pet", "stance", "microbar", "bags"}

-- Bars that receive action bar skinning (icon crop, backdrop, gloss, keybind text, etc.)
-- Micro menu and bag bar buttons are NOT action buttons and should not be skinned.
SKINNABLE_BAR_KEYS = {
    bar1 = true, bar2 = true, bar3 = true, bar4 = true,
    bar5 = true, bar6 = true, bar7 = true, bar8 = true,
    pet = true, stance = true,
}

---------------------------------------------------------------------------
-- MODULE STATE
---------------------------------------------------------------------------

ActionBarsOwned = {
    initialized = false,
    containers = {},       -- barKey → container frame
    nativeButtons = {},    -- barKey → { button, ... } (native ActionButtonTemplate or reparented Blizzard)
    cachedLayouts = {},    -- barKey → { numCols, numRows, isVertical, numIcons }
    editModeActive = false,
    editOverlays = {},     -- barKey → overlay frame
    fadeState = {},         -- barKey → fade state (shared by all fade subsystems)
    pendingExtraButtonRefresh = false,
    pendingExtraButtonInit = false,
    skinnedButtons = {},    -- button → true (tracking for re-skin on updates)
}
ns.ActionBarsOwned = ActionBarsOwned

-- Forward declaration: defined ~line 3296, called from SafeUpdate (below)
env.__declared.UpdateAssistedCombatRotationFrame = true
env.__declared.UpdateAllAssistedHighlights = true
env.__declared.ResetButtonChargeCapabilityCache = true
env.__declared.ResetAllChargeCapabilityCaches = true
env.__declared.IsButtonInsideVisibleLayout = true
env.__declared.MarkSpellIdMapDirty = true
-- Forward declaration: defined in usability section, called from OnOwnedEvent
env.__declared.ScheduleUsabilityUpdate = true

-- Backward compat alias for any code referencing mirrorButtons
ActionBarsOwned.mirrorButtons = ActionBarsOwned.nativeButtons

-- Taint-safe UpdateAction replacement.  The mixin's UpdateAction calls
-- ActionButton_CalculateAction and uses comparison operators, which can
-- error in tainted context during combat.  This version just syncs the
-- Lua-side self.action from the attribute (set by restricted code) and
-- triggers a safe visual refresh.  Called explicitly via CallMethod from
-- the _childupdate-offset restricted snippet after page changes, and
-- also installed as an instance shadow so any residual mixin path that
-- reaches UpdateAction hits this safe version.
function ActionBarsOwned.SafeSyncAction(self)
    local oldAction = self.action
    local action = self:GetAttribute("action")
    local actionChanged
    if action then
        actionChanged = oldAction and oldAction ~= action
        self.action = action
        if actionChanged and ResetButtonChargeCapabilityCache then
            ResetButtonChargeCapabilityCache(self)
        end
        -- Keep slotMap in sync when bar 1 pages (action ID changes)
        local slotMap = ActionBarsOwned.slotMap
        if slotMap then
            if actionChanged then
                slotMap[oldAction] = nil
            end
            if action > 0 then
                local entry = slotMap[action]
                if entry then
                    entry.button = self
                else
                    slotMap[action] = { button = self, barKey = "bar1" }
                end
            end
        end
    end
    -- Re-register with C-side after page change so it pushes updates
    -- for the new action (critical for assisted combat rotation).
    if SetActionUIButton and action and self.cooldown then
        SetActionUIButton(self, action, self.cooldown)
    end
    ActionBarsOwned.SafeUpdate(self)
    -- Refresh assisted combat highlights after page change — the button
    -- now shows a different spell so the old highlight may be stale.
    if actionChanged and UpdateAllAssistedHighlights then
        UpdateAllAssistedHighlights()
    end
end

-- Taint-safe Update replacement for addon-created action buttons.
-- The Blizzard mixin's Update uses comparison operators (==, ~=, >) on
-- secret number values returned by restricted APIs, which errors when
-- the button is tainted.  This version uses ONLY truthiness tests
-- (if X then) on API returns — Lua evaluates truthiness without
-- comparison operators, so secret booleans/numbers pass through safely.
-- Installed as an instance shadow so any residual mixin path that
-- reaches self:Update() hits this safe version.
-- Pre-filtered "buttons with an action" set. Mirrors LibActionButton's
-- ActiveButtons pattern: maintained by SafeUpdate, consumed by the centralized
-- state/usable/cooldown loops so they skip empty slots without an O(N)
-- iterate + HasAction check every tick. Weak-keyed so destroyed buttons
-- drop out automatically.
ActionBarsOwned._activeButtons = ActionBarsOwned._activeButtons
    or setmetatable({}, { __mode = "k" })
ActionBarsOwned._activeStandardButtons = ActionBarsOwned._activeStandardButtons
    or setmetatable({}, { __mode = "k" })

local function SetupDebugInstrumentation()
    local mp = ns._memprobes or {}; ns._memprobes = mp
    mp[#mp + 1] = {
        name = "AB_activeButtons",
        fn = function()
            local count = 0
            for _ in pairs(ActionBarsOwned._activeButtons) do count = count + 1 end
            return count, 0
        end,
    }
    mp[#mp + 1] = {
        name = "AB_activeStandardButtons",
        fn = function()
            local count = 0
            for _ in pairs(ActionBarsOwned._activeStandardButtons) do count = count + 1 end
            return count, 0
        end,
    }
end
if ns.DebugRegister then -- gate contract: core/debug_gate.lua
    ns.DebugRegister(SetupDebugInstrumentation)
else
    SetupDebugInstrumentation() -- standalone test harness: no gate, run eagerly
end

env.__declared.UpdateButtonProfessionQuality = true
env.__declared.SafeHasAction = true
env.__declared.HasButtonContent = true

function ActionBarsOwned.SafeUpdate(self)
    local action = self.action
    if not action then return end
    local hasAction = SafeHasAction(action)
    local hasContent = hasAction or (self.GetAttribute and self:GetAttribute("gse-button"))

    if hasContent then
        if not InCombatLockdown() and hasAction then
            local flyoutID
            local actionType, actionID, subType = GetActionInfo(action)
            if actionType == "flyout" then
                flyoutID = actionID or subType
            end
            local prevFlyoutID = self:GetAttribute("qui-flyout-id")
            self:SetAttribute("qui-flyout-id", flyoutID)
            if prevFlyoutID and prevFlyoutID ~= flyoutID then
                local popup = _G.QUI_SpellFlyout
                if popup and popup:IsShown()
                    and popup:GetParent() == self
                    and ActionBarsOwned.HideOwnedFlyout then
                    ActionBarsOwned.HideOwnedFlyout()
                end
            end
        end

        local barKey = self._quiBarKey
        local visibleInLayout = not IsButtonInsideVisibleLayout or IsButtonInsideVisibleLayout(self, barKey)
        if visibleInLayout then
            ActionBarsOwned._activeButtons[self] = true
        else
            ActionBarsOwned._activeButtons[self] = nil
        end
        if visibleInLayout and STANDARD_BAR_KEY_SET[barKey] then
            ActionBarsOwned._activeStandardButtons[self] = true
        else
            ActionBarsOwned._activeStandardButtons[self] = nil
        end
        -- Icon — GSE override buttons use the sequence macro icon instead
        -- of the action slot texture, so SafeUpdate doesn't overwrite it.
        local gseSeq = self:GetAttribute("gse-button")
        local texture
        if gseSeq then
            if _G.QUI_GetGSEButtonIcon then
                texture = _G.QUI_GetGSEButtonIcon(self)
            end
            if not texture and GetMacroIndexByName then
                local idx = GetMacroIndexByName(gseSeq)
                if idx and idx > 0 then
                    local _, macTex = GetMacroInfo(idx)
                    local logoIcon = _G.GSE and _G.GSE.Static
                        and _G.GSE.Static.Icons and _G.GSE.Static.Icons.GSE_Logo_Dark
                    if macTex and macTex ~= logoIcon then
                        texture = macTex
                    end
                end
            end
        else
            texture = GetActionTexture(action)
        end
        if texture then
            self.icon:SetTexture(texture)
            self.icon:Show()
            if self.SlotBackground then self.SlotBackground:Hide() end
        else
            self.icon:Hide()
            if self.SlotBackground then self.SlotBackground:Show() end
        end

        UpdateButtonProfessionQuality(self)

        self:SetAlpha(1.0)

        -- Checked state (autoattack, toggle abilities)
        if hasAction and (IsCurrentAction(action) or IsAutoRepeatAction(action)) then
            self:SetChecked(true)
        else
            self:SetChecked(false)
        end

        -- Usability coloring is handled entirely by the QUI tint overlay
        -- system (UpdateButtonUsability).  Keep icon vertex color neutral
        -- so the overlay is the sole source of range/mana/unusable tinting.
        self.icon:SetVertexColor(1, 1, 1)

        -- Equipped border
        if hasAction and IsEquippedAction(action) then
            self.Border:SetVertexColor(0, 1, 0, 0.35)
            self.Border:Show()
        else
            self.Border:Hide()
        end

        -- Action text (macro name)
        if hasAction then
            self.Name:SetText(GetActionText(action) or "")
        else
            self.Name:SetText("")
        end

        -- Delegated to shadowed methods
        self:UpdateCount()
        self:UpdateCooldown()

        -- Proc glow (spell activation overlay)
        ActionBarsOwned.UpdateOverlayGlow(self)

        -- Flyout arrow
        if self.UpdateFlyout then
            pcall(self.UpdateFlyout, self)
        end

        -- Assisted combat rotation arrow (one-button rotation).
        -- Set everActive flag here — SafeUpdate already confirmed
        -- IsAssistedCombatAction, so unblock the rotation frame's
        -- fast-path early return.
        if hasAction
            and C_ActionBar and C_ActionBar.IsAssistedCombatAction
            and C_ActionBar.IsAssistedCombatAction(action) then
            ActionBarsOwned._assistedCombatEverActive = true
        end
        UpdateAssistedCombatRotationFrame(self)

        -- Level link lock
        if hasAction and self.LevelLinkLockIcon and C_LevelLink and C_LevelLink.IsActionLocked then
            if C_LevelLink.IsActionLocked(action) then
                self.icon:SetDesaturated(true)
                self.LevelLinkLockIcon:SetShown(true)
            else
                self.icon:SetDesaturated(false)
                self.LevelLinkLockIcon:SetShown(false)
            end
        end

        -- Flash animation (auto-attack / auto-repeat)
        local shouldFlash = hasAction and (
            (IsAttackAction(action) and IsCurrentAction(action))
            or IsAutoRepeatAction(action)
        )
        if shouldFlash then
            if not self.flashing then
                if ActionButton_StartFlash then
                    pcall(ActionButton_StartFlash, self)
                end
            end
        else
            if self.flashing then
                if ActionButton_StopFlash then
                    pcall(ActionButton_StopFlash, self)
                end
            end
        end
    else
        if not InCombatLockdown() then
            local prevFlyoutID = self:GetAttribute("qui-flyout-id")
            self:SetAttribute("qui-flyout-id", nil)
            if prevFlyoutID then
                local popup = _G.QUI_SpellFlyout
                if popup and popup:IsShown()
                    and popup:GetParent() == self
                    and ActionBarsOwned.HideOwnedFlyout then
                    ActionBarsOwned.HideOwnedFlyout()
                end
            end
        end
        -- Empty slot
        ActionBarsOwned._activeButtons[self] = nil
        ActionBarsOwned._activeStandardButtons[self] = nil
        self.icon:Hide()
        if self.SlotBackground then self.SlotBackground:Show() end
        self:SetChecked(false)
        self.cooldown:Hide()
        self.Count:SetText("")
        self.Name:SetText("")
        self.Border:Hide()
        UpdateButtonProfessionQuality(self)
        if self.LevelLinkLockIcon then
            self.LevelLinkLockIcon:SetShown(false)
        end
        if self.flashing then
            if ActionButton_StopFlash then
                pcall(ActionButton_StopFlash, self)
            end
        end
        -- Clean up overlays/elements that belong to the departed action
        if self.UpdateFlyout then
            pcall(self.UpdateFlyout, self)
        end
        UpdateAssistedCombatRotationFrame(self)
        ActionBarsOwned.UpdateOverlayGlow(self)
    end
end

hiddenBarParent = CreateFrame("Frame")
hiddenBarParent:Hide()

---@type fun(...)
noop = function() end

function HideManagedBlizzardBarFrame(frame, clearEvents)
    if not frame then return end

    if clearEvents then
        frame:UnregisterAllEvents()
    end

    -- Purge Edit Mode's tainted show flag before reparenting, matching the
    -- safer HideBlizzard patterns used elsewhere in this module and by BT4.
    if frame.system then
        frame.isShownExternal = nil
        local c = 42
        repeat
            if frame[c] == nil then
                frame[c] = nil
            end
            c = c + 1
        until issecurevariable(frame, "isShownExternal")
    end

    frame:SetParent(hiddenBarParent)
    if frame.HideBase then
        frame:HideBase()
    else
        frame:Hide()
    end
end

-- QUI uses ActionButtonTemplate + SecureActionButtonTemplate (not
-- ActionBarButtonTemplate) to avoid auto-registering with the secure
-- ActionBarButtonEventsFrame dispatch.  Adding tainted buttons to that
-- array permanently taints its iteration.

function SuppressBlizzardButton(btn)
    btn:Hide()
    btn:UnregisterAllEvents()
    btn:SetAttribute("statehidden", true)
    -- Keep the original secure OnEvent handler intact.  The dispatch
    -- calls it, but with events unregistered and the button hidden,
    -- the secure handler runs harmlessly without tainting the context.
end

env.__declared.LayoutNativeButtons = true

-- Reclaim reparented buttons back to their QUI container and re-layout.
-- Used after Blizzard steals them during vehicle/override transitions.
function ReclaimBarButtons(barKey)
    local btns = ActionBarsOwned.nativeButtons[barKey]
    local cont = ActionBarsOwned.containers[barKey]
    if not btns or not cont then return end
    for _, btn in ipairs(btns) do
        if btn:GetParent() ~= cont then
            btn:SetParent(cont)
        end
    end
    LayoutNativeButtons(barKey)
end

---------------------------------------------------------------------------
-- SECURE LAYOUT HANDLER
---------------------------------------------------------------------------
-- A single SecureHandlerAttributeTemplate whose restricted snippet executes
-- SetScale/SetPoint/Show/Hide on secure action buttons, bypassing combat
-- lockdown entirely. Normal Lua encodes layout data as attributes; the
-- restricted environment reads them and applies the layout.
---------------------------------------------------------------------------

layoutHandler = CreateFrame("Frame", "QUI_ActionBarLayoutHandler", UIParent, "SecureHandlerAttributeTemplate")

layoutHandler:SetAttribute("_onattributechanged", [=[
    if name ~= "do-layout" then return end
    local barKey = self:GetAttribute("layout-target")
    if not barKey then return end

    local prefix = "bl-" .. barKey
    local count  = self:GetAttribute(prefix .. "-count") or 0
    local anchor = self:GetAttribute(prefix .. "-anchor") or "TOPLEFT"
    local scale  = tonumber(self:GetAttribute(prefix .. "-scale")) or 1
    local cw     = tonumber(self:GetAttribute(prefix .. "-cw"))
    local ch     = tonumber(self:GetAttribute(prefix .. "-ch"))
    local barRef = self:GetFrameRef("bar-" .. barKey)
    if not barRef then return end

    if cw and ch then
        barRef:SetScale(1)
        barRef:SetWidth(cw)
        barRef:SetHeight(ch)
    end

    for i = 1, count do
        local btnRef = self:GetFrameRef("btn-" .. barKey .. "-" .. i)
        if btnRef then
            local data = self:GetAttribute(prefix .. "-" .. i)
            if data then
                local x, y, show = strsplit("|", data)
                btnRef:SetScale(scale)
                btnRef:ClearAllPoints()
                btnRef:SetPoint(anchor, barRef, anchor, tonumber(x) or 0, tonumber(y) or 0)
                if show == "1" then
                    btnRef:Show()
                else
                    btnRef:Hide()
                end
            end
        end
    end
]=])

-- Encode layout data as attributes and trigger the secure snippet.
function SecureLayoutBar(barKey, buttons, numVisible, anchor, btnScale, positions, groupWidth, groupHeight)
    local prefix = "bl-" .. barKey
    layoutHandler:SetAttribute(prefix .. "-count", #buttons)
    layoutHandler:SetAttribute(prefix .. "-anchor", anchor)
    layoutHandler:SetAttribute(prefix .. "-scale", btnScale)
    layoutHandler:SetAttribute(prefix .. "-cw", groupWidth)
    layoutHandler:SetAttribute(prefix .. "-ch", groupHeight)

    for i = 1, #buttons do
        if i <= numVisible then
            local pos = positions[i]
            layoutHandler:SetAttribute(prefix .. "-" .. i, pos.x .. "|" .. pos.y .. "|1")
        else
            layoutHandler:SetAttribute(prefix .. "-" .. i, "0|0|0")
        end
    end

    layoutHandler:SetAttribute("layout-target", barKey)
    layoutHandler:SetAttribute("do-layout", GetTime())
end

-- Forward declarations for functions defined later but needed by BuildBar / event handlers
env.__declared.SkinButton = true
env.__declared.UpdateButtonText = true
env.__declared.UpdateEmptySlotVisibility = true
env.__declared.UpdateKeybindText = true
env.__declared.FadeHideTextures = true
env.__declared.FadeShowTextures = true
env.__declared.ApplyAllBarSpacing = true
env.__declared.ApplyFlyoutDirection = true
env.__declared.ApplyAllFlyoutDirections = true

-- Store QUI state outside secure Blizzard frame tables.
-- Writing custom keys directly on action buttons can taint secret values.
-- UNIFIED: both LibKeyBound patch and keybind registration use this single table.
frameState, GetFrameState = Helpers.CreateStateTable()
