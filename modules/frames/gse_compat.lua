--[[
    QUI GSE Action Bar Compatibility

    GSE identifies override-capable action buttons by global name prefix
    (ActionButton, MultiBarBottomLeftButton, BT4, ElvUI, Dominos, ...).
    QUI's native engine creates buttons named QUI_Bar<N>Button<i> /
    QUI_PetButton<i> / QUI_StanceButton<i>, none of which match GSE's
    prefix table, so GSE falls into its generic third-party branch and
    applies an OnEnter WrapScript that is restricted on ActionButtonTemplate
    in modern WoW — the override install errors and the button never fires
    the GSE sequence.

    This shim intercepts GSE.CreateActionBarOverride / RemoveActionBarOverride
    for QUI-owned buttons and installs the equivalent secure OnClick WrapScript
    ourselves (OnClick WrapScript IS allowed on ActionButtonTemplate; only
    OnEnter WrapScript is blocked — confirmed by GSE's own Events.lua:532
    comment).  OnEnter tooltip/type-correction is handled via a non-secure
    HookScript.  QUI-button overrides are persisted in our own AceDB table
    and re-applied on login / spec change, so GSE's LoadOverrides loop never
    touches them.
]]

local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local GetCore = Helpers and Helpers.GetCore

local pairs = pairs
local type = type
local tonumber = tonumber
local string_gmatch = string.gmatch
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local GetActionTexture = GetActionTexture
local GetMacroIndexByName = GetMacroIndexByName
local GetMacroInfo = GetMacroInfo

---------------------------------------------------------------------------
-- Button name classification
---------------------------------------------------------------------------

local function IsQUIButtonName(name)
    if type(name) ~= "string" then return false end
    if name:match("^QUI_Bar[1-8]Button%d+$") then return true end
    if name:match("^QUI_PetButton%d+$") then return true end
    if name:match("^QUI_StanceButton%d+$") then return true end
    return false
end

---------------------------------------------------------------------------
-- Secure handler + snippets
--
-- BAR_SWAP_OAC / BAR_SWAP_ONCLICK mirror GSE's equivalent snippets: they
-- flip between type="click" (fire GSE sequence) and type="action" (let a
-- vehicle/override/possession bar handle the slot).  Kept behaviourally
-- identical so vehicle transitions work the same on QUI buttons as on
-- native Blizzard bars.
---------------------------------------------------------------------------

local SHBT
local function GetSHBT()
    if not SHBT then
        SHBT = CreateFrame("Frame", "QUI_GSECompatSecureHandler", nil,
            "SecureHandlerBaseTemplate,SecureFrameTemplate")
    end
    return SHBT
end

local BAR_SWAP_OAC = [[
    if name ~= "action" and name ~= "pressandholdaction" then return end
    if not self:GetAttribute("gse-button") then return end
    local slot = self:GetID()
    local page = slot > 0 and self:GetEffectiveAttribute("actionpage") or nil
    local effectiveAction = (slot == 0 or not page) and self:GetEffectiveAttribute("action")
                            or (page and (slot + page * 12 - 12)) or nil
    if effectiveAction then
        local at = GetActionInfo(effectiveAction)
        if at == nil or at == "macro" then
            self:SetAttribute("type", "click")
        else
            self:SetAttribute("type", "action")
        end
    end
]]

local BAR_SWAP_ONCLICK = [[
    local gseButton = self:GetAttribute('gse-button')
    if gseButton then
        local slot = self:GetID()
        local page = slot > 0 and self:GetEffectiveAttribute("actionpage") or nil
        local effectiveAction = (slot == 0 or not page) and self:GetEffectiveAttribute("action")
                                or (page and (slot + page * 12 - 12)) or nil
        if effectiveAction then
            local at = GetActionInfo(effectiveAction)
            if at == nil or at == "macro" then
                self:SetAttribute('type', 'click')
            else
                self:SetAttribute('type', 'action')
            end
        end
    else
        self:SetAttribute('type', 'action')
    end
]]

---------------------------------------------------------------------------
-- Icon management
--
-- GSE's icon helpers (getGSEButtonIcon, addGSEWatermark,
-- hookButtonIconUpdates, scheduleIconRestore) are local to Events.lua
-- and never run for QUI buttons because our shim intercepts
-- CreateActionBarOverride before overrideActionButton is reached.
-- We replicate the essential behaviour here.
---------------------------------------------------------------------------

local watermarkedButtons = {}   -- [buttonName] = texture region
local iconHookedButtons = {}    -- [buttonName] = true

--- Resolve the effective action slot for a QUI button.
local function GetButtonEffectiveSlot(btn)
    local action = tonumber(btn:GetAttribute("action"))
    if action and action > 0 then return action end
    local slot = btn:GetID()
    if not slot or slot == 0 then return nil end
    local page = tonumber(btn:GetAttribute("actionpage")) or 1
    return slot + (page - 1) * 12
end

--- Return the display icon for a GSE-overridden button.
local function GetGSEButtonIcon(btn)
    local effectiveSlot = GetButtonEffectiveSlot(btn)
    if effectiveSlot and GetActionTexture then
        local texture = GetActionTexture(effectiveSlot)
        if texture then return texture end
    end
    if not GetMacroIndexByName then return nil end
    local seq = btn:GetAttribute("gse-button")
    if not seq then return nil end
    local idx = GetMacroIndexByName(seq)
    if not idx or idx == 0 then return nil end
    local _, texture = GetMacroInfo(idx)
    return texture
end

--- Resolve the button's icon texture child.
local function GetButtonIcon(btn, buttonName)
    return btn.icon or (buttonName and _G[buttonName .. "Icon"])
end

--- Defer icon restore one frame so WoW's own ActionButton_Update runs first.
local function ScheduleIconRestore(btn, icon)
    C_Timer.After(0, function()
        if not btn:GetAttribute("gse-button") then return end
        local texture = GetGSEButtonIcon(btn)
        if texture then
            icon:SetTexture(texture)
            icon:Show()
            return
        end
        local seq = btn:GetAttribute("gse-button")
        if seq and _G[seq] and GSE and GSE.UpdateIcon then
            GSE.UpdateIcon(_G[seq], false)
        end
    end)
end

--- Show GSE spell tooltip for an overridden button.
local function ShowGSEButtonTooltip(btn)
    if not btn or not btn.GetAttribute then return end
    local seqName = btn:GetAttribute("gse-button")
    if not seqName then return end
    local seqFrame = _G[seqName]
    if not seqFrame or not GSE or not GSE.SequencesExec then return end
    local step = seqFrame:GetAttribute("step") or 1
    local executionseq = GSE.SequencesExec[seqName]
    if not executionseq or not executionseq[step] then return end
    local entry = executionseq[step]
    local spellID
    if entry.type == "spell" and entry.spell and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(GSE.UnEscapeString(entry.spell))
        spellID = info and info.spellID
    elseif entry.type == "macro" and entry.macrotext then
        local info = GSE.GetSpellsFromString and GSE.GetSpellsFromString(entry.macrotext)
        if info then
            spellID = info.spellID or (info[1] and info[1].spellID)
        end
        if not spellID and C_Spell and C_Spell.GetSpellInfo then
            for line in string_gmatch(entry.macrotext .. "\n", "([^\n]+)\n") do
                local rest = line:match("^/%a+%s+(.*)")
                if rest then
                    local spell = SecureCmdOptionParse and SecureCmdOptionParse(rest)
                    if spell and spell ~= "" then
                        local si = C_Spell.GetSpellInfo(spell)
                        if si and si.spellID then
                            spellID = si.spellID
                            break
                        end
                    end
                end
            end
        end
    elseif entry.type == "macro" and entry.macro and GetMacroIndexByName then
        local idx = GetMacroIndexByName(entry.macro)
        if idx and idx > 0 then spellID = GetMacroSpell(idx) end
    end
    GameTooltip_SetDefaultAnchor(GameTooltip, btn)
    if spellID then
        if GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(spellID)
        else
            GameTooltip:SetHyperlink("spell:" .. spellID)
        end
    else
        local L = GSE.L or {}
        GameTooltip:SetText(seqName, 1, 1, 1)
        GameTooltip:AddLine(L["GSE Sequence"] or "GSE Sequence", 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

--- Add small GSE logo watermark to bottom-right of button.
local function AddWatermark(buttonName)
    if watermarkedButtons[buttonName] then return end
    local btn = _G[buttonName]
    if not btn then return end
    local iconPath = GSE and GSE.Static and GSE.Static.Icons and GSE.Static.Icons.GSE_Logo_Dark
    if not iconPath then return end
    local wm = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    wm:SetTexture(iconPath)
    wm:SetSize(14, 14)
    wm:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    wm:SetAlpha(0.85)
    if GSEOptions and GSEOptions.showActionBarWatermark == false then wm:Hide() end
    watermarkedButtons[buttonName] = wm
end

local function RemoveWatermark(buttonName)
    local wm = watermarkedButtons[buttonName]
    if not wm then return end
    wm:Hide()
    watermarkedButtons[buttonName] = nil
end

local function SetWatermarkVisible(buttonName, visible)
    if GSEOptions and GSEOptions.showActionBarWatermark == false then return end
    local wm = watermarkedButtons[buttonName]
    if not wm then return end
    if visible then wm:Show() else wm:Hide() end
end

--- Hook OnEnter / OnLeave / OnAttributeChanged to keep icon + tooltip correct.
local function HookButtonIconUpdates(buttonName)
    if iconHookedButtons[buttonName] then return end
    iconHookedButtons[buttonName] = true
    local btn = _G[buttonName]
    if not btn then return end

    local function restoreIconNow(self)
        if not self:GetAttribute("gse-button") then return end
        local bName = self:GetName()
        local icon = GetButtonIcon(self, bName)
        if not icon then return end
        local texture = GetGSEButtonIcon(self)
        if texture then
            icon:SetTexture(texture)
            icon:Show()
        end
    end

    btn:HookScript("OnEnter", function(self)
        restoreIconNow(self)
        ShowGSEButtonTooltip(self)
    end)
    btn:HookScript("OnLeave", restoreIconNow)

    btn:HookScript("OnAttributeChanged", function(self, name, value)
        if not self:GetAttribute("gse-button") then return end
        local bName = self:GetName()
        local icon = GetButtonIcon(self, bName)
        if not icon then return end
        if name == "gse-eff-action" then
            if value and value > 0 then
                local texture = GetActionTexture(value)
                if texture then icon:SetTexture(texture) end
                SetWatermarkVisible(bName, false)
            else
                ScheduleIconRestore(self, icon)
                SetWatermarkVisible(bName, true)
            end
        elseif name == "type" and value == "click" then
            ScheduleIconRestore(self, icon)
        end
    end)
end

---------------------------------------------------------------------------
-- Per-button install / uninstall
---------------------------------------------------------------------------

local wrappedButtons = {}   -- [buttonName] = true  (WrapScripts installed once)
local onEnterHooked = {}    -- [buttonName] = true  (HookScript installed once)

local function HookOnEnterOnce(btn, buttonName)
    if onEnterHooked[buttonName] then return end
    onEnterHooked[buttonName] = true
    btn:HookScript("OnEnter", function(self)
        if InCombatLockdown() then return end
        if self:GetAttribute("gse-button") then
            self:SetAttribute("type", "click")
        end
    end)
end

local function InstallOverrideOnButton(buttonName, sequenceName)
    if InCombatLockdown() then return false end
    local btn = _G[buttonName]
    if not btn then return false end
    if not _G[sequenceName] then
        -- GSE stores each sequence as a global SecureActionButton frame named
        -- after the sequence.  Missing global means the sequence hasn't been
        -- compiled yet — skip; GSE.ReloadOverrides will retry later.
        return false
    end

    local handler = GetSHBT()
    if not wrappedButtons[buttonName] then
        -- WrapScript on OnClick is allowed on ActionButtonTemplate; OnEnter is not.
        handler:WrapScript(btn, "OnClick", BAR_SWAP_ONCLICK)
        handler:WrapScript(btn, "OnAttributeChanged", BAR_SWAP_OAC)
        wrappedButtons[buttonName] = true
    end

    HookOnEnterOnce(btn, buttonName)

    btn:SetAttribute("gse-button", sequenceName)
    btn:SetAttribute("type", "click")
    btn:SetAttribute("clickbutton", _G[sequenceName])

    -- Register in GSE.ButtonOverrides so GSE.UpdateIcon (which fires on
    -- every sequence step) knows to push the current spell icon to this
    -- button.  Without this entry, UpdateIcon never touches QUI buttons.
    if GSE.ButtonOverrides then
        GSE.ButtonOverrides[buttonName] = sequenceName
    end

    -- Icon management — replicate what GSE's overrideActionButton does
    HookButtonIconUpdates(buttonName)
    AddWatermark(buttonName)
    local icon = GetButtonIcon(btn, buttonName)
    if icon then
        ScheduleIconRestore(btn, icon)
    end

    return true
end

local function RemoveOverrideFromButton(buttonName)
    if InCombatLockdown() then return false end
    local btn = _G[buttonName]
    if not btn then return false end
    -- WrapScripts are permanent once installed; clearing the gse-button
    -- attribute makes both snippets fall through to type="action", which
    -- is the correct restored behaviour for a QUI action button.
    btn:SetAttribute("gse-button", nil)
    btn:SetAttribute("clickbutton", nil)
    btn:SetAttribute("type", "action")
    RemoveWatermark(buttonName)
    if GSE and GSE.ButtonOverrides then
        GSE.ButtonOverrides[buttonName] = nil
    end
    -- Re-run the button's update so the icon refreshes back to the
    -- normal action slot state (or hides if the slot is empty).
    if btn.Update then
        pcall(btn.Update, btn)
    end
    return true
end

---------------------------------------------------------------------------
-- Persistence (QUI DB)
---------------------------------------------------------------------------

local function GetSpecID()
    if GSE and GSE.GetCurrentSpecID then return GSE.GetCurrentSpecID() end
    if PlayerUtil and PlayerUtil.GetCurrentSpecID then
        return PlayerUtil.GetCurrentSpecID() or 0
    end
    return 0
end

local function GetBindingsTable(create)
    local QUI = _G.QUI
    if not QUI or not QUI.db or not QUI.db.profile then return nil end
    local root = QUI.db.profile.gseCompat
    if not root then
        if not create then return nil end
        root = {}
        QUI.db.profile.gseCompat = root
    end
    if not root.bindings then
        if not create then return nil end
        root.bindings = {}
    end
    local spec = GetSpecID()
    local specTable = root.bindings[spec]
    if not specTable then
        if not create then return nil end
        specTable = {}
        root.bindings[spec] = specTable
    end
    return specTable
end

local function SaveBinding(buttonName, sequenceName)
    local t = GetBindingsTable(true)
    if not t then return end
    t[buttonName] = sequenceName
end

local function ClearBinding(buttonName)
    local t = GetBindingsTable(false)
    if not t then return end
    t[buttonName] = nil
end

---------------------------------------------------------------------------
-- Re-install pass (login, spec change, after bar rebuild)
---------------------------------------------------------------------------

local function ReapplyAll()
    if InCombatLockdown() then return end
    local t = GetBindingsTable(false)
    if not t then return end
    for buttonName, sequenceName in pairs(t) do
        if IsQUIButtonName(buttonName) then
            InstallOverrideOnButton(buttonName, sequenceName)
        end
    end
end

---------------------------------------------------------------------------
-- GSE API hooks
---------------------------------------------------------------------------

local hooksInstalled = false

local function InstallGSEHooks()
    if hooksInstalled then return end
    if not _G.GSE then return end
    hooksInstalled = true

    local origCreate = GSE.CreateActionBarOverride
    GSE.CreateActionBarOverride = function(buttonName, sequenceName)
        if IsQUIButtonName(buttonName) then
            if InCombatLockdown() then return end
            if InstallOverrideOnButton(buttonName, sequenceName) then
                SaveBinding(buttonName, sequenceName)
            end
            return
        end
        return origCreate(buttonName, sequenceName)
    end

    local origRemove = GSE.RemoveActionBarOverride
    GSE.RemoveActionBarOverride = function(buttonName)
        if IsQUIButtonName(buttonName) then
            if InCombatLockdown() then return end
            RemoveOverrideFromButton(buttonName)
            ClearBinding(buttonName)
            return
        end
        return origRemove(buttonName)
    end

    -- After GSE reloads overrides (e.g. spec change, sequence recompile) our
    -- QUI button clickbuttons may point at stale sequence frames.  Re-apply.
    if GSE.ReloadOverrides then
        hooksecurefunc(GSE, "ReloadOverrides", function()
            ReapplyAll()
        end)
    end
end

---------------------------------------------------------------------------
-- Right-click sequence picker popup
--
-- GSE hooks OnClick on known addon buttons to show a context menu for
-- assigning / changing / clearing sequence overrides.  QUI buttons are
-- not in that list, so we install the equivalent handler ourselves.
---------------------------------------------------------------------------

local rightClickHooked = {}  -- [buttonName] = true

local function HookRightClickOnce(btn, buttonName)
    if rightClickHooked[buttonName] then return end
    rightClickHooked[buttonName] = true
    btn:HookScript("OnClick", function(self, mousebutton, down)
        if not _G.GSE then return end
        if not _G.GSEOptions or not _G.GSEOptions.actionBarOverridePopup then return end
        if InCombatLockdown() then return end
        if not down then return end
        if mousebutton ~= "RightButton" then return end

        local existingSequence = self:GetAttribute("gse-button")

        if not existingSequence then
            local action = self.action or self:GetAttribute("action")
            if not action or action == 0 then return end
            if HasAction(action) then return end
        end

        local classIconText = ""
        local classInfo = C_CreatureInfo and C_CreatureInfo.GetClassInfo(GSE.GetCurrentClassID())
        if classInfo and classInfo.classFile then
            classIconText = "|A:classicon-" .. classInfo.classFile:lower() .. ":16:16|a "
        end

        local names = {}
        local function addSequences(classID)
            for k, seq in pairs(GSE.Library[classID] or {}) do
                local specID = seq and seq.MetaData and seq.MetaData.SpecID
                local disabled = seq and seq.MetaData and seq.MetaData.Disabled
                names[#names + 1] = { name = k, specID = specID, disabled = disabled }
            end
        end
        addSequences(GSE.GetCurrentClassID())
        addSequences(0)

        table.sort(names, function(a, b) return a.name < b.name end)

        local L = GSE.L or {}
        local bName = self:GetName()
        MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
            if existingSequence then
                rootDescription:CreateTitle((L["GSE"] or "GSE") .. ": " .. existingSequence)
                rootDescription:CreateButton(L["Clear Override"] or "Clear Override", function()
                    GSE.RemoveActionBarOverride(bName)
                end)
                if #names > 0 then
                    rootDescription:CreateDivider()
                    rootDescription:CreateTitle(L["Change Sequence"] or "Change Sequence")
                end
            else
                rootDescription:CreateTitle(L["Assign GSE Sequence"] or "Assign GSE Sequence")
            end
            for _, entry in ipairs(names) do
                local iconText = classIconText
                local specID = entry.specID
                if specID and specID >= 15 and GetSpecializationInfoByID then
                    local _, _, _, specIconID = GetSpecializationInfoByID(specID)
                    if specIconID then
                        iconText = "|T" .. specIconID .. ":16:16|t "
                    end
                end
                local label = iconText .. entry.name
                if entry.disabled then
                    local element = rootDescription:CreateButton("|cFF808080" .. label .. "|r", function() end)
                    element:SetTooltip(function(tooltip)
                        GameTooltip_SetTitle(tooltip, L["Sequence Disabled"] or "Sequence Disabled")
                    end)
                else
                    rootDescription:CreateButton(label, function()
                        GSE.CreateActionBarOverride(bName, entry.name)
                    end)
                end
            end
        end)
    end)
end

local function HookRightClickAllQUIButtons()
    if not _G.GSE then return end
    for bar = 1, 8 do
        for slot = 1, 12 do
            local name = "QUI_Bar" .. bar .. "Button" .. slot
            local btn = _G[name]
            if btn then
                HookRightClickOnce(btn, name)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Event wiring
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        InstallGSEHooks()
        -- Defer one frame so GSE has finished its own PLAYER_LOGIN setup
        -- (sequence globals, ReloadOverrides) before we install on top.
        C_Timer.After(0.1, function()
            InstallGSEHooks()
            ReapplyAll()
            HookRightClickAllQUIButtons()
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        InstallGSEHooks()
        C_Timer.After(0.1, function()
            ReapplyAll()
            HookRightClickAllQUIButtons()
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.1, ReapplyAll)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- In case a spec change or reload landed in combat, retry OOC.
        ReapplyAll()
    end
end)

---------------------------------------------------------------------------
-- Public namespace (for debugging / manual re-apply)
---------------------------------------------------------------------------

ns.QUI_GSECompat = {
    IsQUIButtonName = IsQUIButtonName,
    Reapply = ReapplyAll,
    Install = InstallOverrideOnButton,
    Remove = RemoveOverrideFromButton,
}
