local ADDON_NAME, ns = ...

local function EnsureCJKFont(fs)
    if not fs or not fs.GetFont then return fs end
    local fp, sz, fl = fs:GetFont()
    if fp and ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, fp, sz, fl)
    end
    return fs
end

local Helpers = ns.Helpers
local UIKit = ns.UIKit

local QUI_LayoutMode = {}
ns.QUI_LayoutMode = QUI_LayoutMode

local ACCENT_R, ACCENT_G, ACCENT_B = 0.376, 0.647, 0.980

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

local HANDLE_STRATA      = "FULLSCREEN_DIALOG"
local HANDLE_BG_ALPHA    = 0.55
local HANDLE_HOVER_ALPHA = 0.85
local HANDLE_DRAG_ALPHA  = 0.95
local HANDLE_BORDER_SIZE = 1
local HANDLE_BORDER_SIZE_ANCHORED = 2
local HANDLE_MIN_SIZE    = 20
local TINY_THRESHOLD     = 3

local GetPixelSize = UIKit.GetPixelSize

local function GetPixelLineSize(frame, pixels)
    return (pixels or 1) * GetPixelSize(frame)
end

local CreateHandle, CreateProxyMover, CreateChildOverlay
local SyncHandle, HandleToOffsets, SetHandleFromOffsets
local SnapshotPositions, CommitPositions, RevertPositions
local ShowSaveDiscardPopup, AddHandleVisuals, AddHandleScripts
local GetFrameAnchoring

local function MigrateDBKey(db)
    if db.unlockMode and not db.layoutMode then
        db.layoutMode = db.unlockMode
        db.unlockMode = nil
    end
end

local function GetHiddenHandlesDB()
    local core = ns.Helpers and ns.Helpers.GetCore and ns.Helpers.GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    MigrateDBKey(db)
    if not db.layoutMode then db.layoutMode = {} end
    if not db.layoutMode.hiddenHandles then db.layoutMode.hiddenHandles = {} end
    return db.layoutMode.hiddenHandles
end

local InCombatLockdown = InCombatLockdown

QUI_LayoutMode._gameplayHidden = {}

function QUI_LayoutMode:EnforceGameplayVisibility()
    if self.isActive then return end
    local hidden = GetHiddenHandlesDB()
    if not hidden then return end

    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if not def then break end

        if def.noHandle then
        elseif def.isEnabled and not def.isEnabled() then
        else
            local shouldHide = hidden[key] == true
            local wasHiddenByUs = self._gameplayHidden[key]

            if shouldHide and not wasHiddenByUs then
                if def.setGameplayHidden then
                    self._gameplayHidden[key] = true
                    ns.SafeCall("bulkhead", def.setGameplayHidden, true)
                else
                    local frame = def.getFrame and def.getFrame()
                    if frame then
                        if InCombatLockdown() then
                            self._deferredGameplayHides = self._deferredGameplayHides or {}
                            self._deferredGameplayHides[key] = true
                        else
                            self._gameplayHidden[key] = true
                            ns.SafeCallMethod("best-effort-style", frame, "SetAlpha", 0)
                            ns.SafeCallMethod("best-effort-style", frame, "EnableMouse", false)
                        end
                    end
                end
            elseif not shouldHide and wasHiddenByUs then
                self._gameplayHidden[key] = nil
                if def.setGameplayHidden then
                    ns.SafeCall("bulkhead", def.setGameplayHidden, false)
                else
                    local frame = def.getFrame and def.getFrame()
                    if frame then
                        ns.SafeCallMethod("best-effort-style", frame, "SetAlpha", 1)
                        ns.SafeCallMethod("best-effort-style", frame, "EnableMouse", true)
                    end
                end
            end
        end
    end
end

QUI_LayoutMode.isActive       = false
QUI_LayoutMode._combatSuspended = false
QUI_LayoutMode._hasChanges      = false
QUI_LayoutMode._pendingPositions   = {}
QUI_LayoutMode._snapshotPositions  = {}
QUI_LayoutMode._handles           = {}
QUI_LayoutMode._elements          = {}
QUI_LayoutMode._elementOrder      = {}
QUI_LayoutMode._selectedKey       = nil
QUI_LayoutMode._enterCallbacks    = {}
QUI_LayoutMode._exitCallbacks     = {}
QUI_LayoutMode._savedMovableState = {}

QUI_LayoutMode._movers = QUI_LayoutMode._handles

local ReleaseHandle

function QUI_LayoutMode:RegisterElement(def)
    if not def or not def.key then return end

    local previous = self._elements[def.key]
    self._elements[def.key] = def
    self:_RebuildOrder()

    ReleaseHandle(self, def.key, previous or def)

    if self.isActive and not self._combatSuspended then
        if not def.isEnabled or def.isEnabled() then
            local handle = CreateHandle(def)
            self._handles[def.key] = handle
            SyncHandle(def.key)
            handle:Show()
        end
    end
end

function QUI_LayoutMode:UpdateElementLabel(key, newLabel)
    if not key or type(newLabel) ~= "string" or newLabel == "" then return false end
    local def = self._elements[key]
    if not def then return false end
    def.label = newLabel
    local handle = self._handles[key]
    if handle and handle._label then
        handle._label:SetText(ns.L[def.label or key])
    end
    return true
end

local function RestoreTargetFrame(handle, def, suspending)
    if not handle or not handle._savedTargetParent then return end

    local targetFrame = def and def.getFrame and def.getFrame()
    if targetFrame then
        ns.SafeCallMethod("best-effort-style", targetFrame, "SetParent", handle._savedTargetParent)
        if handle._savedTargetStrata then
            ns.SafeCallMethod("best-effort-style", targetFrame, "SetFrameStrata", handle._savedTargetStrata)
        end
        if not suspending and _G.QUI_SetFrameLayoutOwned then
            _G.QUI_SetFrameLayoutOwned(targetFrame, nil)
        end
        local cx, cy = handle:GetCenter()
        if cx and cy then
            local hs = handle:GetEffectiveScale() or 1
            local us = UIParent:GetEffectiveScale() or 1
            local uw = UIParent:GetWidth() or 0
            local uh = UIParent:GetHeight() or 0
            local ox = (cx * hs / us) - (uw / 2)
            local oy = (cy * hs / us) - (uh / 2)
            ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
            ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", UIParent, "CENTER", ox, oy)
        end
    end

    if not suspending then
        handle._savedTargetParent = nil
        handle._savedTargetStrata = nil
    end
end

function ReleaseHandle(self, key, def)
    local handle = self._handles[key]
    if not handle then return end
    handle:Hide()
    if handle._isChildOverlay and handle._parentFrame then
        local saved = self._savedMovableState[key]
        if saved ~= nil then
            ns.SafeCallMethod("best-effort-style", handle._parentFrame, "SetMovable", saved)
            self._savedMovableState[key] = nil
        end
    end
    RestoreTargetFrame(handle, def)
    handle:SetParent(nil)
    self._handles[key] = nil
end

function QUI_LayoutMode:UnregisterElement(key)
    if not key then return end

    local def = self._elements[key]
    self._elements[key] = nil
    self:_RebuildOrder()

    ReleaseHandle(self, key, def)

    self._pendingPositions[key] = nil

    if self._selectedKey == key then
        self._selectedKey = nil
    end
end

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

function QUI_LayoutMode:IsElementEnabled(key)
    local def = self._elements[key]
    if not def then return false end
    if not def.isEnabled then return true end
    return def.isEnabled()
end

function QUI_LayoutMode:SetElementEnabled(key, enabled)
    local def = self._elements[key]
    if not def or not def.setEnabled then return end

    def.setEnabled(enabled)

    if enabled then
        self:ClearHiddenState(key)
    end

    if not self.isActive then return end
    if def.noHandle then return end

    if enabled then
        if def.onOpen then ns.SafeCall("bulkhead", def.onOpen) end
        if not self._handles[key] then
            local handle = CreateHandle(def)
            self._handles[key] = handle
            SyncHandle(key)
            handle:Show()
            if handle._isChildOverlay and not handle:IsVisible() and key ~= "mplusTimer" then
                handle:Hide()
                handle:SetParent(nil)
                handle = CreateProxyMover(def)
                self._handles[key] = handle
                SyncHandle(key)
                handle:Show()
            end
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
        if def.onClose then ns.SafeCall("bulkhead", def.onClose) end
        local handle = self._handles[key]
        if handle then
            RestoreTargetFrame(handle, def)
            handle:Hide()
            if handle._isChildOverlay and handle._parentFrame then
                local saved = self._savedMovableState[key]
                if saved ~= nil then
                    ns.SafeCallMethod("best-effort-style", handle._parentFrame, "SetMovable", saved)
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
        print("|cff60A5FAQUI:|r " .. ns.L["Cannot open Layout Mode during combat."])
        return
    end

    local QUI = _G.QUI
    if QUI and type(QUI.EnsureOptionsLoaded) == "function" then
        QUI:EnsureOptionsLoaded()
    end

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

    if self._selectedKey and self._handles[self._selectedKey] then
        local prev = self._handles[self._selectedKey]
        prev._selected = false
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG then LCG.PixelGlow_Stop(prev, "_QUILayoutSelect") end
    end
    self._selectedKey = nil
    self._prevSelectedKey = nil

    SnapshotPositions()

    local hiddenSnap = {}
    local hiddenDB = GetHiddenHandlesDB()
    if hiddenDB then
        for k, v in pairs(hiddenDB) do
            hiddenSnap[k] = v
        end
    end
    self._snapshotHiddenHandles = hiddenSnap

    self._enterCallbacksRunning = true
    for _, cb in ipairs(self._enterCallbacks) do
        ns.SafeCall("bulkhead", cb)
    end
    self._enterCallbacksRunning = false

    local hidden = GetHiddenHandlesDB()
    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        local enabled = not def.isEnabled or def.isEnabled()

        if enabled and not def.noHandle then
            if hidden and hidden[key] then
                if not self._handles[key] then
                    self._handles[key] = CreateHandle(def)
                end
                SyncHandle(key)
                self._handles[key]:Hide()
                if def.onClose then ns.SafeCall("bulkhead", def.onClose) end
            else
                if def.onOpen then ns.SafeCall("bulkhead", def.onOpen) end
                if not self._handles[key] then
                    self._handles[key] = CreateHandle(def)
                else
                    local handle = self._handles[key]
                    if handle._isChildOverlay and handle._parentFrame then
                        local wasMovable = handle._parentFrame:IsMovable()
                        self._savedMovableState[key] = wasMovable
                        handle._parentFrame:SetMovable(true)
                        handle._parentFrame:SetClampedToScreen(true)
                    end
                end

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

                if handle._isChildOverlay and handle._parentFrame
                    and not handle._parentFrame:IsVisible() and key ~= "mplusTimer" then
                    handle:Hide()
                    handle:SetParent(nil)
                    handle = CreateProxyMover(def)
                    self._handles[key] = handle
                    SyncHandle(key)
                    if not isAnchored then
                        handle:Show()
                    end
                end

                if not handle._isChildOverlay and key ~= "bossFrames" then
                    local previewFrame = def.getFrame and def.getFrame()
                    if previewFrame and previewFrame.GetObjectType and previewFrame:IsShown() then
                        if not handle._savedTargetParent then
                            handle._savedTargetParent = previewFrame:GetParent()
                        end
                        if not handle._savedTargetStrata then
                            handle._savedTargetStrata = previewFrame:GetFrameStrata()
                        end
                        previewFrame:SetParent(handle)
                        previewFrame:SetFrameStrata("DIALOG")
                        previewFrame:SetFrameLevel(1)
                        if _G.QUI_SetFrameLayoutOwned then
                            _G.QUI_SetFrameLayoutOwned(previewFrame, key)
                        end
                        previewFrame:ClearAllPoints()
                        if def.getCenterOffset then
                            local cdx, cdy = def.getCenterOffset(handle:GetSize())
                            previewFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                        else
                            previewFrame:SetAllPoints(handle)
                        end
                    end
                end
            end
        end
    end

    do
        local fa = GetFrameAnchoring()
        if fa then
            local depths = {}
            local function getDepth(key, seen)
                if depths[key] then return depths[key] end
                if seen and seen[key] then return 0 end
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
                local h = self._handles[childKey]
                if h and not (hiddenDB and hiddenDB[childKey]) then
                    h:Show()
                end
            end
        end
    end

    C_Timer.After(0, function()
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
                    targetFrame:SetFrameStrata("DIALOG")
                    targetFrame:SetFrameLevel(1)
                    if _G.QUI_SetFrameLayoutOwned then
                        _G.QUI_SetFrameLayoutOwned(targetFrame, hKey)
                    end
                    local cdx, cdy = 0, 0
                    if hDef.getCenterOffset then
                        cdx, cdy = hDef.getCenterOffset(handle:GetSize())
                    end
                    targetFrame:ClearAllPoints()
                    if hDef.getCenterOffset then
                        targetFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                    else
                        targetFrame:SetAllPoints(handle)
                    end

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
                                    if _G.QUI_SetFrameLayoutOwned then
                                        _G.QUI_SetFrameLayoutOwned(bf, hKey)
                                    end
                                end
                            end
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
                end
            end
        end

        for hKey in pairs(self._handles) do
            SyncHandle(hKey)
        end
    end)

    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Show()
    end

    if not self._combatFrame then
        self._combatFrame = CreateFrame("Frame")
        self._combatFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                QUI_LayoutMode:_CombatSuspend()
                QUI_LayoutMode._pendingCombatClose = true
                print("|cff60A5FAQUI:|r " .. ns.L["Layout Mode closed (combat). Unsaved changes discarded."])
            elseif event == "PLAYER_REGEN_ENABLED" then
                C_Timer.After(0.5, function()
                    if InCombatLockdown() then return end
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

    if not self._firstOpenDone then
        self._firstOpenDone = true
        print("|cff60A5FAQUI Layout Mode:|r " .. ns.L["Drag to move | Click to select | Arrow keys to nudge | Shift+Drag near edge = anchor | Escape to close"])
    end
end

function QUI_LayoutMode:Close(skipSaveCheck)
    if not self.isActive then return end

    if self._hasChanges and not skipSaveCheck then
        ShowSaveDiscardPopup()
        return
    end

    self.isActive = false
    self._combatSuspended = false

    for key, handle in pairs(self._handles) do
        RestoreTargetFrame(handle, self._elements[key])
        if handle._savedBossParents then
            local QUI_UF = ns.QUI_UnitFrames
            local bossFrames = QUI_UF and QUI_UF.frames
            if bossFrames then
                for i, savedParent in pairs(handle._savedBossParents) do
                    local bf = bossFrames["boss" .. i]
                    if bf then
                        ns.SafeCallMethod("best-effort-style", bf, "SetParent", savedParent)
                        if _G.QUI_SetFrameLayoutOwned then
                            _G.QUI_SetFrameLayoutOwned(bf, nil)
                        end
                    end
                end
            end
            handle._savedBossParents = nil
        end
        if handle._savedCastbarParents then
            local castbars = ns.QUI_Castbar and ns.QUI_Castbar.castbars
            if castbars then
                for i, savedParent in pairs(handle._savedCastbarParents) do
                    local cb = castbars["boss" .. i]
                    if cb then ns.SafeCallMethod("best-effort-style", cb, "SetParent", savedParent) end
                end
            end
            handle._savedCastbarParents = nil
        end
        handle:Hide()
        if handle._isChildOverlay and handle._parentFrame then
            local saved = self._savedMovableState[key]
            if saved ~= nil then
                ns.SafeCallMethod("best-effort-style", handle._parentFrame, "SetMovable", saved)
            end
        end
    end
    self._savedMovableState = {}

    if self._selectedKey and self._handles[self._selectedKey] then
        local prev = self._handles[self._selectedKey]
        prev._selected = false
        local LCG = LibStub("LibCustomGlow-1.0", true)
        if LCG then LCG.PixelGlow_Stop(prev, "_QUILayoutSelect") end
    end
    self._selectedKey = nil
    self._prevSelectedKey = nil

    local ui = ns.QUI_LayoutMode_UI
    if ui then
        ui:Hide()
    end

    local settings = ns.QUI_LayoutMode_Settings
    if settings then
        settings:Reset()
    end

    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if def.onClose then
            ns.SafeCall("bulkhead", def.onClose)
        end
    end

    for _, key in ipairs(self._elementOrder) do
        local def = self._elements[key]
        if def.setEnabled and def.isEnabled then
            local enabled = def.isEnabled()
            if not enabled then
                ns.SafeCall("bulkhead", def.setEnabled, false)
            end
        end
    end

    self:EnforceGameplayVisibility()

    for _, cb in ipairs(self._exitCallbacks) do
        ns.SafeCall("bulkhead", cb)
    end

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
    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll(true)
    end
end

function QUI_LayoutMode:DiscardAndClose()
    RevertPositions()
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
    local ApplyAll = _G.QUI_ApplyAllFrameAnchors
    if ApplyAll then
        ApplyAll(true)
    end
end

function QUI_LayoutMode:_CombatSuspend()
    if not self.isActive then return end
    self._combatSuspended = true

    for key, handle in pairs(self._handles) do
        if not handle._isChildOverlay then
            RestoreTargetFrame(handle, self._elements[key], true)
        end
    end

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

    if self._selectedKey then
        local settings = ns.QUI_LayoutMode_Settings
        if settings then
            settings:Show(self._selectedKey)
        end
    end
end

function QUI_LayoutMode:ActivateElement(key)
    if not self.isActive then return end
    local def = self._elements[key]
    if not def then return end
    if self._handles[key] then return end

    if def.onOpen then ns.SafeCall("bulkhead", def.onOpen) end

    local handle = CreateHandle(def)
    if handle then
        self._handles[key] = handle
        SyncHandle(key)
        handle:Show()
    end
end

function QUI_LayoutMode:SelectMover(key)
    local LCG = LibStub("LibCustomGlow-1.0", true)

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

    local ui = ns.QUI_LayoutMode_UI
    if ui and ui.OnSelectionChanged then
        ui:OnSelectionChanged(key)
    end

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

GetFrameAnchoring = function()
    local core = Helpers.GetCore()
    local db = core and core.db and core.db.profile
    if not db then return nil end
    if type(db.frameAnchoring) ~= "table" then
        db.frameAnchoring = {}
    end
    return db.frameAnchoring
end

function QUI_LayoutMode:IsElementAnchored(key)
    if not key then return false end
    local fa = GetFrameAnchoring()
    local entry = fa and fa[key]
    if type(entry) ~= "table" then return false end
    return entry.parent ~= nil and entry.parent ~= "disabled"
end

function QUI_LayoutMode:FlashLockedHandle(key)
    local handle = key and self._handles[key]
    local border = handle and handle._border
    if border and border.SetColor then
        border:SetColor(1, 0.3, 0.3, 1)
        C_Timer.After(0.3, function()
            if border and border.SetColor then
                border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
            end
        end)
    end
end

function QUI_LayoutMode:DetachElementAnchor(key)
    if not self:IsElementAnchored(key) then return end
    local fa = GetFrameAnchoring()
    local entry = fa and fa[key]
    if type(entry) ~= "table" then return end

    local def = self._elements[key]
    local frame = def and def.getFrame and def.getFrame()
    if frame and frame.GetCenter then
        local cx, cy = frame:GetCenter()
        if cx and cy then
            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
            entry.offsetX = math.floor(cx - pw / 2 + 0.5)
            entry.offsetY = math.floor(cy - ph / 2 + 0.5)
        end
    end
    entry.parent = "disabled"
    entry.point = "CENTER"
    entry.relative = "CENTER"

    if _G.QUI_ApplyFrameAnchor then
        ns.SafeCall("bulkhead", _G.QUI_ApplyFrameAnchor, key)
    end
    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
    end
    self._hasChanges = true
end

local function LoadPosition(key)
    local def = QUI_LayoutMode._elements[key]
    if not def then return nil end

    if def.loadPosition then
        return def.loadPosition(key)
    end

    local fa = GetFrameAnchoring()
    if not fa then return nil end

    local entry = fa[key]
    if type(entry) ~= "table" then return nil end

    return entry.point or "CENTER",
           entry.relative or "CENTER",
           entry.offsetX or 0,
           entry.offsetY or 0
end

local ComputeAnchoredRectFromChain

local function GetAnchorRectInUIParent(anchorKey, seen)
    if not anchorKey then return nil end
    if anchorKey == "screen" or anchorKey == "disabled" then
        return 0, UIParent:GetWidth(), UIParent:GetHeight(), 0
    end
    local h = QUI_LayoutMode._handles and QUI_LayoutMode._handles[anchorKey]
    if h then
        local l, r, t, b = h:GetLeft(), h:GetRight(), h:GetTop(), h:GetBottom()
        if l and r and t and b then return l, r, t, b end
    end
    local pf = _G.QUI_ResolveAnchorTargetFrame and _G.QUI_ResolveAnchorTargetFrame(anchorKey)
    if pf and pf.GetLeft then
        local l, r, t, b = pf:GetLeft(), pf:GetRight(), pf:GetTop(), pf:GetBottom()
        if l and r and t and b then
            local fs = (pf.GetEffectiveScale and pf:GetEffectiveScale()) or 1
            local us = UIParent:GetEffectiveScale() or 1
            if fs ~= us and us > 0 then
                local ratio = fs / us
                l, r, t, b = l * ratio, r * ratio, t * ratio, b * ratio
            end
            return l, r, t, b
        end
    end
    return ComputeAnchoredRectFromChain(anchorKey, seen)
end

ComputeAnchoredRectFromChain = function(key, seen)
    local fa = GetFrameAnchoring()
    local entry = fa and fa[key]
    if type(entry) ~= "table" or not entry.parent then return nil end
    if entry.parent == "disabled" then return nil end

    seen = seen or {}
    if seen[key] then return nil end
    seen[key] = true

    local w, h
    local def = QUI_LayoutMode._elements and QUI_LayoutMode._elements[key]
    if def and def.getSize then
        w, h = def.getSize()
    end
    if not (w and h) then
        local frame = def and def.getFrame and def.getFrame()
        if frame and frame.GetSize then
            local ok, fw, fh = pcall(frame.GetSize, frame)
            if ok and fw and fh then w, h = fw, fh end
        end
    end
    if not w or not h or w <= 0 or h <= 0 then return nil end

    local pL, pR, pT, pB = GetAnchorRectInUIParent(entry.parent or "screen", seen)
    if not (pL and pR and pT and pB) then return nil end

    local relPt = entry.relative or "CENTER"
    local pt = entry.point or "CENTER"
    local px, py = (pL + pR) / 2, (pT + pB) / 2
    if relPt:find("LEFT") then px = pL elseif relPt:find("RIGHT") then px = pR end
    if relPt:find("TOP") then py = pT elseif relPt:find("BOTTOM") then py = pB end
    px = px + (entry.offsetX or 0)
    py = py + (entry.offsetY or 0)
    local cx, cy = px, py
    if pt:find("LEFT") then cx = px + w / 2 elseif pt:find("RIGHT") then cx = px - w / 2 end
    if pt:find("TOP") then cy = py - h / 2 elseif pt:find("BOTTOM") then cy = py + h / 2 end
    return cx - w / 2, cx + w / 2, cy + h / 2, cy - h / 2
end

local function ReapplyAnchoredDescendants(rootKey)
    local fa = GetFrameAnchoring()
    if not fa then return end
    local visited = { [rootKey] = true }
    local queue = { rootKey }
    while #queue > 0 do
        local parentKey = table.remove(queue, 1)
        for childKey, childSettings in pairs(fa) do
            if not visited[childKey] and type(childSettings) == "table"
                and childSettings.parent == parentKey then
                visited[childKey] = true
                queue[#queue + 1] = childKey
                QUI_LayoutMode._pendingPositions[childKey] = nil
                if _G.QUI_ForceReapplyFrameAnchor then
                    _G.QUI_ForceReapplyFrameAnchor(childKey)
                end
                if SyncHandle then SyncHandle(childKey) end
            end
        end
    end
end

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

    local fa = GetFrameAnchoring()
    if fa and not (def and def.usesCustomPositionPersistence) then
        if not fa[key] then fa[key] = {} end
        if anchorTarget then
            local ptSelf = anchorPointSelf or "CENTER"
            local ptTarget = anchorPointTarget or "CENTER"
            local relOx, relOy = offsetX, offsetY

            local childHandle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[key]

            local pL, pR, pT, pB = GetAnchorRectInUIParent(anchorTarget)

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
            local existingParent = fa[key].parent
            local existingPt = fa[key].point or "CENTER"
            local existingRelPt = fa[key].relative or "CENTER"

            local hasRealParent = existingParent
                and existingParent ~= "disabled"
                and existingParent ~= "screen"
            local hasNonCenterPoints = existingPt ~= "CENTER" or existingRelPt ~= "CENTER"

            if hasRealParent and hasNonCenterPoints then
                local childHandle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[key]
                local pL, pR, pT, pB = GetAnchorRectInUIParent(existingParent)

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
                local isGrowAnchorKey = key == "buffFrame" or key == "debuffFrame"
                local growCorner
                if isGrowAnchorKey then
                    growCorner = (fa[key] and fa[key].growAnchor) or "TOPRIGHT"
                end

                if growCorner then
                    local def = QUI_LayoutMode._elements[key]
                    local frame = def and def.getFrame and def.getFrame()
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
                    fa[key].point = "CENTER"
                    fa[key].relative = "CENTER"
                    fa[key].offsetX = offsetX
                    fa[key].offsetY = offsetY
                end
            end
        end
    end

    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
    end

    if fa and not (def and def.usesCustomPositionPersistence) then
        local resolved = _G.QUI_ResolveAnchorApplyFrame and _G.QUI_ResolveAnchorApplyFrame(key)
        local elFrame = def and def.getFrame and def.getFrame()
        if resolved and elFrame and resolved ~= elFrame and _G.QUI_ApplyFrameAnchor then
            _G.QUI_ApplyFrameAnchor(key)
        end
        ReapplyAnchoredDescendants(key)
    end
end

function QUI_LayoutMode:RecordFreeElementPosition(key, frame)
    if not self.isActive then return end
    if not key or not frame or not frame.GetCenter then return end
    if self:IsElementAnchored(key) then return end
    local cx, cy = frame:GetCenter()
    if not cx or not cy then return end
    local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
    SavePendingPosition(key, "CENTER", "CENTER",
        math.floor(cx - pw / 2 + 0.5), math.floor(cy - ph / 2 + 0.5))
end

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
        ns.SafeCallMethod("best-effort-style", parent, "ClearAllPoints")
        ns.SafeCallMethod("best-effort-style", parent, "SetPoint", "CENTER", UIParent, "CENTER", ox, oy)
    else
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", UIParent, "CENTER", offsetX or 0, offsetY or 0)
    end
end

function QUI_LayoutMode:GetHandleEdges(handle)
    if handle._isChildOverlay and handle._parentFrame then
        local p = handle._parentFrame
        return p:GetLeft(), p:GetRight(), p:GetTop(), p:GetBottom()
    end
    return handle:GetLeft(), handle:GetRight(), handle:GetTop(), handle:GetBottom()
end

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

CommitPositions = function()
    if InCombatLockdown() then
        print("|cff60A5FAQUI:|r " .. ns.L["Cannot save positions during combat. Try again after combat ends."])
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
                if pos.anchorTarget then
                    fa[key].parent = pos.anchorTarget
                    fa[key].point = pos.anchorPointSelf or "CENTER"
                    fa[key].relative = pos.anchorPointTarget or "CENTER"
                else
                    fa[key].offsetX = pos.offsetX
                    fa[key].offsetY = pos.offsetY
                    if not pos.anchorTarget then
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

    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        for key in pairs(QUI_LayoutMode._pendingPositions) do
            QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
        end
    end

    QUI_LayoutMode._pendingPositions = {}
end

RevertPositions = function()
    if InCombatLockdown() then
        print("|cff60A5FAQUI:|r " .. ns.L["Cannot revert positions during combat."])
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
                    ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
                    ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "CENTER", UIParent, "CENTER", snap.offsetX, snap.offsetY)
                end
            elseif fa then
                if snap.parent == nil and not fa[key] then
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

    local QUI = _G.QUI
    if QUI and QUI.SendMessage then
        for key in pairs(QUI_LayoutMode._snapshotPositions) do
            QUI:SendMessage("QUI_FRAME_ANCHOR_CHANGED", key)
        end
    end

    for key in pairs(QUI_LayoutMode._handles) do
        SyncHandle(key)
    end

    QUI_LayoutMode._pendingPositions = {}
end

AddHandleVisuals = function(handle, def)
    local bg = handle:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.08, 0.10, HANDLE_BG_ALPHA)
    handle._bg = bg

    local border = {}
    local function MakeBorderLine(point1, rel1, point2, rel2, isHoriz)
        local line = handle:CreateTexture(nil, "BORDER")
        line:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        line:ClearAllPoints()
        line:SetPoint(point1, handle, rel1, 0, 0)
        line:SetPoint(point2, handle, rel2, 0, 0)
        if isHoriz then
            line:SetHeight(GetPixelLineSize(handle, HANDLE_BORDER_SIZE))
        else
            line:SetWidth(GetPixelLineSize(handle, HANDLE_BORDER_SIZE))
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
        border._lineSizePixels = size or HANDLE_BORDER_SIZE
        local lineSize = GetPixelLineSize(handle, border._lineSizePixels)
        border.top:SetHeight(lineSize)
        border.bottom:SetHeight(lineSize)
        border.left:SetWidth(lineSize)
        border.right:SetWidth(lineSize)
    end
    handle._border = border
    border:SetLineSize(HANDLE_BORDER_SIZE)

    if UIKit and UIKit.RegisterScaleRefresh then
        UIKit.RegisterScaleRefresh(handle, "layoutModeHandleBorder", function(owner)
            if owner and owner._border and owner._border.SetLineSize then
                owner._border:SetLineSize(owner._border._lineSizePixels or HANDLE_BORDER_SIZE)
            end
        end)
    end

    local label = EnsureCJKFont(handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    label:SetPoint("CENTER", handle, "CENTER", 0, 6)
    label:SetText(ns.L[def.label or def.key])
    label:SetTextColor(1, 1, 1, 1)
    label:SetJustifyH("CENTER")
    handle._label = label

    local coords = EnsureCJKFont(handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
    coords:SetPoint("CENTER", handle, "CENTER", 0, -8)
    coords:SetTextColor(0.8, 0.8, 0.8, 0.8)
    coords:SetJustifyH("CENTER")
    handle._coords = coords

    if def.group then
        local groupLabel = EnsureCJKFont(handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
        groupLabel:SetPoint("TOP", handle, "TOP", 0, -3)
        groupLabel:SetText(ns.L[def.group])
        groupLabel:SetTextColor(ACCENT_R, ACCENT_G, ACCENT_B, 0.7)
        groupLabel:SetScale(0.85)
        handle._groupLabel = groupLabel
    end

end

AddHandleScripts = function(handle, def)
    handle:SetScript("OnEnter", function(self)
        if not self._dragging then
            self._bg:SetAlpha(HANDLE_HOVER_ALPHA)
        end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(ns.L[def.label or self._barKey], 1, 1, 1)
        GameTooltip:AddLine(ns.L["Drag to move"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(ns.L["Right-click for settings"], 0.7, 0.7, 0.7)
        local fa = GetFrameAnchoring()
        local entry = fa and fa[self._barKey]
        if entry and type(entry) == "table" and entry.parent and entry.parent ~= "disabled" then
            GameTooltip:AddLine(ns.L["Middle-click to unanchor"], 0.9, 0.6, 0.3)
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

            if QUI_LayoutMode:IsElementAnchored(self._barKey) then
                QUI_LayoutMode:DetachElementAnchor(self._barKey)
                if self._isAnchored then
                    self._isAnchored = false
                    if self._border and self._border.SetLineSize then
                        self._border:SetLineSize(HANDLE_BORDER_SIZE)
                    end
                end
                if self._border and self._border.SetColor then
                    self._border:SetColor(0.2, 1, 0.4, 1)
                    C_Timer.After(0.3, function()
                        self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
                    end)
                end
                local settings = ns.QUI_LayoutMode_Settings
                if settings and settings.Refresh then settings:Refresh() end
            end
        end
    end)

    handle:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        GameTooltip:Hide()

        local def = QUI_LayoutMode._elements[self._barKey]
        local usesCustomPersistence = def and def.usesCustomPositionPersistence

        local hasActiveAnchor = (not usesCustomPersistence)
            and QUI_LayoutMode:IsElementAnchored(self._barKey) or false

        if hasActiveAnchor and not IsShiftKeyDown() then
            QUI_LayoutMode:FlashLockedHandle(self._barKey)
            return
        end

        self._wasAnchoredOnDragStart = hasActiveAnchor

        self._dragging = true
        self._snapState = nil

        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local hx, hy
        if self._isChildOverlay and self._parentFrame then
            hx, hy = self._parentFrame:GetCenter()
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

        self._shiftDragStart = IsShiftKeyDown()

        self._anchorGroupHandles = nil
        do
            local myKey = self._barKey
            local anchorRoot

            if self._shiftDragStart then
                anchorRoot = myKey
            elseif usesCustomPersistence then
                anchorRoot = myKey
            else
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

            local group = {}
            local function collectChildren(parentKey)
                for k, pending in pairs(QUI_LayoutMode._pendingPositions) do
                    if pending.anchorTarget == parentKey and not group[k] then
                        local h = QUI_LayoutMode._handles[k]
                        if h and h:IsShown() then
                            group[k] = h
                            collectChildren(k)
                        end
                    end
                end
                local fa = GetFrameAnchoring()
                if fa then
                    for k, entry in pairs(fa) do
                        if type(entry) == "table" and entry.parent == parentKey and not group[k] then
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

            local rootHandle = QUI_LayoutMode._handles[anchorRoot]
            if rootHandle and rootHandle:IsShown() then
                group[anchorRoot] = rootHandle
            end
            collectChildren(anchorRoot)

            group[myKey] = nil

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
                local groupKeys = {}
                for gk in pairs(groupData) do groupKeys[gk] = true end
                self._anchorGroupKeys = groupKeys
            end
        end

        self._bg:SetAlpha(HANDLE_DRAG_ALPHA)

        local settings = ns.QUI_LayoutMode_Settings
        if settings and settings:IsShown() then
            settings:Hide()
            self._settingsWasShown = true
        end

        self:SetScript("OnUpdate", function(frame)
            local curX, curY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            if not curX or not curY or not scale or scale == 0 then return end
            curX, curY = curX / scale, curY / scale

            local intendedCX = curX + (frame._dragCursorOffX or 0)
            local intendedCY = curY + (frame._dragCursorOffY or 0)
            local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
            local ox = math.floor(intendedCX - pw / 2 + 0.5)
            local oy = math.floor(intendedCY - ph / 2 + 0.5)

            SetHandleFromOffsets(frame, ox, oy)

            local ui = ns.QUI_LayoutMode_UI
            if ui and ui.ApplySnap then
                ui:ApplySnap(frame)
            end

            local postSnapOx, postSnapOy = HandleToOffsets(frame)

            if not frame._isChildOverlay then
                local key = frame._barKey
                local def2 = QUI_LayoutMode._elements[key]
                if def2 then
                    local targetFrame = def2.getFrame and def2.getFrame()
                    if targetFrame then
                        if key == "bossFrames" then
                            local cdx, cdy = 0, 0
                            if def2.getCenterOffset then
                                cdx, cdy = def2.getCenterOffset(frame:GetSize())
                            end
                            ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                            ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", frame, "CENTER", -cdx, -cdy)
                        else
                            ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                            local frameOx, frameOy = postSnapOx, postSnapOy
                            if def2.getCenterOffset then
                                local cdx, cdy = def2.getCenterOffset(frame:GetSize())
                                frameOx = frameOx - cdx
                                frameOy = frameOy - cdy
                            end
                            ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", UIParent, "CENTER", frameOx, frameOy)
                        end
                    end
                end
            end

            if frame._anchorGroupHandles then
                for k, data in pairs(frame._anchorGroupHandles) do
                    local newOx = postSnapOx + data.deltaFromDrag.x
                    local newOy = postSnapOy + data.deltaFromDrag.y
                    SetHandleFromOffsets(data.handle, newOx, newOy)
                    local def2 = QUI_LayoutMode._elements[k]
                    if def2 then
                        local targetFrame = def2.getFrame and def2.getFrame()
                        if targetFrame then
                            if k == "bossFrames" then
                                local cdx, cdy = 0, 0
                                if def2.getCenterOffset then
                                    cdx, cdy = def2.getCenterOffset(data.handle:GetSize())
                                end
                                ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                                ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", data.handle, "CENTER", -cdx, -cdy)
                            else
                                local frameOx, frameOy = newOx, newOy
                                if def2.getCenterOffset then
                                    local cdx, cdy = def2.getCenterOffset(data.handle:GetSize())
                                    frameOx = frameOx - cdx
                                    frameOy = frameOy - cdy
                                end
                                ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                                ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", UIParent, "CENTER", frameOx, frameOy)
                            end
                        end
                    end
                    if data.handle._coords then
                        data.handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], newOx, newOy))
                    end
                end
            end

            frame._coords:SetText(string.format(ns.L["X: %d  Y: %d"], postSnapOx, postSnapOy))
        end)
    end)

    handle:SetScript("OnDragStop", function(self)
        if not self._dragging then return end
        self._dragging = false
        self._bg:SetAlpha(self:IsMouseOver() and HANDLE_HOVER_ALPHA or HANDLE_BG_ALPHA)

        self:SetScript("OnUpdate", nil)

        local def = QUI_LayoutMode._elements[self._barKey]

        local ox, oy = HandleToOffsets(self)
        local anchorKey = self._snapAnchorKey
        local anchorPtSelf = self._snapAnchorPointSelf
        local anchorPtTarget = self._snapAnchorPointTarget

        if def and def.usesCustomPositionPersistence then
            anchorKey = nil
            anchorPtSelf = nil
            anchorPtTarget = nil
        end

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

        if not (def and def.usesCustomPositionPersistence)
           and not anchorKey and self._shiftDragStart and self._wasAnchoredOnDragStart then
            local fa = GetFrameAnchoring()
            if fa and fa[self._barKey] then
                fa[self._barKey].parent = "disabled"
                fa[self._barKey].point = "CENTER"
                fa[self._barKey].relative = "CENTER"
            end
        end

        if self._anchorGroupHandles then
            for k, data in pairs(self._anchorGroupHandles) do
                local gox, goy = HandleToOffsets(data.handle)
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

        if not self._isChildOverlay then
            local key = self._barKey
            local def2 = QUI_LayoutMode._elements[key]
            if def2 then
                local targetFrame = def2.getFrame and def2.getFrame()
                if targetFrame then
                    if key == "bossFrames" then
                        local cdx, cdy = 0, 0
                        if def2.getCenterOffset then
                            cdx, cdy = def2.getCenterOffset(self:GetSize())
                        end
                        ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                        ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", self, "CENTER", -cdx, -cdy)
                    else
                        local frameOx, frameOy = ox, oy
                        if def2.getCenterOffset then
                            local cdx, cdy = def2.getCenterOffset(self:GetSize())
                            frameOx = frameOx - cdx
                            frameOy = frameOy - cdy
                        end
                        ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
                        ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", UIParent, "CENTER", frameOx, frameOy)
                    end
                end
                if def2.onLiveMove then
                    ns.SafeCall("bulkhead", def2.onLiveMove, key)
                end
            end
        else
            local def2 = QUI_LayoutMode._elements[self._barKey]
            if def2 and def2.onLiveMove then
                ns.SafeCall("bulkhead", def2.onLiveMove, self._barKey)
            end
        end

        if anchorKey then
            self._isAnchored = true
            local fa = GetFrameAnchoring()
            local entry = fa and fa[self._barKey]
            local displayOx = entry and entry.offsetX or ox
            local displayOy = entry and entry.offsetY or oy
            self._coords:SetText(string.format(ns.L["X: %d  Y: %d"], displayOx, displayOy))
            if self._border and self._border.SetLineSize then
                self._border:SetLineSize(HANDLE_BORDER_SIZE_ANCHORED)
            end
        else
            self._isAnchored = false
            self._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
            if self._border and self._border.SetLineSize then
                self._border:SetLineSize(HANDLE_BORDER_SIZE)
            end
        end

        if self._border and self._border.SetColor then
            self._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
        end

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

        local ui = ns.QUI_LayoutMode_UI
        if ui and ui._anchorLine then
            ui._anchorLine:Hide()
        end

        if ui and ui.ClearSnapGuides then
            ui:ClearSnapGuides()
        end

        if self._settingsWasShown then
            self._settingsWasShown = nil
            local settingsPanel = ns.QUI_LayoutMode_Settings
            if settingsPanel then
                settingsPanel._currentKey = nil
                settingsPanel:Show(self._barKey)
            end
        end
    end)

    handle:EnableKeyboard(false)
end

local handleCache = { proxy = {}, overlay = {} }

local function ResetHandleForReuse(handle, def)
    handle:Hide()
    handle:ClearAllPoints()
    handle._selected = false
    handle._dragging = false
    handle._isAnchored = nil
    handle._savedTargetParent = nil
    handle._savedTargetStrata = nil
    handle._savedBossParents = nil
    handle._savedCastbarParents = nil
    if handle._bg then handle._bg:SetAlpha(HANDLE_BG_ALPHA) end
    if handle._border then
        if handle._border.SetLineSize then handle._border:SetLineSize(HANDLE_BORDER_SIZE) end
        if handle._border.SetColor then handle._border:SetColor(ACCENT_R, ACCENT_G, ACCENT_B, 1) end
    end
    if handle._coords then handle._coords:SetText("") end
    if handle._label then handle._label:SetText(ns.L[def.label or def.key]) end
    if handle._groupLabel and def.group then handle._groupLabel:SetText(ns.L[def.group]) end
    local LCG = LibStub("LibCustomGlow-1.0", true)
    if LCG then LCG.PixelGlow_Stop(handle, "_QUILayoutSelect") end
    AddHandleScripts(handle, def)
end

CreateChildOverlay = function(def)
    local targetFrame = def.getFrame and def.getFrame()

    if not targetFrame or not targetFrame:IsShown() then
        return CreateProxyMover(def)
    end

    local overlay = handleCache.overlay[def.key]
    if overlay then
        ResetHandleForReuse(overlay, def)
        overlay:SetParent(targetFrame)
        overlay:SetFrameStrata(HANDLE_STRATA)
        overlay:SetFrameLevel(100)
        if def.setupOverlay then
            def.setupOverlay(overlay, targetFrame)
        else
            overlay:SetAllPoints(targetFrame)
        end
        overlay._parentFrame = targetFrame
        QUI_LayoutMode._savedMovableState[def.key] = targetFrame:IsMovable()
        targetFrame:SetMovable(true)
        targetFrame:SetClampedToScreen(true)
        return overlay
    end

    local name = "QUI_Overlay_" .. def.key
    overlay = CreateFrame("Button", name, targetFrame)
    handleCache.overlay[def.key] = overlay
    overlay:SetFrameStrata(HANDLE_STRATA)
    overlay:SetFrameLevel(100)

    if def.setupOverlay then
        def.setupOverlay(overlay, targetFrame)
    else
        overlay:SetAllPoints(targetFrame)
    end

    overlay:RegisterForDrag("LeftButton")
    overlay:EnableMouse(true)
    overlay:Hide()

    overlay._barKey = def.key
    overlay._selected = false
    overlay._dragging = false
    overlay._isChildOverlay = true
    overlay._parentFrame = targetFrame

    local wasMovable = targetFrame:IsMovable()
    QUI_LayoutMode._savedMovableState[def.key] = wasMovable
    targetFrame:SetMovable(true)
    targetFrame:SetClampedToScreen(true)

    AddHandleVisuals(overlay, def)
    AddHandleScripts(overlay, def)

    return overlay
end

CreateProxyMover = function(def)
    local mover = handleCache.proxy[def.key]
    if mover then
        ResetHandleForReuse(mover, def)
        mover:SetParent(UIParent)
        mover:SetFrameStrata(HANDLE_STRATA)
        mover:SetFrameLevel(100)
        mover:SetSize(HANDLE_MIN_SIZE, HANDLE_MIN_SIZE)
        return mover
    end

    local name = "QUI_Mover_" .. def.key
    mover = CreateFrame("Button", name, UIParent)
    handleCache.proxy[def.key] = mover
    mover:SetFrameStrata(HANDLE_STRATA)
    mover:SetFrameLevel(100)
    mover:SetSize(HANDLE_MIN_SIZE, HANDLE_MIN_SIZE)
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:RegisterForDrag("LeftButton")
    mover:EnableMouse(true)
    mover:Hide()

    mover._barKey = def.key
    mover._selected = false
    mover._dragging = false
    mover._isChildOverlay = false

    AddHandleVisuals(mover, def)
    AddHandleScripts(mover, def)

    return mover
end

local TEST_CONTAINER_PARENTS = { partyFrames = true, raidFrames = true }

CreateHandle = function(def)
    if def.isOwned and (not def.getSize or def.setupOverlay) then
        if def.group == "Castbars" then
            return CreateProxyMover(def)
        end
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

SyncHandle = function(key)
    local handle = QUI_LayoutMode._handles[key]
    local def = QUI_LayoutMode._elements[key]
    if not handle or not def then return end

    if handle._isChildOverlay then
        local currentFrame = def.getFrame and def.getFrame()
        if currentFrame and currentFrame ~= handle._parentFrame then
            handle._parentFrame = currentFrame
            handle:SetParent(currentFrame)
            handle:SetFrameStrata(HANDLE_STRATA)
            handle:SetFrameLevel(100)
            if def.setupOverlay then
                def.setupOverlay(handle, currentFrame)
            else
                handle:ClearAllPoints()
                handle:SetAllPoints(currentFrame)
            end
            local wasMovable = currentFrame:IsMovable()
            QUI_LayoutMode._savedMovableState[key] = wasMovable
            currentFrame:SetMovable(true)
            currentFrame:SetClampedToScreen(true)
        end

        handle:SetFrameStrata(HANDLE_STRATA)
        handle:SetFrameLevel(100)

        if def.setupOverlay then
            def.setupOverlay(handle, handle._parentFrame)
        end
        local pending = QUI_LayoutMode._pendingPositions[key]
        if pending then
            SetHandleFromOffsets(handle, pending.offsetX, pending.offsetY)
        end

    else
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

        local cdx, cdy = 0, 0
        if def.getCenterOffset then
            cdx, cdy = def.getCenterOffset(w, h)
        end

        local pending = QUI_LayoutMode._pendingPositions[key]
        if pending then
            handle:ClearAllPoints()
            handle:SetPoint("CENTER", UIParent, "CENTER", pending.offsetX, pending.offsetY)
        else
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
                    local function anchorPos(l, r, t, b, pt)
                        local x, y = (l + r) / 2, (t + b) / 2
                        if pt:find("LEFT") then x = l
                        elseif pt:find("RIGHT") then x = r end
                        if pt:find("TOP") then y = t
                        elseif pt:find("BOTTOM") then y = b end
                        return x, y
                    end
                    local px, py = anchorPos(pL, pR, pT, pB, ptTarget)

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
                    handle:SetPoint("CENTER", UIParent, "CENTER", centerX, centerY)
                else
                    local rL, rR, rT, rB = GetAnchorRectInUIParent(anchorParent)
                    if rL and rR and rT and rB then
                        local px, py = (rL + rR) / 2, (rT + rB) / 2
                        if ptTarget:find("LEFT") then px = rL
                        elseif ptTarget:find("RIGHT") then px = rR end
                        if ptTarget:find("TOP") then py = rT
                        elseif ptTarget:find("BOTTOM") then py = rB end
                        local cW, cH = handle:GetSize()
                        local selfOffX, selfOffY = 0, 0
                        if ptSelf:find("LEFT") then selfOffX = cW / 2
                        elseif ptSelf:find("RIGHT") then selfOffX = -cW / 2 end
                        if ptSelf:find("TOP") then selfOffY = -cH / 2
                        elseif ptSelf:find("BOTTOM") then selfOffY = cH / 2 end
                        local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                        handle:ClearAllPoints()
                        handle:SetPoint("CENTER", UIParent, "CENTER",
                            math.floor(px + dbOx + selfOffX - pw / 2 + 0.5),
                            math.floor(py + dbOy + selfOffY - ph / 2 + 0.5))
                    else
                        local pt, relPt, ox, oy = LoadPosition(key)
                        if pt then
                            handle:ClearAllPoints()
                            handle:SetPoint("CENTER", UIParent, "CENTER", (ox or 0), (oy or 0))
                        end
                    end
                end
            else
                local pt, relPt, ox, oy = LoadPosition(key)
                local rL, rR, rT, rB
                if pt and relPt and not (pt == "CENTER" and relPt == "CENTER") then
                    rL, rR, rT, rB = GetAnchorRectInUIParent(anchorParent or "screen")
                end
                if pt then
                    if pt == "CENTER" and relPt == "CENTER" then
                        handle:ClearAllPoints()
                        handle:SetPoint("CENTER", UIParent, "CENTER", ox + cdx, oy + cdy)
                    elseif relPt and rL and rR and rT and rB then
                        local px, py = (rL + rR) / 2, (rT + rB) / 2
                        if relPt:find("LEFT") then px = rL
                        elseif relPt:find("RIGHT") then px = rR end
                        if relPt:find("TOP") then py = rT
                        elseif relPt:find("BOTTOM") then py = rB end
                        local cW, cH = handle:GetSize()
                        local selfOffX, selfOffY = 0, 0
                        if pt:find("LEFT") then selfOffX = cW / 2
                        elseif pt:find("RIGHT") then selfOffX = -cW / 2 end
                        if pt:find("TOP") then selfOffY = -cH / 2
                        elseif pt:find("BOTTOM") then selfOffY = cH / 2 end
                        local pw, ph = UIParent:GetWidth(), UIParent:GetHeight()
                        handle:ClearAllPoints()
                        handle:SetPoint("CENTER", UIParent, "CENTER",
                            math.floor(px + ox + selfOffX - pw / 2 + 0.5),
                            math.floor(py + oy + selfOffY - ph / 2 + 0.5))
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

    if not handle._isChildOverlay and handle._savedTargetParent and key ~= "bossFrames" then
        local targetFrame = def.getFrame and def.getFrame()
        if targetFrame and targetFrame.GetObjectType and targetFrame:GetParent() == handle then
            ns.SafeCallMethod("best-effort-style", targetFrame, "ClearAllPoints")
            if def.getCenterOffset then
                local gdx, gdy = def.getCenterOffset(handle:GetSize())
                ns.SafeCallMethod("best-effort-style", targetFrame, "SetPoint", "CENTER", handle, "CENTER", -gdx, -gdy)
            else
                ns.SafeCallMethod("best-effort-style", targetFrame, "SetAllPoints", handle)
            end
        end
    end

    if key == "bossFrames" and not handle._isChildOverlay then
        local frame = def.getFrame and def.getFrame()
        if frame and handle._savedTargetParent then
            local cdx, cdy = 0, 0
            if def.getCenterOffset then
                cdx, cdy = def.getCenterOffset(handle:GetSize())
            end
            ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
            ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "CENTER", handle, "CENTER", -cdx, -cdy)
        end
    end

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

    local ox, oy
    if existingAnchorKey then
        local fa = GetFrameAnchoring()
        local entry = fa and fa[key]
        ox = entry and entry.offsetX or 0
        oy = entry and entry.offsetY or 0
        handle._isAnchored = true
        handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
        if handle._border and handle._border.SetLineSize then
            handle._border:SetLineSize(HANDLE_BORDER_SIZE_ANCHORED)
        end
    else
        ox, oy = HandleToOffsets(handle)
        handle._isAnchored = false
        handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
        if handle._border and handle._border.SetLineSize then
            handle._border:SetLineSize(HANDLE_BORDER_SIZE)
        end
    end

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

function QUI_LayoutMode:SyncElement(key)
    if not self.isActive then return end
    if not self._handles or not self._handles[key] then return end
    SyncHandle(key)
end

function QUI_LayoutMode:NudgeMover(key, dx, dy, deferPersist)
    if InCombatLockdown() then return false end

    local handle = self._handles[key]
    if not handle then return false end
    local def = self._elements[key]

    local ox, oy = HandleToOffsets(handle)
    ox = ox + dx
    oy = oy + dy

    if handle._isChildOverlay then
        SetHandleFromOffsets(handle, ox, oy)
    else
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", UIParent, "CENTER", ox, oy)

        if def then
            local frame = def.getFrame and def.getFrame()
            if frame then
                if key == "bossFrames" then
                    local cdx, cdy = 0, 0
                    if def.getCenterOffset then
                        cdx, cdy = def.getCenterOffset(handle:GetSize())
                    end
                    ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
                    ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "CENTER", handle, "CENTER", -cdx, -cdy)
                else
                    ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
                    ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "CENTER", UIParent, "CENTER", ox, oy)
                end
            end
        end
    end

    if deferPersist then
        handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
        return true
    end

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

    SavePendingPosition(key, "CENTER", "CENTER", ox, oy, anchorKey, anchorPtSelf, anchorPtTarget)

    if handle._isAnchored then
        local fa = GetFrameAnchoring()
        local entry = fa and fa[key]
        handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], entry and entry.offsetX or ox, entry and entry.offsetY or oy))
    else
        handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
    end

    return true
end

ShowSaveDiscardPopup = function()
    local ui = ns.QUI_LayoutMode_UI
    if ui and ui.ShowSaveDiscardPopup then
        ui:ShowSaveDiscardPopup()
    else
        QUI_LayoutMode:SaveAndClose()
    end
end

local function OnProfileChanged()
    if QUI_LayoutMode.isActive then
        QUI_LayoutMode._hasChanges = false
        QUI_LayoutMode._pendingPositions = {}
        QUI_LayoutMode:Close(true)
        print("|cff60A5FAQUI:|r " .. ns.L["Profile changed. Layout Mode closed — reopen to use new profile positions."])
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

    function core:RegisterEditModeEnter(callback)
        QUI_LayoutMode:RegisterEnterCallback(callback)
    end

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

do
    local function RegisterDisplayElements()
        local um = ns.QUI_LayoutMode
        if not um then return end

        local DISPLAY_ELEMENTS = {
            { key = "objectiveTracker", label = ns.L["Objective Tracker"], frame = "ObjectiveTrackerFrame", order = 2 },
            { key = "topCenterWidgets", label = ns.L["Top Center Widgets"], frame = "UIWidgetTopCenterContainerFrame", order = 14, minWidth = 160, minHeight = 24 },
            { key = "belowMinimapWidgets", label = ns.L["Below Minimap Widgets"], frame = "UIWidgetBelowMinimapContainerFrame", order = 15, minWidth = 180, minHeight = 24 },
            { key = "extraActionButton", label = ns.L["Extra Ability"],   frame = "ExtraActionBarFrame", holder = "QUI_extraActionButtonHolder", order = 5 },
            { key = "zoneAbility",     label = ns.L["Zone Ability"],      frame = "ZoneAbilityFrame",    holder = "QUI_zoneAbilityHolder",      order = 6 },
            { key = "bonusRollFrame",  label = ns.L["Bonus Roll"],        frame = "BonusRollFrame",      order = 16, minWidth = 200, minHeight = 80 },
            {
                key = "equipmentDurability",
                label = ns.L["Equipment Durability"],
                frame = "DurabilityFrame",
                order = 17,
                minWidth = 60,
                minHeight = 75,
                previewOn = function()
                    local frame = _G.DurabilityFrame
                    if not frame then return end
                    frame.isInEditMode = true
                    if frame.UpdateShownState then
                        frame:UpdateShownState()
                    else
                        frame:Show()
                    end
                end,
                previewOff = function()
                    local frame = _G.DurabilityFrame
                    if not frame then return end
                    frame.isInEditMode = false
                    if frame.UpdateShownState then
                        frame:UpdateShownState()
                    else
                        frame:Hide()
                    end
                end,
            },
        }

        for _, info in ipairs(DISPLAY_ELEMENTS) do
            local regDef = {
                key = info.key,
                label = info.label,
                group = ns.L["Display"],
                order = info.order,
                setGameplayHidden = function(hide)
                    local f = (info.holder and _G[info.holder]) or _G[info.frame]
                    if not f then return end
                    if hide then
                        f:SetAlpha(0)
                        ns.SafeCallMethod("best-effort-style", f, "EnableMouse", false)
                    else
                        f:SetAlpha(1)
                        ns.SafeCallMethod("best-effort-style", f, "EnableMouse", true)
                    end
                end,
                getFrame = function()
                    return (info.holder and _G[info.holder]) or _G[info.frame]
                end,
            }
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

        if _G.BonusRollFrame and not _G.BonusRollFrame._QUI_AnchorHooked then
            local bonusRollFrame = _G.BonusRollFrame
            bonusRollFrame._QUI_AnchorHooked = true

            local applyingBonusRollAnchor = false
            local pendingBonusRollAnchor = false
            local bonusRollAnchorScheduled = false

            local function ApplyBonusRollAnchor()
                if applyingBonusRollAnchor then return end
                if _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() then return end

                if InCombatLockdown() then
                    pendingBonusRollAnchor = true
                    return
                end

                if not _G.QUI_ApplyFrameAnchor then return end

                applyingBonusRollAnchor = true
                ns.SafeCall("bulkhead", _G.QUI_ApplyFrameAnchor, "bonusRollFrame")
                applyingBonusRollAnchor = false
            end

            local function RunScheduledBonusRollAnchor()
                bonusRollAnchorScheduled = false
                ApplyBonusRollAnchor()
            end

            local function ScheduleBonusRollAnchor()
                if applyingBonusRollAnchor then return end
                if _G.QUI_IsLayoutModeActive and _G.QUI_IsLayoutModeActive() then return end

                if InCombatLockdown() then
                    pendingBonusRollAnchor = true
                    return
                end

                if bonusRollAnchorScheduled then return end
                bonusRollAnchorScheduled = true

                if RunNextFrame then
                    RunNextFrame(RunScheduledBonusRollAnchor)
                elseif C_Timer and C_Timer.After then
                    C_Timer.After(0, RunScheduledBonusRollAnchor)
                else
                    RunScheduledBonusRollAnchor()
                end
            end

            hooksecurefunc(bonusRollFrame, "SetPoint", ScheduleBonusRollAnchor)
            hooksecurefunc(bonusRollFrame, "Show", ScheduleBonusRollAnchor)
            bonusRollFrame:HookScript("OnShow", ScheduleBonusRollAnchor)

            local bonusRollCombatFrame = CreateFrame("Frame")
            bonusRollCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            bonusRollCombatFrame:SetScript("OnEvent", function()
                if pendingBonusRollAnchor then
                    pendingBonusRollAnchor = false
                    ScheduleBonusRollAnchor()
                end
            end)

            ScheduleBonusRollAnchor()
        end

        local function ChatDB()
            local core = Helpers.GetCore()
            return core and core.db and core.db.profile and core.db.profile.chat
        end

        local function GetChatContainer()
            local D = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
            if D and D.GetContainer then
                return D.GetContainer()
            end
            return _G.QUI_CustomChatFrame
        end

        local function SetupChatWindowOverlay(overlay, frame, getFrame, persist, getTabBar)
            local extraTop = 0
            local tabBar = getTabBar and getTabBar()
            if tabBar and tabBar.GetHeight
                and (not tabBar.IsShown or tabBar:IsShown()) then
                local h = tabBar:GetHeight()
                if type(h) == "number" and h > 0 then
                    extraTop = h
                end
            end

            overlay:ClearAllPoints()
            overlay:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -4,  4 + extraTop)
            overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  4, -4)

            if not overlay._chatResizeGrips then
                RefreshAccentColor()
                overlay._chatResizeGrips = {}
                local CORNERS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }
                for _, corner in ipairs(CORNERS) do
                    local grip = CreateFrame("Button", nil, overlay)
                    grip:SetSize(20, 20)
                    grip:SetFrameLevel(overlay:GetFrameLevel() + 10)
                    grip:EnableMouse(true)

                    local insetX = (corner == "TOPLEFT" or corner == "BOTTOMLEFT") and 2 or -2
                    local insetY = (corner == "TOPLEFT" or corner == "TOPRIGHT") and -2 or 2
                    grip:ClearAllPoints()
                    grip:SetPoint(corner, overlay, corner, insetX, insetY)

                    local barH = grip:CreateTexture(nil, "OVERLAY")
                    barH:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                    barH:SetSize(18, 3)
                    barH:SetPoint(corner, 0, 0)

                    local barV = grip:CreateTexture(nil, "OVERLAY")
                    barV:SetColorTexture(ACCENT_R, ACCENT_G, ACCENT_B, 0.9)
                    barV:SetSize(3, 18)
                    barV:SetPoint(corner, 0, 0)

                    local hl = grip:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetColorTexture(1, 1, 1, 0.35)
                    hl:SetAllPoints()
                    hl:SetBlendMode("ADD")

                    local tooltipAnchor = (corner == "TOPLEFT" or corner == "BOTTOMLEFT")
                        and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT"
                    grip:SetScript("OnEnter", function(self)
                        if GameTooltip then
                            GameTooltip:SetOwner(self, tooltipAnchor)
                            if QUI_LayoutMode:IsElementAnchored(overlay._barKey) then
                                GameTooltip:SetText(ns.L["Hold Shift to resize (anchored)"])
                            else
                                GameTooltip:SetText(ns.L["Drag to resize chat frame"])
                            end
                            GameTooltip:Show()
                        end
                    end)
                    grip:SetScript("OnLeave", function()
                        if GameTooltip then GameTooltip:Hide() end
                    end)
                    grip:SetScript("OnMouseDown", function(_, button)
                        if button ~= "LeftButton" then return end
                        if not QUI_LayoutMode.isActive then return end
                        if InCombatLockdown and InCombatLockdown() then return end
                        local key = overlay._barKey
                        if key and QUI_LayoutMode:IsElementAnchored(key) then
                            if not IsShiftKeyDown() then
                                QUI_LayoutMode:FlashLockedHandle(key)
                                return
                            end
                            QUI_LayoutMode:DetachElementAnchor(key)
                        end
                        local f = getFrame()
                        if not f then return end
                        if f.SetResizable and f.IsResizable and not f:IsResizable() then
                            f:SetResizable(true)
                        end
                        f:StartSizing(corner)
                    end)
                    grip:SetScript("OnMouseUp", function(_, button)
                        if button ~= "LeftButton" then return end
                        if not QUI_LayoutMode.isActive then return end
                        local f = getFrame()
                        if f then
                            f:StopMovingOrSizing()
                            persist()
                            QUI_LayoutMode:RecordFreeElementPosition(overlay._barKey, f)
                        end
                        local U = ns.QUI_LayoutMode_Utils
                        if U and U.RefreshActiveSizeSliders then
                            U.RefreshActiveSizeSliders()
                        end
                    end)

                    overlay._chatResizeGrips[corner] = grip
                end
            end
        end

        local function PersistPrimaryChatGeometry()
            local D = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
            if D and D.PersistGeometry then D.PersistGeometry() end
        end

        um:RegisterElement({
            key = "chatFrame1",
            label = ns.L["Chat Frame"],
            group = ns.L["Display"],
            order = 7,
            isOwned = true,
            setGameplayHidden = function(hide)
                local f = GetChatContainer()
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
                return GetChatContainer()
            end,
            setupOverlay = function(overlay, frame)
                SetupChatWindowOverlay(overlay, frame,
                    GetChatContainer,
                    PersistPrimaryChatGeometry,
                    function() return _G.QUI_CustomChatTabBar end)
            end,
            onOpen = function()
                C_Timer.After(0, function()
                    local f = GetChatContainer()
                    if f and f.SetClampedToScreen then f:SetClampedToScreen(false) end
                end)
            end,
            onClose = function()
                local f = GetChatContainer()
                if f and f.SetClampedToScreen then f:SetClampedToScreen(true) end
            end,
        })

        local CHAT_WINDOW_LAYOUT_FEATURE_ID = "chatWindowLayout"
        do
            local Settings       = ns.Settings
            local Registry       = Settings and Settings.Registry
            local Schema         = Settings and Settings.Schema
            local RenderAdapters = Settings and Settings.RenderAdapters
            if Registry and Schema and RenderAdapters
                and type(Registry.RegisterFeature) == "function"
                and type(Schema.Feature) == "function"
                and type(RenderAdapters.RenderPositionOnly) == "function" then
                Registry:RegisterFeature(Schema.Feature({
                    id     = CHAT_WINDOW_LAYOUT_FEATURE_ID,
                    render = {
                        layout = function(host, options)
                            local providerKey = options and options.providerKey
                            if type(providerKey) ~= "string" or providerKey == "" then
                                return 80
                            end

                            local U = ns.QUI_LayoutMode_Utils
                            local windowID = tonumber(providerKey:match("^chatWindow(%d+)$"))
                            local D = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
                            local container = windowID and D and D.GetContainer
                                and D.GetContainer(windowID)

                            if not container or not U
                                or type(U.BuildPositionCollapsible) ~= "function"
                                or type(U.BuildSizeCollapsible) ~= "function"
                                or type(U.StandardRelayout) ~= "function" then
                                return RenderAdapters.RenderPositionOnly(host, providerKey)
                            end

                            local function getSize()
                                local w, h = container:GetWidth(), container:GetHeight()
                                if type(w) ~= "number" then w = 220 end
                                if type(h) ~= "number" then h = 100 end
                                return math.floor(w + 0.5), math.floor(h + 0.5)
                            end

                            local function setSize(w, h)
                                if type(w) ~= "number" or type(h) ~= "number" then return end
                                w = math.max(220, math.min(1400, math.floor(w + 0.5)))
                                h = math.max(100, math.min(900, math.floor(h + 0.5)))
                                container:SetSize(w, h)
                                if D.PersistGeometry then D.PersistGeometry(windowID) end
                                if _G.QUI_ReassertAnchorAfterResize then
                                    _G.QUI_ReassertAnchorAfterResize(providerKey)
                                end
                            end

                            local prevPosOnly = U._layoutModePositionOnly
                            U._layoutModePositionOnly = false
                            local sections = {}
                            local function relayout() U.StandardRelayout(host, sections) end
                            local ok, err = xpcall(function()
                                U.BuildPositionCollapsible(host, providerKey, nil, sections, relayout)
                                U.BuildSizeCollapsible(host, {
                                    getSize = getSize,
                                    setSize = setSize,
                                    minW = 220, maxW = 1400,
                                    minH = 100, maxH = 900,
                                    widthDescription  = "Chat window width in pixels.",
                                    heightDescription = "Chat window height in pixels.",
                                }, sections, relayout)
                                relayout()
                            end, function(msg) return msg end)
                            U._layoutModePositionOnly = prevPosOnly
                            if not ok and geterrorhandler then geterrorhandler()(err) end
                            return host:GetHeight()
                        end,
                    },
                }))
            end
        end

        local registeredChatWindowKeys = {}
        function um:SyncChatWindowElements()
            local D = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.DisplayLayer
            local count = (D and D.GetWindowCount and D.GetWindowCount()) or 0
            local registered = 0
            for _ in pairs(registeredChatWindowKeys) do
                registered = registered + 1
            end
            if registered == math.max(count - 1, 0) then return end
            for key in pairs(registeredChatWindowKeys) do
                um:UnregisterElement(key)
                registeredChatWindowKeys[key] = nil
            end
            if not (D and D.GetContainer) then return end
            for i = 2, count do
                local windowID = i
                local key = "chatWindow" .. windowID
                local function getFrame()
                    return D.GetContainer(windowID)
                end
                local function persist()
                    if D.PersistGeometry then D.PersistGeometry(windowID) end
                end
                um:RegisterElement({
                    key = key,
                    label = ns.L["Chat Window "] .. windowID,
                    group = ns.L["Display"],
                    order = 7 + windowID,
                    isOwned = true,
                    isEnabled = function()
                        local db = ChatDB()
                        return db and db.enabled ~= false
                    end,
                    setGameplayHidden = function(hide)
                        local f = getFrame()
                        if not f then return end
                        if hide then
                            f:SetAlpha(0)
                            f:EnableMouse(false)
                        else
                            f:SetAlpha(1)
                            f:EnableMouse(true)
                        end
                    end,
                    getFrame = getFrame,
                    setupOverlay = function(overlay, frame)
                        SetupChatWindowOverlay(overlay, frame, getFrame, persist,
                            function()
                                local TabUI = ns.QUI and ns.QUI.Chat and ns.QUI.Chat.TabUI
                                return TabUI and TabUI.GetBar and TabUI.GetBar(windowID)
                            end)
                    end,
                    onOpen = function()
                        C_Timer.After(0, function()
                            local f = getFrame()
                            if f and f.SetClampedToScreen then f:SetClampedToScreen(false) end
                        end)
                    end,
                    onClose = function()
                        local f = getFrame()
                        if f and f.SetClampedToScreen then f:SetClampedToScreen(true) end
                    end,
                })
                registeredChatWindowKeys[key] = true

                if _G.QUI_RegisterFrameResolver then
                    _G.QUI_RegisterFrameResolver(key, {
                        resolver    = getFrame,
                        displayName = "Chat Window " .. windowID,
                        category    = "Display",
                        order       = 7 + windowID,
                    })
                end

                local Registry = ns.Settings and ns.Settings.Registry
                if Registry and type(Registry.RegisterLookupKey) == "function" then
                    Registry:RegisterLookupKey(CHAT_WINDOW_LAYOUT_FEATURE_ID, key)
                end

                if _G.QUI_ApplyFrameAnchor and not QUI_LayoutMode.isActive then
                    _G.QUI_ApplyFrameAnchor(key)
                end
            end
        end
        um:SyncChatWindowElements()
    end

    C_Timer.After(2, RegisterDisplayElements)
end

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

        local function ModuleDB(key)
            local db = GetProfileDB()
            return db and db[key]
        end

        local function GeneralSubDB(subKey)
            local db = GetProfileDB()
            return db and db.general and db.general[subKey]
        end

        local function AlertAnchorsEnabled()
            local db = GetProfileDB()
            local general = db and db.general
            return general and (general.skinAlerts ~= false or general.controlAlertAnchors == true)
        end

        local function SetAlertAnchorsEnabled(val)
            local db = GetProfileDB()
            local general = db and db.general
            if not general then return end
            general.controlAlertAnchors = val and true or false
        end

        local QOL_ELEMENTS = {
            {
                key = "buffFrame", label = ns.L["Buff Frame"], group = ns.L["Display"], order = 3,
                frame = "QUI_BuffIconContainer", isOwned = true,
                dbKey = "buffBorders", enabledField = "enableBuffs",
                refresh = "QUI_RefreshBuffBorders",
                getFrame = function() return _G["QUI_BuffIconContainer"] end,
                getSize = function()
                    local f = _G["QUI_BuffIconContainer"]
                    if f then return f._naturalW, f._naturalH end
                end,
                previewOn  = function() if _G.QUI_BuffBordersShowPreview then _G.QUI_BuffBordersShowPreview() end end,
                previewOff = function() if _G.QUI_BuffBordersHidePreview then _G.QUI_BuffBordersHidePreview() end end,
            },
            {
                key = "debuffFrame", label = ns.L["Debuff Frame"], group = ns.L["Display"], order = 4,
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
                key = "crosshair", label = ns.L["Crosshair"], group = ns.L["QoL"], order = 1,
                frame = "QUI_Crosshair",
                dbKey = "crosshair", enabledField = "enabled",
                refresh = "QUI_RefreshCrosshair",
            },
            {
                key = "skyriding", label = ns.L["Skyriding HUD"], group = ns.L["QoL"], order = 2,
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
                    local db = ModuleDB("skyriding")
                    if db then
                        local swMode = db.secondWindMode or "MINIBAR"
                        if swMode == "MINIBAR" then
                            h = h + 2 + (db.secondWindHeight or 20)
                        elseif swMode == "PIPS" then
                            h = h + 3 + 6 * (db.secondWindScale or 2.1)
                        elseif swMode == "TEXT" then
                            h = h + 12
                        end
                    end
                    return w, h
                end,
                getCenterOffset = function()
                    local db = ModuleDB("skyriding")
                    if not db then return 0, 0 end
                    local swMode = db.secondWindMode or "MINIBAR"
                    if swMode == "MINIBAR" then
                        local extra = 2 + (db.secondWindHeight or 20)
                        return 0, -(extra / 2)
                    elseif swMode == "PIPS" then
                        local extra = 3 + 6 * (db.secondWindScale or 2.1)
                        return 0, extra / 2
                    elseif swMode == "TEXT" then
                        return 0, -6
                    end
                    return 0, 0
                end,
            },
            {
                key = "xpTracker", label = ns.L["XP Tracker"], group = ns.L["QoL"], order = 3,
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
                key = "combatTimer", label = ns.L["Combat Timer"], group = ns.L["Instance"], order = 3,
                frame = "QUI_CombatTimer",
                dbKey = "combatTimer", enabledField = "enabled",
                refresh = "QUI_RefreshCombatTimer",
                previewOn  = function() if _G.QUI_ToggleCombatTimerPreview then _G.QUI_ToggleCombatTimerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleCombatTimerPreview then _G.QUI_ToggleCombatTimerPreview(false) end end,
            },
            {
                key = "lustTimer", label = ns.L["Lust Timer"], group = ns.L["QoL"], order = 4,
                frame = "QUI_LustTimer",
                dbKey = "lustTimer", enabledField = "enabled",
                refresh = "QUI_RefreshLustTimer",
                previewOn  = function() if _G.QUI_ToggleLustTimerPreview then _G.QUI_ToggleLustTimerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleLustTimerPreview then _G.QUI_ToggleLustTimerPreview(false) end end,
            },
            {
                key = "brezCounter", label = ns.L["Brez Counter"], group = ns.L["Instance"], order = 1,
                frame = "QUI_BrezCounter",
                dbKey = "brzCounter", enabledField = "enabled",
                refresh = "QUI_RefreshBrezCounter",
                previewOn  = function() if _G.QUI_ToggleBrezCounterPreview then _G.QUI_ToggleBrezCounterPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleBrezCounterPreview then _G.QUI_ToggleBrezCounterPreview(false) end end,
            },
            {
                key = "atonementCounter", label = ns.L["Atonement Counter"], group = ns.L["QoL"], order = 9.5,
                frame = "QUI_AtonementCounter",
                dbKey = "atonementCounter", enabledField = "enabled",
                refresh = "QUI_RefreshAtonementCounter",
                previewOn  = function() if _G.QUI_ToggleAtonementCounterPreview then _G.QUI_ToggleAtonementCounterPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleAtonementCounterPreview then _G.QUI_ToggleAtonementCounterPreview(false) end end,
            },
            {
                key = "mplusTimer", label = ns.L["M+ Timer"], group = ns.L["Instance"], order = 2,
                frame = "QUI_MPlusTimerFrame",
                dbKey = "mplusTimer", enabledField = "enabled",
                setupOverlay = function(overlay, targetFrame)
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints(targetFrame)
                end,
                previewOn  = function() local t = _G.QUI_MPlusTimer; if t and t.EnableDemoMode then t:EnableDemoMode() end end,
                previewOff = function() local t = _G.QUI_MPlusTimer; if t and t.DisableDemoMode then t:DisableDemoMode() end end,
            },
            {
                key = "rangeCheck", label = ns.L["Range Check"], group = ns.L["QoL"], order = 5,
                frame = "QUI_RangeCheckFrame",
                dbKey = "rangeCheck", enabledField = "enabled",
                refresh = "QUI_RefreshRangeCheck",
                previewOn  = function() if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleRangeCheckPreview then _G.QUI_ToggleRangeCheckPreview(false) end end,
            },
            {
                key = "actionTracker", label = ns.L["Action Tracker"], group = ns.L["QoL"], order = 6,
                frame = "QUI_ActionTracker",
                dbGetter = function() return GeneralSubDB("actionTracker") end,
                enabledField = "enabled",
                refresh = "QUI_RefreshActionTracker",
                previewOn  = function() if _G.QUI_ToggleActionTrackerPreview then _G.QUI_ToggleActionTrackerPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleActionTrackerPreview then _G.QUI_ToggleActionTrackerPreview(false) end end,
            },
            {
                key = "focusCastAlert", label = ns.L["Focus Cast Alert"], group = ns.L["QoL"], order = 7,
                frame = "QUI_FocusCastAlertFrame",
                dbGetter = function() return GeneralSubDB("focusCastAlert") end,
                enabledField = "enabled",
                refresh = "QUI_RefreshFocusCastAlert",
                previewOn  = function() if _G.QUI_ToggleFocusCastAlertPreview then _G.QUI_ToggleFocusCastAlertPreview(true) end end,
                previewOff = function() if _G.QUI_ToggleFocusCastAlertPreview then _G.QUI_ToggleFocusCastAlertPreview(false) end end,
            },
            {
                key = "petWarning", label = ns.L["Pet Warning"], group = ns.L["QoL"], order = 8,
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
                key = "noTargetWarning", label = ns.L["No Target Warning"], group = ns.L["QoL"], order = 8.5,
                frame = "QUI_NoTargetWarningFrame",
                dbGetter = function() return GeneralSubDB("noTargetWarning") end,
                enabledField = "enabled",
                previewOn  = function() if ns.ToggleNoTargetWarningPreview then ns.ToggleNoTargetWarningPreview(true) end end,
                previewOff = function() if ns.ToggleNoTargetWarningPreview then ns.ToggleNoTargetWarningPreview(false) end end,
            },
            {
                key = "healerMana", label = ns.L["Healer Mana"], group = ns.L["QoL"], order = 8.6,
                frame = "QUI_HealerManaFrame",
                dbGetter = function() return GeneralSubDB("healerMana") end,
                enabledField = "enabled",
                previewOn  = function() if ns.ToggleHealerManaPreview then ns.ToggleHealerManaPreview(true) end end,
                previewOff = function() if ns.ToggleHealerManaPreview then ns.ToggleHealerManaPreview(false) end end,
            },
            {
                key = "deathAlert", label = ns.L["Death Alert"], group = ns.L["QoL"], order = 8.7,
                frame = "QUI_DeathAlertFrame",
                dbGetter = function() return GeneralSubDB("deathAlert") end,
                enabledField = "enabled",
                previewOn  = function() if ns.ToggleDeathAlertPreview then ns.ToggleDeathAlertPreview(true) end end,
                previewOff = function() if ns.ToggleDeathAlertPreview then ns.ToggleDeathAlertPreview(false) end end,
            },
            {
                key = "preyTracker", label = ns.L["Prey Tracker"], group = ns.L["QoL"], order = 9,
                frame = "QUI_PreyTracker",
                dbKey = "preyTracker", enabledField = "enabled",
                refresh = "QUI_RefreshPreyTracker",
                previewOn  = function() if _G.QUI_TogglePreyTrackerPreview then _G.QUI_TogglePreyTrackerPreview(true) end end,
                previewOff = function() if _G.QUI_TogglePreyTrackerPreview then _G.QUI_TogglePreyTrackerPreview(false) end end,
            },
            {
                key = "incomingCasts", label = ns.L["Incoming Casts"], group = ns.L["QoL"], order = 9.2,
                frame = "QUI_IncomingCasts",
                dbKey = "incomingCasts", enabledField = "enabled",
                refresh = function() local ic = ns.QUI_IncomingCasts; if ic then ic.Refresh() end end,
                previewOn  = function() local ic = ns.QUI_IncomingCasts; if ic and ic.EnablePreview then ic.EnablePreview() end end,
                previewOff = function() local ic = ns.QUI_IncomingCasts; if ic and ic.DisablePreview then ic.DisablePreview() end end,
            },
            {
                key = "readyCheck", label = ns.L["Ready Check"], group = ns.L["Instance"], order = 4,
                frame = nil,
                blizzFrame = "ReadyCheckFrame",
                dbGetter = function()
                    local db = GetProfileDB()
                    return db and db.general
                end,
                enabledField = "skinReadyCheck",
            },
            {
                key = "consumables", label = ns.L["Consumable Check"], group = ns.L["Instance"], order = 4.5,
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
                key = "missingRaidBuffs", label = ns.L["Missing Raid Buffs"], group = ns.L["Instance"], order = 5,
                frame = "QUI_MissingRaidBuffs",
                dbKey = "raidBuffs", enabledField = "enabled",
                refresh = "QUI_RefreshRaidBuffs",
                previewOn  = function() local r = ns.RaidBuffs; if r and r.EnablePreview then r:EnablePreview() end end,
                previewOff = function() local r = ns.RaidBuffs; if r and r.DisablePreview then r:DisablePreview() end end,
            },
            {
                key = "rotationAssistIcon", label = ns.L["Rotation Assist Icon"], group = ns.L["Cooldown Manager & Custom Tracker Bars"], order = 5,
                frame = "QUI_RotationAssistIcon",
                dbKey = "rotationAssistIcon", enabledField = "enabled",
                refresh = "QUI_RefreshRotationAssistIcon",
            },
            {
                key = "totemBar", label = ns.L["Totem Bar"], group = ns.L["Action Bars"], order = 20,
                frame = "QUI_TotemBar",
                dbKey = "totemBar", enabledField = "enabled",
                refresh = "QUI_RefreshTotemBar",
                previewOn  = function() if _G.QUI_ShowTotemBarPreview then _G.QUI_ShowTotemBarPreview() end end,
                previewOff = function() if _G.QUI_HideTotemBarPreview then _G.QUI_HideTotemBarPreview() end end,
            },
            {
                key = "raidMarkersBar", label = ns.L["Raid Markers Bar"], group = ns.L["Action Bars"], order = 21,
                frame = "QUI_RaidMarkersBar",
                dbKey = "raidMarkersBar", enabledField = "enabled",
                refresh = "QUI_RefreshRaidMarkersBar",
                previewOn  = function() if _G.QUI_ShowRaidMarkersBarPreview then _G.QUI_ShowRaidMarkersBarPreview() end end,
                previewOff = function() if _G.QUI_HideRaidMarkersBarPreview then _G.QUI_HideRaidMarkersBarPreview() end end,
            },
            {
                key = "partyKeystones", label = ns.L["Party Keystones"], group = ns.L["Instance"], order = 6,
                frame = "QUIKeyTrackerFrame",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "keyTrackerEnabled",
                refresh = "QUI_RefreshKeyTracker",
            },
            {
                key = "lootFrame", label = ns.L["Loot Frame"], group = ns.L["Display"], order = 7,
                frame = "QUI_LootFrame",
                dbKey = "loot", enabledField = "enabled",
                requiresReload = true,
            },
            {
                key = "lootRollAnchor", label = ns.L["Loot Roll Anchor"], group = ns.L["Display"], order = 8,
                frame = "QUI_LootRollAnchor",
                dbKey = "lootRoll", enabledField = "enabled",
                requiresReload = true,
            },
            {
                key = "alertAnchor", label = ns.L["Alert Anchor"], group = ns.L["Display"], order = 9,
                frame = "QUI_AlertFrameHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
                isEnabled = AlertAnchorsEnabled,
                setEnabled = SetAlertAnchorsEnabled,
            },
            {
                key = "toastAnchor", label = ns.L["Toast Anchor"], group = ns.L["Display"], order = 10,
                frame = "QUI_EventToastHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
                isEnabled = AlertAnchorsEnabled,
                setEnabled = SetAlertAnchorsEnabled,
            },
            {
                key = "bnetToastAnchor", label = ns.L["BNet Toast Anchor"], group = ns.L["Display"], order = 11,
                frame = "QUI_BNetToastHolder",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinAlerts",
                isEnabled = AlertAnchorsEnabled,
                setEnabled = SetAlertAnchorsEnabled,
            },
            {
                key = "powerBarAlt", label = ns.L["Encounter Power Bar"], group = ns.L["Display"], order = 12,
                frame = "QUI_AltPowerBar",
                dbGetter = function() return GetProfileDB() and GetProfileDB().general end,
                enabledField = "skinPowerBarAlt",
            },
            {
                key = "tooltipAnchor", label = ns.L["Tooltip Anchor"], group = ns.L["Display"], order = 13,
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
                isEnabled = info.isEnabled or function()
                    local db = GetDB()
                    return db and db[info.enabledField] ~= false
                end,
                setEnabled = info.setEnabled or function(val)
                    local db = GetDB()
                    if not db then return end
                    local old = db[info.enabledField]
                    db[info.enabledField] = val
                    local changed = (old ~= false) ~= (val ~= false)
                    if changed and info.requiresReload then
                        local GUI = QUI and QUI.GUI
                        if GUI then
                            GUI:ShowConfirmation({
                                title = ns.L["Reload UI?"],
                                message = ns.L["This change requires a reload to take effect."],
                                acceptText = ns.L["Reload"],
                                cancelText = ns.L["Later"],
                                onAccept = function() QUI:SafeReload() end,
                            })
                        end
                    end
                    if type(info.refresh) == "function" then
                        info.refresh()
                    elseif info.refresh and _G[info.refresh] then
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

function QUI_LayoutMode:ToggleHandlePreview(key)
    if not self.isActive then return false end
    local def = self._elements[key]
    if not def then return false end

    local hidden = GetHiddenHandlesDB()
    local handle = self._handles[key]

    if handle and handle:IsShown() then
        RestoreTargetFrame(handle, def)
        if key == "bossFrames" then
            if handle._savedBossParents then
                local QUI_UF = ns.QUI_UnitFrames
                local bossFrames = QUI_UF and QUI_UF.frames
                if bossFrames then
                    for i, savedParent in pairs(handle._savedBossParents) do
                        local bf = bossFrames["boss" .. i]
                        if bf then
                            ns.SafeCallMethod("best-effort-style", bf, "SetParent", savedParent)
                            if _G.QUI_SetFrameLayoutOwned then
                                _G.QUI_SetFrameLayoutOwned(bf, nil)
                            end
                        end
                    end
                end
                handle._savedBossParents = nil
            end
            if handle._savedCastbarParents then
                local castbars = ns.QUI_Castbar and ns.QUI_Castbar.castbars
                if castbars then
                    for i, savedParent in pairs(handle._savedCastbarParents) do
                        local cb = castbars["boss" .. i]
                        if cb then ns.SafeCallMethod("best-effort-style", cb, "SetParent", savedParent) end
                    end
                end
                handle._savedCastbarParents = nil
            end
        end
        handle:Hide()
        if hidden then hidden[key] = true end
        if self._selectedKey == key then
            self:SelectMover(nil)
        end
        if def.onClose then ns.SafeCall("bulkhead", def.onClose) end
        return false
    else
        if hidden then hidden[key] = nil end
        if def.onOpen then ns.SafeCall("bulkhead", def.onOpen) end
        if not handle then
            handle = CreateHandle(def)
            self._handles[key] = handle
        end
        SyncHandle(key)
        handle:Show()

        if handle._isChildOverlay and not handle:IsVisible() then
            handle:Hide()
            handle:SetParent(nil)
            handle = CreateProxyMover(def)
            self._handles[key] = handle
            SyncHandle(key)
            handle:Show()
        end

        C_Timer.After(0, function()
            if not handle:IsShown() then return end
            if handle._isChildOverlay then return end
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
                if def.getCenterOffset then
                    local cdx, cdy = def.getCenterOffset(handle:GetSize())
                    targetFrame:SetPoint("CENTER", handle, "CENTER", -cdx, -cdy)
                else
                    targetFrame:SetAllPoints(handle)
                end
                if key == "bossFrames" then
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
                                if _G.QUI_SetFrameLayoutOwned then
                                    _G.QUI_SetFrameLayoutOwned(bf, key)
                                end
                            end
                        end
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
            end
        end)
        return true
    end
end

function QUI_LayoutMode:SetHandlePreviewVisible(key, shouldShow)
    if not self.isActive then return false end
    if not self:IsElementEnabled(key) then return false end

    local isShown = self:IsHandleShown(key)
    if isShown == shouldShow then
        return isShown
    end

    return self:ToggleHandlePreview(key)
end

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

function QUI_LayoutMode:SoloHandlePreview(key)
    if not self.isActive then return false end
    if not self:IsElementEnabled(key) then return false end

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

function QUI_LayoutMode:ClearHiddenState(key)
    local hidden = GetHiddenHandlesDB()
    if hidden then hidden[key] = nil end
end

function QUI_LayoutMode:IsHandleShown(key)
    if self.isActive then
        local handle = self._handles[key]
        return handle ~= nil and handle:IsShown()
    end
    local hidden = GetHiddenHandlesDB()
    return not (hidden and hidden[key])
end

function QUI_LayoutMode:ResetToCenter(key)
    if not self.isActive then return end
    local def = self._elements[key]
    if not def then return end

    local handle = self._handles[key]
    if not handle then
        handle = CreateHandle(def)
        self._handles[key] = handle
    end

    SavePendingPosition(key, "CENTER", "CENTER", 0, 0)

    SetHandleFromOffsets(handle, 0, 0)
    if not handle._isChildOverlay then
        local frame = def.getFrame and def.getFrame()
        if frame then
            ns.SafeCallMethod("best-effort-style", frame, "ClearAllPoints")
            ns.SafeCallMethod("best-effort-style", frame, "SetPoint", "CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    if handle._coords then
        handle._coords:SetText(ns.L["X: 0  Y: 0"])
    end
    if not handle:IsShown() then
        handle:Show()
    end

    SyncHandle(key)
end

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

_G.QUI_IsLayoutModeManaged = function(key)
    if not QUI_LayoutMode.isActive then return false end
    if QUI_LayoutMode._handles[key] then return true end
    if QUI_LayoutMode._enterCallbacksRunning and QUI_LayoutMode._elements[key] then
        return true
    end
    return false
end

_G.QUI_LayoutModeSyncHandle = function(key)
    if QUI_LayoutMode.isActive and SyncHandle then
        SyncHandle(key)
    end
end

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

_G.QUI_LayoutModeSaveCurrentHandlePosition = function(key)
    if not QUI_LayoutMode.isActive or not key then return end
    local handle = QUI_LayoutMode._handles and QUI_LayoutMode._handles[key]
    if not handle then return end

    local def = QUI_LayoutMode._elements and QUI_LayoutMode._elements[key]
    local ox, oy = HandleToOffsets(handle)

    local anchorKey, anchorPtSelf, anchorPtTarget
    if not (def and def.usesCustomPositionPersistence) then
        local pending = QUI_LayoutMode._pendingPositions[key]
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

    SavePendingPosition(key, "CENTER", "CENTER", ox, oy, anchorKey, anchorPtSelf, anchorPtTarget)

    if handle._coords then
        if anchorKey then
            local fa = GetFrameAnchoring()
            local entry = fa and fa[key]
            handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], entry and entry.offsetX or ox, entry and entry.offsetY or oy))
        else
            handle._coords:SetText(string.format(ns.L["X: %d  Y: %d"], ox, oy))
        end
    end
end

_G.QUI_LayoutModeMarkChanged = function()
    if QUI_LayoutMode.isActive then
        QUI_LayoutMode._hasChanges = true
    end
end

_G.QUI_LayoutModeClearPending = function(key)
    if QUI_LayoutMode.isActive and key then
        QUI_LayoutMode._pendingPositions[key] = nil
    end
end

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

HookRefreshForLayoutSync("QUI_RefreshUnitFrames")
HookRefreshForLayoutSync("QUI_RefreshCastbar")
HookRefreshForLayoutSync("QUI_RefreshCastbars")

C_Timer.After(1, function()
    HookRefreshForLayoutSync("QUI_RefreshNCDM")
    HookRefreshForLayoutSync("QUI_RefreshCDMBuffLayout")
    HookRefreshForLayoutSync("QUI_RefreshCustomTrackers")
    HookRefreshForLayoutSync("QUI_RefreshBrezCounter")
    HookRefreshForLayoutSync("QUI_RefreshAtonementCounter")
    HookRefreshForLayoutSync("QUI_RefreshCombatTimer")
    HookRefreshForLayoutSync("QUI_RefreshXPTracker")
    HookRefreshForLayoutSync("QUI_RefreshBuffBorders")
end)

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
