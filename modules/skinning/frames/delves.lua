local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local function SkinDelvesFrame(frame)
    if not frame or SkinBase.IsSkinned(frame) then return end

    if frame.Border and SkinBase.StripTextures then SkinBase.StripTextures(frame.Border) end
    SkinBase.SkinWindow(frame)
    SkinBase.SkinDropdown(frame.Dropdown, { skinArrow = true })
    SkinBase.SkinButton(frame.EnterDelveButton, { strip = true, font = true })
    SkinBase.SkinButton(frame.CompanionConfigShowAbilitiesButton, { strip = true, font = true })
    SkinBase.MarkSkinned(frame)
end

local function StyleDelvesAbilities(frame)
    if not frame then return end
    SkinBase.SkinWindow(frame)
    SkinBase.ClampTextureHidden(frame.CompanionAbilityListBackground, true)
    SkinBase.SkinDropdown(frame.DelvesCompanionRoleDropdown, { skinArrow = true })
    local title = frame.GetTitleText and frame:GetTitleText() or frame.TitleText
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
    local paging = frame.DelvesCompanionAbilityListPagingControls
    if paging then
        SkinBase.SkinNextPrevButton(paging.PrevPageButton, "prev")
        SkinBase.SkinNextPrevButton(paging.NextPageButton, "next")
    end
    for _, button in ipairs(frame.buttons or {}) do
        local shade = button.locked and 0.55 or 0.9
        SkinBase.SkinFontString(button.Name, { color = { shade, shade, shade, 1 } })
        SkinBase.SkinFontString(button.UnlockCondition)
        SkinBase.SkinFontString(button.Rank)
        if button.Icon then
            local border = SkinBase.SkinIcon(button.Icon, { parent = button })
            SkinBase.ApplyChromeBackdrop(border, { radius = 4, withBackground = false })
            SkinBase.RoundIconTexture(button, button.Icon)
        end
    end
    if not SkinBase.GetFrameData(frame, "qDelvesAbilitiesHooked") then
        SkinBase.SetFrameData(frame, "qDelvesAbilitiesHooked", true)
        frame:HookScript("OnShow", StyleDelvesAbilities)
        if frame.Refresh then hooksecurefunc(frame, "Refresh", StyleDelvesAbilities) end
        if frame.UpdatePaginatedButtonDisplay then hooksecurefunc(frame, "UpdatePaginatedButtonDisplay", StyleDelvesAbilities) end
    end
end

local function SkinDelvesCompanion()
    if not IsSettingEnabled("skinDelves") then return end
    SkinDelvesFrame(_G.DelvesCompanionConfigurationFrame)
    StyleDelvesAbilities(_G.DelvesCompanionAbilityListFrame)
end

local function SkinDelvesDifficulty()
    if not IsSettingEnabled("skinDelves") then return end
    SkinDelvesFrame(_G.DelvesDifficultyPickerFrame)
end

local function RefreshDelves()
    SkinBase.RefreshFrameBackdropColors(_G.DelvesCompanionConfigurationFrame)
    SkinBase.RefreshFrameBackdropColors(_G.DelvesDifficultyPickerFrame)
    if IsSettingEnabled("skinDelves") then StyleDelvesAbilities(_G.DelvesCompanionAbilityListFrame) end
end
if ns.Registry then
    ns.Registry:Register("skinDelves", {
        refresh = RefreshDelves,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_DelvesCompanionConfiguration", SkinDelvesCompanion, 0)
SkinBase.OnAddOnLoaded("Blizzard_DelvesDifficultyPicker", SkinDelvesDifficulty, 0)
