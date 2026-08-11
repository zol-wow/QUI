local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase
local Helpers = ns.Helpers

local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
    textMuted = { 0.6, 0.6, 0.6, 1 },
}

local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button then return end

    local btnBd = SkinBase.GetFrameData(button, "backdrop")
    if not btnBd then
        btnBd = CreateFrame("Frame", nil, button, "BackdropTemplate")
        btnBd:SetAllPoints()
        btnBd:SetFrameLevel(button:GetFrameLevel())
        btnBd:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", btnBd)
    end

    SkinBase.ApplyPixelBackdrop(btnBd, SkinBase.CHROME.BORDER_PX, true, true)
    local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
    local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
    Helpers.SetFrameBackdropColor(btnBd, btnBgR, btnBgG, btnBgB, 1)
    Helpers.SetFrameBackdropBorderColor(btnBd, sr, sg, sb, sa)

    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.LeftSeparator then button.LeftSeparator:SetAlpha(0) end
    if button.RightSeparator then button.RightSeparator:SetAlpha(0) end

    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end

    SkinBase.ApplyButtonFontObjects(button, { size = 12, color = COLORS.text, disabledColor = COLORS.textMuted })

    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            local r, g, b, a = unpack(sc)
            SkinBase.SetBackdropColors(bd, { math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a }, nil)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            SkinBase.SetBackdropColors(bd, sc, nil)
        end
    end)
end

local function StyleKeystoneSlot(slot, sr, sg, sb, sa)
    if not slot then return end

    if not SkinBase.GetFrameData(slot, "border") then
        local slotBorder = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        SkinBase.SetExpandedPixelPoints(slotBorder, slot, 4)
        slotBorder:SetFrameLevel(slot:GetFrameLevel() - 1)
        slotBorder:EnableMouse(false)
        SkinBase.ApplyPixelBackdrop(slotBorder, SkinBase.CHROME.BORDER_PX, true, true)
        Helpers.SetFrameBackdropColor(slotBorder, 0, 0, 0, 0.5)
        Helpers.SetFrameBackdropBorderColor(slotBorder, sr, sg, sb, sa)
        SkinBase.SetFrameData(slot, "border", slotBorder)
    end
end

local function HideBlizzardDecorations(f)
    local region = f:GetRegions()
    if region then region:SetAlpha(0) end
    if f.InstructionBackground then f.InstructionBackground:SetAlpha(0) end
    if f.KeystoneSlotGlow then f.KeystoneSlotGlow:Hide() end
    if f.SlotBG then f.SlotBG:Hide() end
    if f.KeystoneFrame then f.KeystoneFrame:Hide() end
    if f.Divider then f.Divider:Hide() end
end

local function SkinKeystoneFrame()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinKeystoneFrame then return end

    local keystoneFrame = _G.ChallengesKeystoneFrame
    if not keystoneFrame or SkinBase.IsSkinned(keystoneFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "keystone")

    SkinBase.CreateBackdrop(keystoneFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    hooksecurefunc(keystoneFrame, "Reset", HideBlizzardDecorations)
    keystoneFrame:HookScript("OnShow", HideBlizzardDecorations)

    if keystoneFrame.DungeonName then
        SkinBase.SkinFontString(keystoneFrame.DungeonName, { size = 22, color = COLORS.text })
    end

    if keystoneFrame.TimeLimit then
        SkinBase.SkinFontString(keystoneFrame.TimeLimit, { size = 16, color = COLORS.textMuted })
    end

    if keystoneFrame.Instructions then
        SkinBase.SkinFontString(keystoneFrame.Instructions, { size = 11, color = COLORS.textMuted })
    end

    StyleButton(keystoneFrame.StartButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    SkinBase.SkinCloseButton(keystoneFrame.CloseButton)

    StyleKeystoneSlot(keystoneFrame.KeystoneSlot, sr, sg, sb, sa)

    SkinBase.SetFrameData(keystoneFrame, "skinColor", { sr, sg, sb, sa })

    hooksecurefunc(keystoneFrame, "OnKeystoneSlotted", function(f)
        if not f.Affixes then return end
        local sc = SkinBase.GetFrameData(f, "skinColor") or { 0.376, 0.647, 0.980, 1 }
        local r, g, b, a = unpack(sc)
        for _, affix in ipairs(f.Affixes) do
            if affix.Portrait and not SkinBase.GetFrameData(affix, "border") then
                if affix.Border then affix.Border:SetAlpha(0) end
                affix.Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                local affixBorder = CreateFrame("Frame", nil, affix, "BackdropTemplate")
                SkinBase.SetExpandedPixelPoints(affixBorder, affix.Portrait, 1)
                affixBorder:SetFrameLevel(affix:GetFrameLevel())
                affixBorder:EnableMouse(false)
                SkinBase.ApplyPixelBackdrop(affixBorder, SkinBase.CHROME.BORDER_PX, false, false)
                Helpers.SetFrameBackdropBorderColor(affixBorder, r, g, b, a)
                SkinBase.SetFrameData(affix, "border", affixBorder)
            end
        end
    end)

    SkinBase.MarkSkinned(keystoneFrame)
end

local function RefreshKeystoneColors()
    local keystoneFrame = _G.ChallengesKeystoneFrame
    if not keystoneFrame or not SkinBase.IsSkinned(keystoneFrame) then return end

    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors(settings, "keystone")

    local ksBd = SkinBase.GetBackdrop(keystoneFrame)
    if ksBd then
        SkinBase.SetBackdropColors(ksBd, { sr, sg, sb, sa }, { bgr, bgg, bgb, bga })
    end

    local startBtnBd = keystoneFrame.StartButton and SkinBase.GetFrameData(keystoneFrame.StartButton, "backdrop")
    if startBtnBd then
        local btnBgR = math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1)
        local btnBgG = math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1)
        local btnBgB = math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
        Helpers.SetFrameBackdropColor(startBtnBd, btnBgR, btnBgG, btnBgB, 1)
        Helpers.SetFrameBackdropBorderColor(startBtnBd, sr, sg, sb, sa)
        SkinBase.SetFrameData(keystoneFrame.StartButton, "skinColor", { sr, sg, sb, sa })
    end

    local slotBorder = keystoneFrame.KeystoneSlot and SkinBase.GetFrameData(keystoneFrame.KeystoneSlot, "border")
    if slotBorder then
        Helpers.SetFrameBackdropBorderColor(slotBorder, sr, sg, sb, sa)
    end

    if keystoneFrame.Affixes then
        for _, affix in ipairs(keystoneFrame.Affixes) do
            local affixBorder = SkinBase.GetFrameData(affix, "border")
            if affixBorder then
                Helpers.SetFrameBackdropBorderColor(affixBorder, sr, sg, sb, sa)
            end
        end
    end

    SkinBase.SetFrameData(keystoneFrame, "skinColor", { sr, sg, sb, sa })
end

_G.QUI_RefreshKeystoneColors = RefreshKeystoneColors

if ns.Registry then
    ns.Registry:Register("skinKeystone", {
        refresh = _G.QUI_RefreshKeystoneColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

SkinBase.OnAddOnLoaded("Blizzard_ChallengesUI", function()
    if ChallengesKeystoneFrame then
        SkinKeystoneFrame()
    end
end)
