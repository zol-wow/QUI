---------------------------------------------------------------------------
-- QUI Layout Mode — Core Engine
-- Self-contained frame positioning system replacing Blizzard Edit Mode
-- dependency. Provides registration API, hybrid overlay/proxy system,
-- drag system, position save/load, and combat suspend/resume.
--
-- Hybrid approach:
--   isOwned = true  → child overlay parented to the frame (no sync needed)
--   isOwned = false → separate proxy mover parented to UIParent (synced)
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local QUI_LayoutMode = {}
ns.QUI_LayoutMode = QUI_LayoutMode

-- Accent color: cached from GUI.Colors.accent, refreshed via RefreshAccentColor().
-- Falls back to Sky Blue (#60A5FA) if GUI hasn't loaded yet.
local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980

-- Upvalue caching for hot-path performance
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local tostring = tostring
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown

local function RefreshAccentColor()
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and GUI.Colors and GUI.Colors.accent then
        ACCENT_R = GUI.Colors.accent[1]
        ACCENT_G = GUI.Colors.accent[2]
        ACCENT_B = GUI.Colors.accent[3]
    end
end

-- Visual constants
local HANDLE_STRATA      = "FULLSCREEN_DIALOG"
local HANDLE_BG_ALPHA    = 0.55
local HANDLE_HOVER_ALPHA = 0.85
local HANDLE_DRAG_ALPHA  = 0.95
local HANDLE_BORDER_SIZE = 1
local HANDLE_BORDER_SIZE_ANCHORED = 2
local HANDLE_MIN_SIZE    = 20
local TINY_THRESHOLD     = 3   -- frames above this use real size, not the 20px floor

-- Anchor indicator (custom TGA texture — WoW fonts can't render Unicode ⚓)

-- Forward declarations
local CreateHandle, CreateProxyMover, CreateChildOverlay
local SyncHandle, HandleToOffsets, SetHandleFromOffsets
local SnapshotPositions, CommitPositions, RevertPositions
local ShowSaveDiscardPopup, AddHandleVisuals, AddHandleScripts
local GetFrameAnchoring

--- Migrate db.unlockMode → db.layoutMode for existing users.
local function MigrateDBKey(db)
    if db.unlockMode and not db.layoutMode then
        db.layoutMode = db.unlockMode
        db.unlockMode = nil
    end
end

--- Get the persisted hidden-handles table from DB.
local function GetHiddenHandlesDB()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    MigrateDBKey(db)
    if not db.layoutMode then db.layoutMode = {} end
    if not db.layoutMode.hiddenHandles then db.layoutMode.hiddenHandles = {} end
    return db.layoutMode.hiddenHandles
end

---------------------------------------------------------------------------
-- GAMEPLAY VISIBILITY ENFORCEMENT
-- When layout mode "hides" a handle, also hide the actual frame during
-- normal gameplay.  Each element can provide a `setGameplayHidden(bool)`
-- callback for module-specific hide/show logic.  Fallback: alpha-0 +
-- disable mouse.
---------------------------------------------------------------------------
local InCombatLockdown = InCombatLockdown

-- Track which keys WE have gameplay-hidden so we only restore those.
-- Without this, restoring would force-show frames that are naturally
-- hidden (loot window, pet frame, party keystones, etc.).
QUI_LayoutMode._gameplayHidden = {}

function QUI_LayoutMode:EnforceGameplayVisibility()
    if self.isActive then return end  -- layout mode handles its own visibility
    local hidden = GetHiddenHandlesDB()
    if not hidden then return end

    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if not def then break end

        -- Skip disabled elements and master toggles (no visual frame to hide)
        if def.noHandle then
            -- noop: master toggles have no visual presence
        elseif def.isEnabled and not def.isEnabled() then
            -- noop: disabled elements are already hidden/reverted
        else
            local shouldHide = hidden[key] == true
            local wasHiddenByUs = self._gameplayHidden[key]

            if shouldHide and not wasHiddenByUs then
                -- Hide this frame
                self._gameplayHidden[key] = true
                if def.setGameplayHidden then
                    pcall(def.setGameplayHidden, true)
                else
                    local frame = def.getFrame and def.getFrame()
                    if frame then
                        if InCombatLockdown() then
                            self._deferredGameplayHides = self._deferredGameplayHides or {}
                            self._deferredGameplayHides[key] = true
                        else
                            pcall(frame.SetAlpha, frame, 0)
                            pcall(frame.EnableMouse, frame, false)
                        end
                    end
                end
            elseif not shouldHide and wasHiddenByUs then
                -- Restore only frames WE previously hid
                self._gameplayHidden[key] = nil
                if def.setGameplayHidden then
                    pcall(def.setGameplayHidden, false)
                else
                    local frame = def.getFrame and def.getFrame()
                    if frame then
                        pcall(frame.SetAlpha, frame, 1)
                        pcall(frame.EnableMouse, frame, true)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
QUI_LayoutMode.isActive       = false
QUI_LayoutMode._combatSuspended = false
QUI_LayoutMode._hasChanges      = false
QUI_LayoutMode._pendingPositions   = {}  -- { [key] = {point, relPoint, offsetX, offsetY, anchorTarget?, anchorPointSelf?, anchorPointTarget?} }
QUI_LayoutMode._snapshotPositions  = {}  -- captured on open for revert
QUI_LayoutMode._handles           = {}  -- { [key] = handleFrame } (replaces _movers)
QUI_LayoutMode._elements          = {}  -- { [key] = definition }
QUI_LayoutMode._elementOrder      = {}  -- sorted array of keys
QUI_LayoutMode._selectedKey       = nil -- currently selected handle key
QUI_LayoutMode._enterCallbacks    = {}  -- registered open callbacks
QUI_LayoutMode._exitCallbacks     = {}  -- registered close callbacks
QUI_LayoutMode._savedMovableState = {}  -- { [key] = wasMovable } for owned frames

-- Backward compat alias
QUI_LayoutMode._movers = QUI_LayoutMode._handles

---------------------------------------------------------------------------
-- REGISTRATION API
---------------------------------------------------------------------------

--- Register an element for Layout Mode positioning.
--- @param def table Element definition with required fields:
---   key (string), label (string), group (string), order (number),
---   getFrame (function) — returns frame to measure/position
--- Optional fields:
---   isOwned (boolean) — true = child overlay, false/nil = proxy mover
---   isEnabled (function) — returns whether the element is currently enabled
---   setEnabled (function) — callback to enable/disable the element in DB
---   getSize (function) — override measured size (w, h); forces proxy mover
---   getCenterOffset (function(w, h)) — returns (dx, dy) to shift mover center from frame center
---   setupOverlay (function(overlay, frame)) — custom child overlay sizing/anchoring
---   isAnchored (function) — true if anchored to another element
---   onOpen (function) — called when Layout Mode opens
---   onClose (function) — called when Layout Mode closes
---   onLiveMove (function) — callback during/after drag
---   loadPosition (function) — custom position loader (overrides frameAnchoring)
---   savePosition (function) — custom position saver (overrides frameAnchoring)
---   usesCustomPositionPersistence (boolean) — skip generic frameAnchoring DB writes/lock handling
function QUI_LayoutMode:RegisterElement(def)
    if not def or not def.key then return end

    self._elements[def.key] = def
    self:_RebuildOrder()

    -- If Layout Mode is already active, create handle immediately (if enabled)
    if self.isActive and not self._combatSuspended then
        if not def.isEnabled or def.isEnabled() then
            local handle = CreateHandle(def)
            self._handles[def.key] = handle
            SyncHandle(def.key)
            handle:Show()
        end
    end
end

--- Unregister an element from Layout Mode.
--- @param key string The element key to unregister
function QUI_LayoutMode:UnregisterElement(key)
    if not key then return end

    self._elements[key] = nil
    self:_RebuildOrder()

    local handle = self._handles[key]
    if handle then
        handle:Hide()
        -- Restore movable state for owned frames
        if handle._isChildOverlay and handle._parentFrame then
            local saved = self._savedMovableState[key]
            if saved ~= nil then
                pcall(handle._parentFrame.SetMovable, handle._parentFrame, saved)
                self._savedMovableState[key] = nil
            end
        end
        handle:SetParent(nil)
        self._handles[key] = nil
    end

    self._pendingPositions[key] = nil

    if self._selectedKey == key then
        self._selectedKey = nil
    end
end

--- Rebuild sorted element order from registered elements.
function QUI_LayoutMode:_RebuildOrder()
    local order = {}
    for key in pairs(self._elements) do
        order[#order + 1] = key
    end
    table.sort(order, function(a, b)
        local da, db = self._elements[a], self._elements[b]
        local ga, gb = da.group or "", db.group or ""
        if ga ~= gb then return ga < gb end
        return (da.order or 999) < (db.order or 999)
    end)
    self._elementOrder = order
end

--- Check if an element is currently enabled.
function QUI_LayoutMode:IsElementEnabled(key)
    local def = self._elements[key]
    if not def then return false end
    if not def.isEnabled then return true end  -- no isEnabled = always enabled
    return def.isEnabled()
end

--- Toggle an element's enabled state and create/destroy handle.
function QUI_LayoutMode:SetElementEnabled(key, enabled)
    local def = self._elements[key]
    if not def or not def.setEnabled then return end

    def.setEnabled(enabled)

    -- When re-enabling, clear the hidden state so the frame becomes visible
    if enabled then
        self:ClearHiddenState(key)
    end

    if not self.isActive then return end
    if def.noHandle then return end

    if enabled then
        -- Show preview if element has one
        if def.onOpen then pcall(def.onOpen) end
        -- Create handle if it doesn't exist
        if not self._handles[key] then
            local handle = CreateHandle(def)
            self._handles[key] = handle
            SyncHandle(key)
            handle:Show()
            -- If child overlay isn't visible (parent hidden), replace with proxy mover.
            -- mplusTimer exempt (see main code path).
            if handle._isChildOverlay and not handle:IsVisible() and key ~= "mplusTimer" then
                handle:Hide()
                handle:SetParent(nil)
                handle = CreateProxyMover(def)
                self._handles[key] = handle
                SyncHandle(key)
                handle:Show()
            end
            -- Deferred: attach preview to mover
            C_Timer.After(0, function()
                if not handle:IsShown() or handle._isChildOverlay then return end
                local targetFrame = def.getFrame and def.getFrame()
                if targetFrame and targetFrame:IsShown() then
                    if not handle._savedTargetParent then
                        handle._savedTargetParent = targetFrame:GetParent()
                    end
                    if not handle._savedTargetStrata then
                        handle._savedTargetStrata = targetFrame:GetFrameStrata()
                    end
                    targetFrame:SetParent(handle)
                    targetFrame:SetFrameStrata("DIALOG")
                    targetFrame:SetFrameLevel(1)
                    if _G.QUI_SetFrameLayoutOwned then
                        _G.QUI_SetFrameLayoutOwned(targetFrame, def.key)
                    end
                    targetFrame:ClearAllPoints()
                    -- Elements with getCenterOffset: offset the preview within the mover
                    if def.getCenterOffset then
                        local cdx, cdy = def.getCenterOffset(handle:GetSize())
                        targetFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                    else
                        targetFrame:SetAllPoints(handle)
                    end
                end
            end)
        end
    else
        -- Hide preview if element has one
        if def.onClose then pcall(def.onClose) end
        -- Restore preview frame parent and destroy handle
        local handle = self._handles[key]
        if handle then
            if handle._savedTargetParent then
                local targetFrame = def.getFrame and def.getFrame()
                if targetFrame then
                    pcall(targetFrame.SetParent, targetFrame, handle._savedTargetParent)
                    if handle._savedTargetStrata then
                        pcall(targetFrame.SetFrameStrata, targetFrame, handle._savedTargetStrata)
                    end
                    if _G.QUI_SetFrameLayoutOwned then
                        _G.QUI_SetFrameLayoutOwned(targetFrame, nil)
                    end
                    -- Re-pin to UIParent at the handle's current screen
                    -- position — otherwise SetAllPoints(handle) leaves a
                    -- dangling anchor to the about-to-be-hidden handle and
                    -- the frame disappears.  See Close() for details.
                    local cx, cy = handle:GetCenter()
                    if cx and cy then
                        local hs = handle:GetEffectiveScale() or 1
                        local us = UIParent:GetEffectiveScale() or 1
                        local uw = UIParent:GetWidth() or 0
                        local uh = UIParent:GetHeight() or 0
                        local ox = (cx * hs / us) - (uw / 2)
                        local oy = (cy * hs / us) - (uh / 2)
                        pcall(targetFrame.ClearAllPoints, targetFrame)
                        pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", ox, oy)
                    end
                end
                handle._savedTargetParent = nil
                handle._savedTargetStrata = nil
            end
            handle:Hide()
            if handle._isChildOverlay and handle._parentFrame then
                local saved = self._savedMovableState[key]
                if saved ~= nil then
                    pcall(handle._parentFrame.SetMovable, handle._parentFrame, saved)
                    self._savedMovableState[key] = nil
                end
            end
            handle:SetParent(nil)
            self._handles[key] = nil
        end
        if self._selectedKey == key then
            self:SelectMover(nil)
        end
    end
end

---------------------------------------------------------------------------
-- CALLBACK REGISTRY
---------------------------------------------------------------------------

function QUI_LayoutMode:RegisterEnterCallback(callback)
    if type(callback) == "function" then
        self._enterCallbacks[#self._enterCallbacks + 1] = callback
    end
end

function QUI_LayoutMode:RegisterExitCallback(callback)
    if type(callback) == "function" then
        self._exitCallbacks[#self._exitCallbacks + 1] = callback
    end
end

---------------------------------------------------------------------------
-- OPEN / CLOSE / TOGGLE
---------------------------------------------------------------------------

function QUI_LayoutMode:Toggle()
    if self.isActive then
        self:Close()
    else
        self:Open()
    end
end

function QUI_LayoutMode:Open()
    if self.isActive then return end
    if InCombatLockdown() then
        print("|cff60A5FAQUI:|r Cannot open Layout Mode during combat.")
        return
    end

    -- Pick up any accent color changes before creating/showing handles
    RefreshAccentColor()
    if ns.QUI_LayoutMode_UI and ns.QUI_LayoutMode_UI.RefreshAccentColor then
        ns.QUI_LayoutMode_UI:RefreshAccentColor()
    end
    if ns.QUI_LayoutMode_Utils and ns.QUI_LayoutMode_Utils.RefreshAccentColor then
        ns.QUI_LayoutMode_Utils:RefreshAccentColor()
    end
    if ns.QUI_LayoutMode_Settings and ns.QUI_LayoutMode_Settings.RefreshAccentColor then
        ns.QUI_LayoutMode_Settings:RefreshAccentColor()
    end

    self.isActive = true

    self._hasChanges = false

    -- Clear previous selection and stop any lingering pixel glow
    if self._selectedKey and self._handles[self._selectedKey] then
        local prev = self._handles[self._selectedKey]
        prev._selected = false
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG then LCG.PixelGlow_Stop(prev, "_QUILayoutSelect") end
    end
    self._selectedKey = nil
    self._prevSelectedKey = nil

    -- Snapshot current positions for revert
    SnapshotPositions()

    -- Snapshot hidden-handle state for revert on discard
    local hiddenSnap = {}
    local hiddenDB = GetHiddenHandlesDB()
    if hiddenDB then
        for k, v in pairs(hiddenDB) do
            hiddenSnap[k] = v
        end
    end
    self._snapshotHiddenHandles = hiddenSnap

    -- Fire enter callbacks BEFORE handle creation — callbacks like
    -- QUI_OnEditModeEnterCDM show/populate CDM containers so their frames
    -- are visible when CreateHandle runs (enabling child overlays instead
    -- of proxy mover fallbacks).
    -- Flag: during this window, _handles don't exist yet but we still need
    -- QUI_IsLayoutModeManaged to block positioning triggered by callbacks.
    self._enterCallbacksRunning = true
    for _, cb in ipairs(self._enterCallbacks) do
        pcall(cb)
    end
    self._enterCallbacksRunning = false

    -- Create and show handles (only for enabled elements, respecting persisted hidden state)
    -- onOpen previews only fire for elements that are both enabled AND not hidden.
    local hidden = GetHiddenHandlesDB()
    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        local enabled = not def.isEnabled or def.isEnabled()

        if enabled and not def.noHandle then
            -- Respect persisted hidden state
            if hidden and hidden[key] then
                -- Create handle but keep hidden, don't show preview
                if not self._handles[key] then
                    self._handles[key] = CreateHandle(def)
                end
                SyncHandle(key)
                self._handles[key]:Hide()
                if def.onClose then pcall(def.onClose) end
            else
                -- Activate preview FIRST so frame is shown before CreateHandle
                if def.onOpen then pcall(def.onOpen) end
                if not self._handles[key] then
                    self._handles[key] = CreateHandle(def)
                else
                    -- Re-enable movable on existing child overlay parents
                    local handle = self._handles[key]
                    if handle._isChildOverlay and handle._parentFrame then
                        local wasMovable = handle._parentFrame:IsMovable()
                        self._savedMovableState[key] = wasMovable
                        handle._parentFrame:SetMovable(true)
                        handle._parentFrame:SetClampedToScreen(true)
                    end
                end

                -- Check if this handle is anchored to another handle (not screen).
                -- If so, defer showing until the deferred sync positions it correctly
                -- — avoids a visible jump from fallback position to correct position.
                local fa = GetFrameAnchoring()
                local faEntry = fa and fa[key]
                local isAnchored = faEntry and type(faEntry) == "table"
                    and faEntry.parent and faEntry.parent ~= "screen"
                    and faEntry.parent ~= "disabled"

                SyncHandle(key)
                local handle = self._handles[key]

                if not isAnchored then
                    handle:Show()
                end

                -- If child overlay isn't visible (parent hidden), replace with proxy mover.
                -- mplusTimer is exempt: its parent is shown via demo mode and we
                -- need the child overlay to inherit the parent's user-set scale.
                if handle._isChildOverlay and not handle:IsVisible() and key ~= "mplusTimer" then
                    handle:Hide()
                    handle:SetParent(nil)
                    handle = CreateProxyMover(def)
                    self._handles[key] = handle
                    SyncHandle(key)
                    if not isAnchored then
                        handle:Show()
                    end
                end
            end
        end
    end

    -- Sync anchored handles in topological order (parents before children)
    -- so multi-level chains resolve correctly (e.g., cdmEssential →
    -- targetFrame → totFrame). Done immediately — all handles exist now.
    do
        local fa = GetFrameAnchoring()
        if fa then
            local depths = {}
            local function getDepth(key, seen)
                if depths[key] then return depths[key] end
                if seen and seen[key] then return 0 end  -- cycle guard
                local entry = fa[key]
                local parent = entry and type(entry) == "table" and entry.parent
                if not parent or parent == "screen" or parent == "disabled" then
                    depths[key] = 0
                    return 0
                end
                if not seen then seen = {} end
                seen[key] = true
                depths[key] = getDepth(parent, seen) + 1
                return depths[key]
            end

            local sorted = {}
            local hiddenDB = GetHiddenHandlesDB()
            for childKey in pairs(self._handles) do
                local entry = fa[childKey]
                if entry and type(entry) == "table" and entry.parent
                    and entry.parent ~= "screen" and entry.parent ~= "disabled" then
                    getDepth(childKey)
                    sorted[#sorted + 1] = childKey
                end
            end
            table.sort(sorted, function(a, b) return (depths[a] or 0) < (depths[b] or 0) end)
            for _, childKey in ipairs(sorted) do
                SyncHandle(childKey)
                -- Show anchored handles now that they're correctly positioned
                -- (they were deferred during initial creation to avoid jump).
                local h = self._handles[childKey]
                if h and not (hiddenDB and hiddenDB[childKey]) then
                    h:Show()
                end
            end
        end
    end

    -- Deferred: attach preview frames to proxy movers so movers render on top.
    C_Timer.After(0, function()
        local reparentedKeys = {}
        local hiddenDB = GetHiddenHandlesDB()
        for hKey, handle in pairs(self._handles) do
            local isUserHidden = hiddenDB and hiddenDB[hKey]
            if not isUserHidden and not handle._isChildOverlay then
                local hDef = self._elements[hKey]
                local targetFrame = hDef and hDef.getFrame and hDef.getFrame()
                if targetFrame and targetFrame:IsShown() then
                    if not handle._savedTargetParent then
                        handle._savedTargetParent = targetFrame:GetParent()
                    end
                    if not handle._savedTargetStrata then
                        handle._savedTargetStrata = targetFrame:GetFrameStrata()
                    end
                    targetFrame:SetParent(handle)
                    -- Use DIALOG strata — one level below the handle's
                    -- FULLSCREEN_DIALOG — so preview children (CDM icons,
                    -- action buttons) never render above the mover overlay
                    -- regardless of their frame level.
                    targetFrame:SetFrameStrata("DIALOG")
                    targetFrame:SetFrameLevel(1)
                    -- Block module positioning (PositionFrame) for this
                    -- frame while it's managed by the layout mode handle.
                    if _G.QUI_SetFrameLayoutOwned then
                        _G.QUI_SetFrameLayoutOwned(targetFrame, hKey)
                    end
                    targetFrame:ClearAllPoints()
                    if hKey == "bossFrames" then
                        -- Boss1 anchors to the TOP of the handle, not center
                        targetFrame:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, 0)
                        targetFrame:SetPoint("TOPRIGHT", handle, "TOPRIGHT", 0, 0)
                    elseif hDef.getCenterOffset then
                        local cdx, cdy = hDef.getCenterOffset(handle:GetSize())
                        targetFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                    else
                        targetFrame:SetAllPoints(handle)
                    end

                    -- Boss frames: reparent all boss frames + castbars into the mover
                    if hKey == "bossFrames" then
                        local QUI_UF = ns.QUI_UnitFrames
                        local bossFrames = QUI_UF and QUI_UF.frames
                        if bossFrames then
                            for i = 2, 5 do
                                local bf = bossFrames["boss" .. i]
                                if bf and bf:IsShown() then
                                    if not handle._savedBossParents then handle._savedBossParents = {} end
                                    handle._savedBossParents[i] = bf:GetParent()
                                    bf:SetParent(handle)
                                    bf:SetFrameStrata("DIALOG")
                                    bf:SetFrameLevel(1)
                                end
                            end
                            -- Reparent boss castbars
                            local castbars = ns.QUI_Castbar and ns.QUI_Castbar.castbars
                            if castbars then
                                if not handle._savedCastbarParents then handle._savedCastbarParents = {} end
                                for i = 1, 5 do
                                    local cb = castbars["boss" .. i]
                                    if cb and cb:IsShown() then
                                        handle._savedCastbarParents[i] = cb:GetParent()
                                        cb:SetParent(handle)
                                        cb:SetFrameStrata("DIALOG")
                                        cb:SetFrameLevel(2)
                                    end
                                end
                            end
                        end
                    end

                    reparentedKeys[hKey] = true
                end
            end
        end

        -- Re-sync all handles after reparenting so positions reflect
        -- any frame-size changes from the reparent.
        for hKey in pairs(self._handles) do
            SyncHandle(hKey)
        end
    end)

    -- Show UI overlay, grid, toolbar (layoutmode_ui.lua)
    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Show()
    end

    -- Register combat events
    if not self._combatFrame then
        self._combatFrame = CreateFrame("Frame")
        self._combatFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                QUI_LayoutMode:_CombatSuspend()
                QUI_LayoutMode._pendingCombatClose = true
                print("|cff60A5FAQUI:|r Layout Mode closed (combat). Unsaved changes discarded.")
            elseif event == "PLAYER_REGEN_ENABLED" then
                C_Timer.After(0.5, function()
                    if QUI_LayoutMode._pendingCombatClose then
                        QUI_LayoutMode._pendingCombatClose = nil
                        QUI_LayoutMode:DiscardAndClose()
                    else
                        QUI_LayoutMode:_CombatResume()
                    end
                end)
            end
        end)
    end
    self._combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self._combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Show first-time tips
    if not self._firstOpenDone then
        self._firstOpenDone = true
        print("|cff60A5FAQUI Layout Mode:|r Drag to move | Click to select | Arrow keys to nudge | Shift+Drag near edge = anchor | Escape to close")
    end
end

function QUI_LayoutMode:Close(skipSaveCheck)
    if not self.isActive then return end

    -- If there are unsaved changes and we're not forcing close, show popup
    if self._hasChanges and not skipSaveCheck then
        ShowSaveDiscardPopup()
        return
    end

    self.isActive = false
    self._combatSuspended = false

    -- Restore preview frame parents and hide handles
    for key, handle in pairs(self._handles) do
        if handle._savedTargetParent then
            local def = self._elements[key]
            local targetFrame = def and def.getFrame and def.getFrame()
            if targetFrame then
                pcall(targetFrame.SetParent, targetFrame, handle._savedTargetParent)
                -- Restore original strata (was changed to DIALOG during layout mode)
                if handle._savedTargetStrata then
                    pcall(targetFrame.SetFrameStrata, targetFrame, handle._savedTargetStrata)
                end
                -- Release the PositionFrame guard set during reparenting
                if _G.QUI_SetFrameLayoutOwned then
                    _G.QUI_SetFrameLayoutOwned(targetFrame, nil)
                end
                -- The frame was SetAllPoints(handle) while layout mode was
                -- active.  The handle is about to be hidden, leaving the
                -- frame with a dangling anchor to a hidden ancestor — the
                -- frame disappears even though it's still "shown".  Re-pin
                -- to UIParent at the handle's current screen position so
                -- the frame stays where the user left it.  SaveAndClose /
                -- DiscardAndClose run QUI_ApplyAllFrameAnchors after this,
                -- which will override with any saved anchor; for elements
                -- without a frameAnchoring entry (e.g. zoneAbility that
                -- the user never moved), this keeps them visible.
                local cx, cy = handle:GetCenter()
                if cx and cy then
                    local hs = handle:GetEffectiveScale() or 1
                    local us = UIParent:GetEffectiveScale() or 1
                    local uw = UIParent:GetWidth() or 0
                    local uh = UIParent:GetHeight() or 0
                    local ox = (cx * hs / us) - (uw / 2)
                    local oy = (cy * hs / us) - (uh / 2)
                    pcall(targetFrame.ClearAllPoints, targetFrame)
                    pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", ox, oy)
                end
            end
            handle._savedTargetParent = nil
            handle._savedTargetStrata = nil
        end
        -- Restore boss frame children
        if handle._savedBossParents then
            local QUI_UF = ns.QUI_UnitFrames
            local bossFrames = QUI_UF and QUI_UF.frames
            if bossFrames then
                for i, savedParent in pairs(handle._savedBossParents) do
                    local bf = bossFrames["boss" .. i]
                    if bf then pcall(bf.SetParent, bf, savedParent) end
                end
            end
            handle._savedBossParents = nil
        end
        if handle._savedCastbarParents then
            local castbars = ns.QUI_Castbar and ns.QUI_Castbar.castbars
            if castbars then
                for i, savedParent in pairs(handle._savedCastbarParents) do
                    local cb = castbars["boss" .. i]
                    if cb then pcall(cb.SetParent, cb, savedParent) end
                end
            end
            handle._savedCastbarParents = nil
        end
        handle:Hide()
        if handle._isChildOverlay and handle._parentFrame then
            local saved = self._savedMovableState[key]
            if saved ~= nil then
                pcall(handle._parentFrame.SetMovable, handle._parentFrame, saved)
            end
        end
    end
    self._savedMovableState = {}

    -- Clear selection and stop pixel glow before hiding handles
    if self._selectedKey and self._handles[self._selectedKey] then
        local prev = self._handles[self._selectedKey]
        prev._selected = false
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG then LCG.PixelGlow_Stop(prev, "_QUILayoutSelect") end
    end
    self._selectedKey = nil
    self._prevSelectedKey = nil

    -- Hide UI
    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Hide()
    end

    -- Hide settings panel
    local settings = ns.QUI_LayoutMode_Settings
    if settings then
        settings:Reset()
    end

    -- Fire element onClose callbacks
    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if def.onClose then
            pcall(def.onClose)
        end
    end

    -- Re-enforce enabled/disabled state for owned elements
    -- (ensures disabled frames stay hidden after edit mode)
    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if def.setEnabled and def.isEnabled then
            local enabled = def.isEnabled()
            if not enabled then
                pcall(def.setEnabled, false)
            end
        end
    end

    -- Enforce gameplay visibility (hide frames the user toggled off)
    self:EnforceGameplayVisibility()

    -- Fire exit callbacks
    for _, cb in ipairs(self._exitCallbacks) do
        pcall(cb)
    end

    -- Unregister combat events
    if self._combatFrame then
        self._combatFrame:UnregisterAllEvents()
    end

    self._selectedKey = nil
    self._pendingPositions = {}
    self._snapshotPositions = {}
    self._snapshotHiddenHandles = nil
end

function QUI_LayoutMode:SaveAndClose()
    CommitPositions()
    self._hasChanges = false
    self:Close(true)
    -- Re-apply anchors now that layout mode is fully closed and frames
    -- are restored to their original parents. The CommitPositions() call
    -- above applies anchors while layout mode is still active — frames are
    -- reparented to handles and some (e.g., boss frames) bail from
    -- ApplyFrameAnchor while QUI_IsLayoutModeActive() is true. After
    -- Close() deactivates layout mode and restores parents, a fresh apply
    -- ensures all frames land at their saved positions.
    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll(true)
    end
end

function QUI_LayoutMode:DiscardAndClose()
    RevertPositions()
    -- Revert hidden-handle state to snapshot
    local snap = self._snapshotHiddenHandles
    if snap then
        local hidden = GetHiddenHandlesDB()
        if hidden then
            wipe(hidden)
            for k, v in pairs(snap) do
                hidden[k] = v
            end
        end
    end
    self._hasChanges = false
    self:Close(true)
    -- Re-apply anchors after Close() for the same reason as SaveAndClose.
    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll(true)
    end
end

---------------------------------------------------------------------------
-- COMBAT SUSPEND / RESUME
---------------------------------------------------------------------------

function QUI_LayoutMode:_CombatSuspend()
    if not self.isActive then return end
    self._combatSuspended = true

    -- Hide all handles and UI but preserve state
    for _, handle in pairs(self._handles) do
        handle:Hide()
    end

    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Hide()
    end

    local settings = ns.QUI_LayoutMode_Settings
    if settings then
        settings:Hide()
    end
end

function QUI_LayoutMode:_CombatResume()
    if not self._combatSuspended then return end
    if InCombatLockdown() then return end
    self._combatSuspended = false

    -- Re-show everything and re-sync handles
    for _, key in ipairs(self._elementOrder) do
        local handle = self._handles[key]
        if handle then
            SyncHandle(key)
            handle:Show()
        end
    end

    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Show()
    end

    -- Restore settings panel if a handle was selected
    if self._selectedKey then
        local settings = ns.QUI_LayoutMode_Settings
        if settings then
            settings:Show(self._selectedKey)
        end
    end
end

---------------------------------------------------------------------------
-- SELECTION
---------------------------------------------------------------------------

--- Activate a newly registered element during an active layout mode session.
--- Creates a handle and shows it. Used when elements are added dynamically.
function QUI_LayoutMode:ActivateElement(key)
    if not self.isActive then return end
    local def = self._elements[key]
    if not def then return end
    if self._handles[key] then return end  -- already active

    -- Fire preview
    if def.onOpen then pcall(def.onOpen) end

    -- Create handle
    local handle = CreateHandle(def)
    if handle then
        self._handles[key] = handle
        SyncHandle(key)
        handle:Show()
    end
end

function QUI_LayoutMode:SelectMover(key)
    local LCG = LibStub("LibCustomGlow-1.0", true)

    -- Deselect previous
    if self._selectedKey and self._handles[self._selectedKey] then
        local prev = self._handles[self._selectedKey]
        if prev._border then
            prev._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end
        if LCG then LCG.PixelGlow_Stop(prev, "_QUILayoutSelect") end
        prev._selected = false
    end

    self._selectedKey = key

    if key and self._handles[key] then
        local handle = self._handles[key]
        handle._selected = true
        if LCG then
            LCG.PixelGlow_Start(handle, {1, 1, 1, 0.7}, 12, 0.4, nil, 2, 0, 0, false, "_QUILayoutSelect")
        end
    end

    -- Update UI (nudge handler, coordinate display)
    local ui = ns.QUI_LayoutMode_UI
    if ui and ui.OnSelectionChanged then
        ui:OnSelectionChanged(key)
    end

    -- Show/hide settings panel (toggle if clicking same key again)
    local settings = ns.QUI_LayoutMode_Settings
    if settings then
        if key then
            if key == self._prevSelectedKey and settings:IsShown() then
                settings:Reset()
            else
                settings:Show(key)
            end
        else
            settings:Reset()
        end
    end
    self._prevSelectedKey = key
end


---------------------------------------------------------------------------
-- POSITION HELPERS
---------------------------------------------------------------------------

GetFrameAnchoring = function()
    local core = Helpers.GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if type(db.frameAnchoring) ~= "table" then
        db.frameAnchoring = {}
    end
    return db.frameAnchoring
end

--- Load position for an element key.
--- Returns point, relPoint, offsetX, offsetY or nil if no saved position.
local function LoadPosition(key)
    local def = QUI_LayoutMode._elements[key]
    if not def then return nil end

    -- Custom loader takes priority
    if def.loadPosition then
        return def.loadPosition(key)
    end

    -- Default: read from frameAnchoring DB
    local fa = GetFrameAnchoring()
    if not fa then return nil end

    local entry = fa[key]
    if type(entry) ~= "table" then return nil end

    return entry.point or "CENTER",
           entry.relative or "CENTER",
           entry.offsetX or 0,
           entry.offsetY or 0
end

--- Save a pending position for a key.
--- anchorTarget, anchorPointSelf, anchorPointTarget are optional (nil = absolute/screen).
local function SavePendingPosition(key, point, relPoint, offsetX, offsetY, anchorTarget, anchorPointSelf, anchorPointTarget)
    local def = QUI_LayoutMode._elements[key]
    if def and def.usesCustomPositionPersistence then
        anchorTarget = nil
        anchorPointSelf = nil
        anchorPointTarget = nil
    end

    QUI_LayoutMode._pendingPositions[key] = {
        point = point,
        relPoint = relPoint,
        offsetX = offsetX,
        offsetY = offsetY,
        anchorTarget = anchorTarget,
        anchorPointSelf = anchorPointSelf,
        anchorPointTarget = anchorPointTarget,
    }
    QUI_LayoutMode._hasChanges = true

    -- Write anchor data to DB immediately so settings panel widgets reflect
    -- the pending state. The snapshot system handles revert on discard.
    local fa = GetFrameAnchoring()
    if fa and not (def and def.usesCustomPositionPersistence) then
        if not fa[key] then fa[key] = {} end
        if anchorTarget then
            -- Compute relative offset from anchor parent.
            -- offsetX/Y are CENTER-based from UIParent, but the anchoring system
            -- needs offsets relative to the anchor point on the parent frame.
            local ptSelf = anchorPointSelf or "CENTER"
            local ptTarget = anchorPointTarget or "CENTER"
            local relOx, relOy = offsetX, offsetY  -- fallback to absolute

            -- Use handle edges for offset computation. During layout mode, actual
            -- frames may be hidden, reparented to proxy movers, or at stale positions.
            -- Handles always reflect the correct visual position.
            local childHandle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[key]

            -- For "screen" parent, use UIParent edges (no layout handle exists).
            local pL, pR, pT, pB
            if anchorTarget == "screen" then
                pL, pB = 0, 0
                pR, pT = UIParent:GetWidth(), UIParent:GetHeight()
            else
                local parentHandle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[anchorTarget]
                if parentHandle then
                    pL, pR, pT, pB = parentHandle:GetLeft(), parentHandle:GetRight(), parentHandle:GetTop(), parentHandle:GetBottom()
                end
            end

            if childHandle and pL and pR and pT and pB then
                local cL, cR, cT, cB = childHandle:GetLeft(), childHandle:GetRight(), childHandle:GetTop(), childHandle:GetBottom()

                if cL and cR and cT and cB then
                    -- Compute anchor point positions on each handle
                    local function anchorPos(l, r, t, b, pt)
                        local x, y = (l + r) / 2, (t + b) / 2  -- CENTER
                        if pt:find("LEFT") then x = l
                        elseif pt:find("RIGHT") then x = r end
                        if pt:find("TOP") then y = t
                        elseif pt:find("BOTTOM") then y = b end
                        return x, y
                    end

                    local cx, cy = anchorPos(cL, cR, cT, cB, ptSelf)
                    local px, py = anchorPos(pL, pR, pT, pB, ptTarget)
                    relOx = math.floor(cx - px + 0.5)
                    relOy = math.floor(cy - py + 0.5)
                end
            end

            fa[key].offsetX = relOx
            fa[key].offsetY = relOy
            fa[key].parent = anchorTarget
            fa[key].point = ptSelf
            fa[key].relative = ptTarget
        else
            -- No anchor target = free position drag. The handle's offsetX/offsetY
            -- are screen-CENTER-relative (computed against UIParent CENTER).
            -- If the existing entry has non-CENTER point/relative AND a real
            -- parent frame, we recompute via handle edges so the offset is
            -- expressed relative to the existing anchor pair. Otherwise we
            -- store the raw CENTER-based drag offsets and reset point/relative
            -- to CENTER/CENTER so the offsets are interpreted in the same
            -- coordinate space they were measured in.
            --
            -- Bug fix: previously the "disabled"-parent case fell through to
            -- a raw offset write WITHOUT resetting point/relative. If the
            -- entry still carried stale TOPRIGHT/TOPRIGHT from a prior
            -- corner-conversion (e.g. buffFrame/debuffFrame), the new
            -- CENTER-based offsets were applied as TOPRIGHT-anchored offsets
            -- and the frame teleported off-screen. CommitPositions' corner
            -- conversion only re-derives offsets when both point AND relative
            -- match its expected before-state, so we MUST normalize here.
            local existingParent = fa[key].parent
            local existingPt = fa[key].point or "CENTER"
            local existingRelPt = fa[key].relative or "CENTER"

            local hasRealParent = existingParent
                and existingParent ~= "disabled"
                and existingParent ~= "screen"
            local hasNonCenterPoints = existingPt ~= "CENTER" or existingRelPt ~= "CENTER"

            if hasRealParent and hasNonCenterPoints then
                -- Compute relative offset from anchor parent
                local childHandle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[key]
                local parentHandle = QUI_LayoutMode._handles
                    and QUI_LayoutMode._handles[existingParent]

                local pL, pR, pT, pB
                if parentHandle then
                    pL, pR, pT, pB = parentHandle:GetLeft(), parentHandle:GetRight(), parentHandle:GetTop(), parentHandle:GetBottom()
                end

                if childHandle and pL and pR and pT and pB then
                    local cL, cR, cT, cB = childHandle:GetLeft(), childHandle:GetRight(), childHandle:GetTop(), childHandle:GetBottom()
                    if cL and cR and cT and cB then
                        local function anchorPos(l, r, t, b, pt)
                            local x, y = (l + r) / 2, (t + b) / 2
                            if pt:find("LEFT") then x = l
                            elseif pt:find("RIGHT") then x = r end
                            if pt:find("TOP") then y = t
                            elseif pt:find("BOTTOM") then y = b end
                            return x, y
                        end
                        local cx, cy = anchorPos(cL, cR, cT, cB, existingPt)
                        local px, py = anchorPos(pL, pR, pT, pB, existingRelPt)
                        fa[key].offsetX = math.floor(cx - px + 0.5)
                        fa[key].offsetY = math.floor(cy - py + 0.5)
                    else
                        fa[key].offsetX = offsetX
                        fa[key].offsetY = offsetY
                    end
                else
                    fa[key].offsetX = offsetX
                    fa[key].offsetY = offsetY
                end
            else
                -- Free-position fall-through: parent is nil/screen/disabled,
                -- or there's no real chain to recompute against.
                --
                -- Dynamic-size buff-borders containers (buffFrame/debuffFrame)
                -- get stored as CORNER-anchored directly, using the growth
                -- corner derived from buffBorders config. This decouples
                -- the stored position from the container's current size —
                -- apply time just SetPoints with the stored corner offsets,
                -- no size-dependent math.
                --
                -- NOTE: this is NOT applied to CDM containers (buffIcon,
                -- buffBar, cdmEssential, cdmUtility). Those are owned by
                -- the CDM module and positioned via `ncdm.<key>.pos` —
                -- their frameAnchoring entries are actively stripped by
                -- CDM_OWNED_KEYS in the migration layer. They also support
                -- a different growth model (CENTERED_HORIZONTAL / auraBar
                -- growUp / etc.) that doesn't fit the four-corner scheme.
                local isGrowAnchorKey = key == "buffFrame" or key == "debuffFrame"
                local growCorner
                if isGrowAnchorKey then
                    local profile = QUI and QUI.db and QUI.db.profile
                    local bbDB = profile and profile.buffBorders
                    if bbDB then
                        local growLeft, growUp
                        if key == "buffFrame" then
                            growLeft = bbDB.buffGrowLeft
                            growUp   = bbDB.buffGrowUp
                        else
                            growLeft = bbDB.debuffGrowLeft
                            growUp   = bbDB.debuffGrowUp
                        end
                        if growUp then
                            growCorner = growLeft and "BOTTOMRIGHT" or "BOTTOMLEFT"
                        else
                            growCorner = growLeft and "TOPRIGHT" or "TOPLEFT"
                        end
                    end
                end

                if growCorner then
                    -- Convert the drag handle's CENTER offset to a corner
                    -- offset using the live container's current size. This
                    -- one-time conversion at SAVE time means the apply path
                    -- can use the stored values directly — no recomputation.
                    local def = QUI_LayoutMode._elements[key]
                    local frame = def and def.frame and _G[def.frame]
                    local fw = frame and (frame._naturalW or (frame.GetWidth and frame:GetWidth())) or 0
                    local fh = frame and (frame._naturalH or (frame.GetHeight and frame:GetHeight())) or 0
                    if fw < 4 then fw = 32 end
                    if fh < 4 then fh = 32 end
                    local pw = UIParent:GetWidth()
                    local ph = UIParent:GetHeight()
                    local FRAC_X = { TOPLEFT = 0, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 1 }
                    local FRAC_Y = { TOPLEFT = 1, TOPRIGHT = 1, BOTTOMLEFT = 0, BOTTOMRIGHT = 0 }
                    local cornerX = (offsetX or 0) + (FRAC_X[growCorner] - 0.5) * (fw - pw)
                    local cornerY = (offsetY or 0) + (FRAC_Y[growCorner] - 0.5) * (fh - ph)
                    fa[key].point = growCorner
                    fa[key].relative = growCorner
                    fa[key].offsetX = math.floor(cornerX + 0.5)
                    fa[key].offsetY = math.floor(cornerY + 0.5)
                    fa[key].growAnchor = growCorner
                else
                    -- Normal free-position frame: CENTER-anchored, drag
                    -- offsets used verbatim. Reset point/relative to CENTER
                    -- so the offsets are interpreted in the same coordinate
                    -- space they were measured in.
                    fa[key].point = "CENTER"
                    fa[key].relative = "CENTER"
                    fa[key].offsetX = offsetX
                    fa[key].offsetY = offsetY
                end
            end
        end
    end

    -- Fire live-update message for options panel sync
    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
    end
end

--- Convert a handle's position to CENTER-based offsets relative to UIParent.
--- Works for both proxy movers and child overlays.
--- Returns offsets in UIParent local coord. For scaled child overlay parents,
--- GetCenter returns in the frame's own scaled coord, so we multiply by the
--- frame's scale to get UIParent local coord.
HandleToOffsets = function(handle)
    local cx, cy
    if handle._isChildOverlay and handle._parentFrame then
        cx, cy = handle._parentFrame:GetCenter()
        if cx and cy and handle._parentFrame.GetScale then
            local pScale = handle._parentFrame:GetScale() or 1
            if pScale > 0 and pScale ~= 1 then
                cx = cx * pScale
                cy = cy * pScale
            end
        end
    else
        cx, cy = handle:GetCenter()
    end
    if not cx or not cy then return 0, 0 end

    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    return math.floor(cx - pw / 2 + 0.5), math.floor(cy - ph / 2 + 0.5)
end

--- Position a handle from CENTER-based offsets.
--- For child overlays, repositions the parent frame.
--- offsetX/Y are in UIParent local coord. For child overlays whose parent has
--- a custom scale, divide by the scale because SetPoint offsets are interpreted
--- in the frame's own scaled coord space. No-op for scale=1 frames.
SetHandleFromOffsets = function(handle, offsetX, offsetY)
    if handle._isChildOverlay and handle._parentFrame then
        local parent = handle._parentFrame
        local ox, oy = offsetX or 0, offsetY or 0
        if parent.GetScale then
            local pScale = parent:GetScale() or 1
            if pScale > 0 and pScale ~= 1 then
                ox = ox / pScale
                oy = oy / pScale
            end
        end
        pcall(parent.ClearAllPoints, parent)
        pcall(parent.SetPoint, parent, "CENTER", UIParent, "CENTER", ox, oy)
    else
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", UIParent, "CENTER", offsetX or 0, offsetY or 0)
    end
end

--- Get the edges of a handle (for snap system).
--- For child overlays, reads from parent frame.
function QUI_LayoutMode:GetHandleEdges(handle)
    if handle._isChildOverlay and handle._parentFrame then
        local p = handle._parentFrame
        return p:GetLeft(), p:GetRight(), p:GetTop(), p:GetBottom()
    end
    return handle:GetLeft(), handle:GetRight(), handle:GetTop(), handle:GetBottom()
end

--- Snapshot all current positions.
SnapshotPositions = function()
    local snapshot = {}
    local fa = GetFrameAnchoring()

    for key, def in pairs(QUI_LayoutMode._elements) do
        if def.loadPosition then
            local pt, relPt, ox, oy = def.loadPosition(key)
            if pt then
                snapshot[key] = { point = pt, relPoint = relPt, offsetX = ox, offsetY = oy, custom = true }
            end
        elseif fa and fa[key] then
            local entry = fa[key]
            if type(entry) == "table" then
                snapshot[key] = {
                    parent = entry.parent,
                    point = entry.point,
                    relative = entry.relative,
                    offsetX = entry.offsetX,
                    offsetY = entry.offsetY,
                    sizeStable = entry.sizeStable,
                    autoWidth = entry.autoWidth,
                    widthAdjust = entry.widthAdjust,
                    autoHeight = entry.autoHeight,
                    heightAdjust = entry.heightAdjust,
                    hideWithParent = entry.hideWithParent,
                    keepInPlace = entry.keepInPlace,
                }
            end
        else
            local frame = def.getFrame and def.getFrame()
            if frame and frame.GetCenter then
                local cx, cy = frame:GetCenter()
                if cx and cy then
                    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                    snapshot[key] = {
                        point = "CENTER",
                        relPoint = "CENTER",
                        offsetX = math.floor(cx - pw / 2 + 0.5),
                        offsetY = math.floor(cy - ph / 2 + 0.5),
                        _fromFrame = true,
                    }
                end
            end
        end
    end

    QUI_LayoutMode._snapshotPositions = snapshot
end

--- Commit pending positions to DB and apply.
CommitPositions = function()
    if InCombatLockdown() then
        print("|cff60A5FAQUI:|r Cannot save positions during combat. Try again after combat ends.")
        return
    end

    local fa = GetFrameAnchoring()

    for key, pos in pairs(QUI_LayoutMode._pendingPositions) do
        local def = QUI_LayoutMode._elements[key]
        if def then
            if def.savePosition then
                def.savePosition(key, pos.point, pos.relPoint, pos.offsetX, pos.offsetY)
            elseif fa then
                if not fa[key] then
                    fa[key] = {}
                end
                -- Anchor data (parent, point, relative, and relative offsets) was
                -- already written to DB by SavePendingPosition. Only write screen
                -- offsets for non-anchored frames — anchored frames have correct
                -- relative offsets in the DB already.
                if pos.anchorTarget then
                    fa[key].parent = pos.anchorTarget
                    fa[key].point = pos.anchorPointSelf or "CENTER"
                    fa[key].relative = pos.anchorPointTarget or "CENTER"
                    -- Offsets already written by SavePendingPosition (relative to parent)
                else
                    fa[key].offsetX = pos.offsetX
                    fa[key].offsetY = pos.offsetY
                    -- Ensure point/relative are CENTER for unanchored frames.
                    -- Writing nil to AceDB fields lets explicit defaults
                    -- (e.g. TOPRIGHT/BOTTOMRIGHT) leak back through the
                    -- metatable on reload, misinterpreting CENTER-based offsets.
                    if not pos.anchorTarget then
                        -- Free-position frames are stored as CENTER offsets,
                        -- including dynamic-size containers like buffFrame /
                        -- debuffFrame. The apply path handles corner-anchor
                        -- conversion for those via the `growAnchor` field
                        -- (set by the buff borders module). Layout mode no
                        -- longer special-cases buff/debuff here.
                        fa[key].point = "CENTER"
                        fa[key].relative = "CENTER"
                    end
                end
                if fa[key].sizeStable == nil then
                    fa[key].sizeStable = true
                end
            end
        end
    end

    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll()
    end

    -- Fire live-update messages for all committed keys
    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        for key in pairs(QUI_LayoutMode._pendingPositions) do
            QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
        end
    end

    QUI_LayoutMode._pendingPositions = {}
end

--- Revert to snapshot positions and apply.
RevertPositions = function()
    if InCombatLockdown() then
        print("|cff60A5FAQUI:|r Cannot revert positions during combat.")
        return
    end

    local fa = GetFrameAnchoring()

    for key, snap in pairs(QUI_LayoutMode._snapshotPositions) do
        local def = QUI_LayoutMode._elements[key]
        if def then
            if snap.custom and def.savePosition then
                def.savePosition(key, snap.point, snap.relPoint, snap.offsetX, snap.offsetY)
            elseif snap._fromFrame then
                local frame = def.getFrame and def.getFrame()
                if frame then
                    pcall(frame.ClearAllPoints, frame)
                    pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", snap.offsetX, snap.offsetY)
                end
            elseif fa then
                if snap.parent == nil and not fa[key] then
                    -- No entry existed before
                else
                    fa[key] = {
                        parent = snap.parent,
                        point = snap.point,
                        relative = snap.relative,
                        offsetX = snap.offsetX,
                        offsetY = snap.offsetY,
                        sizeStable = snap.sizeStable,
                        autoWidth = snap.autoWidth,
                        widthAdjust = snap.widthAdjust,
                        autoHeight = snap.autoHeight,
                        heightAdjust = snap.heightAdjust,
                        hideWithParent = snap.hideWithParent,
                        keepInPlace = snap.keepInPlace,
                    }
                end
            end
        end
    end

    for key in pairs(QUI_LayoutMode._pendingPositions) do
        if not QUI_LayoutMode._snapshotPositions[key] then
            if fa and fa[key] then
                fa[key] = nil
            end
        end
    end

    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll()
    end

    -- Fire live-update messages for all reverted keys
    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        for key in pairs(QUI_LayoutMode._snapshotPositions) do
            QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
        end
    end

    -- Re-sync handles to reverted positions
    for key in pairs(QUI_LayoutMode._handles) do
        SyncHandle(key)
    end

    QUI_LayoutMode._pendingPositions = {}
end

---------------------------------------------------------------------------
-- SHARED VISUAL BUILDER (used by both proxy movers and child overlays)
---------------------------------------------------------------------------

--- Add visual elements (bg, border, label, coords, group) to a handle frame.
AddHandleVisuals = function(handle, def)
    -- Background
    local bg = handle:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, HANDLE_BG_ALPHA)
    handle._bg = bg

    -- Border (4 lines)
    local border = {}
    local function MakeBorderLine(point1, rel1, point2, rel2, isHoriz)
        local line = handle:CreateTexture(nil, "BORDER")
        line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        line:ClearAllPoints()
        line:SetPoint(point1, handle, rel1, 0, 0)
        line:SetPoint(point2, handle, rel2, 0, 0)
        if isHoriz then
            line:SetHeight(HANDLE_BORDER_SIZE)
        else
            line:SetWidth(HANDLE_BORDER_SIZE)
        end
        return line
    end

    border.top    = MakeBorderLine("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
    border.bottom = MakeBorderLine("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
    border.left   = MakeBorderLine("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
    border.right  = MakeBorderLine("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)

    border.SetColor = function(_, r, g, b, a)
        for _, line in pairs(border) do
            if type(line) == "table" and line.SetColorTexture then
                line:SetColorTexture(r, g, b, a or 1)
            end
        end
    end
    border.SetLineSize = function(_, size)
        border.top:SetHeight(size)
        border.bottom:SetHeight(size)
        border.left:SetWidth(size)
        border.right:SetWidth(size)
    end
    handle._border = border

    -- Label text
    local label = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", handle, "CENTER", 0, 6)
    label:SetText(def.label or def.key)
    label:SetTextColor(1, 1, 1, 1)
    label:SetJustifyH("CENTER")
    handle._label = label

    -- Coordinate text
    local coords = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coords:SetPoint("CENTER", handle, "CENTER", 0, -8)
    coords:SetTextColor(0.8, 0.8, 0.8, 0.8)
    coords:SetJustifyH("CENTER")
    handle._coords = coords

    -- Group label (small text at top)
    if def.group then
        local groupLabel = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        groupLabel:SetPoint("TOP", handle, "TOP", 0, -3)
        groupLabel:SetText(def.group)
        groupLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.7)
        groupLabel:SetScale(0.85)
        handle._groupLabel = groupLabel
    end

end

--- Add interaction scripts to a handle frame (click, hover, drag, escape).
AddHandleScripts = function(handle, def)
    handle:SetScript("OnEnter", function(self)
        if not self._dragging then
            self._bg:SetAlpha(HANDLE_HOVER_ALPHA)
        end
        -- Show hint tooltip
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(def.label or self._barKey, 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Right-click for settings", 0.7, 0.7, 0.7)
        -- Show unanchor hint if frame is anchored
        local fa = GetFrameAnchoring()
        local entry = fa and fa[self._barKey]
        if entry and type(entry) == "table" and entry.parent and entry.parent ~= "disabled" then
            GameTooltip:AddLine("Middle-click to unanchor", 0.9, 0.6, 0.3)
        end
        GameTooltip:Show()
    end)

    handle:SetScript("OnLeave", function(self)
        if not self._dragging then
            self._bg:SetAlpha(HANDLE_BG_ALPHA)
        end
        GameTooltip:Hide()
    end)

    handle:SetScript("OnClick", nil)
    handle:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            QUI_LayoutMode:SelectMover(self._barKey)
        elseif button == "MiddleButton" then
            local def = QUI_LayoutMode._elements[self._barKey]
            if def and def.usesCustomPositionPersistence then
                return
            end

            -- Middle-click: unanchor the frame
            local fa = GetFrameAnchoring()
            local entry = fa and fa[self._barKey]
            if entry and type(entry) == "table" and entry.parent and entry.parent ~= "disabled" then
                entry.parent = "disabled"
                entry.point = "CENTER"
                entry.relative = "CENTER"
                QUI_LayoutMode._hasChanges = true
                -- Update handle visuals (remove anchored state)
                if self._isAnchored then
                    self._isAnchored = false
                    if self._border and self._border.SetLineSize then
                        self._border:SetLineSize(HANDLE_BORDER_SIZE)
                    end
                end
                -- Flash green to confirm
                if self._border and self._border.SetColor then
                    self._border:SetColor(0.2, 1, 0.4, 1)
                    C_Timer.After(0.3, function()
                        self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                    end)
                end
                -- Refresh settings panel to show updated anchor state
                local settings = ns.QUI_LayoutMode_Settings
                if settings and settings.Refresh then settings:Refresh() end
                -- Fire anchor changed message for UI sync
                local QUI = _G.QUI
                if QUI and QUI.SendMessage then
                    QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", self._barKey)
                end
            end
        end
    end)

    handle:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        GameTooltip:Hide()

        local def = QUI_LayoutMode._elements[self._barKey]
        local usesCustomPersistence = def and def.usesCustomPositionPersistence

        -- Check if frame has an active anchor (position controlled by anchoring system).
        -- If so, block dragging unless Shift is held (Shift = re-anchor/detach intent).
        local hasActiveAnchor = false
        if not usesCustomPersistence then
            local fa = GetFrameAnchoring()
            if fa and fa[self._barKey] and type(fa[self._barKey]) == "table" then
                local parent = fa[self._barKey].parent
                hasActiveAnchor = parent and parent ~= "disabled"
            end
        end

        if hasActiveAnchor and not IsShiftKeyDown() then
            -- Flash border to indicate locked state
            if self._border and self._border.SetColor then
                self._border:SetColor(1, 0.3, 0.3, 1)
                C_Timer.After(0.3, function()
                    self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                end)
            end
            return
        end

        -- Track whether frame was anchored at drag start (for anchor preservation)
        self._wasAnchoredOnDragStart = hasActiveAnchor

        self._dragging = true
        self._snapState = nil  -- reset snap hysteresis for new drag

        -- Capture cursor-to-handle offset so snap can compute cursor-intended position
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale  -- cursor in UIParent local coord
        local hx, hy
        if self._isChildOverlay and self._parentFrame then
            hx, hy = self._parentFrame:GetCenter()
            -- parent.GetCenter returns in the frame's OWN (scaled) coord space.
            -- Convert to UIParent local coord so it matches the cursor's space.
            if hx and hy and self._parentFrame.GetScale then
                local pScale = self._parentFrame:GetScale() or 1
                if pScale > 0 and pScale ~= 1 then
                    hx = hx * pScale
                    hy = hy * pScale
                end
            end
        else
            hx, hy = self:GetCenter()
        end
        if hx and hy then
            self._dragCursorOffX = hx - cx
            self._dragCursorOffY = hy - cy
        end

        -- Track if Shift was held at drag start (intent: re-anchor/detach mode)
        self._shiftDragStart = IsShiftKeyDown()

        -- Anchor group drag: collect all DESCENDANT frames to move them
        -- together as a unit. This runs regardless of Shift state — Shift
        -- only controls the dragged frame's own anchor (detach/re-anchor),
        -- not whether children follow along.
        self._anchorGroupHandles = nil
        do
            -- Find which anchor group this frame belongs to by finding the root.
            -- When Shift is held, the user is detaching/re-anchoring THIS frame,
            -- so don't walk UP the chain — start from this frame as root.
            local myKey = self._barKey
            local anchorRoot

            if self._shiftDragStart then
                -- Shift-drag: this frame is the root (detaching from its parent)
                anchorRoot = myKey
            elseif usesCustomPersistence then
                -- Custom-persisted elements should not inherit stale generic anchors.
                anchorRoot = myKey
            else
                -- Normal drag: walk up to find the root of the anchor chain
                local visited = {}
                local current = myKey
                while current and not visited[current] do
                    visited[current] = true
                    local pending = QUI_LayoutMode._pendingPositions[current]
                    local parentKey = nil
                    if pending and pending.anchorTarget then
                        parentKey = pending.anchorTarget
                    else
                        local fa = GetFrameAnchoring()
                        if fa and fa[current] and type(fa[current]) == "table" then
                            local p = fa[current].parent
                            if p and p ~= "screen" then parentKey = p end
                        end
                    end
                    if parentKey and QUI_LayoutMode._handles[parentKey] then
                        current = parentKey
                    else
                        anchorRoot = current
                        break
                    end
                end
                anchorRoot = anchorRoot or myKey
            end

            -- Collect all frames in this anchor group (root + all descendants)
            local group = {}
            local function collectChildren(parentKey)
                -- Check pending positions
                for k, pending in pairs(QUI_LayoutMode._pendingPositions) do
                    if pending.anchorTarget == parentKey and not group[k] then
                        local h = QUI_LayoutMode._handles[k]
                        if h and h:IsShown() then
                            group[k] = h
                            collectChildren(k)
                        end
                    end
                end
                -- Check DB
                local fa = GetFrameAnchoring()
                if fa then
                    for k, entry in pairs(fa) do
                        if type(entry) == "table" and entry.parent == parentKey and not group[k] then
                            -- Skip if pending has a different anchor
                            local pending = QUI_LayoutMode._pendingPositions[k]
                            if not pending or not pending.anchorTarget or pending.anchorTarget == parentKey then
                                local h = QUI_LayoutMode._handles[k]
                                if h and h:IsShown() then
                                    group[k] = h
                                    collectChildren(k)
                                end
                            end
                        end
                    end
                end
            end

            -- Start from root
            local rootHandle = QUI_LayoutMode._handles[anchorRoot]
            if rootHandle and rootHandle:IsShown() then
                group[anchorRoot] = rootHandle
            end
            collectChildren(anchorRoot)

            -- Remove self from group (self is moved by StartMoving)
            group[myKey] = nil

            -- Store starting offsets for group members
            if next(group) then
                local startOx, startOy = HandleToOffsets(self)
                local groupData = {}
                for k, h in pairs(group) do
                    local gox, goy = HandleToOffsets(h)
                    groupData[k] = {
                        handle = h,
                        startOffX = gox,
                        startOffY = goy,
                        deltaFromDrag = { x = gox - startOx, y = goy - startOy },
                    }
                end
                self._anchorGroupHandles = groupData
                self._anchorGroupStartX = startOx
                self._anchorGroupStartY = startOy
                -- Build key set so snap system can exclude group members
                local groupKeys = {}
                for gk in pairs(groupData) do groupKeys[gk] = true end
                self._anchorGroupKeys = groupKeys
            end
        end

        self._bg:SetAlpha(HANDLE_DRAG_ALPHA)

        -- Hide settings panel during drag
        local settings = ns.QUI_LayoutMode_Settings
        if settings and settings:IsShown() then
            settings:Hide()
            self._settingsWasShown = true
        end

        -- Drive all positioning from cursor in OnUpdate (no StartMoving).
        -- This avoids jitter from StartMoving fighting with snap repositioning.
        self:SetScript("OnUpdate", function(frame)
            -- Compute handle position from cursor + captured offset
            local curX, curY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            if not curX or not curY or not scale or scale == 0 then return end
            curX, curY = curX / scale, curY / scale

            local intendedCX = curX + (frame._dragCursorOffX or 0)
            local intendedCY = curY + (frame._dragCursorOffY or 0)
            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
            local ox = math.floor(intendedCX - pw / 2 + 0.5)
            local oy = math.floor(intendedCY - ph / 2 + 0.5)

            -- Position the handle itself
            SetHandleFromOffsets(frame, ox, oy)

            -- Snap + anchor system — run BEFORE positioning children and actual
            -- frames so that children track the post-snap parent position.
            -- (Runs even with snap off for Shift+anchor detection.)
            local ui = ns.QUI_LayoutMode_UI
            if ui and ui.ApplySnap then
                ui:ApplySnap(frame)
            end

            -- Re-read parent position after snap (snap may have adjusted it)
            local postSnapOx, postSnapOy = HandleToOffsets(frame)

            -- Position the actual frame (proxy movers only)
            if not frame._isChildOverlay then
                local key = frame._barKey
                local def2 = QUI_LayoutMode._elements[key]
                if def2 then
                    local targetFrame = def2.getFrame and def2.getFrame()
                    if targetFrame then
                        pcall(targetFrame.ClearAllPoints, targetFrame)
                        -- Boss frames: keep boss1 at TOPLEFT of handle.
                        -- Boss1 is a child of the handle so it moves with it;
                        -- setting CENTER/UIParent would fight the anchor point.
                        if key == "bossFrames" then
                            pcall(targetFrame.SetPoint, targetFrame, "TOPLEFT", frame, "TOPLEFT", 0, 0)
                            pcall(targetFrame.SetPoint, targetFrame, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                        else
                            local frameOx, frameOy = postSnapOx, postSnapOy
                            if def2.getCenterOffset then
                                local cdx, cdy = def2.getCenterOffset(frame:GetSize())
                                frameOx = frameOx - cdx
                                frameOy = frameOy - cdy
                            end
                            pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", frameOx, frameOy)
                        end
                    end
                end
            end

            -- Move anchor group members along with the dragging frame
            if frame._anchorGroupHandles then
                for k, data in pairs(frame._anchorGroupHandles) do
                    local newOx = postSnapOx + data.deltaFromDrag.x
                    local newOy = postSnapOy + data.deltaFromDrag.y
                    SetHandleFromOffsets(data.handle, newOx, newOy)
                    -- Also reposition the actual frame
                    local def2 = QUI_LayoutMode._elements[k]
                    if def2 then
                        local targetFrame = def2.getFrame and def2.getFrame()
                        if targetFrame then
                            local frameOx, frameOy = newOx, newOy
                            if def2.getCenterOffset then
                                local cdx, cdy = def2.getCenterOffset(data.handle:GetSize())
                                frameOx = frameOx - cdx
                                frameOy = frameOy - cdy
                            end
                            pcall(targetFrame.ClearAllPoints, targetFrame)
                            pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", frameOx, frameOy)
                        end
                    end
                    -- Update coordinate display
                    if data.handle._coords then
                        data.handle._coords:SetText(string.format("X: %d  Y: %d", newOx, newOy))
                    end
                end
            end

            -- Update coordinate display
            frame._coords:SetText(string.format("X: %d  Y: %d", postSnapOx, postSnapOy))
        end)
    end)

    handle:SetScript("OnDragStop", function(self)
        self._dragging = false
        self._bg:SetAlpha(self:IsMouseOver() and HANDLE_HOVER_ALPHA or HANDLE_BG_ALPHA)

        -- Remove drag OnUpdate
        self:SetScript("OnUpdate", nil)

        local def = QUI_LayoutMode._elements[self._barKey]

        -- Store pending position (with anchor data if Shift+snap was active)
        local ox, oy = HandleToOffsets(self)
        local anchorKey = self._snapAnchorKey
        local anchorPtSelf = self._snapAnchorPointSelf
        local anchorPtTarget = self._snapAnchorPointTarget

        if def and def.usesCustomPositionPersistence then
            anchorKey = nil
            anchorPtSelf = nil
            anchorPtTarget = nil
        end

        -- If frame was anchored and dragged without Shift, preserve existing anchor
        -- Use _shiftDragStart (captured at drag start) — if user started with Shift,
        -- they intend to re-anchor or detach, so don't preserve the old anchor.
        if not (def and def.usesCustomPositionPersistence)
           and not anchorKey and self._wasAnchoredOnDragStart and not self._shiftDragStart then
            local pending = QUI_LayoutMode._pendingPositions[self._barKey]
            if pending and pending.anchorTarget then
                anchorKey = pending.anchorTarget
                anchorPtSelf = pending.anchorPointSelf
                anchorPtTarget = pending.anchorPointTarget
            else
                local fa = GetFrameAnchoring()
                if fa and fa[self._barKey] and type(fa[self._barKey]) == "table" then
                    local entry = fa[self._barKey]
                    if entry.parent and entry.parent ~= "disabled" then
                        anchorKey = entry.parent
                        anchorPtSelf = entry.point
                        anchorPtTarget = entry.relative
                    end
                end
            end
        end

        SavePendingPosition(self._barKey, "CENTER", "CENTER", ox, oy, anchorKey, anchorPtSelf, anchorPtTarget)

        -- Explicit detach: Shift+drag with no new anchor target — set to disabled
        -- so the frame is freely positionable via layout mode dragging
        if not (def and def.usesCustomPositionPersistence)
           and not anchorKey and self._shiftDragStart and self._wasAnchoredOnDragStart then
            local fa = GetFrameAnchoring()
            if fa and fa[self._barKey] then
                fa[self._barKey].parent = "disabled"
                fa[self._barKey].point = "CENTER"
                fa[self._barKey].relative = "CENTER"
            end
        end

        -- Save final positions for anchor group members that moved with us
        if self._anchorGroupHandles then
            for k, data in pairs(self._anchorGroupHandles) do
                local gox, goy = HandleToOffsets(data.handle)
                -- Preserve existing anchor info for group members
                local gAnchorKey, gAnchorPtSelf, gAnchorPtTarget
                local gPending = QUI_LayoutMode._pendingPositions[k]
                if gPending and gPending.anchorTarget then
                    gAnchorKey = gPending.anchorTarget
                    gAnchorPtSelf = gPending.anchorPointSelf
                    gAnchorPtTarget = gPending.anchorPointTarget
                else
                    local fa = GetFrameAnchoring()
                    if fa and fa[k] and type(fa[k]) == "table" then
                        local entry = fa[k]
                        if entry.parent and entry.parent ~= "screen" then
                            gAnchorKey = entry.parent
                            gAnchorPtSelf = entry.point
                            gAnchorPtTarget = entry.relative
                        end
                    end
                end
                SavePendingPosition(k, "CENTER", "CENTER", gox, goy, gAnchorKey, gAnchorPtSelf, gAnchorPtTarget)
            end
            self._anchorGroupHandles = nil
            self._anchorGroupKeys = nil
        end

        -- Final live-reposition (proxy movers only — child overlays already positioned)
        if not self._isChildOverlay then
            local key = self._barKey
            local def2 = QUI_LayoutMode._elements[key]
            if def2 then
                local targetFrame = def2.getFrame and def2.getFrame()
                if targetFrame then
                    local frameOx, frameOy = ox, oy
                    if def2.getCenterOffset then
                        local cdx, cdy = def2.getCenterOffset(self:GetSize())
                        frameOx = frameOx - cdx
                        frameOy = frameOy - cdy
                    end
                    pcall(targetFrame.ClearAllPoints, targetFrame)
                    pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", frameOx, frameOy)
                end
                if def2.onLiveMove then
                    pcall(def2.onLiveMove, key)
                end
            end
        else
            local def2 = QUI_LayoutMode._elements[self._barKey]
            if def2 and def2.onLiveMove then
                pcall(def2.onLiveMove, self._barKey)
            end
        end

        -- Update coordinate display and anchored state after drag.
        -- For anchored frames, show the anchor-relative offsets from DB
        -- (SavePendingPosition has already written them).
        if anchorKey then
            self._isAnchored = true
            local fa = GetFrameAnchoring()
            local entry = fa and fa[self._barKey]
            local displayOx = entry and entry.offsetX or ox
            local displayOy = entry and entry.offsetY or oy
            self._coords:SetText(string.format("X: %d  Y: %d", displayOx, displayOy))
            -- Thicker border for anchored state
            if self._border and self._border.SetLineSize then
                self._border:SetLineSize(HANDLE_BORDER_SIZE_ANCHORED)
            end
        else
            self._isAnchored = false
            self._coords:SetText(string.format("X: %d  Y: %d", ox, oy))
            -- Normal border for non-anchored state
            if self._border and self._border.SetLineSize then
                self._border:SetLineSize(HANDLE_BORDER_SIZE)
            end
        end

        -- Restore border color on dragging handle (may still be gold from anchor preview)
        if self._border and self._border.SetColor then
            self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end

        -- Restore border on previously highlighted anchor target
        if self._anchorHighlightTarget then
            local prevTarget = QUI_LayoutMode._handles[self._anchorHighlightTarget]
            if prevTarget and prevTarget._border then
                if prevTarget._border.SetLineSize then
                    prevTarget._border:SetLineSize(prevTarget._isAnchored and HANDLE_BORDER_SIZE_ANCHORED or HANDLE_BORDER_SIZE)
                end
                if prevTarget._border.SetColor then
                    prevTarget._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                end
            end
            self._anchorHighlightTarget = nil
        end

        -- Clear anchor line
        local ui = ns.QUI_LayoutMode_UI
        if ui and ui._anchorLine then
            ui._anchorLine:Hide()
        end

        -- Clear snap guides
        if ui and ui.ClearSnapGuides then
            ui:ClearSnapGuides()
        end

        -- Refresh settings panel after drag to pick up position/anchor changes.
        -- Only re-show if it was visible before the drag started (don't open it fresh).
        if self._settingsWasShown then
            self._settingsWasShown = nil
            local settingsPanel = ns.QUI_LayoutMode_Settings
            if settingsPanel then
                settingsPanel._currentKey = nil
                settingsPanel:Show(self._barKey)
            end
        end
    end)

    -- Disable keyboard on handles — nudge frame handles all keyboard input
    handle:EnableKeyboard(false)
end

---------------------------------------------------------------------------
-- HANDLE FACTORIES
---------------------------------------------------------------------------

--- Create a child overlay parented to the target frame.
--- Falls back to proxy mover if the frame doesn't exist or is hidden.
CreateChildOverlay = function(def)
    local targetFrame = def.getFrame and def.getFrame()

    if not targetFrame or not targetFrame:IsShown() then
        -- Fallback to proxy if frame not available or hidden
        return CreateProxyMover(def)
    end

    local name = "QUI_Overlay_" .. def.key
    -- Parent to targetFrame; strata is set to FULLSCREEN_DIALOG which
    -- renders above the target's children at their inherited strata.
    local overlay = CreateFrame("Button", name, targetFrame)
    overlay:SetFrameStrata(HANDLE_STRATA)
    overlay:SetFrameLevel(100)

    -- If setupOverlay is provided, let it handle sizing/anchoring
    -- (e.g., XP tracker overlay spans bar + details pane)
    if def.setupOverlay then
        def.setupOverlay(overlay, targetFrame)
    else
        overlay:SetAllPoints(targetFrame)
    end

    overlay:RegisterForDrag("LeftButton")
    overlay:EnableMouse(true)
    overlay:Hide()

    -- State
    overlay._barKey = def.key
    overlay._selected = false
    overlay._dragging = false
    overlay._isChildOverlay = true
    overlay._parentFrame = targetFrame

    -- Make parent movable (save old state for restore)
    local wasMovable = targetFrame:IsMovable()
    QUI_LayoutMode._savedMovableState[def.key] = wasMovable
    targetFrame:SetMovable(true)
    targetFrame:SetClampedToScreen(true)

    -- Add visuals and scripts
    AddHandleVisuals(overlay, def)
    AddHandleScripts(overlay, def)

    return overlay
end

--- Create a separate proxy mover (original approach for Blizzard frames).
CreateProxyMover = function(def)
    local name = "QUI_Mover_" .. def.key
    local mover = CreateFrame("Button", name, UIParent)
    mover:SetFrameStrata(HANDLE_STRATA)
    mover:SetFrameLevel(100)
    mover:SetSize(HANDLE_MIN_SIZE, HANDLE_MIN_SIZE)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true)
    mover:Hide()

    -- State
    mover._barKey = def.key
    mover._selected = false
    mover._dragging = false
    mover._isChildOverlay = false

    -- Add visuals and scripts
    AddHandleVisuals(mover, def)
    AddHandleScripts(mover, def)

    return mover
end

--- Dispatcher: choose child overlay or proxy mover based on element definition.
--- Elements with getSize use proxy movers, unless setupOverlay is also set
--- (which means the child overlay can handle the extended size natively).
--- Frames anchored to partyFrames/raidFrames use proxy movers because those
--- parents use test containers in layout mode (different frame than actual header).
local TEST_CONTAINER_PARENTS = { partyFrames = true, raidFrames = true }

CreateHandle = function(def)
    if def.isOwned and (not def.getSize or def.setupOverlay) then
        -- Only force proxy mover for elements anchored to parents that use
        -- test containers (party/raid). Other anchored elements (e.g. power
        -- bars anchored to cdmEssential) keep child overlays for accurate sizing.
        local fa = GetFrameAnchoring()
        local entry = fa and fa[def.key]
        if entry and type(entry) == "table" and entry.parent
            and TEST_CONTAINER_PARENTS[entry.parent] then
            return CreateProxyMover(def)
        end
        return CreateChildOverlay(def)
    else
        return CreateProxyMover(def)
    end
end

---------------------------------------------------------------------------
-- SYNC HANDLE
---------------------------------------------------------------------------

--- Sync a handle to match its element's current position and size.
SyncHandle = function(key)
    local handle = QUI_LayoutMode._handles[key]
    local def = QUI_LayoutMode._elements[key]
    if not handle or not def then return end

    if handle._isChildOverlay then
        -- Check if the parent frame changed (e.g., test container was rebuilt
        -- by a settings change). Re-target the existing overlay to the new
        -- frame instead of destroying and recreating it — avoids churn
        -- during rapid changes (slider drags).
        local currentFrame = def.getFrame and def.getFrame()
        if currentFrame and currentFrame ~= handle._parentFrame then
            handle._parentFrame = currentFrame
            -- Reparent and re-anchor to new frame
            handle:SetParent(currentFrame)
            handle:SetFrameStrata(HANDLE_STRATA)
            handle:SetFrameLevel(100)
            if def.setupOverlay then
                def.setupOverlay(handle, currentFrame)
            else
                handle:ClearAllPoints()
                handle:SetAllPoints(currentFrame)
            end
            -- Update movable state on new frame
            local wasMovable = currentFrame:IsMovable()
            QUI_LayoutMode._savedMovableState[key] = wasMovable
            currentFrame:SetMovable(true)
            currentFrame:SetClampedToScreen(true)
        end

        -- Re-assert strata/level so the overlay stays above the parent
        -- frame after settings-triggered refreshes that may reset levels.
        handle:SetFrameStrata(HANDLE_STRATA)
        handle:SetFrameLevel(100)

        -- Child overlay: position is automatic via SetAllPoints.
        -- Re-sync via setupOverlay if provided (dynamic sizing)
        if def.setupOverlay then
            def.setupOverlay(handle, handle._parentFrame)
        end
        -- Re-anchor parent frame if there's a pending position.
        local pending = QUI_LayoutMode._pendingPositions[key]
        if pending then
            SetHandleFromOffsets(handle, pending.offsetX, pending.offsetY)
        end

        -- NOTE: Frames anchored to other elements use proxy movers (not
        -- child overlays), so parent-handle-based repositioning is handled
        -- in the proxy mover path below.
    else
        -- Proxy mover: full sync (size + position from frame)
        local w, h
        if def.getSize then
            w, h = def.getSize()
        end

        if not w or not h then
            local frame = def.getFrame and def.getFrame()
            if frame and frame.GetSize then
                local ok, fw, fh = pcall(frame.GetSize, frame)
                if ok and fw and fh then
                    w = Helpers.SafeToNumber(fw, HANDLE_MIN_SIZE)
                    h = Helpers.SafeToNumber(fh, HANDLE_MIN_SIZE)
                end
            end
        end

        w = (w and w >= TINY_THRESHOLD) and w or math.max(w or HANDLE_MIN_SIZE, HANDLE_MIN_SIZE)
        h = (h and h >= TINY_THRESHOLD) and h or math.max(h or HANDLE_MIN_SIZE, HANDLE_MIN_SIZE)
        handle:SetSize(w, h)

        -- Center offset: when getSize makes the mover larger than the frame,
        -- shift the mover center so the frame aligns correctly within it.
        local cdx, cdy = 0, 0
        if def.getCenterOffset then
            cdx, cdy = def.getCenterOffset(w, h)
        end

        -- Position: check pending first, then anchored-to-parent-handle, then saved, then frame
        local pending = QUI_LayoutMode._pendingPositions[key]
        if pending then
            handle:ClearAllPoints()
            handle:SetPoint("CENTER", UIParent, "CENTER", pending.offsetX, pending.offsetY)
        else
            -- For frames anchored to another frame (not screen), position the
            -- handle relative to the PARENT HANDLE using the DB offsets. During
            -- layout mode, actual frames may be hidden or at stale positions.
            local fa = GetFrameAnchoring()
            local entry = fa and fa[key]
            local anchorParent = entry and entry.parent
            local parentHandle = anchorParent and anchorParent ~= "screen" and anchorParent ~= "disabled"
                and QUI_LayoutMode._handles and QUI_LayoutMode._handles[anchorParent]

            if parentHandle and entry then
                local ptSelf = entry.point or "CENTER"
                local ptTarget = entry.relative or "CENTER"
                local dbOx = entry.offsetX or 0
                local dbOy = entry.offsetY or 0

                local pL, pR, pT, pB = parentHandle:GetLeft(), parentHandle:GetRight(), parentHandle:GetTop(), parentHandle:GetBottom()
                if pL and pR and pT and pB then
                    -- Compute target anchor point on parent handle
                    local function anchorPos(l, r, t, b, pt)
                        local x, y = (l + r) / 2, (t + b) / 2
                        if pt:find("LEFT") then x = l
                        elseif pt:find("RIGHT") then x = r end
                        if pt:find("TOP") then y = t
                        elseif pt:find("BOTTOM") then y = b end
                        return x, y
                    end
                    local px, py = anchorPos(pL, pR, pT, pB, ptTarget)

                    -- Position child handle so its anchor point lands at parent anchor + offset
                    -- For simplicity, use CENTER positioning with adjustment for the anchor point
                    local cW, cH = handle:GetSize()
                    local selfOffX, selfOffY = 0, 0
                    if ptSelf:find("LEFT") then selfOffX = cW / 2
                    elseif ptSelf:find("RIGHT") then selfOffX = -cW / 2 end
                    if ptSelf:find("TOP") then selfOffY = -cH / 2
                    elseif ptSelf:find("BOTTOM") then selfOffY = cH / 2 end

                    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                    local centerX = math.floor(px + dbOx + selfOffX - pw / 2 + 0.5)
                    local centerY = math.floor(py + dbOy + selfOffY - ph / 2 + 0.5)

                    handle:ClearAllPoints()
                    -- Don't add getCenterOffset (cdx/cdy) for anchored handles.
                    -- selfOffX/selfOffY already positions the handle so its anchor
                    -- edge aligns with the parent's anchor edge. getCenterOffset
                    -- would shift boss1 away from the intended anchor point.
                    handle:SetPoint("CENTER", UIParent, "CENTER", centerX, centerY)
                else
                    -- Parent handle not positioned yet, fall back to DB offsets
                    local pt, relPt, ox, oy = LoadPosition(key)
                    if pt then
                        handle:ClearAllPoints()
                        handle:SetPoint("CENTER", UIParent, "CENTER", (ox or 0), (oy or 0))
                    end
                end
            else
                local pt, relPt, ox, oy = LoadPosition(key)
                if pt then
                    if pt == "CENTER" and relPt == "CENTER" then
                        handle:ClearAllPoints()
                        handle:SetPoint("CENTER", UIParent, "CENTER", ox + cdx, oy + cdy)
                    else
                        local frame = def.getFrame and def.getFrame()
                        if frame and frame.GetCenter then
                            local cx, cy = frame:GetCenter()
                            if cx and cy then
                                local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                                handle:ClearAllPoints()
                                handle:SetPoint("CENTER", UIParent, "CENTER",
                                    math.floor(cx - pw / 2 + cdx + 0.5), math.floor(cy - ph / 2 + cdy + 0.5))
                            else
                                handle:ClearAllPoints()
                                handle:SetPoint("CENTER", UIParent, "CENTER", ox + cdx, oy + cdy)
                            end
                        else
                            handle:ClearAllPoints()
                            handle:SetPoint("CENTER", UIParent, "CENTER", ox + cdx, oy + cdy)
                        end
                    end
                else
                    local frame = def.getFrame and def.getFrame()
                    if frame and frame.GetCenter then
                        local cx, cy = frame:GetCenter()
                        if cx and cy then
                            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                            handle:ClearAllPoints()
                            handle:SetPoint("CENTER", UIParent, "CENTER",
                                math.floor(cx - pw / 2 + cdx + 0.5), math.floor(cy - ph / 2 + cdy + 0.5))
                        end
                    end
                end
            end
        end
    end

    -- Boss frames: re-anchor boss1 to the top of the handle after any sync.
    -- ApplyFrameAnchor may have repositioned boss1 relative to a different
    -- parent, breaking the TOP anchoring set during deferred reparenting.
    if key == "bossFrames" and not handle._isChildOverlay then
        local frame = def.getFrame and def.getFrame()
        if frame and handle._savedTargetParent then
            pcall(frame.ClearAllPoints, frame)
            pcall(frame.SetPoint, frame, "TOPLEFT", handle, "TOPLEFT", 0, 0)
            pcall(frame.SetPoint, frame, "TOPRIGHT", handle, "TOPRIGHT", 0, 0)
        end
    end

    -- Check for existing anchor relationship (from DB or pending)
    local existingAnchorKey = nil
    if not (def and def.usesCustomPositionPersistence) then
        local pending = QUI_LayoutMode._pendingPositions[key]
        if pending and pending.anchorTarget then
            existingAnchorKey = pending.anchorTarget
        else
            local fa = GetFrameAnchoring()
            if fa and fa[key] and type(fa[key]) == "table" then
                local parent = fa[key].parent
                if parent and parent ~= "disabled" then
                    existingAnchorKey = parent
                end
            end
        end
    end

    -- Update coordinate text — show DB offsets for anchored frames, screen offsets otherwise.
    -- Always read from DB (not pending) because pending stores CENTER-based offsets
    -- while the DB has the correct anchor-relative offsets.
    local ox, oy
    if existingAnchorKey then
        local fa = GetFrameAnchoring()
        local entry = fa and fa[key]
        ox = entry and entry.offsetX or 0
        oy = entry and entry.offsetY or 0
        handle._isAnchored = true
        handle._coords:SetText(string.format("X: %d  Y: %d", ox, oy))
        -- Thicker border for anchored handles
        if handle._border and handle._border.SetLineSize then
            handle._border:SetLineSize(HANDLE_BORDER_SIZE_ANCHORED)
        end
    else
        ox, oy = HandleToOffsets(handle)
        handle._isAnchored = false
        handle._coords:SetText(string.format("X: %d  Y: %d", ox, oy))
        -- Normal border for non-anchored handles
        if handle._border and handle._border.SetLineSize then
            handle._border:SetLineSize(HANDLE_BORDER_SIZE)
        end
    end

    -- Handle label/group visibility based on size
    local w, h
    if handle._isChildOverlay and handle._parentFrame then
        local ok, fw, fh = pcall(handle._parentFrame.GetSize, handle._parentFrame)
        if ok then w, h = fw, fh end
    else
        w, h = handle:GetSize()
    end
    w = w or HANDLE_MIN_SIZE
    h = h or HANDLE_MIN_SIZE

    if w < 60 or h < 30 then
        if handle._groupLabel then handle._groupLabel:Hide() end
        handle._label:SetPoint("CENTER", handle, "CENTER", 0, 0)
        handle._coords:Hide()
    else
        if handle._groupLabel then handle._groupLabel:Show() end
        handle._label:SetPoint("CENTER", handle, "CENTER", 0, 6)
        handle._coords:Show()
    end
end

---------------------------------------------------------------------------
-- PUBLIC SYNC — re-sync a handle's size/position from its target frame.
-- Called by external modules after resizing managed frames (e.g. buff layout).
---------------------------------------------------------------------------
function QUI_LayoutMode:SyncElement(key)
    if not self.isActive then return end
    if not self._handles or not self._handles[key] then return end
    SyncHandle(key)
end

---------------------------------------------------------------------------
-- NUDGE (called by layoutmode_ui.lua arrow key handler)
---------------------------------------------------------------------------

function QUI_LayoutMode:NudgeMover(key, dx, dy)
    if InCombatLockdown() then return false end

    local handle = self._handles[key]
    if not handle then return false end
    local def = self._elements[key]

    local ox, oy = HandleToOffsets(handle)
    ox = ox + dx
    oy = oy + dy

    if handle._isChildOverlay then
        -- Child overlay: just reposition parent (overlay follows)
        SetHandleFromOffsets(handle, ox, oy)
    else
        -- Proxy: reposition mover + actual frame
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", UIParent, "CENTER", ox, oy)

        if def then
            local frame = def.getFrame and def.getFrame()
            if frame then
                pcall(frame.ClearAllPoints, frame)
                -- Boss frames: keep boss1 anchored to TOP of handle
                if key == "bossFrames" then
                    pcall(frame.SetPoint, frame, "TOPLEFT", handle, "TOPLEFT", 0, 0)
                    pcall(frame.SetPoint, frame, "TOPRIGHT", handle, "TOPRIGHT", 0, 0)
                else
                    pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", ox, oy)
                end
            end
        end
    end

    -- Preserve any existing anchor metadata when nudging. Without this,
    -- SaveAndClose() can later treat the nudge as a plain CENTER/CENTER move
    -- and overwrite the anchor-relative offsets we just wrote to the DB.
    local anchorKey, anchorPtSelf, anchorPtTarget
    if not (def and def.usesCustomPositionPersistence) then
        local pending = self._pendingPositions[key]
        if pending and pending.anchorTarget then
            anchorKey = pending.anchorTarget
            anchorPtSelf = pending.anchorPointSelf
            anchorPtTarget = pending.anchorPointTarget
        else
            local fa = GetFrameAnchoring()
            local entry = fa and fa[key]
            if type(entry) == "table" and entry.parent and entry.parent ~= "disabled" then
                anchorKey = entry.parent
                anchorPtSelf = entry.point or "CENTER"
                anchorPtTarget = entry.relative or "CENTER"
            end
        end
    end

    -- Store pending
    SavePendingPosition(key, "CENTER", "CENTER", ox, oy, anchorKey, anchorPtSelf, anchorPtTarget)

    -- Update coordinate text — show anchor-relative offsets for anchored frames
    if handle._isAnchored then
        local fa = GetFrameAnchoring()
        local entry = fa and fa[key]
        handle._coords:SetText(string.format("X: %d  Y: %d", entry and entry.offsetX or ox, entry and entry.offsetY or oy))
    else
        handle._coords:SetText(string.format("X: %d  Y: %d", ox, oy))
    end

    return true
end

---------------------------------------------------------------------------
-- SAVE/DISCARD POPUP
---------------------------------------------------------------------------

ShowSaveDiscardPopup = function()
    local ui = ns.QUI_LayoutMode_UI
    if ui and ui.ShowSaveDiscardPopup then
        ui:ShowSaveDiscardPopup()
    else
        QUI_LayoutMode:SaveAndClose()
    end
end

-- Escape key handling is done by the nudge frame in layoutmode_ui.lua

---------------------------------------------------------------------------
-- PROFILE / SPEC CHANGE HANDLING
---------------------------------------------------------------------------
local function OnProfileChanged()
    if QUI_LayoutMode.isActive then
        QUI_LayoutMode._hasChanges = false
        QUI_LayoutMode._pendingPositions = {}
        QUI_LayoutMode:Close(true)
        print("|cff60A5FAQUI:|r Profile changed. Layout Mode closed — reopen to use new profile positions.")
    end
end

C_Timer.After(1, function()
    local core = Helpers.GetCore()
    if core and core.db then
        core.db.RegisterCallback(QUI_LayoutMode, "OnProfileChanged", OnProfileChanged)
        core.db.RegisterCallback(QUI_LayoutMode, "OnProfileCopied", OnProfileChanged)
        core.db.RegisterCallback(QUI_LayoutMode, "OnProfileReset", OnProfileChanged)
    end
end)

---------------------------------------------------------------------------
-- BACKWARD COMPATIBILITY
---------------------------------------------------------------------------
local function SetupBackwardCompat()
    local core = Helpers.GetCore()
    if not core then return end

    core._editModeEnterCallbacks = core._editModeEnterCallbacks or {}
    core._editModeExitCallbacks = core._editModeExitCallbacks or {}

    function core:RegisterLayoutModeEnter(callback)
        QUI_LayoutMode:RegisterEnterCallback(callback)
    end

    function core:RegisterLayoutModeExit(callback)
        QUI_LayoutMode:RegisterExitCallback(callback)
    end

    local origRegEnter = core.RegisterEditModeEnter
    function core:RegisterEditModeEnter(callback)
        QUI_LayoutMode:RegisterEnterCallback(callback)
    end

    local origRegExit = core.RegisterEditModeExit
    function core:RegisterEditModeExit(callback)
        QUI_LayoutMode:RegisterExitCallback(callback)
    end

    for _, cb in ipairs(core._editModeEnterCallbacks) do
        QUI_LayoutMode:RegisterEnterCallback(cb)
    end
    for _, cb in ipairs(core._editModeExitCallbacks) do
        QUI_LayoutMode:RegisterExitCallback(cb)
    end
end

C_Timer.After(0, function()
    SetupBackwardCompat()
end)

---------------------------------------------------------------------------
-- DISPLAY FRAME ELEMENT REGISTRATION
-- Blizzard frames — use proxy movers (isOwned = false / default)
---------------------------------------------------------------------------
do
    local function RegisterDisplayElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local DISPLAY_ELEMENTS = {
            { key = "objectiveTracker", label = "Objective Tracker", frame = "ObjectiveTrackerFrame", order = 2 },
            { key = "topCenterWidgets", label = "Top Center Widgets", frame = "UIWidgetTopCenterContainerFrame", order = 14, minWidth = 160, minHeight = 24 },
            { key = "belowMinimapWidgets", label = "Below Minimap Widgets", frame = "UIWidgetBelowMinimapContainerFrame", order = 15, minWidth = 180, minHeight = 24 },
            { key = "extraActionButton", label = "Extra Ability",   frame = "ExtraActionBarFrame", holder = "QUI_extraActionButtonHolder", order = 5 },
            { key = "zoneAbility",     label = "Zone Ability",      frame = "ZoneAbilityFrame",    holder = "QUI_zoneAbilityHolder",      order = 6 },
            { key = "bonusRollFrame",  label = "Bonus Roll",        frame = "BonusRollFrame",      order = 16, minWidth = 200, minHeight = 80 },
        }

        for _, info in ipairs(DISPLAY_ELEMENTS) do
            local regDef = {
                key = info.key,
                label = info.label,
                group = "Display",
                order = info.order,
                setGameplayHidden = function(hide)
                    local f = (info.holder and _G[info.holder]) or _G[info.frame]
                    if not f then return end
                    if hide then
                        f:SetAlpha(0)
                        pcall(f.EnableMouse, f, false)
                    else
                        f:SetAlpha(1)
                        pcall(f.EnableMouse, f, true)
                    end
                end,
                getFrame = function()
                    return (info.holder and _G[info.holder]) or _G[info.frame]
                end,
            }
            -- Widget containers may have zero size when not in relevant content
            -- (M+, BG, etc.). Provide a minimum so the mover fits its label.
            if info.minWidth then
                regDef.getSize = function()
                    local minW = info.minWidth
                    local minH = info.minHeight or 24
                    local f = _G[info.frame]
                    if f then
                        local fw = Helpers.SafeToNumber(f:GetWidth(), 0)
                        local fh = Helpers.SafeToNumber(f:GetHeight(), 0)
                        if fw > minW then minW = fw end
                        if fh > minH then minH = fh end
                    end
                    return minW, minH
                end
            end
            um:RegisterElement(regDef)
        end

        -- BonusRollFrame: reapply our saved anchor when Blizzard shows the
        -- prompt. Blizzard re-SetPoints the frame on each bonus roll start.
        if _G.BonusRollFrame and not _G.BonusRollFrame._QUI_AnchorHooked then
            _G.BonusRollFrame._QUI_AnchorHooked = true
            hooksecurefunc(_G.BonusRollFrame, "Show", function()
                C_Timer.After(0, function()
                    if not InCombatLockdown() and _G.QUI_ApplyFrameAnchor then
                        _G.QUI_ApplyFrameAnchor("bonusRollFrame")
                    end
                end)
            end)
        end

        -- Chat frame — child overlay so the handle matches the Blizzard
        -- frame exactly (SetAllPoints) and drag moves ChatFrame1 directly.
        local function ChatDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.chat
        end

        um:RegisterElement({
            key = "chatFrame1",
            label = "Chat Frame",
            group = "Display",
            order = 7,
            isOwned = true,
            isEnabled = function()
                local db = ChatDB()
                return db and db.enabled ~= false
            end,
            setEnabled = function(val)
                local db = ChatDB()
                if db then db.enabled = val end
                if _G.QUI_RefreshChat then _G.QUI_RefreshChat() end
            end,
            setGameplayHidden = function(hide)
                local f = _G.ChatFrame1
                if not f then return end
                if hide then
                    f:SetAlpha(0)
                    f:EnableMouse(false)
                else
                    f:SetAlpha(1)
                    f:EnableMouse(true)
                end
            end,
            getFrame = function()
                return _G.ChatFrame1
            end,
            -- Extend overlay to cover tab bar above + glass backdrop + editbox below
            setupOverlay = function(overlay, frame)
                overlay:ClearAllPoints()
                overlay:SetPoint("TOPLEFT", frame, "TOPLEFT", -8, 32)
                overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 8, -32)

                -- Corner resize grip — drag to resize ChatFrame1 directly.
                if not overlay._chatResizeGrip then
                    local grip = CreateFrame("Button", nil, overlay)
                    grip:SetSize(20, 20)
                    grip:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -2, -2)
                    grip:SetFrameLevel(overlay:GetFrameLevel() + 10)
                    grip:EnableMouse(true)

                    -- Accent-colored corner indicator (two mint bars forming an L).
                    local barH = grip:CreateTexture(nil, "OVERLAY")
                    barH:SetColorTexture(0.204, 0.827, 0.600, 0.9)
                    barH:SetPoint("TOPRIGHT", 0, 0)
                    barH:SetSize(18, 3)

                    local barV = grip:CreateTexture(nil, "OVERLAY")
                    barV:SetColorTexture(0.204, 0.827, 0.600, 0.9)
                    barV:SetPoint("TOPRIGHT", 0, 0)
                    barV:SetSize(3, 18)

                    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetColorTexture(1, 1, 1, 0.35)
                    hl:SetAllPoints()
                    hl:SetBlendMode("ADD")

                    grip:SetScript("OnEnter", function(self)
                        if GameTooltip then
                            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                            GameTooltip:SetText("Drag to resize chat frame")
                            GameTooltip:Show()
                        end
                    end)
                    grip:SetScript("OnLeave", function()
                        if GameTooltip then GameTooltip:Hide() end
                    end)
                    grip:SetScript("OnMouseDown", function(self, button)
                        if button ~= "LeftButton" then return end
                        if InCombatLockdown and InCombatLockdown() then return end
                        local f = _G.ChatFrame1
                        if not f then return end
                        if f.SetResizable then f:SetResizable(true) end
                        f:StartSizing("TOPRIGHT")
                    end)
                    grip:SetScript("OnMouseUp", function(self, button)
                        local f = _G.ChatFrame1
                        if f then
                            f:StopMovingOrSizing()
                            if _G.FCF_SavePositionAndDimensions then
                                _G.FCF_SavePositionAndDimensions(f)
                            end
                        end
                        if _G.QUI_RefreshChatSizeSliders then
                            _G.QUI_RefreshChatSizeSliders()
                        end
                    end)

                    overlay._chatResizeGrip = grip
                end
            end,
            onOpen = function()
                -- Deferred: CreateChildOverlay sets SetClampedToScreen(true)
                -- after onOpen fires, so override on next frame.
                C_Timer.After(0, function()
                    local f = _G.ChatFrame1
                    if f then
                        f:SetClampedToScreen(false)
                        if f.SetResizable then f:SetResizable(true) end
                    end
                end)
            end,
        })
    end

    C_Timer.After(2, RegisterDisplayElements)
end

---------------------------------------------------------------------------
-- QOL / UTILITY FRAME ELEMENT REGISTRATION
-- Addon-owned frames — use child overlays (isOwned = true)
---------------------------------------------------------------------------
do
    local function RegisterQoLElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local Helpers = ns.Helpers
        local GetCore = Helpers.GetCore

        local function GetProfileDB()
            local core = GetCore()
            return core and core.db and core.db.profile
        end

        -- Helper: standard module DB getter
        local function ModuleDB(key)
            local db = GetProfileDB()
            return db and db[key]
        end

        -- Helper: nested setting under db.general
        local function GeneralSubDB(subKey)
            local db = GetProfileDB()
            return db and db.general and db.general[subKey]
        end

        local QOL_ELEMENTS = {
            {
                key = "buffFrame", label = "Buff Frame", group = "Display", order = 3,
                frame = "QUI_BuffIconContainer", isOwned = true,
                dbKey = "buffBorders", enabledField = "enableBuffs",
                refresh = "QUI_RefreshBuffBorders",
                getFrame = function() return _G["QUI_BuffIconContainer"] end,
                -- SecureAuraHeaderTemplate auto-sizes from its secure children.
                -- Return _naturalW/_naturalH so the mover tracks the settings-
                -- computed size (from StyleHeaderChildren / preview grid).
                getSize = function()
                    local f = _G["QUI_BuffIconContainer"]
                    if f then return f._naturalW, f._naturalH end
                end,
                previewOn  = function() if _G.QUI_BuffBordersShowPreview then _G.QUI_BuffBordersShowPreview() end end,
                previewOff = function() if _G.QUI_BuffBordersHidePreview then _G.QUI_BuffBordersHidePreview() end end,
            },
            {
                key = "debuffFrame", label = "Debuff Frame", group = "Display", order = 4,
                frame = "QUI_DebuffIconContainer", isOwned = true,
                dbKey = "buffBorders", enabledField = "enableDebuffs",
                refresh = "QUI_RefreshBuffBorders",
                getFrame = function() return _G["QUI_DebuffIconContainer"] end,
                getSize = function()
                    local f = _G["QUI_DebuffIconContainer"]
                    if f then return f._naturalW, f._naturalH end
                end,
                previewOn  = function() if _G.QUI_BuffBordersShowPreview then _G.QUI_BuffBordersShowPreview() end end,
                previewOff = function() if _G.QUI_BuffBordersHidePreview then _G.QUI_BuffBordersHidePreview() end end,
            },
            {
                key = "crosshair", label = "Crosshair", group = "QoL", order = 1,
                frame = "QUI_Crosshair",
                dbKey = "crosshair", enabledField = "enabled",
                refresh = "QUI_RefreshCrosshair",
            },
            {
                key = "skyriding", label = "Skyriding HUD", group = "QoL", order = 2,
                frame = "QUI_Skyriding",
                dbKey = "skyriding", enabledField = "enabled",
                refresh = "QUI_RefreshSkyriding",
                previewOn  = function() if _G.QUI_ToggleSkyridingPreview then _G.QUI_ToggleSkyridingPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleSkyridingPreview then _G.QUI_ToggleSkyridingPreview(false) end end,
                getSize = function()
                    local f = _G.QUI_Skyriding
                    if not f then return nil end
                    local w = f:GetWidth()
                    local h = f:GetHeight()
                    -- Include Second Wind display area
                    local db = ModuleDB("skyriding")
                    if db then
                        local swMode = db.secondWindMode or "PIPS"
                        if swMode == "MINIBAR" then
                            h = h + 2 + (db.secondWindHeight or 6)
                        elseif swMode == "PIPS" then
                            h = h + 10
                        end
                    end
                    return w, h
                end,
                getCenterOffset = function()
                    local db = ModuleDB("skyriding")
                    if not db then return 0, 0 end
                    local swMode = db.secondWindMode or "PIPS"
                    if swMode == "MINIBAR" then
                        local extra = 2 + (db.secondWindHeight or 6)
                        return 0, -(extra / 2)  -- Shift down (minibar below)
                    elseif swMode == "PIPS" then
                        return 0, 5  -- Shift up (pips above)
                    end
                    return 0, 0
                end,
            },
            {
                key = "xpTracker", label = "XP Tracker", group = "QoL", order = 3,
                frame = "QUI_XPTracker",
                dbKey = "xpTracker", enabledField = "enabled",
                refresh = "QUI_RefreshXPTracker",
                previewOn  = function() if _G.QUI_ToggleXPTrackerPreview then _G.QUI_ToggleXPTrackerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleXPTrackerPreview then _G.QUI_ToggleXPTrackerPreview(false) end end,
                setupOverlay = function(overlay, barFrame)
                    overlay:ClearAllPoints()
                    local details = barFrame.detailsFrame
                    if details and details:IsShown() then
                        local detailsTop = details:GetTop()
                        local barTop = barFrame:GetTop()
                        if detailsTop and barTop and detailsTop > barTop then
                            overlay:SetPoint("TOPLEFT", details, "TOPLEFT", 0, 0)
                            overlay:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
                        else
                            overlay:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
                            overlay:SetPoint("BOTTOMRIGHT", details, "BOTTOMRIGHT", 0, 0)
                        end
                    else
                        overlay:SetAllPoints(barFrame)
                    end
                end,
            },
            {
                key = "combatTimer", label = "Combat Timer", group = "Instance", order = 3,
                frame = "QUI_CombatTimer",
                dbKey = "combatTimer", enabledField = "enabled",
                refresh = "QUI_RefreshCombatTimer",
                previewOn  = function() if _G.QUI_ToggleCombatTimerPreview then _G.QUI_ToggleCombatTimerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleCombatTimerPreview then _G.QUI_ToggleCombatTimerPreview(false) end end,
            },
            {
                key = "brezCounter", label = "Brez Counter", group = "Instance", order = 1,
                frame = "QUI_BrezCounter",
                dbKey = "brzCounter", enabledField = "enabled",
                refresh = "QUI_RefreshBrezCounter",
                previewOn  = function() if _G.QUI_ToggleBrezCounterPreview then _G.QUI_ToggleBrezCounterPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleBrezCounterPreview then _G.QUI_ToggleBrezCounterPreview(false) end end,
            },
            {
                key = "atonementCounter", label = "Atonement Counter", group = "QoL", order = 9.5,
                frame = "QUI_AtonementCounter",
                dbKey = "atonementCounter", enabledField = "enabled",
                refresh = "QUI_RefreshAtonementCounter",
                previewOn  = function() if _G.QUI_ToggleAtonementCounterPreview then _G.QUI_ToggleAtonementCounterPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleAtonementCounterPreview then _G.QUI_ToggleAtonementCounterPreview(false) end end,
            },
            {
                key = "mplusTimer", label = "M+ Timer", group = "Instance", order = 2,
                frame = "QUI_MPlusTimerFrame",
                dbKey = "mplusTimer", enabledField = "enabled",
                -- Use child overlay (setupOverlay forces the child overlay
                -- code path because of `isOwned and (not getSize or setupOverlay)`).
                -- Child overlay parents to QUI_MPlusTimerFrame so it inherits
                -- the frame's scale automatically — no coord-space math.
                setupOverlay = function(overlay, targetFrame)
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints(targetFrame)
                end,
                previewOn  = function() local t = _G.QUI_MPlusTimer; if t and t.EnableDemoMode then t:EnableDemoMode() end end,
                previewOff = function() local t = _G.QUI_MPlusTimer; if t and t.DisableDemoMode then t:DisableDemoMode() end end,
            },
            {
                key = "rangeCheck", label = "Range Check", group = "QoL", order = 5,
                frame = "QUI_RangeCheckFrame",
                dbKey = "rangeCheck", enabledField = "enabled",
                refresh = "QUI_RefreshRangeCheck",
                previewOn  = function() if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(false) end end,
            },
            {
                key = "actionTracker", label = "Action Tracker", group = "QoL", order = 6,
                frame = "QUI_ActionTracker",
                dbGetter = function() return GeneralSubDB("actionTracker") end,
                enabledField = "enabled",
                refresh = "QUI_RefreshActionTracker",
                previewOn  = function() if _G.QUI_ToggleActionTrackerPreview then _G.QUI_ToggleActionTrackerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleActionTrackerPreview then _G.QUI_ToggleActionTrackerPreview(false) end end,
            },
            {
                key = "focusCastAlert", label = "Focus Cast Alert", group = "QoL", order = 7,
                frame = "QUI_FocusCastAlertFrame",
                dbGetter = function() return GeneralSubDB("focusCastAlert") end,
                enabledField = "enabled",
                refresh = "QUI_RefreshFocusCastAlert",
                previewOn  = function() if _G.QUI_ToggleFocusCastAlertPreview then _G.QUI_ToggleFocusCastAlertPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleFocusCastAlertPreview then _G.QUI_ToggleFocusCastAlertPreview(false) end end,
            },
            {
                key = "petWarning", label = "Pet Warning", group = "QoL", order = 8,
                frame = "QUI_PetWarningFrame",
                dbGetter = function()
                    local db = GetProfileDB()
                    return db and db.general
                end,
                enabledField = "petCombatWarning",
                refresh = "QUI_RefreshPetWarning",
                previewOn  = function() if _G.QUI_TogglePetWarningPreview then _G.QUI_TogglePetWarningPreview(true) end end,
                previewOff = function() if _G.QUI_TogglePetWarningPreview then _G.QUI_TogglePetWarningPreview(false) end end,
            },
            {
                key = "preyTracker", label = "Prey Tracker", group = "QoL", order = 9,
                frame = "QUI_PreyTracker",
                dbKey = "preyTracker", enabledField = "enabled",
                refresh = "QUI_RefreshPreyTracker",
                previewOn  = function() if _G.QUI_TogglePreyTrackerPreview then _G.QUI_TogglePreyTrackerPreview(true) end end,
                previewOff = function() if _G.QUI_TogglePreyTrackerPreview then _G.QUI_TogglePreyTrackerPreview(false) end end,
            },
            {
                key = "readyCheck", label = "Ready Check", group = "Instance", order = 4,
                frame = nil,
                blizzFrame = "ReadyCheckFrame",
                dbGetter = function()
                    local db = GetProfileDB()
                    return db and db.general
                end,
                enabledField = "skinReadyCheck",
            },
            {
                key = "consumables", label = "Consumable Check", group = "Instance", order = 4.5,
                frame = "QUI_ConsumablesFrame",
                dbGetter = function()
                    local db = GetProfileDB()
                    return db and db.general
                end,
                enabledField = "consumableCheckEnabled",
                previewOn  = function() if _G.QUI_ShowConsumables then _G.QUI_ShowConsumables() end end,
                previewOff = function() if _G.QUI_HideConsumables then _G.QUI_HideConsumables() end end,
            },
            {
                key = "missingRaidBuffs", label = "Missing Raid Buffs", group = "Instance", order = 5,
                frame = "QUI_MissingRaidBuffs",
                dbKey = "raidBuffs", enabledField = "enabled",
                refresh = "QUI_RefreshRaidBuffs",
                previewOn  = function() local r = ns.RaidBuffs; if r and r.EnablePreview then r:EnablePreview() end end,
                previewOff = function() local r = ns.RaidBuffs; if r and r.DisablePreview then r:DisablePreview() end end,
            },
            {
                key = "rotationAssistIcon", label = "Rotation Assist Icon", group = "Cooldown Manager & Custom Tracker Bars", order = 5,
                frame = "QUI_RotationAssistIcon",
                dbKey = "rotationAssistIcon", enabledField = "enabled",
                refresh = "QUI_RefreshRotationAssistIcon",
            },
            {
                key = "totemBar", label = "Totem Bar", group = "Action Bars", order = 20,
                frame = "QUI_TotemBar",
                dbKey = "totemBar", enabledField = "enabled",
                refresh = "QUI_RefreshTotemBar",
                previewOn  = function() if _G.QUI_ShowTotemBarPreview then _G.QUI_ShowTotemBarPreview() end end,
                previewOff = function() if _G.QUI_HideTotemBarPreview then _G.QUI_HideTotemBarPreview() end end,
            },
            {
                key = "partyKeystones", label = "Party Keystones", group = "Instance", order = 6,
                frame = "QUIKeyTrackerFrame",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "keyTrackerEnabled",
                refresh = "QUI_RefreshKeyTracker",
            },
            {
                key = "lootFrame", label = "Loot Frame", group = "Display", order = 7,
                frame = "QUI_LootFrame",
                dbKey = "loot", enabledField = "enabled",
                requiresReload = true,
            },
            {
                key = "lootRollAnchor", label = "Loot Roll Anchor", group = "Display", order = 8,
                frame = "QUI_LootRollAnchor",
                dbKey = "lootRoll", enabledField = "enabled",
                requiresReload = true,
            },
            {
                key = "alertAnchor", label = "Alert Anchor", group = "Display", order = 9,
                frame = "QUI_AlertFrameHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
            },
            {
                key = "toastAnchor", label = "Toast Anchor", group = "Display", order = 10,
                frame = "QUI_EventToastHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
            },
            {
                key = "bnetToastAnchor", label = "BNet Toast Anchor", group = "Display", order = 11,
                frame = "QUI_BNetToastHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
            },
            {
                key = "powerBarAlt", label = "Encounter Power Bar", group = "Display", order = 12,
                frame = "QUI_AltPowerBar",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinPowerBarAlt",
            },
            {
                key = "tooltipAnchor", label = "Tooltip Anchor", group = "Display", order = 13,
                frame = "QUI_TooltipAnchor",
                dbKey = "tooltip", enabledField = "enabled",
            },
        }

        for _, info in ipairs(QOL_ELEMENTS) do
            local function GetDB()
                if info.dbGetter then return info.dbGetter() end
                return ModuleDB(info.dbKey)
            end

            um:RegisterElement({
                key = info.key,
                label = info.label,
                group = info.group,
                order = info.order,
                isOwned = true,
                isEnabled = function()
                    local db = GetDB()
                    return db and db[info.enabledField] ~= false
                end,
                setEnabled = function(val)
                    local db = GetDB()
                    if not db then return end
                    local old = db[info.enabledField]
                    db[info.enabledField] = val
                    local changed = (old ~= false) ~= (val ~= false)
                    if changed and info.requiresReload then
                        local GUI = QUI and QUI.GUI
                        if GUI then
                            GUI:ShowConfirmation({
                                title = "Reload UI?",
                                message = "This change requires a reload to take effect.",
                                acceptText = "Reload",
                                cancelText = "Later",
                                onAccept = function() QUI:SafeReload() end,
                            })
                        end
                    end
                    if info.refresh and _G[info.refresh] then
                        _G[info.refresh]()
                    end
                end,
                setGameplayHidden = function(hide)
                    local f = info.frame and _G[info.frame]
                    if not f then return end
                    if hide then f:Hide() else f:Show() end
                end,
                getFrame = info.getFrame or function()
                    if info.frame then
                        return _G[info.frame]
                    elseif info.blizzFrame then
                        return _G[info.blizzFrame]
                    end
                end,
                getSize = info.getSize,
                getCenterOffset = info.getCenterOffset,
                setupOverlay = info.setupOverlay,
                savePosition = info.savePosition,
                loadPosition = info.loadPosition,
                onOpen = info.previewOn,
                onClose = info.previewOff,
            })
        end
    end

    C_Timer.After(2, RegisterQoLElements)
end

---------------------------------------------------------------------------
-- HANDLE VISIBILITY & RESET (used by drawer UI)
---------------------------------------------------------------------------

--- Toggle mover handle visibility for preview (show handles for off-screen
--- or disabled frames so users can see and reposition them).
function QUI_LayoutMode:ToggleHandlePreview(key)
    if not self.isActive then return false end
    local def = self._elements[key]
    if not def then return false end

    local hidden = GetHiddenHandlesDB()
    local handle = self._handles[key]

    if handle and handle:IsShown() then
        -- Restore preview frame parent before hiding
        if handle._savedTargetParent then
            local targetFrame = def.getFrame and def.getFrame()
            if targetFrame then
                pcall(targetFrame.SetParent, targetFrame, handle._savedTargetParent)
                if _G.QUI_SetFrameLayoutOwned then
                    _G.QUI_SetFrameLayoutOwned(targetFrame, nil)
                end
                -- Re-pin the frame to UIParent at the handle's current
                -- screen position; SetAllPoints(handle) would otherwise
                -- leave a dangling anchor to the hidden handle.  See
                -- Close() for details.
                local cx, cy = handle:GetCenter()
                if cx and cy then
                    local hs = handle:GetEffectiveScale() or 1
                    local us = UIParent:GetEffectiveScale() or 1
                    local uw = UIParent:GetWidth() or 0
                    local uh = UIParent:GetHeight() or 0
                    local ox = (cx * hs / us) - (uw / 2)
                    local oy = (cy * hs / us) - (uh / 2)
                    pcall(targetFrame.ClearAllPoints, targetFrame)
                    pcall(targetFrame.SetPoint, targetFrame, "CENTER", UIParent, "CENTER", ox, oy)
                end
            end
            handle._savedTargetParent = nil
        end
        -- Hide it
        handle:Hide()
        if hidden then hidden[key] = true end
        if self._selectedKey == key then
            self:SelectMover(nil)
        end
        if def.onClose then pcall(def.onClose) end
        return false
    else
        -- Activate preview FIRST so the frame exists before CreateHandle
        if hidden then hidden[key] = nil end
        if def.onOpen then pcall(def.onOpen) end
        -- Create handle if needed (after onOpen so getFrame returns the correct frame)
        if not handle then
            handle = CreateHandle(def)
            self._handles[key] = handle
        end
        SyncHandle(key)
        handle:Show()

        -- If child overlay isn't visible (parent hidden), replace with proxy mover
        if handle._isChildOverlay and not handle:IsVisible() then
            handle:Hide()
            handle:SetParent(nil)
            handle = CreateProxyMover(def)
            self._handles[key] = handle
            SyncHandle(key)
            handle:Show()
        end

        -- Deferred: attach preview frame to proxy mover so they stay together
        -- and the mover renders on top
        C_Timer.After(0, function()
            if not handle:IsShown() then return end
            if handle._isChildOverlay then return end
            local targetFrame = def.getFrame and def.getFrame()
            if targetFrame and targetFrame:IsShown() then
                -- Save original parent/strata for restore
                if not handle._savedTargetParent then
                    handle._savedTargetParent = targetFrame:GetParent()
                end
                if not handle._savedTargetStrata then
                    handle._savedTargetStrata = targetFrame:GetFrameStrata()
                end
                -- Re-parent preview under the mover, behind it.
                -- DIALOG strata keeps preview below the FULLSCREEN_DIALOG handle.
                targetFrame:SetParent(handle)
                targetFrame:SetFrameStrata("DIALOG")
                targetFrame:SetFrameLevel(1)
                if _G.QUI_SetFrameLayoutOwned then
                    _G.QUI_SetFrameLayoutOwned(targetFrame, def.key)
                end
                targetFrame:ClearAllPoints()
                if def.getCenterOffset then
                    local cdx, cdy = def.getCenterOffset(handle:GetSize())
                    targetFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                else
                    targetFrame:SetAllPoints(handle)
                end
            end
        end)
        return true
    end
end

--- Ensure a handle preview matches the requested visibility state.
function QUI_LayoutMode:SetHandlePreviewVisible(key, shouldShow)
    if not self.isActive then return false end
    if not self:IsElementEnabled(key) then return false end

    local isShown = self:IsHandleShown(key)
    if isShown == shouldShow then
        return isShown
    end

    return self:ToggleHandlePreview(key)
end

--- Show or hide every enabled handle preview.
function QUI_LayoutMode:SetAllHandlePreviewsVisible(shouldShow)
    if not self.isActive then return end

    for _, key in ipairs(self._elementOrder) do
        if self:IsElementEnabled(key) then
            self:SetHandlePreviewVisible(key, shouldShow)
        end
    end

    if not shouldShow then
        self:SelectMover(nil)
    end
end

--- Show only one enabled handle preview and hide the rest.
function QUI_LayoutMode:SoloHandlePreview(key)
    if not self.isActive then return false end
    if not self:IsElementEnabled(key) then return false end

    -- If already soloed, clicking again un-solos (restores all enabled handles).
    if self:IsHandleSolo(key) then
        self:SetAllHandlePreviewsVisible(true)
        self:SelectMover(key)
        return true
    end

    for _, otherKey in ipairs(self._elementOrder) do
        if self:IsElementEnabled(otherKey) then
            self:SetHandlePreviewVisible(otherKey, otherKey == key)
        end
    end

    self:SelectMover(key)
    return true
end

--- Returns true when this is the only visible enabled handle.
function QUI_LayoutMode:IsHandleSolo(key)
    if not self:IsElementEnabled(key) or not self:IsHandleShown(key) then
        return false
    end

    for _, otherKey in ipairs(self._elementOrder) do
        if otherKey ~= key and self:IsElementEnabled(otherKey) and self:IsHandleShown(otherKey) then
            return false
        end
    end

    return true
end

--- Clear the hidden state for a key (used when enabling an element).
function QUI_LayoutMode:ClearHiddenState(key)
    local hidden = GetHiddenHandlesDB()
    if hidden then hidden[key] = nil end
end

--- Returns whether a handle is currently shown (or would be shown based on persisted state).
function QUI_LayoutMode:IsHandleShown(key)
    if self.isActive then
        local handle = self._handles[key]
        return handle ~= nil and handle:IsShown()
    end
    -- When closed, check persisted state
    local hidden = GetHiddenHandlesDB()
    return not (hidden and hidden[key])
end

--- Reset a mover/frame to screen center (0, 0 offsets).
function QUI_LayoutMode:ResetToCenter(key)
    if not self.isActive then return end
    local def = self._elements[key]
    if not def then return end

    -- Create handle if it doesn't exist
    local handle = self._handles[key]
    if not handle then
        handle = CreateHandle(def)
        self._handles[key] = handle
    end

    -- Save center position as pending
    SavePendingPosition(key, "CENTER", "CENTER", 0, 0)

    -- Reposition handle and actual frame to center
    SetHandleFromOffsets(handle, 0, 0)
    if not handle._isChildOverlay then
        local frame = def.getFrame and def.getFrame()
        if frame then
            pcall(frame.ClearAllPoints, frame)
            pcall(frame.SetPoint, frame, "CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    -- Update coords display
    if handle._coords then
        handle._coords:SetText("X: 0  Y: 0")
    end
    -- Show handle if hidden
    if not handle:IsShown() then
        handle:Show()
    end

    SyncHandle(key)
end

---------------------------------------------------------------------------
-- GLOBAL API
---------------------------------------------------------------------------
_G.QUI_ToggleLayoutMode = function()
    QUI_LayoutMode:Toggle()
end

_G.QUI_OpenLayoutMode = function()
    if not QUI_LayoutMode.isActive then
        QUI_LayoutMode:Open()
    end
end

_G.QUI_LayoutModeSelectMover = function(key)
    if QUI_LayoutMode.isActive and QUI_LayoutMode.SelectMover then
        QUI_LayoutMode:SelectMover(key)
    end
end

_G.QUI_IsLayoutModeActive = function()
    return QUI_LayoutMode.isActive
end

-- Returns true if layout mode is active and owns a handle for this key.
-- During the brief enter-callback window (handles not yet created), falls
-- back to checking registered elements so that positioning triggered by
-- callbacks is still blocked.
_G.QUI_IsLayoutModeManaged = function(key)
    if not QUI_LayoutMode.isActive then return false end
    if QUI_LayoutMode._handles[key] then return true end
    -- Enter callbacks fire before handles are created — use element
    -- registration as a proxy during that narrow window only.
    if QUI_LayoutMode._enterCallbacksRunning and QUI_LayoutMode._elements[key] then
        return true
    end
    return false
end

-- Sync a mover handle to match current DB position (called from options panel)
_G.QUI_LayoutModeSyncHandle = function(key)
    if QUI_LayoutMode.isActive and SyncHandle then
        SyncHandle(key)
    end
end

-- Re-sync all visible handles (called after frame refreshes to fix z-order).
-- Two-pass: first sync all (recreates stale parents), then re-sync anchored
-- children so they read updated parent handle bounds.
_G.QUI_LayoutModeSyncAllHandles = function()
    if not QUI_LayoutMode.isActive or not SyncHandle then return end
    for hKey in pairs(QUI_LayoutMode._handles) do
        SyncHandle(hKey)
    end
    local fa = GetFrameAnchoring()
    if fa then
        for childKey in pairs(QUI_LayoutMode._handles) do
            local entry = fa[childKey]
            if entry and type(entry) == "table" and entry.parent
                and entry.parent ~= "screen" and entry.parent ~= "disabled" then
                SyncHandle(childKey)
            end
        end
    end
end

-- Mark layout mode as having unsaved changes
_G.QUI_LayoutModeMarkChanged = function()
    if QUI_LayoutMode.isActive then
        QUI_LayoutMode._hasChanges = true
    end
end

-- Clear a pending position so SyncHandle reads from the actual frame
_G.QUI_LayoutModeClearPending = function(key)
    if QUI_LayoutMode.isActive and key then
        QUI_LayoutMode._pendingPositions[key] = nil
    end
end


---------------------------------------------------------------------------
-- REFRESH HOOKS: re-sync handles after module refreshes so child overlays
-- maintain correct z-order (strata/level) and detect stale parent frames.
---------------------------------------------------------------------------
local _layoutSyncPending = false
local function DebouncedLayoutSync()
    if _layoutSyncPending then return end
    _layoutSyncPending = true
    C_Timer.After(0.05, function()
        _layoutSyncPending = false
        if _G.QUI_LayoutModeSyncAllHandles then
            _G.QUI_LayoutModeSyncAllHandles()
        end
    end)
end

local function HookRefreshForLayoutSync(name)
    local original = _G[name]
    if not original then return end
    _G[name] = function(...)
        original(...)
        if QUI_LayoutMode.isActive then
            DebouncedLayoutSync()
        end
    end
end

-- Hook globals that exist at file-load time
HookRefreshForLayoutSync("QUI_RefreshUnitFrames")
HookRefreshForLayoutSync("QUI_RefreshCastbar")
HookRefreshForLayoutSync("QUI_RefreshCastbars")

-- Hook globals that are defined by later-loading modules
C_Timer.After(1, function()
    HookRefreshForLayoutSync("QUI_RefreshNCDM")
    HookRefreshForLayoutSync("QUI_RefreshBuffBar")
    HookRefreshForLayoutSync("QUI_RefreshCustomTrackers")
    HookRefreshForLayoutSync("QUI_RefreshBrezCounter")
    HookRefreshForLayoutSync("QUI_RefreshAtonementCounter")
    HookRefreshForLayoutSync("QUI_RefreshCombatTimer")
    HookRefreshForLayoutSync("QUI_RefreshXPTracker")
    HookRefreshForLayoutSync("QUI_RefreshBuffBorders")
end)

---------------------------------------------------------------------------
-- STARTUP: Enforce hidden-handle visibility on login/reload
-- Delayed to ensure all modules have registered their elements
-- (CDM registers at C_Timer.After(2)).
---------------------------------------------------------------------------
do
    local startupFrame = CreateFrame("Frame")
    startupFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    startupFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    startupFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(3, function()
                QUI_LayoutMode:EnforceGameplayVisibility()
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            if QUI_LayoutMode._deferredGameplayHides then
                QUI_LayoutMode._deferredGameplayHides = nil
                QUI_LayoutMode:EnforceGameplayVisibility()
            end
        end
    end)
end
