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

local function SkinLegacyFriendsContents(frame)
    if not frame then return end
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
        end
        SkinButtons(_G.WhoFrameGroupInviteButton, _G.WhoFrameAddFriendButton, _G.WhoFrameWhoButton)
    end

    local whoSearch = _G.WhoFrameEditBox
    SkinBase.SkinEditBox(whoSearch)
    if whoSearch and whoSearch.searchIcon and whoSearch.searchIcon.SetAlpha then
        whoSearch.searchIcon:SetAlpha(1)
    end
    SkinBase.SkinEditBox(_G.AddFriendNameEditBox)
    SkinBase.SkinDropdown(_G.FriendsFrameStatusDropdown, { skinArrow = true })

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

    for i = 1, 40 do SkinSocialRow(_G["RaidGroupButton" .. i], 2) end
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
        SkinBase.SkinWindow(frame, { tabs = tabs })
        SkinBase.MarkSkinned(frame)
    end
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

local function RefreshFriends() RefreshBackdropColors(_G.FriendsFrame) end
_G.QUI_RefreshFriendsColors = RefreshFriends
if ns.Registry then
    ns.Registry:Register("skinFriends", {
        refresh = RefreshFriends,
        priority = 80,
        group = "skinning",
        importCategories = { "skinning", "theme" },
    })
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
    SkinBase.MarkSkinned(frame)
end

local function RefreshCommunities()
    RefreshBackdropColors(_G.CommunitiesFrame)
    LockGuildNameAlertText(_G.CommunitiesFrame)
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
