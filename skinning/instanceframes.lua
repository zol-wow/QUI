local addonName, ns = ...

---------------------------------------------------------------------------
-- INSTANCE FRAMES SKINNING (PVE, Dungeons & Raids, PVP, M+ Dungeons)
---------------------------------------------------------------------------

-- Get skinning colors
local function GetColors()
    local QUI = _G.QUI
    local sr, sg, sb, sa = 0.2, 1.0, 0.6, 1
    local bgr, bgg, bgb, bga = 0.05, 0.05, 0.05, 0.95

    if QUI and QUI.GetSkinColor then
        sr, sg, sb, sa = QUI:GetSkinColor()
    end
    if QUI and QUI.GetSkinBgColor then
        bgr, bgg, bgb, bga = QUI:GetSkinBgColor()
    end

    return sr, sg, sb, sa, bgr, bgg, bgb, bga
end

-- Create backdrop for a frame
local function CreateQUIBackdrop(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not frame.quiBackdrop then
        frame.quiBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        frame.quiBackdrop:SetAllPoints()
        frame.quiBackdrop:SetFrameLevel(frame:GetFrameLevel())
        frame.quiBackdrop:EnableMouse(false)
    end

    frame.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    frame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
    frame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Strip textures from a frame
local function StripTextures(frame)
    if not frame then return end

    for i = 1, frame:GetNumRegions() do
        local region = select(i, frame:GetRegions())
        if region and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
end

-- Style a button
local function StyleButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or button.quiStyled then return end

    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetAllPoints()
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Hide default textures
    if button.Left then button.Left:SetAlpha(0) end
    if button.Right then button.Right:SetAlpha(0) end
    if button.Middle then button.Middle:SetAlpha(0) end
    if button.Center then button.Center:SetAlpha(0) end

    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end
    local pushed = button:GetPushedTexture()
    if pushed then pushed:SetAlpha(0) end
    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    -- Store colors for hover
    button.quiSkinColor = { sr, sg, sb, sa }

    button:HookScript("OnEnter", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            local r, g, b, a = unpack(self.quiSkinColor)
            self.quiBackdrop:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            self.quiBackdrop:SetBackdropBorderColor(unpack(self.quiSkinColor))
        end
    end)

    button.quiStyled = true
end

-- Style dropdown (WowStyle1DropdownTemplate)
local function StyleDropdown(dropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga, width)
    if not dropdown or dropdown.quiStyled then return end

    -- Set width if provided
    if width then
        dropdown:SetWidth(width)
    end

    -- Strip textures (but keep Arrow visible)
    if dropdown.NineSlice then dropdown.NineSlice:SetAlpha(0) end
    if dropdown.NormalTexture then dropdown.NormalTexture:SetAlpha(0) end
    if dropdown.HighlightTexture then dropdown.HighlightTexture:SetAlpha(0) end

    -- Create backdrop
    if not dropdown.quiBackdrop then
        dropdown.quiBackdrop = CreateFrame("Frame", nil, dropdown, "BackdropTemplate")
        dropdown.quiBackdrop:SetPoint("TOPLEFT", 0, -2)
        dropdown.quiBackdrop:SetPoint("BOTTOMRIGHT", 0, 2)
        dropdown.quiBackdrop:SetFrameLevel(dropdown:GetFrameLevel())
        dropdown.quiBackdrop:EnableMouse(false)
    end

    dropdown.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    dropdown.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    dropdown.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Store colors for hover
    dropdown.quiSkinColor = { sr, sg, sb, sa }

    dropdown:HookScript("OnEnter", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            local r, g, b, a = unpack(self.quiSkinColor)
            self.quiBackdrop:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    dropdown:HookScript("OnLeave", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            self.quiBackdrop:SetBackdropBorderColor(unpack(self.quiSkinColor))
        end
    end)

    dropdown.quiStyled = true
end

-- Style tab button
local function StyleTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab or tab.quiStyled then return end

    -- Hide default textures (inactive state)
    if tab.Left then tab.Left:SetAlpha(0) end
    if tab.Middle then tab.Middle:SetAlpha(0) end
    if tab.Right then tab.Right:SetAlpha(0) end
    if tab.LeftDisabled then tab.LeftDisabled:SetAlpha(0) end
    if tab.MiddleDisabled then tab.MiddleDisabled:SetAlpha(0) end
    if tab.RightDisabled then tab.RightDisabled:SetAlpha(0) end

    -- Hide active/selected state textures (the yellow border)
    if tab.LeftActive then tab.LeftActive:SetAlpha(0) end
    if tab.MiddleActive then tab.MiddleActive:SetAlpha(0) end
    if tab.RightActive then tab.RightActive:SetAlpha(0) end

    -- Hide highlight textures
    if tab.LeftHighlight then tab.LeftHighlight:SetAlpha(0) end
    if tab.MiddleHighlight then tab.MiddleHighlight:SetAlpha(0) end
    if tab.RightHighlight then tab.RightHighlight:SetAlpha(0) end

    local highlight = tab:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    -- Create backdrop
    if not tab.quiBackdrop then
        tab.quiBackdrop = CreateFrame("Frame", nil, tab, "BackdropTemplate")
        tab.quiBackdrop:SetPoint("TOPLEFT", 3, -3)
        tab.quiBackdrop:SetPoint("BOTTOMRIGHT", -3, 0)
        tab.quiBackdrop:SetFrameLevel(tab:GetFrameLevel())
        tab.quiBackdrop:EnableMouse(false)
    end

    tab.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    tab.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.9)
    tab.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    tab.quiStyled = true
end

-- Hide all Blizzard decorations on PVEFrame (following character.lua/inspect.lua patterns)
local function HidePVEDecorations()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame then return end

    -- Main frame shadows (contains vertical divider line)
    if PVEFrame.shadows then
        PVEFrame.shadows:Hide()
        -- Also strip all textures inside shadows frame
        StripTextures(PVEFrame.shadows)
    end

    -- Blue menu backgrounds and decorations (from PVEFrame.xml)
    if _G.PVEFrameBlueBg then _G.PVEFrameBlueBg:Hide() end
    if _G.PVEFrameTLCorner then _G.PVEFrameTLCorner:Hide() end
    if _G.PVEFrameTRCorner then _G.PVEFrameTRCorner:Hide() end
    if _G.PVEFrameBRCorner then _G.PVEFrameBRCorner:Hide() end
    if _G.PVEFrameBLCorner then _G.PVEFrameBLCorner:Hide() end
    if _G.PVEFrameLLVert then _G.PVEFrameLLVert:Hide() end
    if _G.PVEFrameRLVert then _G.PVEFrameRLVert:Hide() end
    if _G.PVEFrameBottomLine then _G.PVEFrameBottomLine:Hide() end
    if _G.PVEFrameTopLine then _G.PVEFrameTopLine:Hide() end
    if _G.PVEFrameTopFiligree then _G.PVEFrameTopFiligree:Hide() end
    if _G.PVEFrameBottomFiligree then _G.PVEFrameBottomFiligree:Hide() end

    -- Left inset (contains the left panel)
    if _G.PVEFrameLeftInset then _G.PVEFrameLeftInset:Hide() end
    if PVEFrame.Inset then
        PVEFrame.Inset:Hide()
        if PVEFrame.Inset.NineSlice then PVEFrame.Inset.NineSlice:Hide() end
        if PVEFrame.Inset.Bg then PVEFrame.Inset.Bg:Hide() end
    end

    -- PortraitFrameTemplate elements
    if PVEFrame.NineSlice then PVEFrame.NineSlice:Hide() end
    if PVEFrame.Bg then PVEFrame.Bg:Hide() end
    if PVEFrame.Background then PVEFrame.Background:Hide() end

    -- Portrait container (hide portrait but keep frame functional)
    if PVEFrame.PortraitContainer then PVEFrame.PortraitContainer:Hide() end
    if _G.PVEFramePortrait then _G.PVEFramePortrait:Hide() end

    -- Title bar background (the yellow bar)
    if PVEFrame.TitleContainer then
        if PVEFrame.TitleContainer.TitleBg then PVEFrame.TitleContainer.TitleBg:Hide() end
    end
    if _G.PVEFrameTitleBg then _G.PVEFrameTitleBg:Hide() end

    -- PortraitFrame border textures
    if _G.PVEFrameTopBorder then _G.PVEFrameTopBorder:Hide() end
    if _G.PVEFrameTopRightCorner then _G.PVEFrameTopRightCorner:Hide() end
    if _G.PVEFrameRightBorder then _G.PVEFrameRightBorder:Hide() end
    if _G.PVEFrameBottomRightCorner then _G.PVEFrameBottomRightCorner:Hide() end
    if _G.PVEFrameBottomBorder then _G.PVEFrameBottomBorder:Hide() end
    if _G.PVEFrameBottomLeftCorner then _G.PVEFrameBottomLeftCorner:Hide() end
    if _G.PVEFrameLeftBorder then _G.PVEFrameLeftBorder:Hide() end
    if _G.PVEFrameBtnCornerLeft then _G.PVEFrameBtnCornerLeft:Hide() end
    if _G.PVEFrameBtnCornerRight then _G.PVEFrameBtnCornerRight:Hide() end
    if _G.PVEFrameButtonBottomBorder then _G.PVEFrameButtonBottomBorder:Hide() end

    -- Additional backgrounds
    if _G.PVEFrameBg then _G.PVEFrameBg:Hide() end
    if _G.PVEFrameBackground then _G.PVEFrameBackground:Hide() end
    if _G.PVEFrameInset then _G.PVEFrameInset:Hide() end
    if _G.PVEFrameNineSlice then _G.PVEFrameNineSlice:Hide() end

    -- Strip all remaining textures from main frame
    StripTextures(PVEFrame)
end

-- Style GroupFinder buttons (LFD, Raid Finder, Premade Groups on the left)
local function StyleGroupFinderButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or button.quiStyled then return end

    -- Hide default textures - check both lowercase (11.x) and uppercase (12.x PTR) keys
    if button.ring then button.ring:Hide() end
    if button.Ring then button.Ring:Hide() end
    if button.bg then button.bg:SetAlpha(0) end
    if button.Background then button.Background:Hide() end

    -- Create backdrop for button
    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetAllPoints()
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Style the icon
    if button.icon then
        button.icon:SetSize(40, 40)
        button.icon:ClearAllPoints()
        button.icon:SetPoint("LEFT", 8, 0)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Add icon border
        if not button.icon.quiBackdrop then
            button.icon.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            button.icon.quiBackdrop:SetPoint("TOPLEFT", button.icon, -1, 1)
            button.icon.quiBackdrop:SetPoint("BOTTOMRIGHT", button.icon, 1, -1)
            button.icon.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
            button.icon.quiBackdrop:EnableMouse(false)
            button.icon.quiBackdrop:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            button.icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end

    -- Store colors for hover
    button.quiSkinColor = { sr, sg, sb, sa }

    button:HookScript("OnEnter", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            local r, g, b, a = unpack(self.quiSkinColor)
            self.quiBackdrop:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            self.quiBackdrop:SetBackdropBorderColor(unpack(self.quiSkinColor))
        end
    end)

    button.quiStyled = true
end

-- Style close button (QUI pattern - minimal, just hide border)
local function StyleCloseButton(closeButton)
    if not closeButton then return end
    if closeButton.Border then closeButton.Border:SetAlpha(0) end
end

-- Skin PVEFrame (main container)
local function SkinPVEFrame()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or PVEFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide all Blizzard decorations
    HidePVEDecorations()

    -- Create main backdrop
    CreateQUIBackdrop(PVEFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Style close button (minimal - just hide border per QUI pattern)
    local closeButton = PVEFrame.CloseButton or _G.PVEFrameCloseButton
    if closeButton then
        StyleCloseButton(closeButton)
    end

    -- Style tabs
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then
            StyleTab(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Reposition tabs: left justify and tighten spacing
    -- Blizzard default: Tab1 at x=19, Tab2-3 at -16px overlap, Tab4 at +3px gap
    -- QUI: Tab1 at x=-3, tabs at -5px spacing
    _G.PVEFrameTab1:ClearAllPoints()
    _G.PVEFrameTab2:ClearAllPoints()
    _G.PVEFrameTab3:ClearAllPoints()
    _G.PVEFrameTab1:SetPoint("BOTTOMLEFT", PVEFrame, "BOTTOMLEFT", -3, -30)
    _G.PVEFrameTab2:SetPoint("TOPLEFT", _G.PVEFrameTab1, "TOPRIGHT", -5, 0)
    _G.PVEFrameTab3:SetPoint("TOPLEFT", _G.PVEFrameTab2, "TOPRIGHT", -5, 0)

    -- Hook to reposition Tab4 (Delves) - Blizzard repositions it dynamically
    -- Note: Tab4 may not exist in all WoW versions (e.g., 12.x beta)
    hooksecurefunc("PVEFrame_ShowFrame", function()
        local tab4 = _G.PVEFrameTab4
        if not tab4 or not tab4:IsShown() then return end
        local twoShown = _G.PVEFrameTab2:IsShown()
        local threeShown = _G.PVEFrameTab3:IsShown()
        tab4:ClearAllPoints()
        tab4:SetPoint("TOPLEFT", (twoShown and threeShown and _G.PVEFrameTab3) or (twoShown and not threeShown and _G.PVEFrameTab2) or _G.PVEFrameTab1, "TOPRIGHT", -5, 0)
    end)

    -- Style GroupFinder buttons
    local GroupFinderFrame = _G.GroupFinderFrame
    if GroupFinderFrame then
        for i = 1, 4 do
            local button = GroupFinderFrame["groupButton" .. i]
            if button then
                StyleGroupFinderButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    PVEFrame.quiSkinned = true
end

-- Hide LFD decorations
local function HideLFDDecorations()
    local LFDQueueFrame = _G.LFDQueueFrame
    if not LFDQueueFrame then return end

    -- LFDParentFrame (the container for LFD content)
    if _G.LFDParentFrame then
        StripTextures(_G.LFDParentFrame)
    end
    if _G.LFDParentFrameInset then
        StripTextures(_G.LFDParentFrameInset)
        _G.LFDParentFrameInset:Hide()
    end

    -- Background and inset
    if LFDQueueFrame.Bg then LFDQueueFrame.Bg:Hide() end
    if LFDQueueFrame.Background then LFDQueueFrame.Background:Hide() end
    if LFDQueueFrame.NineSlice then LFDQueueFrame.NineSlice:Hide() end

    -- Global decorations
    if _G.LFDQueueFrameBackground then _G.LFDQueueFrameBackground:Hide() end
    if _G.LFDQueueFrameRandomScrollFrameScrollBarBorder then
        _G.LFDQueueFrameRandomScrollFrameScrollBarBorder:Hide()
    end

    -- Specific dropdown decorations
    if LFDQueueFrame.Dropdown then
        if LFDQueueFrame.Dropdown.Left then LFDQueueFrame.Dropdown.Left:SetAlpha(0) end
        if LFDQueueFrame.Dropdown.Right then LFDQueueFrame.Dropdown.Right:SetAlpha(0) end
        if LFDQueueFrame.Dropdown.Middle then LFDQueueFrame.Dropdown.Middle:SetAlpha(0) end
    end

    StripTextures(LFDQueueFrame)
end

-- Hide Raid Finder decorations
local function HideRaidFinderDecorations()
    local RaidFinderFrame = _G.RaidFinderFrame
    if not RaidFinderFrame then return end

    StripTextures(RaidFinderFrame)

    -- Role background (gradient texture behind role buttons)
    if _G.RaidFinderFrameRoleBackground then
        _G.RaidFinderFrameRoleBackground:Hide()
    end
    if RaidFinderFrame.RoleBackground then
        RaidFinderFrame.RoleBackground:Hide()
    end

    -- Role inset (top inset around role buttons) - hide the entire frame
    local roleInset = _G.RaidFinderFrameRoleInset or (RaidFinderFrame.Inset)
    if roleInset then
        StripTextures(roleInset)
        roleInset:Hide()
    end

    -- Bottom inset (around raid selection area) - hide the entire frame
    local bottomInset = _G.RaidFinderFrameBottomInset
    if bottomInset then
        StripTextures(bottomInset)
        bottomInset:Hide()
    end

    -- Queue frame
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame then
        StripTextures(RaidFinderQueueFrame)
        if RaidFinderQueueFrame.Bg then RaidFinderQueueFrame.Bg:Hide() end
        if RaidFinderQueueFrame.Background then RaidFinderQueueFrame.Background:Hide() end

        -- Hide scroll frame background if present
        local scrollFrame = _G.RaidFinderQueueFrameScrollFrame
        if scrollFrame then
            StripTextures(scrollFrame)
        end
    end

    -- Background (quest paper texture)
    if _G.RaidFinderQueueFrameBackground then _G.RaidFinderQueueFrameBackground:Hide() end

    -- Also try common child patterns
    for _, name in ipairs({"NineSlice", "Bg", "Border", "Background", "InsetBorderTop", "InsetBorderBottom", "InsetBorderLeft", "InsetBorderRight"}) do
        local child = RaidFinderFrame[name]
        if child and child.Hide then child:Hide() end
    end
end

-- Skin LFDQueueFrame (Dungeon Finder)
local function SkinLFDFrame()
    local LFDQueueFrame = _G.LFDQueueFrame
    if not LFDQueueFrame or LFDQueueFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide Blizzard decorations
    HideLFDDecorations()

    -- Style role buttons - hide decorative elements
    local roles = { "Tank", "Healer", "DPS" }
    for _, role in ipairs(roles) do
        local button = _G["LFDQueueFrameRoleButton" .. role]
        if button then
            -- Hide the background texture (causes doubled icon appearance)
            if button.background then button.background:SetAlpha(0) end
            if button.Background then button.Background:SetAlpha(0) end
            -- Also check for global name pattern
            local bgTex = _G["LFDQueueFrameRoleButton" .. role .. "Background"]
            if bgTex then bgTex:SetAlpha(0) end

            if button.shortageBorder then button.shortageBorder:SetAlpha(0) end
            if button.cover then button.cover:SetAlpha(0) end
            if button.checkButton then
                -- Style checkbox
                local check = button.checkButton
                if check.SetNormalTexture then check:SetNormalTexture("") end
                if check.SetPushedTexture then check:SetPushedTexture("") end
            end
            local incentiveIcon = _G["LFDQueueFrameRoleButton" .. role .. "IncentiveIcon"]
            if incentiveIcon then incentiveIcon:SetAlpha(0) end
        end
    end

    -- Style find group button
    if _G.LFDQueueFrameFindGroupButton then
        StyleButton(_G.LFDQueueFrameFindGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Style type dropdown
    local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
    if typeDropdown then
        StyleDropdown(typeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga, 200)
    end

    LFDQueueFrame.quiSkinned = true
end

-- Skin RaidFinderQueueFrame (Raid Finder)
local function SkinRaidFinderFrame()
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if not RaidFinderQueueFrame or RaidFinderQueueFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide Blizzard decorations
    HideRaidFinderDecorations()

    -- Style role buttons - hide decorative elements (same as LFD)
    local roles = { "Tank", "Healer", "DPS" }
    for _, role in ipairs(roles) do
        local button = _G["RaidFinderQueueFrameRoleButton" .. role]
        if button then
            -- Hide the background texture (causes doubled icon appearance)
            if button.background then button.background:SetAlpha(0) end
            if button.Background then button.Background:SetAlpha(0) end
            local bgTex = _G["RaidFinderQueueFrameRoleButton" .. role .. "Background"]
            if bgTex then bgTex:SetAlpha(0) end

            if button.shortageBorder then button.shortageBorder:SetAlpha(0) end
            if button.cover then button.cover:SetAlpha(0) end
            if button.checkButton then
                local check = button.checkButton
                if check.SetNormalTexture then check:SetNormalTexture("") end
                if check.SetPushedTexture then check:SetPushedTexture("") end
            end
            local incentiveIcon = _G["RaidFinderQueueFrameRoleButton" .. role .. "IncentiveIcon"]
            if incentiveIcon then incentiveIcon:SetAlpha(0) end
        end
    end

    -- Style find raid button
    if _G.RaidFinderFrameFindRaidButton then
        StyleButton(_G.RaidFinderFrameFindRaidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Style selection dropdown
    local selectionDropdown = RaidFinderQueueFrame.SelectionDropdown
    if selectionDropdown then
        StyleDropdown(selectionDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga, 200)
    end

    RaidFinderQueueFrame.quiSkinned = true
end

-- Hide LFGList decorations
local function HideLFGListDecorations()
    local LFGListFrame = _G.LFGListFrame
    if not LFGListFrame then return end

    -- Main frame decorations
    if LFGListFrame.Bg then LFGListFrame.Bg:Hide() end
    if LFGListFrame.Background then LFGListFrame.Background:Hide() end
    if LFGListFrame.NineSlice then LFGListFrame.NineSlice:Hide() end

    -- Category selection decorations
    if LFGListFrame.CategorySelection then
        local cs = LFGListFrame.CategorySelection
        if cs.Inset then
            cs.Inset:Hide()
            if cs.Inset.NineSlice then cs.Inset.NineSlice:Hide() end
        end
        StripTextures(cs)
    end

    -- Search panel decorations
    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.ResultsInset then
            sp.ResultsInset:Hide()
            if sp.ResultsInset.NineSlice then sp.ResultsInset.NineSlice:Hide() end
        end
        if sp.AutoCompleteFrame then
            StripTextures(sp.AutoCompleteFrame)
        end
        StripTextures(sp)
    end

    -- Application viewer decorations
    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.Inset then
            av.Inset:Hide()
            if av.Inset.NineSlice then av.Inset.NineSlice:Hide() end
        end
        if av.InfoBackground then av.InfoBackground:Hide() end
        StripTextures(av)
    end

    -- Entry creation decorations
    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.Inset then
            ec.Inset:Hide()
            if ec.Inset.NineSlice then ec.Inset.NineSlice:Hide() end
        end
        StripTextures(ec)
    end

    StripTextures(LFGListFrame)
end

-- Skin LFGListFrame (Premade Groups)
local function SkinLFGListFrame()
    local LFGListFrame = _G.LFGListFrame
    if not LFGListFrame or LFGListFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide Blizzard decorations
    HideLFGListDecorations()

    -- Style category selection
    if LFGListFrame.CategorySelection then
        local cs = LFGListFrame.CategorySelection
        if cs.StartGroupButton then
            StyleButton(cs.StartGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if cs.FindGroupButton then
            StyleButton(cs.FindGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Style category buttons
        if cs.CategoryButtons then
            for _, catButton in pairs(cs.CategoryButtons) do
                if catButton and not catButton.quiStyled then
                    StripTextures(catButton)
                    StyleButton(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
        end
    end

    -- Style search panel
    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.BackButton then
            StyleButton(sp.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if sp.SignUpButton then
            StyleButton(sp.SignUpButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if sp.RefreshButton then
            StyleButton(sp.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Style search box
        if sp.SearchBox then
            StripTextures(sp.SearchBox)
            CreateQUIBackdrop(sp.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Style filter button
        if sp.FilterButton then
            StyleButton(sp.FilterButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Style application viewer
    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.RefreshButton then
            StyleButton(av.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if av.RemoveEntryButton then
            StyleButton(av.RemoveEntryButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if av.EditButton then
            StyleButton(av.EditButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Style entry creation
    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.ListGroupButton then
            StyleButton(ec.ListGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if ec.CancelButton then
            StyleButton(ec.CancelButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    LFGListFrame.quiSkinned = true
end

-- Hide Challenges decorations
local function HideChallengesDecorations()
    local ChallengesFrame = _G.ChallengesFrame
    if not ChallengesFrame then return end

    -- Main background and decorations
    if ChallengesFrame.Background then ChallengesFrame.Background:Hide() end
    if ChallengesFrame.Bg then ChallengesFrame.Bg:Hide() end
    if ChallengesFrame.NineSlice then ChallengesFrame.NineSlice:Hide() end

    -- Seasonal affix frame
    if ChallengesFrame.SeasonChangeNoticeFrame then
        StripTextures(ChallengesFrame.SeasonChangeNoticeFrame)
    end

    StripTextures(ChallengesFrame)
end

-- Style dungeon icon frame for M+
local function StyleDungeonIcon(icon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not icon or icon.quiStyled then return end

    -- Hide default backgrounds
    if icon.Bg then icon.Bg:SetAlpha(0) end
    if icon.Background then icon.Background:SetAlpha(0) end

    -- Style the icon texture
    if icon.Icon then
        icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if not icon.Icon.quiBackdrop then
            icon.Icon.quiBackdrop = CreateFrame("Frame", nil, icon, "BackdropTemplate")
            icon.Icon.quiBackdrop:SetPoint("TOPLEFT", icon.Icon, -1, 1)
            icon.Icon.quiBackdrop:SetPoint("BOTTOMRIGHT", icon.Icon, 1, -1)
            icon.Icon.quiBackdrop:SetFrameLevel(icon:GetFrameLevel())
            icon.Icon.quiBackdrop:EnableMouse(false)
            icon.Icon.quiBackdrop:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            icon.Icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end

    -- Store colors
    icon.quiSkinColor = { sr, sg, sb, sa }

    icon.quiStyled = true
end

-- Style affix icon for M+
local function StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not affix or affix.quiStyled then return end

    -- Hide border texture
    if affix.Border then affix.Border:SetAlpha(0) end

    -- Style portrait/icon
    if affix.Portrait then
        affix.Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        if not affix.Portrait.quiBackdrop then
            affix.Portrait.quiBackdrop = CreateFrame("Frame", nil, affix, "BackdropTemplate")
            affix.Portrait.quiBackdrop:SetPoint("TOPLEFT", affix.Portrait, -1, 1)
            affix.Portrait.quiBackdrop:SetPoint("BOTTOMRIGHT", affix.Portrait, 1, -1)
            affix.Portrait.quiBackdrop:SetFrameLevel(affix:GetFrameLevel())
            affix.Portrait.quiBackdrop:EnableMouse(false)
            affix.Portrait.quiBackdrop:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            affix.Portrait.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end

    affix.quiStyled = true
end

-- Skin ChallengesFrame (M+ Dungeons tab)
local function SkinChallengesFrame()
    local ChallengesFrame = _G.ChallengesFrame
    if not ChallengesFrame or ChallengesFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide Blizzard decorations
    HideChallengesDecorations()

    -- Style the weekly best frame
    if ChallengesFrame.WeeklyInfo then
        local wi = ChallengesFrame.WeeklyInfo
        if wi.Child then
            if wi.Child.WeeklyChest then
                local chest = wi.Child.WeeklyChest
                if chest.Highlight then chest.Highlight:SetAlpha(0) end
            end
            -- Style labels
            if wi.Child.Label then
                local QUI = _G.QUI
                local fontPath = QUI and QUI.GetGlobalFont and QUI:GetGlobalFont() or STANDARD_TEXT_FONT
                wi.Child.Label:SetFont(fontPath, 14, "OUTLINE")
            end
        end
    end

    -- Style dungeon icons (dynamically created)
    if ChallengesFrame.DungeonIcons then
        for _, icon in pairs(ChallengesFrame.DungeonIcons) do
            StyleDungeonIcon(icon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Hook to style new dungeon icons when they're created/updated
    if ChallengesFrame.Update and not ChallengesFrame.quiUpdateHooked then
        hooksecurefunc(ChallengesFrame, "Update", function(self)
            if self.DungeonIcons then
                local sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2 = GetColors()
                for _, icon in pairs(self.DungeonIcons) do
                    StyleDungeonIcon(icon, sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2)
                end
            end
        end)
        ChallengesFrame.quiUpdateHooked = true
    end

    -- Style affix frames (check for container first)
    if ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child then
        local affixContainer = ChallengesFrame.WeeklyInfo.Child.AffixesContainer
        if affixContainer and affixContainer.Affixes then
            for _, affix in pairs(affixContainer.Affixes) do
                StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end
    end

    -- Also check direct affix references (older pattern)
    for i = 1, 4 do
        local affix = ChallengesFrame["Affix" .. i]
        if affix then
            StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    ChallengesFrame.quiSkinned = true
end

-- Hide PVP decorations
local function HidePVPDecorations()
    local PVPQueueFrame = _G.PVPQueueFrame
    if not PVPQueueFrame then return end

    -- Main frame decorations
    if PVPQueueFrame.Bg then PVPQueueFrame.Bg:Hide() end
    if PVPQueueFrame.Background then PVPQueueFrame.Background:Hide() end
    if PVPQueueFrame.NineSlice then PVPQueueFrame.NineSlice:Hide() end

    -- HonorInset decorations
    if PVPQueueFrame.HonorInset then
        if PVPQueueFrame.HonorInset.NineSlice then PVPQueueFrame.HonorInset.NineSlice:Hide() end
    end

    -- Honor frame decorations
    if _G.HonorFrame then
        local hf = _G.HonorFrame
        if hf.Bg then hf.Bg:Hide() end
        if hf.Background then hf.Background:Hide() end
        if hf.NineSlice then hf.NineSlice:Hide() end
        if hf.Inset then
            hf.Inset:Hide()
            if hf.Inset.NineSlice then hf.Inset.NineSlice:Hide() end
        end
        -- BonusFrame decorations
        if hf.BonusFrame then
            if hf.BonusFrame.ShadowOverlay then hf.BonusFrame.ShadowOverlay:Hide() end
            if hf.BonusFrame.WorldBattlesTexture then hf.BonusFrame.WorldBattlesTexture:Hide() end
            StripTextures(hf.BonusFrame)
        end
        StripTextures(hf)
    end

    -- Conquest frame decorations
    if _G.ConquestFrame then
        local cf = _G.ConquestFrame
        if cf.Bg then cf.Bg:Hide() end
        if cf.Background then cf.Background:Hide() end
        if cf.NineSlice then cf.NineSlice:Hide() end
        if cf.Inset then
            cf.Inset:Hide()
            if cf.Inset.NineSlice then cf.Inset.NineSlice:Hide() end
        end
        if cf.ShadowOverlay then cf.ShadowOverlay:Hide() end
        StripTextures(cf)
    end

    StripTextures(PVPQueueFrame)
end

-- Style PVP bonus/activity button (right side activity buttons)
local function StylePVPActivityButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or button.quiStyled then return end

    -- Hide default textures
    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.Ring then button.Ring:Hide() end

    -- Create backdrop
    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetAllPoints()
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Style selected texture
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.2)
    end

    -- Style reward icon if present
    if button.Reward then
        local reward = button.Reward
        if reward.Border then reward.Border:Hide() end
        if reward.CircleMask then reward.CircleMask:Hide() end
        if reward.Icon then
            reward.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if not reward.Icon.quiBackdrop then
                reward.Icon.quiBackdrop = CreateFrame("Frame", nil, reward, "BackdropTemplate")
                reward.Icon.quiBackdrop:SetPoint("TOPLEFT", reward.Icon, -1, 1)
                reward.Icon.quiBackdrop:SetPoint("BOTTOMRIGHT", reward.Icon, 1, -1)
                reward.Icon.quiBackdrop:SetFrameLevel(reward:GetFrameLevel())
                reward.Icon.quiBackdrop:EnableMouse(false)
                reward.Icon.quiBackdrop:SetBackdrop({
                    bgFile = nil,
                    edgeFile = "Interface\\Buttons\\WHITE8x8",
                    edgeSize = 1,
                })
                reward.Icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
            end
        end
    end

    -- Store colors for hover
    button.quiSkinColor = { sr, sg, sb, sa }

    button:HookScript("OnEnter", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            local r, g, b, a = unpack(self.quiSkinColor)
            self.quiBackdrop:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self.quiBackdrop and self.quiSkinColor then
            self.quiBackdrop:SetBackdropBorderColor(unpack(self.quiSkinColor))
        end
    end)

    button.quiStyled = true
end

-- Style PVP role icon button
local function StylePVPRoleIcon(roleIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not roleIcon or roleIcon.quiStyled then return end

    -- Hide decorations
    if roleIcon.background then roleIcon.background:SetAlpha(0) end
    if roleIcon.Background then roleIcon.Background:SetAlpha(0) end
    if roleIcon.shortageBorder then roleIcon.shortageBorder:SetAlpha(0) end
    if roleIcon.cover then roleIcon.cover:SetAlpha(0) end

    roleIcon.quiStyled = true
end

-- Style specific battleground list button (PVPSpecificBattlegroundButtonTemplate)
local function StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or button.quiStyled then return end

    -- Hide default textures
    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end

    -- Create backdrop
    if not button.quiBackdrop then
        button.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        button.quiBackdrop:SetAllPoints()
        button.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
        button.quiBackdrop:EnableMouse(false)
    end

    button.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })

    local btnBgR = math.min(bgr + 0.05, 1)
    local btnBgG = math.min(bgg + 0.05, 1)
    local btnBgB = math.min(bgb + 0.05, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 0.9)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Style selected texture
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.3)
        button.SelectedTexture:SetAllPoints()
    end

    -- Style icon border
    if button.Icon then
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if not button.Icon.quiBackdrop then
            button.Icon.quiBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            button.Icon.quiBackdrop:SetPoint("TOPLEFT", button.Icon, -1, 1)
            button.Icon.quiBackdrop:SetPoint("BOTTOMRIGHT", button.Icon, 1, -1)
            button.Icon.quiBackdrop:SetFrameLevel(button:GetFrameLevel())
            button.Icon.quiBackdrop:EnableMouse(false)
            button.Icon.quiBackdrop:SetBackdrop({
                bgFile = nil,
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
            })
            button.Icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end

    -- Add hover highlight
    button:HookScript("OnEnter", function(self)
        if self.quiBackdrop then
            self.quiBackdrop:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end)
    button:HookScript("OnLeave", function(self)
        if self.quiBackdrop then
            self.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end)

    button.quiStyled = true
end

-- Style PVP conquest bar
local function StyleConquestBar(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not bar or bar.quiStyled then return end

    if bar.Border then bar.Border:Hide() end
    if bar.Background then bar.Background:Hide() end

    -- Create backdrop
    if not bar.quiBackdrop then
        bar.quiBackdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        bar.quiBackdrop:SetAllPoints()
        bar.quiBackdrop:SetFrameLevel(bar:GetFrameLevel())
        bar.quiBackdrop:EnableMouse(false)
    end

    bar.quiBackdrop:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    bar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
    bar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)

    -- Style reward icon
    if bar.Reward then
        if bar.Reward.Ring then bar.Reward.Ring:Hide() end
        if bar.Reward.CircleMask then bar.Reward.CircleMask:Hide() end
        if bar.Reward.Icon then
            bar.Reward.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    bar.quiStyled = true
end

-- Helper: Get role icons from a frame (handles both 11.x and 12.x API)
-- 11.x: frame.TankIcon, frame.HealerIcon, frame.DPSIcon
-- 12.x: frame.RoleList.TankIcon, frame.RoleList.HealerIcon, frame.RoleList.DPSIcon
local function GetRoleIcons(frame)
    if not frame then return nil, nil, nil end
    -- Try 12.x structure first (RoleList)
    if frame.RoleList then
        return frame.RoleList.TankIcon, frame.RoleList.HealerIcon, frame.RoleList.DPSIcon
    end
    -- Fall back to 11.x structure
    return frame.TankIcon, frame.HealerIcon, frame.DPSIcon
end

-- Style role icons for a PVP frame (handles both API versions)
local function StylePVPFrameRoleIcons(frame, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local tankIcon, healerIcon, dpsIcon = GetRoleIcons(frame)
    if tankIcon then StylePVPRoleIcon(tankIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
    if healerIcon then StylePVPRoleIcon(healerIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
    if dpsIcon then StylePVPRoleIcon(dpsIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga) end
end

-- Skin PVPQueueFrame
local function SkinPVPFrame()
    local PVPQueueFrame = _G.PVPQueueFrame
    if not PVPQueueFrame or PVPQueueFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Hide Blizzard decorations
    HidePVPDecorations()

    -- Style category buttons (left side buttons) - 5 in 12.x, 4 in 11.x
    -- PTR uses PVPQueueFrame.CategoryButton1, retail uses _G["PVPQueueFrameCategoryButton1"]
    for i = 1, 5 do
        local catButton = PVPQueueFrame["CategoryButton" .. i] or _G["PVPQueueFrameCategoryButton" .. i]
        if catButton then
            StyleGroupFinderButton(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Style Honor frame
    local HonorFrame = _G.HonorFrame
    if HonorFrame then
        -- Queue button
        if _G.HonorFrameQueueButton then
            StyleButton(_G.HonorFrameQueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Type dropdown
        local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
        if typeDropdown then
            StyleDropdown(typeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga, 230)
        end

        -- Role icons (handles both 11.x and 12.x API)
        StylePVPFrameRoleIcons(HonorFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- BonusFrame activity buttons
        if HonorFrame.BonusFrame then
            local bf = HonorFrame.BonusFrame
            local bonusButtons = { "RandomBGButton", "Arena1Button", "RandomEpicBGButton", "BrawlButton", "BrawlButton2", "SpecialEventButton" }
            for _, btnName in ipairs(bonusButtons) do
                if bf[btnName] then
                    StylePVPActivityButton(bf[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
        end

        -- Conquest bar
        if HonorFrame.ConquestBar then
            StyleConquestBar(HonorFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Specific battleground scroll list (shown when "Specific Battlegrounds" is selected)
        if HonorFrame.SpecificScrollBox and not HonorFrame.SpecificScrollBox.quiHooked then
            -- Hook to style buttons as they're created/recycled
            hooksecurefunc(HonorFrame.SpecificScrollBox, "Update", function(scrollBox)
                scrollBox:ForEachFrame(function(button)
                    StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end)
            end)
            -- Style existing buttons
            HonorFrame.SpecificScrollBox:ForEachFrame(function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
            HonorFrame.SpecificScrollBox.quiHooked = true
        end

        -- Style scroll bar if present
        if HonorFrame.SpecificScrollBar then
            if HonorFrame.SpecificScrollBar.Background then
                HonorFrame.SpecificScrollBar.Background:Hide()
            end
        end
    end

    -- Style Conquest frame
    local ConquestFrame = _G.ConquestFrame
    if ConquestFrame then
        -- Join button
        if _G.ConquestJoinButton then
            StyleButton(_G.ConquestJoinButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Role icons (handles both 11.x and 12.x API)
        StylePVPFrameRoleIcons(ConquestFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Activity buttons
        local conquestButtons = { "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG" }
        for _, btnName in ipairs(conquestButtons) do
            if ConquestFrame[btnName] then
                StylePVPActivityButton(ConquestFrame[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        -- Conquest bar
        if ConquestFrame.ConquestBar then
            StyleConquestBar(ConquestFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Style Training Grounds frame (12.x only - CategoryButton4)
    local TrainingGroundsFrame = _G.TrainingGroundsFrame
    if TrainingGroundsFrame then
        -- Hide decorations
        StripTextures(TrainingGroundsFrame)
        if TrainingGroundsFrame.Bg then TrainingGroundsFrame.Bg:Hide() end
        if TrainingGroundsFrame.Background then TrainingGroundsFrame.Background:Hide() end

        -- Hide Inset frame (InsetFrameTemplate has NineSlice border)
        if TrainingGroundsFrame.Inset then
            StripTextures(TrainingGroundsFrame.Inset)
            if TrainingGroundsFrame.Inset.NineSlice then
                TrainingGroundsFrame.Inset.NineSlice:Hide()
            end
        end

        -- Hide BonusTrainingGroundList decorations
        local bonusList = TrainingGroundsFrame.BonusTrainingGroundList
        if bonusList then
            if bonusList.WorldBattlesTexture then bonusList.WorldBattlesTexture:Hide() end
            if bonusList.ShadowOverlay then bonusList.ShadowOverlay:Hide() end
            -- Style the Random Training Ground button
            if bonusList.RandomTrainingGroundButton then
                StylePVPActivityButton(bonusList.RandomTrainingGroundButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        -- Queue button
        if TrainingGroundsFrame.QueueButton then
            StyleButton(TrainingGroundsFrame.QueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Type dropdown
        if TrainingGroundsFrame.TypeDropdown then
            StyleDropdown(TrainingGroundsFrame.TypeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga, 230)
        end

        -- Role icons
        StylePVPFrameRoleIcons(TrainingGroundsFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Conquest bar
        if TrainingGroundsFrame.ConquestBar then
            StyleConquestBar(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Specific Training Ground scroll list (12.x)
        local specificList = TrainingGroundsFrame.SpecificTrainingGroundList
        if specificList and specificList.ScrollBox and not specificList.ScrollBox.quiHooked then
            -- Hook to style buttons as they're created/recycled
            hooksecurefunc(specificList.ScrollBox, "Update", function(scrollBox)
                scrollBox:ForEachFrame(function(button)
                    StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end)
            end)
            -- Style existing buttons
            specificList.ScrollBox:ForEachFrame(function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
            specificList.ScrollBox.quiHooked = true

            -- Style scroll bar
            if specificList.ScrollBar and specificList.ScrollBar.Background then
                specificList.ScrollBar.Background:Hide()
            end
        end

        TrainingGroundsFrame.quiSkinned = true
    end

    -- Style Plunderstorm frame (12.x only - CategoryButton5)
    local PlunderstormFrame = _G.PlunderstormFrame
    if PlunderstormFrame then
        -- Hide decorations
        StripTextures(PlunderstormFrame)
        if PlunderstormFrame.Bg then PlunderstormFrame.Bg:Hide() end
        if PlunderstormFrame.Background then PlunderstormFrame.Background:Hide() end

        -- Queue button (if exists)
        if PlunderstormFrame.QueueButton then
            StyleButton(PlunderstormFrame.QueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        PlunderstormFrame.quiSkinned = true
    end

    PVPQueueFrame.quiSkinned = true
end

-- Main skinning function
local function SkinInstanceFrames()
    local QUICore = _G.QUI and _G.QUI.QUICore
    local settings = QUICore and QUICore.db and QUICore.db.profile and QUICore.db.profile.general
    if not settings or not settings.skinInstanceFrames then return end

    SkinPVEFrame()
    SkinLFDFrame()
    SkinRaidFinderFrame()
    SkinLFGListFrame()
    SkinChallengesFrame()
    SkinPVPFrame()
end

-- Helper to update a styled button's colors
local function UpdateButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or not button.quiBackdrop then return end
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    button.quiSkinColor = { sr, sg, sb, sa }
end

-- Helper to update a tab's colors
local function UpdateTabColors(tab, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not tab or not tab.quiBackdrop then return end
    tab.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.9)
    tab.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Helper to update GroupFinder button colors
local function UpdateGroupFinderButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or not button.quiBackdrop then return end
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    button.quiSkinColor = { sr, sg, sb, sa }
    -- Update icon border if present
    if button.icon and button.icon.quiBackdrop then
        button.icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- Helper to update PVP activity button colors
local function UpdatePVPActivityButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or not button.quiBackdrop then return end
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    button.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    button.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    button.quiSkinColor = { sr, sg, sb, sa }
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.2)
    end
    if button.Reward and button.Reward.Icon and button.Reward.Icon.quiBackdrop then
        button.Reward.Icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end
end

-- Helper to update conquest bar colors
local function UpdateConquestBarColors(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not bar or not bar.quiBackdrop then return end
    bar.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, 0.8)
    bar.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Helper to update dungeon icon colors
local function UpdateDungeonIconColors(icon, sr, sg, sb, sa)
    if not icon or not icon.Icon or not icon.Icon.quiBackdrop then return end
    icon.Icon.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    icon.quiSkinColor = { sr, sg, sb, sa }
end

-- Helper to update affix icon colors
local function UpdateAffixIconColors(affix, sr, sg, sb, sa)
    if not affix or not affix.Portrait or not affix.Portrait.quiBackdrop then return end
    affix.Portrait.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
end

-- Helper to update dropdown colors
local function UpdateDropdownColors(dropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not dropdown or not dropdown.quiBackdrop then return end
    local btnBgR = math.min(bgr + 0.07, 1)
    local btnBgG = math.min(bgg + 0.07, 1)
    local btnBgB = math.min(bgb + 0.07, 1)
    dropdown.quiBackdrop:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    dropdown.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    dropdown.quiSkinColor = { sr, sg, sb, sa }
end

-- Refresh colors
local function RefreshInstanceFramesColors()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or not PVEFrame.quiSkinned then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = GetColors()

    -- Update PVEFrame backdrop
    if PVEFrame.quiBackdrop then
        PVEFrame.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
        PVEFrame.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update PVE tabs
    for i = 1, 4 do
        UpdateTabColors(_G["PVEFrameTab" .. i], sr, sg, sb, sa, bgr, bgg, bgb, bga)
    end

    -- Update GroupFinder buttons
    local GroupFinderFrame = _G.GroupFinderFrame
    if GroupFinderFrame then
        for i = 1, 4 do
            UpdateGroupFinderButtonColors(GroupFinderFrame["groupButton" .. i], sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Update LFD buttons and dropdown
    UpdateButtonColors(_G.LFDQueueFrameFindGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local LFDQueueFrame = _G.LFDQueueFrame
    if LFDQueueFrame then
        local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
        if typeDropdown then
            UpdateDropdownColors(typeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Update Raid Finder buttons and dropdown
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame and RaidFinderQueueFrame.quiSkinned then
        UpdateButtonColors(_G.RaidFinderFrameFindRaidButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        if RaidFinderQueueFrame.SelectionDropdown then
            UpdateDropdownColors(RaidFinderQueueFrame.SelectionDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Update LFGListFrame buttons
    local LFGListFrame = _G.LFGListFrame
    if LFGListFrame and LFGListFrame.quiSkinned then
        if LFGListFrame.CategorySelection then
            UpdateButtonColors(LFGListFrame.CategorySelection.StartGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.CategorySelection.FindGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            if LFGListFrame.CategorySelection.CategoryButtons then
                for _, catButton in pairs(LFGListFrame.CategorySelection.CategoryButtons) do
                    UpdateButtonColors(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
        end
        if LFGListFrame.SearchPanel then
            UpdateButtonColors(LFGListFrame.SearchPanel.BackButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.SearchPanel.SignUpButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.SearchPanel.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.SearchPanel.FilterButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            if LFGListFrame.SearchPanel.SearchBox and LFGListFrame.SearchPanel.SearchBox.quiBackdrop then
                LFGListFrame.SearchPanel.SearchBox.quiBackdrop:SetBackdropColor(bgr, bgg, bgb, bga)
                LFGListFrame.SearchPanel.SearchBox.quiBackdrop:SetBackdropBorderColor(sr, sg, sb, sa)
            end
        end
        if LFGListFrame.ApplicationViewer then
            UpdateButtonColors(LFGListFrame.ApplicationViewer.RefreshButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.ApplicationViewer.RemoveEntryButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.ApplicationViewer.EditButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        if LFGListFrame.EntryCreation then
            UpdateButtonColors(LFGListFrame.EntryCreation.ListGroupButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            UpdateButtonColors(LFGListFrame.EntryCreation.CancelButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Update Challenges/M+ dungeon icons and affixes
    local ChallengesFrame = _G.ChallengesFrame
    if ChallengesFrame and ChallengesFrame.quiSkinned then
        if ChallengesFrame.DungeonIcons then
            for _, icon in pairs(ChallengesFrame.DungeonIcons) do
                UpdateDungeonIconColors(icon, sr, sg, sb, sa)
            end
        end
        -- Update affixes
        if ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child then
            local affixContainer = ChallengesFrame.WeeklyInfo.Child.AffixesContainer
            if affixContainer and affixContainer.Affixes then
                for _, affix in pairs(affixContainer.Affixes) do
                    UpdateAffixIconColors(affix, sr, sg, sb, sa)
                end
            end
        end
        for i = 1, 4 do
            local affix = ChallengesFrame["Affix" .. i]
            if affix then
                UpdateAffixIconColors(affix, sr, sg, sb, sa)
            end
        end
    end

    -- Update PVP buttons and elements
    local PVPQueueFrame = _G.PVPQueueFrame
    if PVPQueueFrame and PVPQueueFrame.quiSkinned then
        -- Category buttons (5 in 12.x, 4 in 11.x)
        -- PTR uses PVPQueueFrame.CategoryButton1, retail uses _G["PVPQueueFrameCategoryButton1"]
        for i = 1, 5 do
            local catButton = PVPQueueFrame["CategoryButton" .. i] or _G["PVPQueueFrameCategoryButton" .. i]
            UpdateGroupFinderButtonColors(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Honor frame
        local HonorFrame = _G.HonorFrame
        if HonorFrame then
            UpdateButtonColors(_G.HonorFrameQueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            -- Type dropdown
            local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
            if typeDropdown then
                UpdateDropdownColors(typeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            -- Bonus frame buttons
            if HonorFrame.BonusFrame then
                local bf = HonorFrame.BonusFrame
                local bonusButtons = { "RandomBGButton", "Arena1Button", "RandomEpicBGButton", "BrawlButton", "BrawlButton2", "SpecialEventButton" }
                for _, btnName in ipairs(bonusButtons) do
                    if bf[btnName] then
                        UpdatePVPActivityButtonColors(bf[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                    end
                end
            end
            -- Conquest bar
            if HonorFrame.ConquestBar then
                UpdateConquestBarColors(HonorFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        -- Conquest frame
        local ConquestFrame = _G.ConquestFrame
        if ConquestFrame then
            UpdateButtonColors(_G.ConquestJoinButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            -- Activity buttons
            local conquestButtons = { "RatedSoloShuffle", "RatedBGBlitz", "Arena2v2", "Arena3v3", "RatedBG" }
            for _, btnName in ipairs(conquestButtons) do
                if ConquestFrame[btnName] then
                    UpdatePVPActivityButtonColors(ConquestFrame[btnName], sr, sg, sb, sa, bgr, bgg, bgb, bga)
                end
            end
            -- Conquest bar
            if ConquestFrame.ConquestBar then
                UpdateConquestBarColors(ConquestFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        -- Training Grounds frame (12.x only)
        local TrainingGroundsFrame = _G.TrainingGroundsFrame
        if TrainingGroundsFrame and TrainingGroundsFrame.quiSkinned then
            UpdateButtonColors(TrainingGroundsFrame.QueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            if TrainingGroundsFrame.TypeDropdown then
                UpdateDropdownColors(TrainingGroundsFrame.TypeDropdown, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
            if TrainingGroundsFrame.ConquestBar then
                UpdateConquestBarColors(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

        -- Plunderstorm frame (12.x only)
        local PlunderstormFrame = _G.PlunderstormFrame
        if PlunderstormFrame and PlunderstormFrame.quiSkinned then
            UpdateButtonColors(PlunderstormFrame.QueueButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end
end

-- Expose refresh function globally
_G.QUI_RefreshInstanceFramesColors = RefreshInstanceFramesColors

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------

local pveHooked = false
local function HookPVEFrame()
    if pveHooked then return end
    if _G.PVEFrame then
        _G.PVEFrame:HookScript("OnShow", function()
            C_Timer.After(0.1, SkinInstanceFrames)
        end)
        pveHooked = true
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "Blizzard_PVPUI" or addon == "Blizzard_ChallengesUI" then
            C_Timer.After(0.1, SkinInstanceFrames)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookPVEFrame()
        C_Timer.After(1, SkinInstanceFrames)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
