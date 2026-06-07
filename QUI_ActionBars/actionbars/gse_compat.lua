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
local GetActionBarsDB = Helpers and Helpers.CreateDBGetter and Helpers.CreateDBGetter("actionBars")

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
-- Debug state (forward declarations — full helpers defined near EOF so they
-- can reference the install/dump state, but these names must be visible to
-- earlier hook closures like the GSE.UpdateIcon secure hook).
---------------------------------------------------------------------------

local DEBUG_GSE = false
local dbg

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

local function GetConfiguredUseOnKeyDown()
    local db = GetActionBarsDB and GetActionBarsDB()
    return db and db.global and db.global.useOnKeyDown == true
end

-- The only compatibility tweak GSE needs from us is Multiclick off.
-- `ActionButtonUseKeyDown` used to require CVar gymnastics here, but we now
-- set useOnKeyDown=false directly on the GSE sequence frame at install time,
-- which overrides the CVar fallback — so the user's CVar choice no longer
-- affects GSE casts and we don't need to mutate it.
local function EnsureOverrideCompatibility()
    if GSEOptions and GSEOptions.Multiclick then
        GSEOptions.Multiclick = false
        if GSE and GSE.ReloadSequences then
            GSE.ReloadSequences()
        end
    end
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
    local effectiveAction = self:GetEffectiveAttribute("action")
    local slot = self:GetAttribute("qui-button-index") or self:GetID() or 0
    local page = slot > 0 and self:GetEffectiveAttribute("actionpage") or nil
    if (not effectiveAction or effectiveAction == 0) and page and slot > 0 then
        effectiveAction = slot + page * 12 - 12
    end
    local swapped = 0
    if effectiveAction then
        local at = GetActionInfo(effectiveAction)
        if at == nil or at == "macro" then
            self:SetAttribute("type", "click")
        else
            self:SetAttribute("type", "action")
            swapped = effectiveAction
        end
    end
    if self:GetAttribute("gse-eff-action") ~= swapped then
        self:SetAttribute("gse-eff-action", swapped)
    end
]]

local BAR_SWAP_ONCLICK = [[
    local gseButton = self:GetAttribute('gse-button')
    if gseButton then
        local effectiveAction = self:GetEffectiveAttribute("action")
        local slot = self:GetAttribute("qui-button-index") or self:GetID() or 0
        local page = slot > 0 and self:GetEffectiveAttribute("actionpage") or nil
        if (not effectiveAction or effectiveAction == 0) and page and slot > 0 then
            effectiveAction = slot + page * 12 - 12
        end
        local swapped = 0
        if effectiveAction then
            local at = GetActionInfo(effectiveAction)
            if at == nil or at == "macro" then
                self:SetAttribute('type', 'click')
            else
                self:SetAttribute('type', 'action')
                swapped = effectiveAction
            end
        end
        if self:GetAttribute("gse-eff-action") ~= swapped then
            self:SetAttribute("gse-eff-action", swapped)
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
local latestSequenceIcons = {}  -- [sequenceName] = iconID

--- Resolve the effective action slot for a QUI button.
local function GetButtonEffectiveSlot(btn)
    local action = tonumber(btn:GetAttribute("action"))
    if action and action > 0 then return action end
    local slot = tonumber(btn:GetAttribute("qui-button-index")) or btn:GetID()
    if not slot or slot == 0 then return nil end
    local page = tonumber(btn:GetAttribute("actionpage")) or 1
    return slot + (page - 1) * 12
end

local function GetSequenceStepEntry(seqName)
    if not GSE or not GSE.SequencesExec or not seqName then return nil end
    local executionseq = GSE.SequencesExec[seqName]
    if not executionseq then return nil end
    local seqFrame = _G[seqName]
    local step = seqFrame and seqFrame.GetAttribute and (seqFrame:GetAttribute("step") or 1) or 1
    local iteration = seqFrame and seqFrame.GetAttribute and (seqFrame:GetAttribute("iteration") or 1) or 1
    if iteration > 1 then
        step = step + iteration * 254
    end
    return executionseq[step]
end

-- Best-effort extractor for a castable spell's icon out of a macrotext
-- block.  GSE.GetSpellsFromString returns nil on anything with complex
-- conditionals that SecureCmdOptionParse can't evaluate out-of-context
-- (very common in real sequences), so we parse lines ourselves.
--
-- Heuristic: GSE templates commonly front-load modifier-gated alternates
-- (/use [mod:alt] 14, /castsequence [mod:shift] X, /castsequence [mod:ctrl] Y)
-- and put the primary cast on the LAST /cast line without a modifier.
-- So we collect all resolvable spell candidates and prefer the one from
-- the LAST line (most specific / modifier-free), with a hard preference
-- for /cast over /castsequence over /use.
local function LooksLikeSpellName(s)
    if type(s) ~= "string" or s == "" then return false end
    if s:match("^reset=") then return false end
    -- "/use 14" (bag slot) or "/use 13" (trinket slot) — numeric candidates
    -- are inventory/slot IDs, not spell names.  Accept only names with at
    -- least one letter.  (SpellIDs are legitimate too, but GSE sequences
    -- don't generally use raw IDs in macrotext.)
    if not s:match("%a") then return false end
    return true
end

local function ExtractIconFromMacroText(macrotext)
    if type(macrotext) ~= "string" or macrotext == "" then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local unescape = (GSE and GSE.UnEscapeString) and GSE.UnEscapeString or function(s) return s end
    local text = unescape(macrotext)

    -- Priority: 3 = plain /cast with no conditionals, 2 = /cast with
    -- conditionals, 1 = /castsequence / /castrandom, 0 = /use.
    -- Ties broken by line position (later wins — closer to "primary").
    local best = { icon = nil, priority = -1, lineIndex = -1 }
    local lineIndex = 0

    for line in string_gmatch(text .. "\n", "([^\r\n]+)") do
        lineIndex = lineIndex + 1
        local cmd, rest = line:match("^%s*/(%w+)%s+(.*)")
        if cmd and rest then
            local lc = cmd:lower()
            local basePriority
            if lc == "cast" then
                basePriority = rest:find("%b[]") and 2 or 3
            elseif lc == "castsequence" or lc == "castrandom" then
                basePriority = 1
            elseif lc == "use" or lc == "userandom" then
                basePriority = 0
            end
            if basePriority then
                rest = rest:gsub("%b[]", " ")
                for chunk in string_gmatch(rest, "[^;]+") do
                    for candidate in string_gmatch(chunk, "[^,]+") do
                        candidate = candidate:gsub("^%s+", ""):gsub("%s+$", "")
                        if LooksLikeSpellName(candidate) then
                            local info = C_Spell.GetSpellInfo(candidate)
                            if info and info.iconID then
                                if basePriority > best.priority
                                    or (basePriority == best.priority and lineIndex > best.lineIndex)
                                then
                                    best.icon = info.iconID
                                    best.priority = basePriority
                                    best.lineIndex = lineIndex
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return best.icon
end

local function GetSequenceIcon(seqName)
    local entry = GetSequenceStepEntry(seqName)
    if not entry then return nil end

    -- Try per-step spell/macrotext/item resolution first (same order as
    -- GSE.UpdateIcon).  entry.Icon is a static sequence-wide fallback that
    -- typically gets copied onto every step's entry — if we short-circuit
    -- on it, every step renders the same icon instead of the live spell.
    if entry.type == "spell" and entry.spell and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(GSE.UnEscapeString(entry.spell))
        if info and info.iconID then return info.iconID end
    elseif entry.type == "macro" and entry.macrotext then
        -- Don't use GSE.GetSpellsFromString here — it returns early as soon
        -- as it hits the first /castsequence, ignoring later /cast lines.
        -- That causes every step that starts with a mod-gated /castsequence
        -- alternate (very common GSE template) to return the alternate's
        -- icon (e.g. Mend Pet, iconID 132179) instead of the primary cast.
        -- Our ExtractIconFromMacroText walks all lines with priority
        -- scoring so the modifier-free /cast at the end wins.
        local ico = ExtractIconFromMacroText(entry.macrotext)
        if ico then return ico end
    elseif entry.type == "macro" and entry.macro and GetMacroIndexByName then
        local idx = GetMacroIndexByName(entry.macro)
        if idx and idx > 0 then
            local _, texture = GetMacroInfo(idx)
            if texture then return texture end
        end
    elseif entry.type == "item" and entry.item and C_Item and C_Item.GetItemInfo then
        local _, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(GSE.UnEscapeString(entry.item))
        if icon then return icon end
    end

    -- Last-resort fallback: static sequence-wide icon.
    if entry.Icon then return entry.Icon end

    return nil
end

--- Return the display icon for a GSE-overridden button.
local function GetGSEButtonIcon(btn)
    local swappedAction = tonumber(btn:GetAttribute("gse-eff-action"))
    if swappedAction and swappedAction > 0 and GetActionTexture then
        local texture = GetActionTexture(swappedAction)
        if texture then return texture end
    end
    local seq = btn:GetAttribute("gse-button")
    if not seq then return nil end

    local liveIcon = latestSequenceIcons[seq]
    if liveIcon then
        return liveIcon
    end

    local texture = GetSequenceIcon(seq)
    if texture then
        return texture
    end

    if not GetMacroIndexByName then return nil end
    local idx = GetMacroIndexByName(seq)
    if idx and idx > 0 then
        local _, texture = GetMacroInfo(idx)
        if texture then return texture end
    end
    return nil
end

_G.QUI_GetGSEButtonIcon = GetGSEButtonIcon

--- Resolve the button's icon texture child.
local function GetButtonIcon(btn, buttonName)
    return btn.icon or (buttonName and _G[buttonName .. "Icon"])
end

local function ApplyGSEButtonIcon(btn, buttonName)
    if not btn or not btn.GetAttribute then return end
    if not btn:GetAttribute("gse-button") then
        if DEBUG_GSE then dbg("ApplyIcon  %s skip: no gse-button", tostring(buttonName)) end
        return
    end
    local icon = GetButtonIcon(btn, buttonName or btn:GetName())
    if not icon then
        if DEBUG_GSE then dbg("ApplyIcon  %s skip: no icon region", tostring(buttonName)) end
        return
    end
    local texture = GetGSEButtonIcon(btn)
    if not texture then
        if DEBUG_GSE then dbg("ApplyIcon  %s skip: no texture", tostring(buttonName)) end
        return
    end
    local before = icon.GetTexture and icon:GetTexture() or "?"
    local beforeFile = icon.GetTextureFileID and icon:GetTextureFileID() or "?"
    icon:SetTexture(texture)
    icon:Show()
    local after = icon.GetTexture and icon:GetTexture() or "?"
    local afterFile = icon.GetTextureFileID and icon:GetTextureFileID() or "?"
    if DEBUG_GSE then
        dbg("ApplyIcon  %s want=%s | before=%s (file=%s) after=%s (file=%s) shown=%s",
            tostring(buttonName), tostring(texture),
            tostring(before), tostring(beforeFile),
            tostring(after), tostring(afterFile),
            tostring(icon:IsShown()))
    end
end

local function UpdateQUIButtonsForSequence(sequenceName)
    if not sequenceName then return end
    for bar = 1, 8 do
        for slot = 1, 12 do
            local buttonName = "QUI_Bar" .. bar .. "Button" .. slot
            local btn = _G[buttonName]
            if btn and btn.GetAttribute and btn:GetAttribute("gse-button") == sequenceName then
                ApplyGSEButtonIcon(btn, buttonName)
            end
        end
    end
end

local function SetSequenceLiveIcon(sequenceName, iconID)
    if not sequenceName or not iconID then return end
    latestSequenceIcons[sequenceName] = iconID
    UpdateQUIButtonsForSequence(sequenceName)
end

--- Defer icon restore one frame so WoW's own ActionButton_Update runs first.
local function ScheduleIconRestore(btn, icon)
    C_Timer.After(0, function()
        if not btn:GetAttribute("gse-button") then return end
        ApplyGSEButtonIcon(btn, btn:GetName())
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
        ApplyGSEButtonIcon(self, self:GetName())
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

local function RefreshQUIOverrides()
    if _G.QUI_ReapplyActionBarBindings then
        _G.QUI_ReapplyActionBarBindings()
    end
    if _G.QUI_RefreshActionBars then
        _G.QUI_RefreshActionBars()
    end
end

local function ForEachQUIActionButton(callback)
    for bar = 1, 8 do
        for slot = 1, 12 do
            local buttonName = "QUI_Bar" .. bar .. "Button" .. slot
            local btn = _G[buttonName]
            if btn then
                callback(buttonName, btn)
            end
        end
    end
end

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

local function InstallOverrideOnButton(buttonName, sequenceName, suppressRefresh)
    if InCombatLockdown() then return false end
    local btn = _G[buttonName]
    if not btn then return false end
    EnsureOverrideCompatibility()
    if not _G[sequenceName] and GSE and GSE.ReloadSequences then
        GSE.ReloadSequences()
    end
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
    btn:SetAttribute("gse-eff-action", 0)
    btn:SetAttribute("LABdisableDragNDrop", true)
    btn:SetAttribute("type", "click")
    btn:SetAttribute("clickbutton", _G[sequenceName])
    btn:SetAttribute("useOnKeyDown", GetConfiguredUseOnKeyDown())
    -- Force the sequence frame into release-mode cast dispatch.  Our consumer
    -- button's press-edge click forwards a synthetic click with down=false;
    -- the seq frame has no useOnKeyDown set so it falls back to the CVar,
    -- and with ActionButtonUseKeyDown=1 the cast dispatcher expects a press
    -- edge and silently drops our release-style forward (step advances via
    -- the WrapScript, but the type="macro"/"spell" action never fires).
    -- Setting useOnKeyDown=false on the seq frame locks it to release-mode
    -- regardless of CVar, which is what GSE relies on and what BT4 gets for
    -- free by running with the CVar already set to 0.
    local seqFrame = _G[sequenceName]
    if seqFrame and seqFrame.SetAttribute then
        seqFrame:SetAttribute("useOnKeyDown", false)
    end
    latestSequenceIcons[sequenceName] = GetSequenceIcon(sequenceName) or latestSequenceIcons[sequenceName]
    -- Force GSE to paint the live step icon right now.  Our hook on
    -- GSE.UpdateIcon populates latestSequenceIcons, which covers the
    -- case where SequencesExec wasn't ready when GetSequenceIcon ran.
    if _G.GSE and _G.GSE.UpdateIcon and _G[sequenceName] then
        pcall(_G.GSE.UpdateIcon, _G[sequenceName], false)
    end
    if btn.RunAttribute then
        btn:RunAttribute("QUI_UpdateActionFlags")
    end

    -- Icon management — replicate what GSE's overrideActionButton does
    HookButtonIconUpdates(buttonName)
    AddWatermark(buttonName)
    local icon = GetButtonIcon(btn, buttonName)
    if icon then
        ScheduleIconRestore(btn, icon)
    end
    if btn.Update then
        pcall(btn.Update, btn)
    end
    if not suppressRefresh then
        RefreshQUIOverrides()
    end

    return true
end

local function RemoveOverrideFromButton(buttonName, suppressRefresh)
    if InCombatLockdown() then return false end
    local btn = _G[buttonName]
    if not btn then return false end
    -- WrapScripts are permanent once installed; clearing the gse-button
    -- attribute makes both snippets fall through to type="action", which
    -- is the correct restored behaviour for a QUI action button.
    btn:SetAttribute("LABdisableDragNDrop", nil)
    btn:SetAttribute("gse-eff-action", 0)
    btn:SetAttribute("clickbutton", nil)
    btn:SetAttribute("type", "action")
    btn:SetAttribute("gse-button", nil)
    btn:SetAttribute("useOnKeyDown", GetConfiguredUseOnKeyDown())
    if btn.RunAttribute then
        btn:RunAttribute("QUI_UpdateActionFlags")
    end
    RemoveWatermark(buttonName)
    -- Re-run the button's update so the icon refreshes back to the
    -- normal action slot state (or hides if the slot is empty).
    if btn.Update then
        pcall(btn.Update, btn)
    end
    if not suppressRefresh then
        RefreshQUIOverrides()
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
    EnsureOverrideCompatibility()
    local t = GetBindingsTable(false)

    ForEachQUIActionButton(function(buttonName, btn)
        local activeSequence = btn.GetAttribute and btn:GetAttribute("gse-button")
        local desiredSequence = t and t[buttonName] or nil
        if activeSequence and activeSequence ~= desiredSequence then
            RemoveOverrideFromButton(buttonName, true)
        end
    end)

    if t then
        for buttonName, sequenceName in pairs(t) do
            if IsQUIButtonName(buttonName) then
                InstallOverrideOnButton(buttonName, sequenceName, true)
            end
        end
    end

    RefreshQUIOverrides()
end

---------------------------------------------------------------------------
-- GSE API hooks
---------------------------------------------------------------------------

local hooksInstalled = false
local updateIconHookInstalled = false
local iconMessageHookInstalled = false

local function InstallGSEHooks()
    if hooksInstalled then return end
    if not _G.GSE then return end
    hooksInstalled = true

    local origCreate = GSE.CreateActionBarOverride
    GSE.CreateActionBarOverride = function(buttonName, sequenceName)
        if IsQUIButtonName(buttonName) then
            if InCombatLockdown() then return end
            SaveBinding(buttonName, sequenceName)
            EnsureOverrideCompatibility()
            if not _G[sequenceName] and GSE.ReloadSequences then
                GSE.ReloadSequences()
            end
            ReapplyAll()
            return
        end
        return origCreate(buttonName, sequenceName)
    end

    local origRemove = GSE.RemoveActionBarOverride
    GSE.RemoveActionBarOverride = function(buttonName)
        if IsQUIButtonName(buttonName) then
            if InCombatLockdown() then return end
            ClearBinding(buttonName)
            ReapplyAll()
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

    if not updateIconHookInstalled and GSE.UpdateIcon then
        updateIconHookInstalled = true
        hooksecurefunc(GSE, "UpdateIcon", function(sequenceButton, reseticon)
            local sequenceName = sequenceButton and sequenceButton.GetName and sequenceButton:GetName()
            if sequenceName then
                -- Compute the per-step icon ourselves.  GSE would normally
                -- broadcast GSE_SEQUENCE_ICON_UPDATE with the authoritative
                -- spellinfo.iconID here, but if GSE.GetSpellsFromString can't
                -- resolve the macrotext (complex conditionals), GSE's own
                -- `if spellinfo and spellinfo.iconID` gate drops the broadcast
                -- entirely.  Our GetSequenceIcon has an additional fallback
                -- parser that handles those cases.
                local liveIcon = GetSequenceIcon(sequenceName)
                if liveIcon then
                    latestSequenceIcons[sequenceName] = liveIcon
                end
                if DEBUG_GSE then
                    local step = sequenceButton.GetAttribute
                        and sequenceButton:GetAttribute("step") or "?"
                    local entry = GetSequenceStepEntry(sequenceName)
                    dbg("UpdateIcon seq=%s step=%s reset=%s type=%s cachedIcon=%s",
                        sequenceName, tostring(step), tostring(reseticon),
                        tostring(entry and entry.type),
                        tostring(latestSequenceIcons[sequenceName]))
                    if entry and entry.macrotext then
                        local mt = entry.macrotext:gsub("\r", ""):gsub("\n", "\\n")
                        dbg("  macrotext: %s", mt)
                    end
                    if entry and entry.spell then
                        dbg("  spell: %s", tostring(entry.spell))
                    end
                end
                UpdateQUIButtonsForSequence(sequenceName)
            end
        end)
    end

    if not iconMessageHookInstalled and GSE.SendMessage then
        iconMessageHookInstalled = true
        -- Preferred path: GSE:SendMessage(GSE_SEQUENCE_ICON_UPDATE, {name, spellinfo})
        -- carries the authoritative per-step icon that GSE.UpdateIcon just
        -- computed.  We listen and cache the iconID — no need to re-parse.
        hooksecurefunc(GSE, "SendMessage", function(_, message, payload)
            if DEBUG_GSE then
                dbg("SendMsg   msg=%s payloadType=%s p1=%s p2Type=%s",
                    tostring(message), type(payload),
                    type(payload) == "table" and tostring(payload[1]) or "?",
                    type(payload) == "table" and type(payload[2]) or "?")
            end
            local messages = GSE.Static and GSE.Static.Messages
            local iconMessage = messages and messages.GSE_SEQUENCE_ICON_UPDATE or "GSE_SEQUENCE_ICON_UPDATE"
            if message ~= iconMessage or type(payload) ~= "table" then return end
            local sequenceName = payload[1]
            local spellinfo = payload[2]
            local logoIcon = GSE.Static and GSE.Static.Icons and GSE.Static.Icons.GSE_Logo_Dark
            if type(sequenceName) ~= "string" or type(spellinfo) ~= "table" then return end
            if not spellinfo.iconID or spellinfo.iconID == logoIcon then return end
            SetSequenceLiveIcon(sequenceName, spellinfo.iconID)
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
-- Debug-only spellcast trace — verifies whether a sequence advance actually
-- produced an outgoing cast.  Listens on "player" for SENT/SUCCEEDED/FAILED
-- and only logs when DEBUG_GSE is on.
---------------------------------------------------------------------------

local castTraceFrame = CreateFrame("Frame")
castTraceFrame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
castTraceFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castTraceFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
castTraceFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
castTraceFrame:SetScript("OnEvent", function(_, event, _, _, spellID)
    if not DEBUG_GSE then return end
    local info = spellID and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or "?"
    dbg("Cast      %s spellID=%s name=%s", event, tostring(spellID), name)
end)

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
-- Debug instrumentation (toggled via /qui gse debug)
-- DEBUG_GSE and dbg are forward-declared near the top of this file so
-- hook closures installed before this block (e.g. GSE.UpdateIcon hook)
-- can see them as upvalues.
---------------------------------------------------------------------------

local DBG_RECENT = {}
local DBG_RECENT_LIMIT = 60
local debugHookedButtons = {}
local debugHookedSequences = {}

dbg = function(fmt, ...)
    if not DEBUG_GSE then return end
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff60A5FA[QUI GSE]|r " .. msg)
    end
    table.insert(DBG_RECENT, 1, date("%H:%M:%S ") .. msg)
    while #DBG_RECENT > DBG_RECENT_LIMIT do
        table.remove(DBG_RECENT)
    end
end

local function AttrSnapshot(btn)
    if not btn or not btn.GetAttribute then return "no-btn" end
    return string.format(
        "type=%s useOnKeyDown=%s typerelease=%s effAction=%s cb=%s gse=%s",
        tostring(btn:GetAttribute("type")),
        tostring(btn:GetAttribute("useOnKeyDown")),
        tostring(btn:GetAttribute("typerelease")),
        tostring(btn:GetAttribute("gse-eff-action")),
        tostring(btn:GetAttribute("clickbutton") and "frame" or "nil"),
        tostring(btn:GetAttribute("gse-button")))
end

local function InstallButtonDebugHooks(btn, buttonName)
    if debugHookedButtons[buttonName] then return end
    debugHookedButtons[buttonName] = true
    btn:HookScript("PreClick", function(self, button, down)
        if not DEBUG_GSE then return end
        if not self:GetAttribute("gse-button") then return end
        dbg("PreClick  %s btn=%s down=%s | %s",
            buttonName, tostring(button), tostring(down), AttrSnapshot(self))
    end)
    btn:HookScript("PostClick", function(self, button, down)
        if not DEBUG_GSE then return end
        local seq = self:GetAttribute("gse-button")
        if not seq then return end
        local seqFrame = _G[seq]
        local step = seqFrame and seqFrame.GetAttribute and seqFrame:GetAttribute("step") or "?"
        local iter = seqFrame and seqFrame.GetAttribute and seqFrame:GetAttribute("iteration") or "?"
        dbg("PostClick %s btn=%s down=%s | seq=%s step=%s iter=%s",
            buttonName, tostring(button), tostring(down), seq, tostring(step), tostring(iter))
    end)
end

local function InstallSequenceDebugHook(sequenceName)
    if debugHookedSequences[sequenceName] then return end
    local frame = _G[sequenceName]
    if not frame or not frame.HookScript then return end
    debugHookedSequences[sequenceName] = true
    frame:HookScript("OnClick", function(self, button, down)
        if not DEBUG_GSE then return end
        local step = self.GetAttribute and self:GetAttribute("step") or "?"
        dbg("SeqFrame  %s btn=%s down=%s newStep=%s",
            sequenceName, tostring(button), tostring(down), tostring(step))
    end)
end

local function InstallAllDebugHooks()
    ForEachQUIActionButton(function(buttonName, btn)
        InstallButtonDebugHooks(btn, buttonName)
    end)
    local t = GetBindingsTable(false)
    if t then
        for _, seqName in pairs(t) do
            if type(seqName) == "string" then
                InstallSequenceDebugHook(seqName)
            end
        end
    end
end

local function DumpOverrideState()
    local function out(line) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) end end
    out(string.format("|cff60A5FA[QUI GSE]|r state dump (debug=%s)", tostring(DEBUG_GSE)))
    out(string.format(
        "  GSEOptions.Multiclick=%s  configuredUseOnKeyDown=%s",
        tostring(GSEOptions and GSEOptions.Multiclick),
        tostring(GetConfiguredUseOnKeyDown())))
    local count = 0
    ForEachQUIActionButton(function(buttonName, btn)
        if not btn:GetAttribute("gse-button") then return end
        count = count + 1
        local seq = btn:GetAttribute("gse-button")
        local seqFrame = _G[seq]
        local step = seqFrame and seqFrame.GetAttribute and seqFrame:GetAttribute("step") or "?"
        local cb = btn:GetAttribute("clickbutton")
        local cbOk = (cb == seqFrame) and "OK" or ("MISMATCH(" .. tostring(cb) .. ")")
        local icon = latestSequenceIcons[seq]
        out(string.format(
            "  %s → %s | step=%s cb=%s icon=%s | %s",
            buttonName, seq, tostring(step), cbOk, tostring(icon), AttrSnapshot(btn)))
    end)
    if count == 0 then
        out("  (no active overrides on QUI buttons)")
    end
    out(string.format("  recent events: %d (/qui gse tail to view)", #DBG_RECENT))
end

local function TailDebugLog(n)
    local count = tonumber(n) or 20
    if count > #DBG_RECENT then count = #DBG_RECENT end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff60A5FA[QUI GSE]|r last %d events:", count))
    end
    for i = count, 1, -1 do
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("  " .. tostring(DBG_RECENT[i]))
        end
    end
end

local function ToggleDebug(force)
    if force == true or force == false then
        DEBUG_GSE = force
    else
        DEBUG_GSE = not DEBUG_GSE
    end
    InstallAllDebugHooks()
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "|cff60A5FA[QUI GSE]|r click-event debug = %s", tostring(DEBUG_GSE)))
    end
end

-- Ensure sequence debug hook is installed after each override install so
-- newly-wired sequences get traced from the first click.
local origInstallOverrideOnButton = InstallOverrideOnButton
InstallOverrideOnButton = function(buttonName, sequenceName, suppressRefresh)
    local ok = origInstallOverrideOnButton(buttonName, sequenceName, suppressRefresh)
    if ok and DEBUG_GSE then
        local btn = _G[buttonName]
        if btn then InstallButtonDebugHooks(btn, buttonName) end
        InstallSequenceDebugHook(sequenceName)
    end
    return ok
end

---------------------------------------------------------------------------
-- Public namespace (for debugging / manual re-apply)
---------------------------------------------------------------------------

ns.QUI_GSECompat = {
    IsQUIButtonName = IsQUIButtonName,
    Reapply = ReapplyAll,
    Install = InstallOverrideOnButton,
    Remove = RemoveOverrideFromButton,
    Dump = DumpOverrideState,
    Tail = TailDebugLog,
    ToggleDebug = ToggleDebug,
}

_G.QUI_GSEDump = DumpOverrideState
_G.QUI_GSEToggleDebug = ToggleDebug
_G.QUI_GSETail = TailDebugLog
