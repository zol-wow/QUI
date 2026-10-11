local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local function ClassColorForGUID(guid)
    if not guid then return nil end
    local _, englishClass = GetPlayerInfoByGUID(guid)
    if not englishClass then return nil end
    return RAID_CLASS_COLORS and RAID_CLASS_COLORS[englishClass] or nil
end

local function DecorateFriendButton(button)
    local settings = GetSettings()
    if not settings or settings.friendsClassColor == false then return end
    if not button or not button.name or button.buttonType == nil then return end

    local color
    if button.buttonType == FRIENDS_BUTTON_TYPE_WOW then
        local info = C_FriendList.GetFriendInfoByIndex(button.id)
        if info and info.connected and info.guid then
            color = ClassColorForGUID(info.guid)
        end
    elseif button.buttonType == FRIENDS_BUTTON_TYPE_BNET then
        local accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
        local ga = accountInfo and accountInfo.gameAccountInfo
        if ga and ga.isOnline and ga.playerGuid and ga.clientProgram == BNET_CLIENT_WOW then
            color = ClassColorForGUID(ga.playerGuid)
        end
    end

    if color then
        button.name:SetTextColor(color.r, color.g, color.b)
    end
end

local inviteMenuHooked = false

local function FilterInviteMenu(manager, owner, rootDescription)
    if rootDescription:GetTag() ~= "MENU_FRIENDS_TRAVEL_PASS" then return end
    local parent = owner and owner.GetParent and owner:GetParent()
    local friendIndex = owner and (owner.friendIndex or (parent and parent.id))
    if not friendIndex then return end

    local numAccounts = C_BattleNet.GetFriendNumGameAccounts(friendIndex)
    local entries = {}
    local removed = false
    for index, description in rootDescription:EnumerateElementDescriptions() do
        local gameAccountInfo
        if index > 1 and index <= numAccounts + 1 then
            gameAccountInfo = C_BattleNet.GetFriendGameAccountInfo(friendIndex, index - 1)
        end
        if gameAccountInfo and gameAccountInfo.clientProgram ~= BNET_CLIENT_WOW
            and not description:IsEnabled() then
            removed = true
        else
            entries[#entries + 1] = description
        end
    end
    if not removed then return end

    local filtered = MenuUtil.CreateRootMenuDescription(owner.menuMixin or _G.MenuVariants.GetDefaultContextMenuMixin())
    local tag, contextData = rootDescription:GetTag()
    filtered:SetTag(tag, contextData)
    for _, description in ipairs(entries) do
        filtered:Insert(description)
    end
    local menu = manager:GetOpenMenu()
    if menu then menu:SetMenuDescription(filtered) end
end

local hooked = false
local function InstallHook()
    if not inviteMenuHooked and _G.Menu and _G.Menu.GetManager then
        hooksecurefunc(_G.Menu.GetManager(), "OpenContextMenu", FilterInviteMenu)
        inviteMenuHooked = true
    end
    if hooked then return end
    if type(_G.FriendsFrame_UpdateFriendButton) ~= "function" then return end
    hooksecurefunc("FriendsFrame_UpdateFriendButton", DecorateFriendButton)
    hooked = true
end

local function RefreshFriendsDecor()
    InstallHook()
    if _G.FriendsListFrame and _G.FriendsListFrame:IsShown()
        and type(_G.FriendsList_Update) == "function" then
        _G.FriendsList_Update()
    end
end
ns.RefreshFriendsDecor = RefreshFriendsDecor

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(_, _, loadedAddon)
    if loadedAddon == "Blizzard_FriendsFrame" then
        InstallHook()
    end
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        InstallHook()
    end)
end

if ns.Registry then
    ns.Registry:Register("friendsDecor", {
        refresh = RefreshFriendsDecor,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end
