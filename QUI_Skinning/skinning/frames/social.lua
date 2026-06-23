---------------------------------------------------------------------------
-- SOCIAL FRAMES SKINNING
--
--   - FriendsFrame      (ButtonFrameTemplate,            LOD Blizzard_FriendsFrame)
--   - CommunitiesFrame  (ButtonFrameTemplateMinimizable, LOD Blizzard_Communities)
--
-- Both inherit a ButtonFrameTemplate variant, so SkinBase.SkinButtonFrameTemplate
-- handles chrome strip + backdrop + close-button styling. Frame-specific
-- sub-elements (friends scroll list, club channel tree, member list) are
-- left for follow-up commits.
---------------------------------------------------------------------------

local addonName, ns = ...
local SkinBase = ns.SkinBase
local GetCore = ns.Helpers.GetCore

local function IsSettingEnabled(key)
    local core = GetCore()
    local settings = core and core.db and core.db.profile and core.db.profile.general
    return settings and settings[key]
end

local RefreshBackdropColors = SkinBase.RefreshFrameBackdropColors

-- Session-once guard: the ColumnDisplayMixin:LayoutColumns hook (member/applicant
-- header fonts) is on the shared mixin, so install it a single time.
local columnDisplayHooked = false

-- Pooled list rows (friends / who / ignore / community roster) are ScrollBox-
-- recycled and Blizzard re-applies their font OBJECT on every acquire / rebind
-- / presence update (FriendsFrame.lua, CommunitiesMemberList.lua). Lock each
-- acquired row's fontstrings so the QUI face survives (fontOnly keeps
-- Blizzard's class / status text colors).
local function HookListRows(scrollBox, depth)
    -- Guarded per-row font lock (runs the recursive pass once; the LockFontObject
    -- hooks re-assert the QUI face on every later acquire/presence/state rebind).
    -- The unguarded form was the guild/friends open-window hitch.
    SkinBase.HookScrollBoxRowFonts(scrollBox, depth or 3)
end

local function LockGuildNameAlertText(frame)
    local alert = frame and frame.GuildNameAlertFrame and frame.GuildNameAlertFrame.Alert
    if not alert then return end
    SkinBase.SkinFontString(alert, { fontOnly = true })
    SkinBase.LockFontObject(alert, { fontOnly = true })
end

---------------------------------------------------------------------------
-- FriendsFrame
---------------------------------------------------------------------------
local function SkinFriends()
    if not IsSettingEnabled("skinFriends") then return end
    local frame = _G.FriendsFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    -- FriendsFrameTab1..4: Friends / Quick Join / Who / Raid
    -- (per Blizzard_FriendsFrame/Mainline/FriendsFrame.lua:273-276).
    local tabs = {}
    for i = 1, 4 do
        local tab = _G["FriendsFrameTab" .. i]
        if tab then tabs[#tabs + 1] = tab end
    end
    SkinBase.SkinWindow(frame, { tabs = tabs })
    -- Friends / Ignore / Who pooled list rows (FriendsFrame.lua:312/326/343).
    if _G.FriendsListFrame then HookListRows(_G.FriendsListFrame.ScrollBox) end
    if frame.IgnoreListWindow then HookListRows(frame.IgnoreListWindow.ScrollBox) end
    if _G.WhoFrame then HookListRows(_G.WhoFrame.ScrollBox) end
    -- WhoFrame sortable column headers swap their Highlight font OBJECT on hover;
    -- Lock* hooks never see the engine's internal swap, so drive the button font
    -- objects directly (the only durable fix).
    if _G.WhoFrame then
        for i = 1, 4 do
            local h = _G["WhoFrameColumnHeader" .. i]
            if h then SkinBase.ApplyButtonFontObjects(h) end
        end
    end

    -- Wire the shared editbox/dropdown skins onto the Friends/Who sub-widgets
    -- (existing verified helpers; guarded — AddFriendNameEditBox is created on
    -- demand so it may be nil at first skin).
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

---------------------------------------------------------------------------
-- CommunitiesFrame
---------------------------------------------------------------------------
local function SkinCommunities()
    if not IsSettingEnabled("skinCommunities") then return end
    local frame = _G.CommunitiesFrame
    if not frame or SkinBase.IsSkinned(frame) then return end
    SkinBase.SkinWindow(frame)
    -- Community / guild roster rows (CommunitiesMemberList.lua:459) re-font on
    -- acquire + presence/state refresh.
    if frame.MemberList then HookListRows(frame.MemberList.ScrollBox) end
    if frame.CommunitiesList then HookListRows(frame.CommunitiesList.ScrollBox) end
    if frame.ApplicantList then HookListRows(frame.ApplicantList.ScrollBox) end
    if frame.GuildBenefitsFrame and frame.GuildBenefitsFrame.Rewards then
        HookListRows(frame.GuildBenefitsFrame.Rewards.ScrollBox)
    end
    -- GuildMemberDetailFrame's Remove / GroupInvite are UIPanelButtons: the engine
    -- swaps their Highlight/Disabled font OBJECT on hover/disable with no setter call,
    -- so LockFrameTextObjects (setter hook) can't catch it — drive the font objects.
    if frame.GuildMemberDetailFrame then
        SkinBase.ApplyButtonFontObjectsDeep(frame.GuildMemberDetailFrame, 3)
    end
    -- Member/Applicant column headers are pool-acquired by LayoutColumns AFTER
    -- skin time, so a one-shot lock finds an empty pool. Hook the shared mixin
    -- method (once) so the lock runs after the headers exist and on every rebuild.
    if not columnDisplayHooked and _G.ColumnDisplayMixin and _G.ColumnDisplayMixin.LayoutColumns then
        hooksecurefunc(_G.ColumnDisplayMixin, "LayoutColumns", function(self)
            -- The sortable column headers are Buttons with a HighlightFont OBJECT
            -- the engine swaps on hover with no setter call. Drive their font
            -- objects so the header label survives mouseover.
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

---------------------------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------------------------
SkinBase.OnAddOnLoaded("Blizzard_FriendsFrame", SkinFriends,     0)
SkinBase.OnAddOnLoaded("Blizzard_Communities",  SkinCommunities, 0)
