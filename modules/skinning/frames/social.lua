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

local columnDisplayHooked = false

local function HookListRows(scrollBox, depth)
    SkinBase.HookScrollBoxRowFonts(scrollBox, depth or 3)
end

local function LockGuildNameAlertText(frame)
    local alert = frame and frame.GuildNameAlertFrame and frame.GuildNameAlertFrame.Alert
    if not alert then return end
    SkinBase.SkinFontString(alert, { fontOnly = true })
    SkinBase.LockFontObject(alert, { fontOnly = true })
end

local function SkinFriends()
    if not IsSettingEnabled("skinFriends") then return end
    local frame = _G.FriendsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    local tabs = {}
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinWindow(frame, { tabs = tabs })
    if _G.FriendsListFrame then HookListRows(_G.FriendsListFrame.ScrollBox) end
    if frame.IgnoreListWindow then HookListRows(frame.IgnoreListWindow.ScrollBox) end
    if _G.WhoFrame then HookListRows(_G.WhoFrame.ScrollBox) end
    if _G.WhoFrame then
        for i = 1, 4 do
            local h = _G["WhoFrameColumnHeader" .. i]
            if h then SkinBase.ApplyButtonFontObjects(h) end
        end
    end

    if SkinBase.SkinEditBox then
        if _G.WhoFrameEditBox then SkinBase.SkinEditBox(_G.WhoFrameEditBox) end
        if _G.AddFriendNameEditBox then SkinBase.SkinEditBox(_G.AddFriendNameEditBox) end
    end
    if SkinBase.SkinDropdown then
        if _G.FriendsFrameStatusDropdown then SkinBase.SkinDropdown(_G.FriendsFrameStatusDropdown) end
        if _G.WhoFrameDropdown then SkinBase.SkinDropdown(_G.WhoFrameDropdown) end
    end

    SkinBase.MarkSkinned(frame)
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

SkinBase.OnAddOnLoaded("Blizzard_FriendsFrame", SkinFriends,     0)
SkinBase.OnAddOnLoaded("Blizzard_Communities",  SkinCommunities, 0)
