local addonName, ns = ...

if ns.IsSkinningEnabled and not ns.IsSkinningEnabled() then return end
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors
local WHITE_TEXT_COLOR = { 1, 1, 1, 1 }

local columnDisplayHooked = false
local legacyAllAssistHooked = false

local function HookListRows(scrollBox, depth)
    SkinBase.HookScrollBoxRowFonts(scrollBox, depth or 3)
end

local SOCIAL_ROW_TEXTURES = { "background", "Background", "NormalTexture", "DragBackground" }

local function SkinSocialRow(row, depth)
    if not row then return end
    for _, key in ipairs(SOCIAL_ROW_TEXTURES) do
        if row[key] then SkinBase.ClampTextureHidden(row[key]) end
    end
    local normal = row.GetNormalTexture and row:GetNormalTexture()
    if normal then SkinBase.ClampTextureHidden(normal) end
    SkinBase.LockPooledRowText(row, depth or 3)
end

local function SkinSocialList(frame, depth, async)
    if not frame then return end
    if frame.ScrollBox and not SkinBase.GetFrameData(frame.ScrollBox, "qSocialRowsHooked") then
        local options
        if not async then options = { sync = true } end
        SkinBase.HookScrollBoxAcquired(frame.ScrollBox, function(row)
            SkinSocialRow(row, depth)
        end, options or nil)
        SkinBase.SetFrameData(frame.ScrollBox, "qSocialRowsHooked", true)
    end
    if frame.ScrollBar then SkinBase.SkinTrimScrollBar(frame.ScrollBar) end
end

local function SkinButtons(...)
    local fontObject = _G.UserScaledFontGameNormal or _G.GameFontNormal
    local fontSize
    if fontObject and fontObject.GetFont then
        local _, size = fontObject:GetFont()
        fontSize = size
    end
    local fontOptions = {
        size = fontSize,
        color = WHITE_TEXT_COLOR,
        disabledColor = WHITE_TEXT_COLOR,
    }
    for index = 1, select("#", ...) do
        local button = select(index, ...)
        if button then
            SkinBase.SkinButton(button, { disabledFontColor = WHITE_TEXT_COLOR })
            SkinBase.ApplyButtonFontObjects(button, fontOptions)
        end
    end
end

local function RefreshAllAssistLabel(check)
    local label = check and (check.AllText or check.Text)
    if not label then return end
    if check.AllText and label.SetText then label:SetText(_G.ALL_ASSIST_LABEL_SHORT) end
    SkinBase.SkinFontString(label, { color = WHITE_TEXT_COLOR })
    if label.ClearAllPoints and label.SetPoint then
        label:ClearAllPoints()
        label:SetPoint("LEFT", check.AllText and check.Icon or check, "RIGHT", 4, 0)
    end
end

local function SkinAllAssistCheckBox(check)
    if not check then return end
    SkinBase.SkinCheckBox(check)
    local backdrop = SkinBase.GetBackdrop(check)
    if backdrop then
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", check, "TOPLEFT", 4, -4)
        backdrop:SetPoint("BOTTOMRIGHT", check, "BOTTOMRIGHT", -4, 4)
    end
    if type(check.UpdateAvailable) == "function"
        and not SkinBase.GetFrameData(check, "qSocialAllAssistHooked") then
        hooksecurefunc(check, "UpdateAvailable", RefreshAllAssistLabel)
        SkinBase.SetFrameData(check, "qSocialAllAssistHooked", true)
    elseif not legacyAllAssistHooked and _G.RaidFrameAllAssistCheckButton_UpdateAvailable then
        hooksecurefunc("RaidFrameAllAssistCheckButton_UpdateAvailable", RefreshAllAssistLabel)
        legacyAllAssistHooked = true
    end
    RefreshAllAssistLabel(check)
end

local function SkinContactView(frame, async)
    if not frame then return end
    SkinBase.StripTextures(frame)
    SkinSocialList(frame, 4, async)
    local filterBar = frame.FilterBar
    if filterBar then
        SkinBase.SkinEditBox(filterBar.SearchBar)
        SkinBase.SkinDropdown(filterBar.SearchFilterDropdown, { belowChildren = true })
    end
    SkinButtons(frame.ActionButton)
    SkinBase.ApplyButtonFontObjectsDeep(frame, 4)
end

local function SkinSideWindow(frame)
    if not frame then return end
    if not SkinBase.IsSkinned(frame) then
        SkinBase.StripTextures(frame)
        if frame.Border then SkinBase.KillNineSlice(frame.Border, true) end
        if frame.Header then SkinBase.StripTextures(frame.Header) end
        SkinBase.SkinWindow(frame)
        SkinBase.MarkSkinned(frame)
    end
    SkinSocialList(frame, 4)
end

local function LockGuildNameAlertText(frame)
    local alert = frame and frame.GuildNameAlertFrame and frame.GuildNameAlertFrame.Alert
    if not alert then return end
    SkinBase.SkinFontString(alert, { fontOnly = true })
    SkinBase.LockFontObject(alert, { fontOnly = true })
end

local function StyleSocialTitle(frame)
    if not frame or not IsSettingEnabled("skinFriends") then return end
    local title = frame.GetTitleText and frame:GetTitleText()
    if not title then title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) end
    if title then SkinBase.SkinFontString(title, { color = WHITE_TEXT_COLOR }) end
end

local function HookSocialTitle(frame)
    StyleSocialTitle(frame)
    if frame.SetTitle and not SkinBase.GetFrameData(frame, "qSocialTitleHooked") then
        hooksecurefunc(frame, "SetTitle", StyleSocialTitle)
        SkinBase.SetFrameData(frame, "qSocialTitleHooked", true)
    end
end

local function SkinLegacyFriendsContents(frame)
    if not frame then return end
    SkinBase.ClampTextureHidden(_G.FriendsFramePortrait)
    SkinBase.ClampTextureHidden(_G.FriendsFrameIcon)
    SkinBase.ClampTextureHidden(frame.TopTileStreaks, true, { preserveLayout = true })
    SkinBase.ClampTextureHidden(_G.FriendsFrameBg, true, { preserveLayout = true })
    if frame.Inset then
        SkinBase.StripTextures(frame.Inset)
        SkinBase.ClampTextureHidden(frame.Inset.Bg, true, { preserveLayout = true })
        SkinBase.KillNineSlice(frame.Inset.NineSlice, true)
    end
    SkinBase.ClampTextureHidden(frame.PortraitContainer, true)
    local battleNet = frame.BattlenetFrame or _G.FriendsFrameBattlenetFrame
    if battleNet then
        SkinBase.StripTextures(battleNet)
        local sr, sg, sb, sa, r, g, b, a = SkinBase.GetWindowColors()
        SkinBase.CreateBackdrop(battleNet, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
        local menu = battleNet.ContactsMenuButton
        SkinBase.SkinDropdown(menu, { skinArrow = true, belowChildren = true })
        if menu then
            SkinBase.ClampTextureHidden(menu:GetNormalTexture())
            SkinBase.ClampTextureHidden(menu:GetPushedTexture())
            SkinBase.ClampTextureHidden(menu:GetDisabledTexture())
            SkinBase.ClampTextureHidden(menu.Icon, true, { preserveLayout = true })
        end
        local broadcast = battleNet.BroadcastFrame
        if broadcast then
            SkinSideWindow(broadcast)
            SkinBase.SkinEditBox(broadcast.EditBox)
            SkinButtons(broadcast.UpdateButton, broadcast.CancelButton)
        end
    end
    SkinSocialList(_G.FriendsListFrame, 4)
    SkinButtons(_G.FriendsFrameAddFriendButton, _G.FriendsFrameSendMessageButton)

    local header = frame.FriendsTabHeader or _G.FriendsTabHeader
    if header and header.TabSystem and header.TabSystem.tabs then
        SkinBase.SkinTabGroup(header.TabSystem.tabs, header, { resizeToText = true })
    end

    local ignoreList = frame.IgnoreListWindow
    if ignoreList then
        SkinSideWindow(ignoreList)
        SkinButtons(ignoreList.UnignorePlayerButton)
    end

    local recentAllies = _G.RecentAlliesFrame and _G.RecentAlliesFrame.List
    SkinSocialList(recentAllies, 4)

    local whoFrame = _G.WhoFrame
    if whoFrame then
        SkinSocialList(whoFrame, 4)
        if whoFrame.WhoFrameListInset then
            SkinBase.HidePortraitFrameChrome(whoFrame.WhoFrameListInset)
        end
        for _, i in ipairs({ 1, 3, 4 }) do
            local h = _G["WhoFrameColumnHeader" .. i]
            if h then SkinBase.SkinButton(h) end
        end
        SkinBase.StripTextures(_G.WhoFrameColumnHeader2)
        local dropdown = _G.WhoFrameDropdown
        if dropdown then
            SkinBase.SkinDropdown(dropdown, { skinArrow = true })
            SkinBase.ClampTextureHidden(dropdown.TabHighlight)
            local header = _G.WhoFrameColumnHeader2
            if header and dropdown.ClearAllPoints and dropdown.SetPoint then
                dropdown:ClearAllPoints()
                dropdown:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
                dropdown:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            end
        end
        local totals = _G.WhoFrameTotals or (whoFrame.WhoFrameListInset and whoFrame.WhoFrameListInset.WhoFrameTotals)
        if totals then SkinBase.SkinFontString(totals, { color = { 0.9, 0.9, 0.9, 1 } }) end
        SkinButtons(_G.WhoFrameGroupInviteButton, _G.WhoFrameAddFriendButton, _G.WhoFrameWhoButton)
    end

    local whoSearch = _G.WhoFrameEditBox
    SkinBase.SkinEditBox(whoSearch)
    if whoSearch and whoSearch.searchIcon and whoSearch.searchIcon.SetAlpha then
        whoSearch.searchIcon:SetAlpha(1)
    end
    SkinBase.SkinEditBox(_G.AddFriendNameEditBox)
    local status = _G.FriendsFrameStatusDropdown
    SkinBase.SkinDropdown(status, { skinArrow = true })
    if status and status.Text then
        status.Text:ClearAllPoints()
        status.Text:SetPoint("LEFT", status, "LEFT", 6, 0)
        status.Text:SetPoint("RIGHT", status, "RIGHT", -20, 0)
    end

    local quickJoin = _G.QuickJoinFrame
    if quickJoin then
        SkinSocialList(quickJoin, 4, true)
        SkinButtons(quickJoin.JoinQueueButton)
    end

    local raidFrame = _G.RaidFrame
    if raidFrame then
        SkinButtons(_G.RaidFrameConvertToRaidButton, _G.RaidFrameRaidInfoButton)
        SkinAllAssistCheckBox(_G.RaidFrameAllAssistCheckButton)
        local notInRaid = raidFrame.RaidFrameNotInRaid or _G.RaidFrameNotInRaid
        if notInRaid and notInRaid.ScrollingDescriptionScrollBar then
            SkinBase.SkinTrimScrollBar(notInRaid.ScrollingDescriptionScrollBar)
        end
    end

    local raidInfo = _G.RaidInfoFrame
    if raidInfo then
        SkinSideWindow(raidInfo)
        SkinBase.SkinCloseButton(_G.RaidInfoCloseButton or raidInfo.CloseButton)
        SkinButtons(_G.RaidInfoExtendButton or raidInfo.ExtendButton,
            _G.RaidInfoCancelButton or raidInfo.CancelButton)
    end

    for i = 1, 40 do
        local row = _G["RaidGroupButton" .. i]
        if row then SkinBase.LockPooledRowText(row, 2) end
    end
end

local function SkinFriends()
    if not IsSettingEnabled("skinFriends") then return end
    local frame = _G.FriendsFrame
    if not frame then return end
    if not SkinBase.IsSkinned(frame) then
        local tabs = {}
        for i = 1, 4 do
            local tab = _G["FriendsFrameTab" .. i]
            if tab then tabs[#tabs + 1] = tab end
        end
        SkinBase.SkinWindow(frame)
        SkinBase.SkinTabGroup(tabs, frame, { resizeToText = true, dockBottom = true })
        SkinBase.MarkSkinned(frame)
    end
    HookSocialTitle(frame)
    SkinLegacyFriendsContents(frame)
end

local function SkinModernRaidRows(frame)
    if not frame then return end
    for _, group in ipairs(frame.groups or {}) do
        SkinBase.StripTextures(group)
        SkinBase.SkinFrameText(group, { recurse = true })
        SkinBase.LockFrameTextObjects(group, 1)
    end
    for _, player in ipairs(frame.players or {}) do
        SkinSocialRow(player, 2)
    end
end

local function SkinModernRaid(frame)
    if not frame then return end
    SkinButtons(frame.RaidInfoButton, frame.ConvertToRaidButton)
    SkinAllAssistCheckBox(frame.AllAssistCheckButton)
    if type(frame.UpdateContents) == "function"
        and not SkinBase.GetFrameData(frame, "qSocialRaidHooked") then
        hooksecurefunc(frame, "UpdateContents", SkinModernRaidRows)
        SkinBase.SetFrameData(frame, "qSocialRaidHooked", true)
    end
    SkinModernRaidRows(frame)
end

local function SkinSocialUI()
    if not IsSettingEnabled("skinFriends") then return end
    local frame = _G.SocialUIFrame
    if not frame then return end
    if not SkinBase.IsSkinned(frame) then
        SkinBase.StripTextures(frame)
        SkinBase.SkinWindow(frame)
        SkinBase.MarkSkinned(frame)
    end

    HookSocialTitle(frame)
    local battleNetBar = frame.BattleNetBar
    local controls = battleNetBar and battleNetBar.ControlsContainer
    if battleNetBar then SkinBase.StripTextures(battleNetBar) end
    if controls then
        SkinBase.StripTextures(controls)
        SkinBase.SkinDropdown(controls.OnlineStatusDropdown, { skinArrow = true })
        if controls.BattleNetMenuButton then
            SkinBase.SkinButton(controls.BattleNetMenuButton, { font = false })
        end
    end

    SkinContactView(frame.FriendsList)
    SkinContactView(frame.RecentAlliesList)
    SkinContactView(frame.QuickJoinFrame, true)
    SkinContactView(frame.FriendRequestsList)

    SkinModernRaid(frame.RaidFrame)
    local raidInfo = frame.RaidInfoFrame
    if raidInfo then
        SkinSideWindow(raidInfo)
        SkinButtons(raidInfo.ExtendButton)
    end

    local ignoreList = frame.IgnoreListFrame
    if ignoreList then
        SkinSideWindow(ignoreList)
        SkinButtons(ignoreList.BlockButton, ignoreList.UnblockButton)
    end

    local broadcast = frame.BattleNetBroadcastFrame
    if broadcast then
        SkinBase.SkinEditBox(broadcast.EditBox)
        SkinButtons(broadcast.UpdateButton, broadcast.CancelButton)
    end
end

local function SkinSocial()
    SkinFriends()
    SkinSocialUI()
end

local function RefreshFriends()
    RefreshBackdropColors(_G.FriendsFrame)
    RefreshBackdropColors(_G.SocialUIFrame)
end
_G.QUI_RefreshFriendsColors = RefreshFriends
if ns.Registry then
    ns.Registry:Register("skinFriends", {
        refresh = RefreshFriends,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

local function SkinCommunitySurface(frame)
    if not frame then return end
    SkinBase.StripTextures(frame)
    SkinBase.KillNineSlice(frame.NineSlice, true)
    local sr, sg, sb, sa = SkinBase.GetWindowColors()
    local r, g, b, a = SkinBase.GetDepthColor("SUBPANEL")
    SkinBase.CreateBackdrop(frame, sr, sg, sb, sa * 0.5, r, g, b, a, 5)
end

local function SkinCommunityTab(tab)
    if not tab then return end
    SkinBase.SkinButton(tab, { strip = true, font = false, belowChildren = true })
    if tab.Icon then
        tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tab.Icon:SetAlpha(1)
        SkinBase.RoundIconTexture(tab, tab.Icon)
    end
    if tab.IconOverlay then tab.IconOverlay:SetAlpha(1) end
    local checked = tab.GetCheckedTexture and tab:GetCheckedTexture()
    SkinBase.ClampTextureHidden(checked)
    local _, _, _, _, r, g, b = SkinBase.GetWindowColors()
    SkinBase.SetFrameData(tab, "bgColor", { r, g, b })
    SkinBase.SetFrameData(tab, "tabChecked", tab.GetChecked and tab:GetChecked() or false)
    if tab.SetChecked and not SkinBase.GetFrameData(tab, "qCommunityTabHooked") then
        hooksecurefunc(tab, "SetChecked", function(self, selected)
            SkinBase.SetFrameData(self, "tabChecked", selected)
            SkinBase.RefreshTabSelected(self)
        end)
        SkinBase.SetFrameData(tab, "qCommunityTabHooked", true)
    end
    SkinBase.RefreshTabSelected(tab)
end

local function SkinCommunityNavigationRow(row)
    if not row then return end
    SkinBase.SkinCategoryButton(row, { isSelected = function(button)
        return button.Selection and button.Selection:IsShown()
    end })
    for _, key in ipairs({ "Icon", "GuildTabardBackground", "GuildTabardEmblem", "GuildTabardBorder",
        "InvitationIcon", "UnreadNotificationIcon", "FavoriteIcon" }) do
        if row[key] then row[key]:SetAlpha(1) end
    end
    SkinBase.ClampTextureHidden(row.Background)
    SkinBase.ClampTextureHidden(row.Selection, true)
    SkinBase.ClampTextureHidden(row.IconRing)
    SkinBase.SkinFontString(row.Name, { color = { 1, 1, 1, 1 } })
    if row.Selection and not SkinBase.GetFrameData(row, "qCommunitySelectionHooked") then
        hooksecurefunc(row.Selection, "SetShown", function() SkinBase.RefreshCategorySelected(row) end)
        SkinBase.SetFrameData(row, "qCommunitySelectionHooked", true)
    end
    SkinBase.RefreshCategorySelected(row)
end

local function SkinCommunityFinder(finder)
    if not finder then return end
    SkinCommunitySurface(finder.InsetFrame)
    SkinCommunitySurface(finder.DisabledFrame)
    SkinBase.SkinFontString(finder.InsetFrame and finder.InsetFrame.GuildDescription,
        { color = { 0.85, 0.85, 0.85, 1 } })
    SkinBase.SkinFontString(finder.DisabledFrame and finder.DisabledFrame.Title,
        { color = { 1, 1, 1, 1 } })
    SkinBase.SkinFontString(finder.DisabledFrame and finder.DisabledFrame.Description,
        { color = { 0.85, 0.85, 0.85, 1 } })
    SkinCommunityTab(finder.ClubFinderSearchTab)
    SkinCommunityTab(finder.ClubFinderPendingTab)
    local options = finder.OptionsList
    if options then
        for _, key in ipairs({ "ClubFilterDropdown", "ClubSizeDropdown", "SortByDropdown" }) do
            SkinBase.SkinDropdown(options[key], { skinArrow = true })
            SkinBase.RefreshWidget(options[key])
            SkinBase.SkinFontString(options[key] and options[key].Label, { color = { 0.9, 0.9, 0.9, 1 } })
        end
        SkinBase.SkinEditBox(options.SearchBox)
        if options.SearchBox and options.SearchBox.searchIcon then options.SearchBox.searchIcon:SetAlpha(1) end
        SkinButtons(options.Search)
        for _, key in ipairs({ "TankRoleFrame", "HealerRoleFrame", "DpsRoleFrame" }) do
            local check = options[key] and options[key].Checkbox
            SkinBase.SkinCheckBox(check)
            local backdrop = SkinBase.GetBackdrop(check)
            if backdrop then SkinBase.SetInsetPixelPoints(backdrop, check, 6) end
        end
    end
    for _, key in ipairs({ "GuildCards", "CommunityCards", "PendingGuildCards", "PendingCommunityCards" }) do
        local cards = finder[key]
        if cards then
            SkinBase.SkinTrimScrollBar(cards.ScrollBar)
            SkinBase.SkinNextPrevButton(cards.PreviousPage, "prev")
            SkinBase.SkinNextPrevButton(cards.NextPage, "next")
        end
    end
end

local function StyleCommunitiesTitle(frame)
    local title = frame.GetTitleText and frame:GetTitleText()
    if not title then title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText) end
    SkinBase.SkinFontString(title, { color = { 1, 1, 1, 1 } })
end

local function SkinCommunitiesContents(frame)
    if not frame then return end
    StyleCommunitiesTitle(frame)
    SkinBase.ClampTextureHidden(frame.PortraitOverlay, true)
    SkinBase.ClampTextureHidden(frame.PortraitContainer, true)
    local sizing = frame.MaximizeMinimizeFrame
    if sizing then
        for _, key in ipairs({ "MaximizeButton", "MinimizeButton" }) do
            local button = sizing[key]
            SkinBase.SkinButton(button, { strip = true, font = false })
            if button and not SkinBase.GetFrameData(button, "qCommunitySizingGlyph") then
                local text = button:CreateFontString(nil, "OVERLAY")
                text:SetPoint("CENTER")
                SkinBase.SkinFontString(text, { size = 14, color = { 0.9, 0.9, 0.9, 1 } })
                text:SetText(key == "MaximizeButton" and "+" or "-")
                SkinBase.SetFrameData(button, "qCommunitySizingGlyph", text)
            end
        end
    end
    local list = frame.CommunitiesList
    if list then
        SkinCommunitySurface(list)
        SkinBase.StripTextures(list.FilligreeOverlay)
        if list.InsetFrame then
            SkinBase.StripTextures(list.InsetFrame)
            SkinBase.KillNineSlice(list.InsetFrame.NineSlice, true)
        end
        SkinBase.SkinTrimScrollBar(list.ScrollBar)
        if list.ScrollBox and not SkinBase.GetFrameData(list.ScrollBox, "qCommunityRowsHooked") then
            SkinBase.HookScrollBoxAcquired(list.ScrollBox, SkinCommunityNavigationRow)
            SkinBase.SetFrameData(list.ScrollBox, "qCommunityRowsHooked", true)
        end
        SkinBase.ForEachScrollBoxFrame(list.ScrollBox, SkinCommunityNavigationRow)
    end
    for _, key in ipairs({ "MemberList", "ApplicantList", "GuildBenefitsFrame", "GuildDetailsFrame" }) do
        local pane = frame[key]
        if pane then
            SkinCommunitySurface(pane)
            if pane.InsetFrame then
                SkinBase.StripTextures(pane.InsetFrame)
                SkinBase.KillNineSlice(pane.InsetFrame.NineSlice, true)
            end
            SkinBase.SkinTrimScrollBar(pane.ScrollBar)
            SkinBase.SkinCheckBox(pane.ShowOfflineButton)
        end
    end
    for _, key in ipairs({ "ChatTab", "RosterTab", "GuildBenefitsTab", "GuildInfoTab" }) do
        SkinCommunityTab(frame[key])
    end
    for _, key in ipairs({ "StreamDropdown", "GuildMemberListDropdown", "CommunityMemberListDropdown",
        "CommunitiesListDropdown", "AddToChatButton" }) do
        SkinBase.SkinDropdown(frame[key], { skinArrow = true })
        SkinBase.RefreshWidget(frame[key])
    end
    SkinButtons(frame.InviteButton, frame.GuildLogButton)
    SkinBase.SkinEditBox(frame.ChatEditBox)
    SkinCommunityFinder(frame.GuildFinderFrame)
    SkinCommunityFinder(frame.CommunityFinderFrame)
    local control = frame.CommunitiesControlFrame
    if control then
        SkinButtons(control.CommunitiesSettingsButton, control.GuildControlButton, control.GuildRecruitmentButton)
    end
end

local function SkinCommunities()
    if not IsSettingEnabled("skinCommunities") then return end
    local frame = _G.CommunitiesFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    if frame.MemberList then HookListRows(frame.MemberList.ScrollBox) end
    if frame.CommunitiesList then HookListRows(frame.CommunitiesList.ScrollBox) end
    if frame.ApplicantList then HookListRows(frame.ApplicantList.ScrollBox) end
    if frame.GuildBenefitsFrame and frame.GuildBenefitsFrame.Rewards then
        HookListRows(frame.GuildBenefitsFrame.Rewards.ScrollBox)
    end
    if frame.GuildMemberDetailFrame then
        SkinBase.ApplyButtonFontObjectsDeep(frame.GuildMemberDetailFrame, 3)
    end
    if not columnDisplayHooked and _G.ColumnDisplayMixin and _G.ColumnDisplayMixin.LayoutColumns then
        hooksecurefunc(_G.ColumnDisplayMixin, "LayoutColumns", function(self)
            if SkinBase.ApplyButtonFontObjectsDeep then
                SkinBase.ApplyButtonFontObjectsDeep(self, 1)
            end
        end)
        columnDisplayHooked = true
    end
    LockGuildNameAlertText(frame)
    SkinCommunitiesContents(frame)
    if type(frame.SetTitle) == "function" then hooksecurefunc(frame, "SetTitle", StyleCommunitiesTitle) end
    frame:HookScript("OnShow", SkinCommunitiesContents)
    SkinBase.MarkSkinned(frame)
end

local function RefreshCommunities()
    RefreshBackdropColors(_G.CommunitiesFrame)
    LockGuildNameAlertText(_G.CommunitiesFrame)
    SkinCommunitiesContents(_G.CommunitiesFrame)
end
_G.QUI_RefreshCommunitiesColors = RefreshCommunities
if ns.Registry then
    ns.Registry:Register("skinCommunities", {
        refresh = RefreshCommunities,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
end

for _, addon in ipairs({
    "Blizzard_FriendsFrame",
    "Blizzard_SocialUI",
    "Blizzard_QuickJoin",
    "Blizzard_RaidFrame",
    "Blizzard_RaidUI",
    "Blizzard_RecentAllies",
}) do
    SkinBase.OnAddOnLoaded(addon, SkinSocial, 0)
end
SkinBase.OnAddOnLoaded("Blizzard_Communities",  SkinCommunities, 0)
