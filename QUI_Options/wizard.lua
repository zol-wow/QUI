local ADDON_NAME, ns = ...
local QUI = QUI
local L = ns.L
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local Wizard = { applied = {} }
ns.QUI_SetupWizard = Wizard

local LAYOUT_NAME = "QUI"

local frame
local bodyHost
local activeBody
local currentPage = 1
local pageBodies = {}
local contentGen = 0

local PAGES
local RenderPage

local function GetGUI()
    return QUI and QUI.GUI
end

local function GetCore()
    return Helpers.GetCore and Helpers.GetCore()
end

local function WizardState()
    local db = QUI and QUI.db
    local g = db and db.global
    if not g then return nil end
    g.setupWizard = g.setupWizard or {}
    return g.setupWizard
end

local function CombatBlocked()
    if InCombatLockdown() then
        print("|cFF30D1FFQUI|r " .. L["This step can't run during combat — try again after combat ends."])
        return true
    end
    return false
end

local function MarkApplied(line)
    contentGen = contentGen + 1
    for _, existing in ipairs(Wizard.applied) do
        if existing == line then return end
    end
    Wizard.applied[#Wizard.applied + 1] = line
end

local function AddText(body, text, sy, size, color)
    local GUI = GetGUI()
    local label = GUI:CreateLabel(body, text, size or 12, color)
    label:SetPoint("TOPLEFT", 0, sy)
    label:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    local height = label.GetStringHeight and label:GetStringHeight() or 14
    if type(height) ~= "number" or height < 14 then height = 14 end
    return sy - height - 10
end

local function AddStatusLine(body, sy)
    local GUI = GetGUI()
    local label = GUI:CreateLabel(body, "", 12)
    label:SetPoint("TOPLEFT", 0, sy)
    label:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    return label, sy - 28
end

local function QueueRerender()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if frame and frame:IsShown() then
                RenderPage(currentPage)
            end
        end)
    end
end

local function ApplyEditModeBaseLayout()
    if InCombatLockdown() then
        return false, L["Cannot change Edit Mode layouts during combat."]
    end
    local entry = QUI and QUI.imports and QUI.imports.QUIEditMode
    local str = entry and entry.data
    if type(str) ~= "string" or str == "" then
        return false, L["Bundled layout string is missing."]
    end
    if not (C_EditMode and C_EditMode.ConvertStringToLayoutInfo and C_EditMode.GetLayouts
        and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout and Enum and Enum.EditModeLayoutType) then
        return false, L["Edit Mode API unavailable on this client."]
    end
    local presetMgr = _G.EditModePresetLayoutManager
    if not (presetMgr and presetMgr.GetCopyOfPresetLayouts) then
        return false, L["Edit Mode API unavailable on this client."]
    end

    local ok, err = pcall(function()
        local newInfo = C_EditMode.ConvertStringToLayoutInfo(str)
        if type(newInfo) ~= "table" or type(newInfo.systems) ~= "table" then
            error(L["The bundled layout string was not recognized."], 0)
        end

        local layoutInfo = C_EditMode.GetLayouts()
        local customs = layoutInfo and layoutInfo.layouts
        if type(customs) ~= "table" then
            error(L["Edit Mode layout list unavailable."], 0)
        end

        local list = presetMgr:GetCopyOfPresetLayouts()
        if type(list) ~= "table" or #list == 0 then
            error(L["Edit Mode layout list unavailable."], 0)
        end
        for i = 1, #customs do
            list[#list + 1] = customs[i]
        end
        layoutInfo.layouts = list

        local targetIndex
        for i, layout in ipairs(list) do
            if layout.layoutName == LAYOUT_NAME and layout.layoutType ~= Enum.EditModeLayoutType.Preset then
                targetIndex = i
                break
            end
        end

        if targetIndex then
            list[targetIndex].systems = newInfo.systems
        else
            newInfo.layoutType = Enum.EditModeLayoutType.Account
            newInfo.layoutName = LAYOUT_NAME
            list[#list + 1] = newInfo
            targetIndex = #list
        end

        C_EditMode.SaveLayouts(layoutInfo)
        C_EditMode.SetActiveLayout(targetIndex)
    end)

    if not ok then
        return false, tostring(err)
    end
    return true
end

Wizard._ApplyEditModeBaseLayout = ApplyEditModeBaseLayout

PAGES = {
    {
        title = L["Welcome to QUI"],
        nextLabel = L["Start Setup"],
        build = function(body)
            local GUI = GetGUI()
            local sy = -4
            sy = AddText(body, L["This short guided setup walks through QUI's recommended UI scale, profile, feature toggles, and frame layout."], sy)
            sy = AddText(body, L["Every step applies immediately and every step is optional — use Next to skip anything."], sy)
            sy = AddText(body, L["You can re-run this any time with |cFFFFFF00/qui install|r."], sy)

            local notNow = GUI:CreateButton(body, L["Not now"], 120, 26, function()
                Wizard:Hide()
            end)
            notNow:SetPoint("TOPLEFT", 0, sy - 8)
        end,
    },
    {
        title = L["UI Scale"],
        build = function(body)
            local GUI = GetGUI()
            local core = GetCore()
            local sy = -4

            local current = (UIParent and UIParent.GetScale and UIParent:GetScale()) or 1
            local recommended = (core and core.GetSmartDefaultScale and core:GetSmartDefaultScale()) or 1

            sy = AddText(body, L["QUI picks a pixel-perfect scale for your resolution. You can fine-tune it later under General settings."], sy)
            sy = AddText(body, string.format("%s |cFFFFFF00%.2f|r    %s |cFF34D399%.2f|r",
                L["Current scale:"], current, L["Recommended:"], recommended), sy)

            local status = AddStatusLine(body, sy - 56)
            if math.abs(current - recommended) < 0.005 then
                status:SetText(L["You are already at the recommended scale."])
            else
                local apply = GUI:CreateButton(body, L["Apply Recommended Scale"], 200, 26, function()
                    if CombatBlocked() then return end
                    local db = QUI and QUI.db
                    if not (db and db.profile) then return end
                    db.profile.general = db.profile.general or {}
                    db.profile.general.uiScale = recommended
                    if core and core.ApplyUIScale then
                        core:ApplyUIScale()
                    end
                    MarkApplied(string.format(L["UI scale set to %.2f"], recommended))
                    QueueRerender()
                end)
                apply:SetPoint("TOPLEFT", 0, sy - 12)
            end
        end,
    },
    {
        title = L["Profile"],
        build = function(body)
            local GUI = GetGUI()
            local sy = -4

            sy = AddText(body, L["A fresh install already runs the Starter Profile layout. Use this step to reset back to it, or to paste a profile string someone shared with you."], sy)

            local status
            local function ImportInto(profileName, importString, appliedLine)
                if CombatBlocked() then return end
                local core = GetCore()
                if not (core and core.ImportProfileFromString) then
                    status:SetText("|cFFFF6666" .. L["Profile import is unavailable."] .. "|r")
                    return
                end
                local ok, msg = core:ImportProfileFromString(importString, profileName)
                if ok then
                    status:SetText("|cFF34D399" .. (msg or L["Profile imported successfully."]) .. "|r")
                    MarkApplied(appliedLine)
                    QueueRerender()
                else
                    status:SetText("|cFFFF6666" .. (msg or L["Import failed."]) .. "|r")
                end
            end

            local starter = GUI:CreateButton(body, L["Apply Starter Profile"], 200, 26, function()
                local core = GetCore()
                local db = core and core.db
                local preset = QUI and QUI._presetProfiles and QUI._presetProfiles[1]
                local importData = preset and QUI.imports and QUI.imports[preset.key]
                if not (db and preset and importData and importData.data) then
                    status:SetText("|cFFFF6666" .. L["Starter Profile preset data not found."] .. "|r")
                    return
                end
                if db:GetCurrentProfile() == preset.profileName then
                    status:SetText(L["The Starter Profile is already active."])
                    return
                end
                ImportInto(preset.profileName, importData.data, L["Starter Profile applied"])
            end)
            starter:SetPoint("TOPLEFT", 0, sy - 4)
            sy = sy - 40

            local header = GUI.CreateSectionHeader and GUI:CreateSectionHeader(body, L["Import a profile string"])
            if header and header.SetPoint then
                header:SetPoint("TOPLEFT", 0, sy)
            end
            sy = sy - 26

            local box = GUI:CreateScrollableTextBox(body, 80, "", {})
            box:SetPoint("TOPLEFT", 0, sy)
            box:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            sy = sy - 88

            local importBtn = GUI:CreateButton(body, L["Import"], 120, 26, function()
                local text = box.editBox and box.editBox:GetText() or ""
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text == "" then
                    status:SetText(L["Paste a profile string first."])
                    return
                end
                ImportInto(L["Imported"], text, L["Profile string imported"])
            end)
            importBtn:SetPoint("TOPLEFT", 0, sy)
            sy = sy - 34

            status = AddStatusLine(body, sy)
        end,
    },
    {
        title = L["Features"],
        build = function(body)
            local GUI = GetGUI()
            local profile = QUI and QUI.db and QUI.db.profile
            if not profile then return end
            local sy = -4

            sy = AddText(body, L["Two high-impact features worth deciding now. Everything else lives in |cFFFFFF00/qui|r."], sy)

            profile.ncdm = profile.ncdm or {}
            sy = Helpers.PlaceRow(GUI:CreateFormToggle(body, L["Cooldown Manager (CDM)"], "enabled", profile.ncdm, function()
                if _G.QUI_RefreshNCDM then _G.QUI_RefreshNCDM() end
                MarkApplied(L["Feature toggles adjusted"])
            end), body, sy)
            sy = AddText(body, L["QUI's cooldown tracking uses Blizzard's Cooldown Manager. If the viewer layout needs changes, QUI shows the required Edit Mode steps without editing Blizzard's layout."], sy, 11)

            profile.actionBars = profile.actionBars or {}
            profile.actionBars.fade = profile.actionBars.fade or {}
            sy = Helpers.PlaceRow(GUI:CreateFormToggle(body, L["Action Bar Mouseover Fade"], "enabled", profile.actionBars.fade, function()
                if _G.QUI_RefreshActionBarFade then _G.QUI_RefreshActionBarFade() end
                MarkApplied(L["Feature toggles adjusted"])
            end), body, sy)
            AddText(body, L["Hide action bars until you mouse over them. Per-bar overrides live in the Action Bars tab."], sy, 11)
        end,
    },
    {
        title = L["Nameplates"],
        build = function(body)
            local GUI = GetGUI()
            local profile = QUI and QUI.db and QUI.db.profile
            if not profile then return end
            local sy = -4

            sy = AddText(body, L["QUI can replace Blizzard's nameplates entirely — pixel-crisp health bars, castbars with interrupt feedback, and a filterable aura display."], sy)

            profile.nameplates = profile.nameplates or {}
            sy = Helpers.PlaceRow(GUI:CreateFormToggle(body, L["Enable QUI Nameplates"], "enabled", profile.nameplates, function()
                MarkApplied(L["Nameplates toggled (takes effect after reload)"])
            end), body, sy)
            sy = AddText(body, L["Nameplates load with the UI — this toggle takes effect after the reload offered at the end of setup."], sy, 11)

            profile.nameplates.friendly = profile.nameplates.friendly or {}
            local friendly = profile.nameplates.friendly
            profile.nameplates.types = profile.nameplates.types or {}
            profile.nameplates.types.friendly = profile.nameplates.types.friendly or {}
            local friendlyType = profile.nameplates.types.friendly
            local friendlyProxy = { bars = friendlyType.renderMode == "bars" }
            sy = Helpers.PlaceRow(GUI:CreateFormToggle(body, L["Friendly health bars (open world)"], "bars", friendlyProxy, function(value)
                friendlyType.renderMode = value and "bars" or "nameonly"
                if ns.QUI_RefreshNameplates then ns.QUI_RefreshNameplates() end
                MarkApplied(L["Friendly nameplate style chosen"])
            end), body, sy)
            AddText(body, L["Off keeps Blizzard's name-only friendly plates. In dungeons and raids, Blizzard protects friendly nameplates, so bars fall back to name-only there."], sy, 11)
        end,
    },
    {
        title = L["Frame Layout"],
        build = function(body)
            local GUI = GetGUI()
            local sy = -4

            sy = AddText(body, L["Apply QUI's base Edit Mode layout as a starting point for Blizzard-managed frames, then fine-tune every QUI frame in Layout Mode."], sy)

            local status
            local applyBtn = GUI:CreateButton(body, L["Apply QUI Edit Mode Layout"], 220, 26, function()
                local ok, err = ApplyEditModeBaseLayout()
                if ok then
                    status:SetText("|cFF34D399" .. string.format(L["Edit Mode layout '%s' applied and activated."], LAYOUT_NAME) .. "|r")
                    MarkApplied(L["Edit Mode base layout applied"])
                else
                    status:SetText("|cFFFF6666" .. (err or L["Layout apply failed."]) .. "|r  " ..
                        L["You can import it manually: copy the string below into Blizzard Edit Mode → Import."])
                    if not body._fallbackBox then
                        local entry = QUI and QUI.imports and QUI.imports.QUIEditMode
                        local box = GUI:CreateScrollableTextBox(body, 70, (entry and entry.data) or "", {})
                        box:SetPoint("BOTTOMLEFT", 0, 4)
                        box:SetPoint("RIGHT", body, "RIGHT", 0, 0)
                        body._fallbackBox = box
                    end
                end
            end)
            applyBtn:SetPoint("TOPLEFT", 0, sy - 4)

            local layoutBtn = GUI:CreateButton(body, L["Open Layout Mode"], 160, 26, function()
                Wizard:Hide()
                if _G.QUI_ToggleLayoutMode then
                    _G.QUI_ToggleLayoutMode()
                end
            end)
            layoutBtn:SetPoint("TOPLEFT", 240, sy - 4)
            sy = sy - 40

            sy = AddText(body, L["Layout Mode (|cFFFFFF00/qui layout|r) repositions every QUI frame by dragging — remember to click Save."], sy, 11)
            status = AddStatusLine(body, sy)
        end,
    },
    {
        title = L["All Done"],
        nextLabel = L["Finish"],
        build = function(body)
            local GUI = GetGUI()
            local sy = -4

            if #Wizard.applied == 0 then
                sy = AddText(body, L["No changes were applied — your setup is untouched. Re-run any time with |cFFFFFF00/qui install|r."], sy)
            else
                sy = AddText(body, L["Applied in this run:"], sy)
                for _, line in ipairs(Wizard.applied) do
                    sy = AddText(body, "|cFF34D399•|r " .. line, sy)
                end
            end
            sy = AddText(body, L["A reload is recommended after profile imports; everything else applied live."], sy, 11)

            local reload = GUI:CreateButton(body, L["Reload UI"], 120, 26, function()
                local sw = WizardState()
                if sw then sw.completedAt = time() end
                if QUI and QUI.SafeReload then QUI:SafeReload() end
            end)
            reload:SetPoint("TOPLEFT", 0, sy - 8)
        end,
    },
}

local function EnsureFrame()
    if frame then return frame end
    local GUI = GetGUI()
    if not GUI then return nil end
    local C = GUI.Colors or {}
    local SkinBase = ns.SkinBase

    frame = CreateFrame("Frame", "QUI_SetupWizard", UIParent, "BackdropTemplate")
    frame:SetSize(560, 440)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(510)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetClampedToScreen(true)
    frame:Hide()

    if SkinBase and SkinBase.ApplyPixelBackdrop and C.border and C.bg then
        SkinBase.ApplyPixelBackdrop(frame, 1, true, false,
            { C.border[1], C.border[2], C.border[3], 1 },
            { C.bg[1], C.bg[2], C.bg[3], 0.98 })
    end

    frame.title = GUI:CreateLabel(frame, "", 15, C.accentLight)
    frame.title:SetPoint("TOPLEFT", 20, -16)

    frame.progress = GUI:CreateLabel(frame, "", 12, C.text)
    frame.progress:SetPoint("TOPRIGHT", -44, -18)

    UIKit.CreateCloseButton(frame, {
        size = 22,
        point = "TOPRIGHT",
        x = -12,
        y = -12,
        onClick = function() Wizard:Hide() end,
    })

    bodyHost = CreateFrame("Frame", nil, frame)
    bodyHost:SetPoint("TOPLEFT", 20, -48)
    bodyHost:SetPoint("BOTTOMRIGHT", -20, 60)

    frame.backBtn = GUI:CreateButton(frame, L["Back"], 100, 28, function()
        if currentPage > 1 then
            RenderPage(currentPage - 1)
        end
    end)
    frame.backBtn:SetPoint("BOTTOMLEFT", 20, 18)

    frame.nextBtn = GUI:CreateButton(frame, L["Next"], 140, 28, function()
        if currentPage < #PAGES then
            RenderPage(currentPage + 1)
        else
            Wizard:Finish()
        end
    end)
    frame.nextBtn:SetPoint("BOTTOMRIGHT", -20, 18)

    return frame
end

RenderPage = function(index)
    if not frame then return end
    currentPage = index
    local page = PAGES[index]

    if activeBody then
        activeBody:Hide()
    end
    local body = pageBodies[index]
    if not body then
        body = CreateFrame("Frame", nil, bodyHost)
        body:SetAllPoints(bodyHost)
        pageBodies[index] = body
    end
    activeBody = body

    frame.title:SetText(page.title or "")
    frame.progress:SetText(index .. " / " .. #PAGES)
    if frame.backBtn.SetShown then
        frame.backBtn:SetShown(index > 1)
    end
    if frame.nextBtn.SetText then
        frame.nextBtn:SetText(page.nextLabel or L["Next"])
    end

    if body._builtGen ~= contentGen then
        if body._builtGen ~= nil then
            local GUI = GetGUI()
            if GUI and GUI.TeardownFrameTree then
                GUI:TeardownFrameTree(body)
            end
            body._fallbackBox = nil
        end
        body._builtGen = contentGen
        page.build(body)
    end
    body:Show()
end

function Wizard:Show()
    if not WizardState() then
        print("|cFF30D1FFQUI|r " .. L["Setup wizard is not ready yet — try again in a moment."])
        return
    end
    if not EnsureFrame() then return end
    wipe(self.applied)
    contentGen = contentGen + 1
    RenderPage(1)
    frame:Show()
end

function Wizard:Hide()
    if frame then frame:Hide() end
end

function Wizard:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Wizard:Finish()
    local sw = WizardState()
    if sw then
        sw.completedAt = time()
    end
    self:Hide()
    print("|cFF30D1FFQUI|r " .. L["Setup complete. Re-run any time with |cFFFFFF00/qui install|r."])
end

function Wizard:_GetPages()
    return PAGES
end
