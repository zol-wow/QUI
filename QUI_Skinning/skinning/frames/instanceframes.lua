local addonName, ns = ...

local GetCore = ns.Helpers.GetCore
local Helpers = ns.Helpers
local SkinBase = ns.SkinBase

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

-- Recursively re-lock the QUI font on a frame's fontstrings. Unlike the
-- one-shot SkinFrameText, this hooks each fontstring's SetFontObject (and a
-- button's SetNormalFontObject) via SkinBase.LockFontObject, so Blizzard's
-- hover / selection / list re-bind font-object swaps don't revert our font.
-- Idempotent per object (LockFontObject guards with its own qFontLocked flag),
-- so it is safe to call repeatedly on pooled rows and on re-skins.
local function LockFrameTextObjects(frame, maxDepth)
    if not frame then return end
    maxDepth = maxDepth or 4
    if frame.GetObjectType and frame:GetObjectType() == "Button" and frame.SetNormalFontObject then
        SkinBase.LockFontObject(frame, { fontOnly = true })
    end
    if frame.GetRegions then
        for i = 1, select("#", frame:GetRegions()) do
            local region = select(i, frame:GetRegions())
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                SkinBase.LockFontObject(region, { fontOnly = true })
            end
        end
    end
    if maxDepth > 0 and frame.GetChildren then
        for i = 1, select("#", frame:GetChildren()) do
            LockFrameTextObjects(select(i, frame:GetChildren()), maxDepth - 1)
        end
    end
end

---------------------------------------------------------------------------
-- INSTANCE FRAMES SKINNING (PVE, Dungeons & Raids, PVP, M+ Dungeons)
---------------------------------------------------------------------------

-- Hide all Blizzard decorations on PVEFrame (following character.lua/inspect.lua patterns)
local function HidePVEDecorations()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame then return end

    -- Main frame shadows (contains vertical divider line)
    if PVEFrame.shadows then
        PVEFrame.shadows:Hide()
        -- Also strip all textures inside shadows frame
        SkinBase.StripTextures(PVEFrame.shadows)
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

    SkinBase.HidePortraitFrameChrome(PVEFrame)

    -- PVE-specific full-inset hide and legacy globals not on the template.
    if _G.PVEFrameLeftInset then _G.PVEFrameLeftInset:Hide() end
    if PVEFrame.Inset then PVEFrame.Inset:Hide() end
    if _G.PVEFramePortrait then _G.PVEFramePortrait:Hide() end
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
    SkinBase.StripTextures(PVEFrame)
end

-- Boosted button background colors (slightly lighter than the panel background)
local function ButtonBoostColors(bgr, bgg, bgb)
    return math.min(bgr + SkinBase.CHROME.BUTTON_BOOST, 1),
           math.min(bgg + SkinBase.CHROME.BUTTON_BOOST, 1),
           math.min(bgb + SkinBase.CHROME.BUTTON_BOOST, 1)
end

-- Install the standard skinColor-based hover brighten/restore border hooks.
-- Reads the stored "backdrop"/"skinColor" frame data set by the styler.
local function AddSkinColorHoverBorder(button)
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

-- Style GroupFinder buttons (LFD, Raid Finder, Premade Groups on the left)
local function StyleGroupFinderButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    -- Hide default textures - check both lowercase (11.x) and uppercase (12.x PTR) keys
    if button.ring then button.ring:Hide() end
    if button.Ring then button.Ring:Hide() end
    if button.bg then button.bg:SetAlpha(0) end
    if button.Background then button.Background:Hide() end

    -- Create backdrop for button
    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    SkinBase.ApplyFullBackdrop(backdrop, sr, sg, sb, sa, btnBgR, btnBgG, btnBgB, 1)

    -- Style the icon
    if button.icon then
        button.icon:SetSize(40, 40)
        button.icon:ClearAllPoints()
        button.icon:SetPoint("LEFT", 8, 0)
        button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Add icon border
        local iconBackdrop = SkinBase.GetFrameData(button.icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, button.icon, 1)
            iconBackdrop:SetFrameLevel(button:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(button.icon, "backdrop", iconBackdrop)
        end
    end

    -- Store colors for hover
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    AddSkinColorHoverBorder(button)

    SkinBase.MarkStyled(button)
end

-- Skin PVEFrame (main container)
local function SkinPVEFrame()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or SkinBase.IsSkinned(PVEFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Hide all Blizzard decorations
    HidePVEDecorations()

    -- Create main backdrop
    SkinBase.CreateBackdrop(PVEFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

    -- Style close button
    SkinBase.SkinCloseButton(PVEFrame.CloseButton or _G.PVEFrameCloseButton)

    -- Style tabs (SkinTabGroup adds selected-state highlighting, matching the
    -- other skinned frames — the active PVE tab is now indicated).
    local pveTabs = {}
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then pveTabs[#pveTabs + 1] = tab end
    end
    SkinBase.SkinTabGroup(pveTabs, PVEFrame)

    -- Reposition tabs: left justify and tighten spacing
    -- Blizzard default: Tab1 at x=19, Tab2-3 at -16px overlap, Tab4 at +3px gap
    -- QUI: Tab1 at x=-3, tabs at -5px spacing
    local pveTab1, pveTab2, pveTab3 = _G.PVEFrameTab1, _G.PVEFrameTab2, _G.PVEFrameTab3
    if pveTab1 then
        pveTab1:ClearAllPoints()
        pveTab1:SetPoint("BOTTOMLEFT", PVEFrame, "BOTTOMLEFT", -3, -30)
    end
    if pveTab2 then
        pveTab2:ClearAllPoints()
        pveTab2:SetPoint("TOPLEFT", pveTab1 or PVEFrame, "TOPRIGHT", -5, 0)
    end
    if pveTab3 then
        pveTab3:ClearAllPoints()
        pveTab3:SetPoint("TOPLEFT", pveTab2 or pveTab1 or PVEFrame, "TOPRIGHT", -5, 0)
    end

    -- Hook to reposition Tab4 (Delves) - Blizzard repositions it dynamically
    -- Note: Tab4 may not exist in all WoW versions (e.g., 12.x beta)
    -- TAINT SAFETY: Defer to break taint chain from secure context.
    hooksecurefunc("PVEFrame_ShowFrame", function()
        C_Timer.After(0, function()
            local tab4 = _G.PVEFrameTab4
            if not tab4 or not tab4:IsShown() then return end
            local tab2 = _G.PVEFrameTab2
            local tab3 = _G.PVEFrameTab3
            local twoShown = tab2 and tab2:IsShown()
            local threeShown = tab3 and tab3:IsShown()
            tab4:ClearAllPoints()
            tab4:SetPoint("TOPLEFT", (twoShown and threeShown and tab3) or (twoShown and not threeShown and tab2) or _G.PVEFrameTab1, "TOPRIGHT", -5, 0)
        end)
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

    SkinBase.SkinFrameText(PVEFrame, { recurse = true })
    SkinBase.MarkSkinned(PVEFrame)
end

-- Hide LFD decorations
local function HideLFDDecorations()
    local LFDQueueFrame = _G.LFDQueueFrame
    if not LFDQueueFrame then return end

    -- LFDParentFrame (the container for LFD content)
    if _G.LFDParentFrame then
        SkinBase.StripTextures(_G.LFDParentFrame)
    end
    if _G.LFDParentFrameInset then
        SkinBase.StripTextures(_G.LFDParentFrameInset)
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

    SkinBase.StripTextures(LFDQueueFrame)
end

-- Hide Raid Finder decorations
local function HideRaidFinderDecorations()
    local RaidFinderFrame = _G.RaidFinderFrame
    if not RaidFinderFrame then return end

    SkinBase.StripTextures(RaidFinderFrame)

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
        SkinBase.StripTextures(roleInset)
        roleInset:Hide()
    end

    -- Bottom inset (around raid selection area) - hide the entire frame
    local bottomInset = _G.RaidFinderFrameBottomInset
    if bottomInset then
        SkinBase.StripTextures(bottomInset)
        bottomInset:Hide()
    end

    -- Queue frame
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame then
        SkinBase.StripTextures(RaidFinderQueueFrame)
        if RaidFinderQueueFrame.Bg then RaidFinderQueueFrame.Bg:Hide() end
        if RaidFinderQueueFrame.Background then RaidFinderQueueFrame.Background:Hide() end

        -- Hide scroll frame background if present
        local scrollFrame = _G.RaidFinderQueueFrameScrollFrame
        if scrollFrame then
            SkinBase.StripTextures(scrollFrame)
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
    if not LFDQueueFrame or SkinBase.IsSkinned(LFDQueueFrame) then return end

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
        SkinBase.SkinButton(_G.LFDQueueFrameFindGroupButton)
    end

    -- Style type dropdown
    local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
    if typeDropdown then
        typeDropdown:SetWidth(200)
        SkinBase.SkinDropdown(typeDropdown, { keepArrow = true, insetY = 2 })
    end

    -- Specific-dungeon selection list: pooled ScrollBox rows get their font
    -- OBJECT swapped on hover/selection/re-bind, reverting the one-shot
    -- SkinFrameText below. Re-lock the QUI font as each row is acquired.
    local specificList = LFDQueueFrame.Specific
    if specificList and specificList.ScrollBox then
        SkinBase.HookScrollBoxAcquired(specificList.ScrollBox, function(row)
            LockFrameTextObjects(row, 2)
        end)
    end

    SkinBase.SkinFrameText(LFDQueueFrame, { recurse = true })
    SkinBase.MarkSkinned(LFDQueueFrame)
end

-- Skin RaidFinderQueueFrame (Raid Finder)
local function SkinRaidFinderFrame()
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if not RaidFinderQueueFrame or SkinBase.IsSkinned(RaidFinderQueueFrame) then return end

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
        SkinBase.SkinButton(_G.RaidFinderFrameFindRaidButton)
    end

    -- Style selection dropdown
    local selectionDropdown = RaidFinderQueueFrame.SelectionDropdown
    if selectionDropdown then
        selectionDropdown:SetWidth(200)
        SkinBase.SkinDropdown(selectionDropdown, { keepArrow = true, insetY = 2 })
    end

    -- Raid Finder uses a dropdown (no row list), but its queue-frame labels and
    -- reward fontstrings get their font OBJECT re-asserted on LFG/role updates,
    -- reverting the one-shot SkinFrameText. Lock the font objects so they stick.
    LockFrameTextObjects(RaidFinderQueueFrame, 4)

    SkinBase.SkinFrameText(RaidFinderQueueFrame, { recurse = true })
    SkinBase.MarkSkinned(RaidFinderQueueFrame)
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
        SkinBase.StripTextures(cs)
    end

    -- Search panel decorations
    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.ResultsInset then
            sp.ResultsInset:Hide()
            if sp.ResultsInset.NineSlice then sp.ResultsInset.NineSlice:Hide() end
        end
        if sp.AutoCompleteFrame then
            SkinBase.StripTextures(sp.AutoCompleteFrame)
        end
        SkinBase.StripTextures(sp)
    end

    -- Application viewer decorations
    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.Inset then
            av.Inset:Hide()
            if av.Inset.NineSlice then av.Inset.NineSlice:Hide() end
        end
        if av.InfoBackground then av.InfoBackground:Hide() end
        SkinBase.StripTextures(av)
    end

    -- Entry creation decorations
    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.Inset then
            ec.Inset:Hide()
            if ec.Inset.NineSlice then ec.Inset.NineSlice:Hide() end
        end
        SkinBase.StripTextures(ec)
    end

    SkinBase.StripTextures(LFGListFrame)
end

-- Skin LFGListFrame (Premade Groups)
local function SkinLFGListFrame()
    local LFGListFrame = _G.LFGListFrame
    if not LFGListFrame or SkinBase.IsSkinned(LFGListFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Hide Blizzard decorations
    HideLFGListDecorations()

    -- Style category selection
    if LFGListFrame.CategorySelection then
        local cs = LFGListFrame.CategorySelection
        if cs.StartGroupButton then
            SkinBase.SkinButton(cs.StartGroupButton)
        end
        if cs.FindGroupButton then
            SkinBase.SkinButton(cs.FindGroupButton)
        end
        -- Style category buttons
        if cs.CategoryButtons then
            for _, catButton in pairs(cs.CategoryButtons) do
                if catButton and not SkinBase.IsStyled(catButton) then
                    SkinBase.StripTextures(catButton)
                    SkinBase.SkinButton(catButton)
                end
            end
        end
    end

    -- Style search panel
    if LFGListFrame.SearchPanel then
        local sp = LFGListFrame.SearchPanel
        if sp.BackButton then
            SkinBase.SkinButton(sp.BackButton)
        end
        if sp.SignUpButton then
            SkinBase.SkinButton(sp.SignUpButton)
        end
        if sp.RefreshButton then
            SkinBase.SkinButton(sp.RefreshButton)
        end
        -- Style search box (uses raw CreateBackdrop — keep colors)
        if sp.SearchBox then
            SkinBase.StripTextures(sp.SearchBox)
            SkinBase.CreateBackdrop(sp.SearchBox, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
        -- Style filter button
        if sp.FilterButton then
            SkinBase.SkinButton(sp.FilterButton)
        end
        -- Search-result rows are pooled ScrollBox buttons whose font OBJECT is
        -- swapped on hover/selection/re-bind, reverting the one-shot
        -- SkinFrameText. Re-lock the QUI font as each row is acquired.
        if sp.ScrollBox then
            SkinBase.HookScrollBoxAcquired(sp.ScrollBox, function(row)
                LockFrameTextObjects(row, 2)
            end)
        end
    end

    -- Style application viewer
    if LFGListFrame.ApplicationViewer then
        local av = LFGListFrame.ApplicationViewer
        if av.RefreshButton then
            SkinBase.SkinButton(av.RefreshButton)
        end
        if av.RemoveEntryButton then
            SkinBase.SkinButton(av.RemoveEntryButton)
        end
        if av.EditButton then
            SkinBase.SkinButton(av.EditButton)
        end
    end

    -- Style entry creation
    if LFGListFrame.EntryCreation then
        local ec = LFGListFrame.EntryCreation
        if ec.ListGroupButton then
            SkinBase.SkinButton(ec.ListGroupButton)
        end
        if ec.CancelButton then
            SkinBase.SkinButton(ec.CancelButton)
        end
    end

    SkinBase.SkinFrameText(LFGListFrame, { recurse = true })
    SkinBase.MarkSkinned(LFGListFrame)
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
        SkinBase.StripTextures(ChallengesFrame.SeasonChangeNoticeFrame)
    end

    SkinBase.StripTextures(ChallengesFrame)
end

-- Style dungeon icon frame for M+
local function StyleDungeonIcon(icon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not icon or SkinBase.IsStyled(icon) then return end

    -- Hide default backgrounds
    if icon.Bg then icon.Bg:SetAlpha(0) end
    if icon.Background then icon.Background:SetAlpha(0) end

    -- Style the icon texture
    if icon.Icon then
        icon.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local iconBackdrop = SkinBase.GetFrameData(icon.Icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, icon, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, icon.Icon, 1)
            iconBackdrop:SetFrameLevel(icon:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(icon.Icon, "backdrop", iconBackdrop)
        end
    end

    -- Lock the QUI font on the tile's level text: Blizzard's SetUp re-asserts
    -- the font OBJECT on HighestLevel when the tile re-binds, reverting the
    -- one-shot SkinFrameText. LockFontObject hooks the swap; idempotent.
    LockFrameTextObjects(icon, 1)

    -- Store colors
    SkinBase.SetFrameData(icon, "skinColor", { sr, sg, sb, sa })

    SkinBase.MarkStyled(icon)
end

-- Style affix icon for M+
local function StyleAffixIcon(affix, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not affix or SkinBase.IsStyled(affix) then return end

    -- Hide border texture
    if affix.Border then affix.Border:SetAlpha(0) end

    -- Style portrait/icon
    if affix.Portrait then
        affix.Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local portraitBackdrop = SkinBase.GetFrameData(affix.Portrait, "backdrop")
        if not portraitBackdrop then
            portraitBackdrop = CreateFrame("Frame", nil, affix, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(portraitBackdrop, affix.Portrait, 1)
            portraitBackdrop:SetFrameLevel(affix:GetFrameLevel())
            portraitBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(portraitBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(portraitBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(affix.Portrait, "backdrop", portraitBackdrop)
        end
    end

    SkinBase.MarkStyled(affix)
end

-- Skin ChallengesFrame (M+ Dungeons tab)
local function SkinChallengesFrame()
    local ChallengesFrame = _G.ChallengesFrame
    if not ChallengesFrame or SkinBase.IsSkinned(ChallengesFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

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
                local fontPath = ns.Helpers.GetGeneralFont()
                CJKFont(wi.Child.Label, fontPath, 14, "OUTLINE")
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
    if ChallengesFrame.Update and not SkinBase.GetFrameData(ChallengesFrame, "updateHooked") then
        -- TAINT SAFETY: Defer to break taint chain from secure Update context.
        hooksecurefunc(ChallengesFrame, "Update", function(self)
            C_Timer.After(0, function()
                if self.DungeonIcons then
                    local sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2 = SkinBase.GetSkinColors()
                    for _, icon in pairs(self.DungeonIcons) do
                        StyleDungeonIcon(icon, sr2, sg2, sb2, sa2, bgr2, bgg2, bgb2, bga2)
                    end
                end
            end)
        end)
        SkinBase.SetFrameData(ChallengesFrame, "updateHooked", true)
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

    SkinBase.SkinFrameText(ChallengesFrame, { recurse = true })
    SkinBase.MarkSkinned(ChallengesFrame)
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
            SkinBase.StripTextures(hf.BonusFrame)
        end
        SkinBase.StripTextures(hf)
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
        SkinBase.StripTextures(cf)
    end

    SkinBase.StripTextures(PVPQueueFrame)
end

-- Style PVP bonus/activity button (right side activity buttons)
local function StylePVPActivityButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    -- Hide default textures
    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.Ring then button.Ring:Hide() end

    -- Create backdrop
    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(backdrop, btnBgR, btnBgG, btnBgB, 1)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

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
            local rewardIconBackdrop = SkinBase.GetFrameData(reward.Icon, "backdrop")
            if not rewardIconBackdrop then
                rewardIconBackdrop = CreateFrame("Frame", nil, reward, "BackdropTemplate")
                SkinBase.SetExpandedPixelPoints(rewardIconBackdrop, reward.Icon, 1)
                rewardIconBackdrop:SetFrameLevel(reward:GetFrameLevel())
                rewardIconBackdrop:EnableMouse(false)
                SkinBase.ApplyPixelBackdrop(rewardIconBackdrop, 1, false, false)
                Helpers.SetFrameBackdropBorderColor(rewardIconBackdrop, sr, sg, sb, sa)
                SkinBase.SetFrameData(reward.Icon, "backdrop", rewardIconBackdrop)
            end
        end
    end

    -- Store colors for hover
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })

    AddSkinColorHoverBorder(button)

    SkinBase.MarkStyled(button)
end

-- Style PVP role icon button
local function StylePVPRoleIcon(roleIcon, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not roleIcon or SkinBase.IsStyled(roleIcon) then return end

    -- Hide decorations
    if roleIcon.background then roleIcon.background:SetAlpha(0) end
    if roleIcon.Background then roleIcon.Background:SetAlpha(0) end
    if roleIcon.shortageBorder then roleIcon.shortageBorder:SetAlpha(0) end
    if roleIcon.cover then roleIcon.cover:SetAlpha(0) end

    SkinBase.MarkStyled(roleIcon)
end

-- Style specific battleground list button (PVPSpecificBattlegroundButtonTemplate)
local function StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not button or SkinBase.IsStyled(button) then return end

    -- Hide default textures
    if button.Bg then button.Bg:Hide() end
    if button.Border then button.Border:Hide() end
    if button.HighlightTexture then button.HighlightTexture:SetAlpha(0) end

    -- Create backdrop
    local backdrop = SkinBase.GetFrameData(button, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(button:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(button, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)

    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(backdrop, btnBgR, btnBgG, btnBgB, 0.9)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    -- Style selected texture
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.3)
        button.SelectedTexture:SetAllPoints()
    end

    -- Style icon border
    if button.Icon then
        button.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local iconBackdrop = SkinBase.GetFrameData(button.Icon, "backdrop")
        if not iconBackdrop then
            iconBackdrop = CreateFrame("Frame", nil, button, "BackdropTemplate")
            SkinBase.SetExpandedPixelPoints(iconBackdrop, button.Icon, 1)
            iconBackdrop:SetFrameLevel(button:GetFrameLevel())
            iconBackdrop:EnableMouse(false)
            SkinBase.ApplyPixelBackdrop(iconBackdrop, 1, false, false)
            Helpers.SetFrameBackdropBorderColor(iconBackdrop, sr, sg, sb, sa)
            SkinBase.SetFrameData(button.Icon, "backdrop", iconBackdrop)
        end
    end

    -- Add hover highlight
    button:HookScript("OnEnter", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        if bd then
            bd:SetBackdropBorderColor(1, 1, 1, 1)
        end
    end)
    button:HookScript("OnLeave", function(self)
        local bd = SkinBase.GetFrameData(self, "backdrop")
        if bd then
            bd:SetBackdropBorderColor(sr, sg, sb, sa)
        end
    end)

    SkinBase.MarkStyled(button)
end

-- Style PVP conquest bar
local function StyleConquestBar(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    if not bar or SkinBase.IsStyled(bar) then return end

    if bar.Border then bar.Border:Hide() end
    if bar.Background then bar.Background:Hide() end

    -- Create backdrop
    local backdrop = SkinBase.GetFrameData(bar, "backdrop")
    if not backdrop then
        backdrop = CreateFrame("Frame", nil, bar, "BackdropTemplate")
        backdrop:SetAllPoints()
        backdrop:SetFrameLevel(bar:GetFrameLevel())
        backdrop:EnableMouse(false)
        SkinBase.SetFrameData(bar, "backdrop", backdrop)
    end

    SkinBase.ApplyPixelBackdrop(backdrop, 1, true, true)
    Helpers.SetFrameBackdropColor(backdrop, bgr, bgg, bgb, 0.8)
    Helpers.SetFrameBackdropBorderColor(backdrop, sr, sg, sb, sa)

    -- Style reward icon
    if bar.Reward then
        if bar.Reward.Ring then bar.Reward.Ring:Hide() end
        if bar.Reward.CircleMask then bar.Reward.CircleMask:Hide() end
        if bar.Reward.Icon then
            bar.Reward.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    SkinBase.MarkStyled(bar)
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
    if not PVPQueueFrame or SkinBase.IsSkinned(PVPQueueFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

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
            SkinBase.SkinButton(_G.HonorFrameQueueButton)
        end

        -- Type dropdown
        local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
        if typeDropdown then
            typeDropdown:SetWidth(230)
            SkinBase.SkinDropdown(typeDropdown, { keepArrow = true, insetY = 2 })
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

        -- Specific battleground scroll list — style buttons on acquisition.
        if HonorFrame.SpecificScrollBox then
            SkinBase.HookScrollBoxAcquired(HonorFrame.SpecificScrollBox, function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)
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
            SkinBase.SkinButton(_G.ConquestJoinButton)
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
        SkinBase.StripTextures(TrainingGroundsFrame)
        if TrainingGroundsFrame.Bg then TrainingGroundsFrame.Bg:Hide() end
        if TrainingGroundsFrame.Background then TrainingGroundsFrame.Background:Hide() end

        -- Hide Inset frame (InsetFrameTemplate has NineSlice border)
        if TrainingGroundsFrame.Inset then
            SkinBase.StripTextures(TrainingGroundsFrame.Inset)
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
            SkinBase.SkinButton(TrainingGroundsFrame.QueueButton)
        end

        -- Type dropdown
        if TrainingGroundsFrame.TypeDropdown then
            TrainingGroundsFrame.TypeDropdown:SetWidth(230)
            SkinBase.SkinDropdown(TrainingGroundsFrame.TypeDropdown, { keepArrow = true, insetY = 2 })
        end

        -- Role icons
        StylePVPFrameRoleIcons(TrainingGroundsFrame, sr, sg, sb, sa, bgr, bgg, bgb, bga)

        -- Conquest bar
        if TrainingGroundsFrame.ConquestBar then
            StyleConquestBar(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Specific Training Ground scroll list (12.x) — style on acquisition.
        local specificList = TrainingGroundsFrame.SpecificTrainingGroundList
        if specificList and specificList.ScrollBox then
            SkinBase.HookScrollBoxAcquired(specificList.ScrollBox, function(button)
                StyleSpecificBGButton(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end)

            -- Style scroll bar
            if specificList.ScrollBar and specificList.ScrollBar.Background then
                specificList.ScrollBar.Background:Hide()
            end
        end

        SkinBase.MarkSkinned(TrainingGroundsFrame)
    end

    SkinBase.SkinFrameText(PVPQueueFrame, { recurse = true })
    SkinBase.MarkSkinned(PVPQueueFrame)
end

-- Main skinning function
local function SkinInstanceFrames()
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    if not settings or not settings.skinInstanceFrames then return end

    SkinPVEFrame()
    SkinLFDFrame()
    SkinRaidFinderFrame()
    SkinLFGListFrame()
    SkinChallengesFrame()
    SkinPVPFrame()
end

-- Helper to update GroupFinder button colors
local function UpdateGroupFinderButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetFrameData(button, "backdrop")
    if not bd then return end
    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    bd:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)
    bd:SetBackdropBorderColor(sr, sg, sb, sa)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    -- Update icon border if present
    local iconBd = button.icon and SkinBase.GetFrameData(button.icon, "backdrop")
    if iconBd then
        Helpers.SetFrameBackdropBorderColor(iconBd, sr, sg, sb, sa)
    end
end

-- Helper to update PVP activity button colors
local function UpdatePVPActivityButtonColors(button, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = button and SkinBase.GetFrameData(button, "backdrop")
    if not bd then return end
    local btnBgR, btnBgG, btnBgB = ButtonBoostColors(bgr, bgg, bgb)
    Helpers.SetFrameBackdropColor(bd, btnBgR, btnBgG, btnBgB, 1)
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
    SkinBase.SetFrameData(button, "skinColor", { sr, sg, sb, sa })
    if button.SelectedTexture then
        button.SelectedTexture:SetColorTexture(sr, sg, sb, 0.2)
    end
    local rewardIconBd = button.Reward and button.Reward.Icon and SkinBase.GetFrameData(button.Reward.Icon, "backdrop")
    if rewardIconBd then
        Helpers.SetFrameBackdropBorderColor(rewardIconBd, sr, sg, sb, sa)
    end
end

-- Helper to update conquest bar colors
local function UpdateConquestBarColors(bar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
    local bd = bar and SkinBase.GetFrameData(bar, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropColor(bd, bgr, bgg, bgb, 0.8)
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
end

-- Helper to update dungeon icon colors
local function UpdateDungeonIconColors(icon, sr, sg, sb, sa)
    if not icon or not icon.Icon then return end
    local bd = SkinBase.GetFrameData(icon.Icon, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
    SkinBase.SetFrameData(icon, "skinColor", { sr, sg, sb, sa })
end

-- Helper to update affix icon colors
local function UpdateAffixIconColors(affix, sr, sg, sb, sa)
    if not affix or not affix.Portrait then return end
    local bd = SkinBase.GetFrameData(affix.Portrait, "backdrop")
    if not bd then return end
    Helpers.SetFrameBackdropBorderColor(bd, sr, sg, sb, sa)
end

-- Refresh colors
local function RefreshInstanceFramesColors()
    local PVEFrame = _G.PVEFrame
    if not PVEFrame or not SkinBase.IsSkinned(PVEFrame) then return end

    local sr, sg, sb, sa, bgr, bgg, bgb, bga = SkinBase.GetSkinColors()

    -- Update PVEFrame backdrop
    local pveBd = SkinBase.GetBackdrop(PVEFrame)
    if pveBd then
        pveBd:SetBackdropColor(bgr, bgg, bgb, bga)
        pveBd:SetBackdropBorderColor(sr, sg, sb, sa)
    end

    -- Update PVE tabs
    local pveTabs = {}
    for i = 1, 4 do
        local tab = _G["PVEFrameTab" .. i]
        if tab then pveTabs[#pveTabs + 1] = tab end
    end
    SkinBase.RefreshTabGroup(pveTabs, PVEFrame)

    -- Update GroupFinder buttons
    local GroupFinderFrame = _G.GroupFinderFrame
    if GroupFinderFrame then
        for i = 1, 4 do
            UpdateGroupFinderButtonColors(GroupFinderFrame["groupButton" .. i], sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end
    end

    -- Update LFD buttons and dropdown
    SkinBase.RefreshWidget(_G.LFDQueueFrameFindGroupButton)
    local LFDQueueFrame = _G.LFDQueueFrame
    if LFDQueueFrame then
        local typeDropdown = LFDQueueFrame.TypeDropdown or _G.LFDQueueFrameTypeDropdown
        if typeDropdown then
            SkinBase.RefreshWidget(typeDropdown)
        end
    end

    -- Update Raid Finder buttons and dropdown
    local RaidFinderQueueFrame = _G.RaidFinderQueueFrame
    if RaidFinderQueueFrame and SkinBase.IsSkinned(RaidFinderQueueFrame) then
        SkinBase.RefreshWidget(_G.RaidFinderFrameFindRaidButton)
        if RaidFinderQueueFrame.SelectionDropdown then
            SkinBase.RefreshWidget(RaidFinderQueueFrame.SelectionDropdown)
        end
    end

    -- Update LFGListFrame buttons
    local LFGListFrame = _G.LFGListFrame
    if LFGListFrame and SkinBase.IsSkinned(LFGListFrame) then
        if LFGListFrame.CategorySelection then
            SkinBase.RefreshWidget(LFGListFrame.CategorySelection.StartGroupButton)
            SkinBase.RefreshWidget(LFGListFrame.CategorySelection.FindGroupButton)
            if LFGListFrame.CategorySelection.CategoryButtons then
                for _, catButton in pairs(LFGListFrame.CategorySelection.CategoryButtons) do
                    SkinBase.RefreshWidget(catButton)
                end
            end
        end
        if LFGListFrame.SearchPanel then
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.BackButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.SignUpButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.RefreshButton)
            SkinBase.RefreshWidget(LFGListFrame.SearchPanel.FilterButton)
            if LFGListFrame.SearchPanel.SearchBox then
                local sbBd = SkinBase.GetBackdrop(LFGListFrame.SearchPanel.SearchBox)
                if sbBd then
                    sbBd:SetBackdropColor(bgr, bgg, bgb, bga)
                    sbBd:SetBackdropBorderColor(sr, sg, sb, sa)
                end
            end
        end
        if LFGListFrame.ApplicationViewer then
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.RefreshButton)
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.RemoveEntryButton)
            SkinBase.RefreshWidget(LFGListFrame.ApplicationViewer.EditButton)
        end
        if LFGListFrame.EntryCreation then
            SkinBase.RefreshWidget(LFGListFrame.EntryCreation.ListGroupButton)
            SkinBase.RefreshWidget(LFGListFrame.EntryCreation.CancelButton)
        end
    end

    -- Update Challenges/M+ dungeon icons and affixes
    local ChallengesFrame = _G.ChallengesFrame
    if ChallengesFrame and SkinBase.IsSkinned(ChallengesFrame) then
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
    if PVPQueueFrame and SkinBase.IsSkinned(PVPQueueFrame) then
        -- Category buttons (5 in 12.x, 4 in 11.x)
        -- PTR uses PVPQueueFrame.CategoryButton1, retail uses _G["PVPQueueFrameCategoryButton1"]
        for i = 1, 5 do
            local catButton = PVPQueueFrame["CategoryButton" .. i] or _G["PVPQueueFrameCategoryButton" .. i]
            UpdateGroupFinderButtonColors(catButton, sr, sg, sb, sa, bgr, bgg, bgb, bga)
        end

        -- Honor frame
        local HonorFrame = _G.HonorFrame
        if HonorFrame then
            SkinBase.RefreshWidget(_G.HonorFrameQueueButton)
            -- Type dropdown
            local typeDropdown = HonorFrame.TypeDropdown or _G.HonorFrameTypeDropdown
            if typeDropdown then
                SkinBase.RefreshWidget(typeDropdown)
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
            SkinBase.RefreshWidget(_G.ConquestJoinButton)
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
        if TrainingGroundsFrame and SkinBase.IsSkinned(TrainingGroundsFrame) then
            SkinBase.RefreshWidget(TrainingGroundsFrame.QueueButton)
            if TrainingGroundsFrame.TypeDropdown then
                SkinBase.RefreshWidget(TrainingGroundsFrame.TypeDropdown)
            end
            if TrainingGroundsFrame.ConquestBar then
                UpdateConquestBarColors(TrainingGroundsFrame.ConquestBar, sr, sg, sb, sa, bgr, bgg, bgb, bga)
            end
        end

    end
end

-- Expose refresh function globally
_G.QUI_RefreshInstanceFramesColors = RefreshInstanceFramesColors

if ns.Registry then
    ns.Registry:Register("skinInstanceFrames", {
        refresh = _G.QUI_RefreshInstanceFramesColors,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

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

local function RunAfterFirstFrame(callback, delay)
    if ns.RunAfterFirstFrame then
        return ns.RunAfterFirstFrame(callback, delay)
    end
    if C_Timer and C_Timer.After then
        return C_Timer.After(delay or 0, callback)
    end
    if type(callback) == "function" then
        return callback()
    end
    return nil
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, addon)
    if event == "ADDON_LOADED" then
        if addon == "Blizzard_PVPUI" or addon == "Blizzard_ChallengesUI" then
            C_Timer.After(0.1, SkinInstanceFrames)
        end
    end
end)

-- LOD catch-up: first PEW already fired before this module loads; the old
-- one-shot PLAYER_ENTERING_WORLD init runs via ns.WhenLoggedIn instead.
-- SkinInstanceFrames also covers Blizzard_PVPUI/Blizzard_ChallengesUI when
-- they loaded before this module.
-- ns.WhenLoggedIn is nil only in the headless test harness.
if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        HookPVEFrame()
        RunAfterFirstFrame(function()
            SkinInstanceFrames()
        end, 0.25)
    end)
end
