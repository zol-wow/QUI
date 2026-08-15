local _, ns = ...

local CDMEditModePolicy = {}
ns.CDMEditModePolicy = CDMEditModePolicy

local function UpsertSetting(settings, settingEnum, desiredValue, defaultValue)
    for _, s in ipairs(settings) do
        if s.setting == settingEnum then
            if s.value ~= desiredValue then
                s.value = desiredValue
                return true
            end
            return false
        end
    end
    if desiredValue == defaultValue then
        return false
    end
    settings[#settings + 1] = { setting = settingEnum, value = desiredValue }
    return true
end

function CDMEditModePolicy.ApplyToSystems(systems, enums)
    local changed = false
    for _, sysInfo in ipairs(systems) do
        if sysInfo.system == enums.cooldownSystem and type(sysInfo.settings) == "table" then
            if UpsertSetting(sysInfo.settings, enums.visSetting, enums.visAlways, enums.visAlways) then
                changed = true
            end
            if sysInfo.systemIndex == enums.buffIconIdx or sysInfo.systemIndex == enums.buffBarIdx then
                if UpsertSetting(sysInfo.settings, enums.hideEnum, 1, 1) then
                    changed = true
                end
            end
        end
    end
    return changed
end

local _applied = false

function CDMEditModePolicy.Enforce()
    if _applied then return end
    if _G.QUI_IsCDMMasterEnabled and not _G.QUI_IsCDMMasterEnabled() then return end
    local C_EditMode = _G.C_EditMode
    local Enum = _G.Enum
    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSystemIndices) then
        return
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return end

    local numPresets = 0
    local presetMgr = _G.EditModePresetLayoutManager
    if presetMgr and presetMgr.GetCopyOfPresetLayouts then
        local presets = presetMgr:GetCopyOfPresetLayouts()
        if type(presets) == "table" then
            numPresets = #presets
            if _G.tAppendAll then
                _G.tAppendAll(presets, layoutInfo.layouts)
            else
                for i = 1, #layoutInfo.layouts do
                    presets[#presets + 1] = layoutInfo.layouts[i]
                end
            end
            layoutInfo.layouts = presets
        end
    end
    if numPresets == 0 then return end

    local activeLayout = type(layoutInfo.activeLayout) == "number"
        and layoutInfo.layouts[layoutInfo.activeLayout]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    if numPresets > 0 and type(layoutInfo.activeLayout) == "number"
        and layoutInfo.activeLayout <= numPresets then
        _applied = true
        return
    end

    local changed = CDMEditModePolicy.ApplyToSystems(activeLayout.systems, {
        cooldownSystem = Enum.EditModeSystem.CooldownViewer,
        visSetting = Enum.EditModeCooldownViewerSetting.VisibleSetting,
        visAlways = Enum.CooldownViewerVisibleSetting.Always,
        hideEnum = Enum.EditModeCooldownViewerSetting.HideWhenInactive,
        buffIconIdx = Enum.EditModeCooldownViewerSystemIndices.BuffIcon,
        buffBarIdx = Enum.EditModeCooldownViewerSystemIndices.BuffBar,
    })

    _applied = true
    local db = _G.QUIDB
    if not changed then
        if db then db.cdmEditModeSavePending = nil end
        return
    end

    if db and db.cdmEditModeSavePending then
        if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then return end
        _G.StaticPopupDialogs["QUI_CDM_EDITMODE_MANUAL"] = {
            text = "QUI could not save the Cooldown Manager Edit Mode settings,"
                .. " so they must be set by hand:\n\n"
                .. "1. Disable the Cooldown Manager in QUI options and reload.\n"
                .. "2. Open Edit Mode and set each Cooldown Manager viewer's"
                .. " Visibility to Always.\n"
                .. "3. On Tracked Buffs and Tracked Bars, enable Hide When Inactive.\n"
                .. "4. Save the layout, leave Edit Mode, and re-enable the"
                .. " Cooldown Manager.\n\n"
                .. "This notice repeats each login until the layout is correct.",
            button1 = _G.OKAY or "Okay",
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
        _G.StaticPopup_Show("QUI_CDM_EDITMODE_MANUAL")
        return
    end

    C_EditMode.SaveLayouts(layoutInfo)
    if db then db.cdmEditModeSavePending = true end

    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then return end

    _G.StaticPopupDialogs["QUI_CDM_EDITMODE_RELOAD"] = {
        text = "QUI has updated your Cooldown Manager Edit Mode settings"
            .. " (viewers must be Always visible with Hide When Inactive on"
            .. " for cooldown tracking to work).\n\nA UI reload is required"
            .. " to apply them.",
        button1 = "Reload UI",
        OnAccept = function()
            if _G.ReloadUI then _G.ReloadUI() end
        end,
        timeout = 0,
        whileDead = 1,
        preferredIndex = 3,
    }
    _G.StaticPopup_Show("QUI_CDM_EDITMODE_RELOAD")
end

local enforceFrame = CreateFrame("Frame")
enforceFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
enforceFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if self and self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
        if _G.InCombatLockdown and _G.InCombatLockdown()
            and self and self.RegisterEvent then
            self:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self and self.UnregisterEvent then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    else
        return
    end
    CDMEditModePolicy.Enforce()
end)
