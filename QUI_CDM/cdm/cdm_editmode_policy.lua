local _, ns = ...

local CDMEditModePolicy = {}
ns.CDMEditModePolicy = CDMEditModePolicy

local function SettingNeedsChange(settings, settingEnum, desiredValue, defaultValue)
    for _, s in ipairs(settings) do
        if s.setting == settingEnum then
            return s.value ~= desiredValue
        end
    end
    return desiredValue ~= defaultValue
end

function CDMEditModePolicy.NeedsManualSetup(systems, enums)
    for _, sysInfo in ipairs(systems) do
        if sysInfo.system == enums.cooldownSystem and type(sysInfo.settings) == "table" then
            if SettingNeedsChange(sysInfo.settings, enums.visSetting, enums.visAlways, enums.visAlways) then
                return true
            end
            if sysInfo.systemIndex == enums.buffIconIdx or sysInfo.systemIndex == enums.buffBarIdx then
                if SettingNeedsChange(sysInfo.settings, enums.hideEnum, 1, 1) then
                    return true
                end
            end
        end
    end
    return false
end

local _applied = false

function CDMEditModePolicy.Enforce()
    if _applied then return end
    if _G.QUI_IsCDMMasterEnabled and not _G.QUI_IsCDMMasterEnabled() then return end
    local C_EditMode = _G.C_EditMode
    local Enum = _G.Enum
    if not (C_EditMode and C_EditMode.GetLayouts
            and Enum and Enum.EditModeSystem and Enum.EditModeSystem.CooldownViewer
            and Enum.EditModeCooldownViewerSetting and Enum.CooldownViewerVisibleSetting
            and Enum.EditModeCooldownViewerSystemIndices) then
        return
    end

    local layoutInfo = C_EditMode.GetLayouts()
    if type(layoutInfo) ~= "table" or type(layoutInfo.layouts) ~= "table" then return end

    local presetMgr = _G.EditModePresetLayoutManager
    if not (presetMgr and presetMgr.GetCopyOfPresetLayouts) then return end
    local presets = presetMgr:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then return end
    if type(layoutInfo.activeLayout) ~= "number" then return end
    if layoutInfo.activeLayout <= #presets then
        _applied = true
        return
    end
    local activeLayout = layoutInfo.layouts[layoutInfo.activeLayout - #presets]
    if not activeLayout or type(activeLayout.systems) ~= "table" then return end

    local needsSetup = CDMEditModePolicy.NeedsManualSetup(activeLayout.systems, {
        cooldownSystem = Enum.EditModeSystem.CooldownViewer,
        visSetting = Enum.EditModeCooldownViewerSetting.VisibleSetting,
        visAlways = Enum.CooldownViewerVisibleSetting.Always,
        hideEnum = Enum.EditModeCooldownViewerSetting.HideWhenInactive,
        buffIconIdx = Enum.EditModeCooldownViewerSystemIndices.BuffIcon,
        buffBarIdx = Enum.EditModeCooldownViewerSystemIndices.BuffBar,
    })

    _applied = true
    if not needsSetup or not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then return end
    _G.StaticPopupDialogs["QUI_CDM_EDITMODE_MANUAL"] = {
        text = "QUI detected a Blizzard Cooldown Manager layout mismatch."
            .. " QUI did not change Blizzard's Edit Mode layout.\n\n"
            .. "1. Open /qui > Module Addons, disable Cooldown Manager, and reload.\n"
            .. "2. Open Edit Mode and set each Cooldown Manager viewer's"
            .. " Visibility to Always.\n"
            .. "3. On Tracked Buffs and Tracked Bars, enable Hide When Inactive.\n"
            .. "4. Save the layout, leave Edit Mode, re-enable Cooldown Manager,"
            .. " and reload.\n\n"
            .. "This notice repeats each login until the layout is correct.",
        button1 = _G.OKAY or "Okay",
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    _G.StaticPopup_Show("QUI_CDM_EDITMODE_MANUAL")
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
