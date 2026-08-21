local settings = { autoInsertKey = true, closeBagsOnKeystoneInsert = true }
local closeAllBags = 0
local takeoverCloses = 0
local showHook

_G.C_AddOns = { IsAddOnLoaded = function() return true end }
_G.C_Container = {
    GetContainerNumSlots = function() return 1 end,
    GetContainerItemID = function() return 999 end,
    PickupContainerItem = function() end,
}
_G.Enum = { ItemClass = { Reagent = "Reagent" }, ItemReagentSubclass = { Keystone = "Keystone" } }
_G.C_Item = { GetItemInfo = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, Enum.ItemClass.Reagent, Enum.ItemReagentSubclass.Keystone end }
_G.C_Cursor = { GetCursorItem = function() return true end }
_G.C_ChallengeMode = { SlotKeystone = function() end }
_G.CloseAllBags = function() closeAllBags = closeAllBags + 1 end
_G.C_Timer = { After = function(_, fn) fn() end }
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        UnregisterEvent = function() end,
        SetScript = function(_, _, fn) showHook = fn end,
    }
end
_G.ChallengesKeystoneFrame = {
    HookScript = function(_, _, fn) showHook = fn end,
}

local ns = {
    Helpers = { CreateDBGetter = function() return function() return settings end end },
    Bags = {
        Takeover = {
            IsActive = function() return true end,
            CloseForFrame = function() takeoverCloses = takeoverCloses + 1 end,
        },
    },
}

assert(loadfile("modules/dungeon/keystone.lua"))("QUI", ns)
assert(showHook, "keystone frame must receive an OnShow hook")
showHook()
assert(takeoverCloses == 1, "QUI bags must close through the active takeover")
assert(closeAllBags == 0, "active QUI bags must not rely on Blizzard's container frames")

ns.Bags.Takeover.IsActive = function() return false end
showHook()
assert(closeAllBags == 1, "Blizzard bags must close when QUI takeover is inactive")

print("keystone_auto_insert_test.lua: ok")
