local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local SkinBase = ns.SkinBase

---------------------------------------------------------------------------
-- KEYSTONE FRAME SKINNING
---------------------------------------------------------------------------

-- Static colors (text only - bg comes from QUI:GetSkinBgColor())
local COLORS = {
    text = { 0.9, 0.9, 0.9, 1 },
    textMuted = { 0.6, 0.6, 0.6, 1 },
}

local FONT_FLAGS = "OUTLINE"

-- Style a button with QUI theme
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

    local btnPx = SkinBase.GetPixelSize(btnBd, 1)
    btnBd:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = btnPx,
        insets = { left = btnPx, right = btnPx, top = btnPx, bottom = btnPx }
    })
    -- Button bg slightly lighter than main bg
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    btnBd:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    btnBd:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default textures
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.LeftSeparator then button.LeftSeparator:SetAlpha(0) end
    if button.RightSeparator then button.RightSeparator:SetAlpha(0) end

    -- Hide highlight/pushed textures (removes red hover tint)
    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end

    -- Style button text
    local text = button:GetFontString()
    if text then
        text:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)
        text:SetTextColor(unpack(COLORS.text))
    end

    -- Store skin color for hover effects
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    -- Hover effect (brighten border)
    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            local r, g, b, a = unpack(sc)
            bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        local sc = SkinBase.GetFrameData(self, "skinColor")
        if bd and sc then
            bd:SetBackdropBorderColor(unpack(sc))
        end
    end)
end

-- Style the close button
local function StyleCloseButton(button)
    if not button then return end
    if button.Border then button.Border:SetAlpha(0) end
end

-- Style the keystone slot
local function StyleKeystoneSlot(slot, sr, sg, sb, sa)
    if not slot then return end

    if not SkinBase.GetFrameData(slot, "border") then
        local slotBorder = CreateFrame("Frame", nil, slot, "BackdropTemplate")
        slotBorder:SetPoint("TOPLEFT", -4, 4)
        slotBorder:SetPoint("BOTTOMRIGHT", 4, -4)
        slotBorder:SetFrameLevel(slot:GetFrameLevel() - 1)
        slotBorder:EnableMouse(false)
        local slotPx = SkinBase.GetPixelSize(slotBorder, 1)
        local slotEdge2 = 2 * slotPx
        slotBorder:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = slotEdge2,
            insets = { left = slotEdge2, right = slotEdge2, top = slotEdge2, bottom = slotEdge2 }
        })
        slotBorder:SetBackdropColor(0, 0, 0, 0.5)
        slotBorder:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(slot, "border", slotBorder)
    end
end

-- Hide Blizzard decorative elements
local function HideBlizzardDecorations(f)
    local region = f:GetRegions()
    if region then region:SetAlpha(0) end
    if f.InstructionBackground then f.InstructionBackground:SetAlpha(0) end
    if f.KeystoneSlotGlow then f.KeystoneSlotGlow:Hide() end
    if f.SlotBG then f.SlotBG:Hide() end
    if f.KeystoneFrame then f.KeystoneFrame:Hide() end
    if f.Divider then f.Divider:Hide() end
end

-- Main skinning function
local function SkinKeystoneFrame()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinKeystoneFrame then return end

    local keystoneFrame = _G.ChallengesKeystoneFrame
    if not keystoneFrame or SkinBase.IsSkinned(keystoneFrame) then return end

    -- Get skin colors from QUI system
    local QUI = _G.QUI
    local sr, sg, sb, sa
    local bgr, bgg, bgb, bga
    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    else
        sr, sg, sb, sa = 0.2, 1.0, 0.6, 1  -- Fallback mint
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    else
        bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95  -- Fallback dark
    end

    -- Create backdrop
    SkinBase.CreateBackdrop(keystoneFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Hide Blizzard decorations via hooks
    hooksecurefunc(keystoneFrame, "Reset", HideBlizzardDecorations)
    keystoneFrame:HookScript("OnShow", HideBlizzardDecorations)

    -- Style fonts
    if keystoneFrame.DungeonName then
        keystoneFrame.DungeonName:SetFont(STANDARD_TEXT_FONT, 22, FONT_FLAGS)
        keystoneFrame.DungeonName:SetTextColor(unpack(COLORS.text))
    end

    if keystoneFrame.TimeLimit then
        keystoneFrame.TimeLimit:SetFont(STANDARD_TEXT_FONT, 16, FONT_FLAGS)
        keystoneFrame.TimeLimit:SetTextColor(unpack(COLORS.textMuted))
    end

    if keystoneFrame.Instructions then
        keystoneFrame.Instructions:SetFont(STANDARD_TEXT_FONT, 11, FONT_FLAGS)
        keystoneFrame.Instructions:SetTextColor(unpack(COLORS.textMuted))
    end

    -- Style buttons
    StyleButton(keystoneFrame.StartButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    StyleCloseButton(keystoneFrame.CloseButton)

    -- Style keystone slot
    StyleKeystoneSlot(keystoneFrame.KeystoneSlot, sr, sg, sb, sa)

    -- Store skin color for affix hook
    SkinBase.SetFrameData(keystoneFrame, "skinColor", { sr, sg, sb, sa })

    -- Style affix icons when keystone is slotted
    hooksecurefunc(keystoneFrame, "OnKeystoneSlotted", function(f)
        local sc = SkinBase.GetFrameData(f, "skinColor") or { 0.2, 1.0, 0.6, 1 }
        local r, g, b, a = unpack(sc)
        for i = 1, 4 do
            local affix = f["Affix" .. i]
            if affix and affix.Portrait then
                if not SkinBase.GetFrameData(affix, "border") then
                    local affixBorder = affix:CreateTexture(nil, "OVERLAY")
                    affixBorder:SetPoint("TOPLEFT", affix.Portrait, -1, 1)
                    affixBorder:SetPoint("BOTTOMRIGHT", affix.Portrait, 1, -1)
                    affixBorder:SetColorTexture(r, g, b, a)
                    affixBorder:SetDrawLayer("OVERLAY", -1)
                    SkinBase.SetFrameData(affix, "border", affixBorder)
                end
            end
        end
    end)

    SkinBase.MarkSkinned(keystoneFrame)
end

-- Refresh colors on already-skinned keystone frame (for live preview)
local function RefreshKeystoneColors()
    local keystoneFrame = _G.ChallengesKeystoneFrame
    if not keystoneFrame or not SkinBase.IsSkinned(keystoneFrame) then return end

    -- Get current colors
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    -- Update main frame backdrop
    local ksBd = SkinBase.GetBackdrop(keystoneFrame)
    if ksBd then
        ksBd:SetBackdropColor(bgr, bgg, bgb, bga)
        ksBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update button backdrop
    local startBtnBd = keystoneFrame.StartButton and SkinBase.GetFrameData(keystoneFrame.StartButton, "backdrop")
    if startBtnBd then
        local btnBgR = math.min(bgr + 0.07, 1)
        local btnBgG = math.min(bgg + 0.07, 1)
        local btnBgB = math.min(bgb + 0.07, 1)
        startBtnBd:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
        startBtnBd:SetBackdropBorderColor(sr, sg, sb, sa)
        SkinBase.SetFrameData(keystoneFrame.StartButton, "skinColor", { sr, sg, sb, sa })
    end

    -- Update keystone slot border
    local slotBorder = keystoneFrame.KeystoneSlot and SkinBase.GetFrameData(keystoneFrame.KeystoneSlot, "border")
    if slotBorder then
        slotBorder:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update affix borders
    for i = 1, 4 do
        local affix = keystoneFrame["Affix" .. i]
        local affixBorder = affix and SkinBase.GetFrameData(affix, "border")
        if affixBorder then
            affixBorder:SetColorTexture(sr, sg, sb, sa)
        end
    end

    -- Update stored color for future affix borders
    SkinBase.MarkSkinned(keystoneFrame)
    SkinBase.SetFrameData(keystoneFrame, "skinColor", { sr, sg, sb, sa })
end

-- Expose refresh function globally
_G.QUI_RefreshKeystoneColors = RefreshKeystoneColors

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if addon == "Blizzard_ChallengesUI" then
        if ChallengesKeystoneFrame then
            SkinKeystoneFrame()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
