-- tests/unit/bags_item_buttons_tooltip_test.lua
-- Cached-button / search-row tooltips must route battlepet: hyperlinks
-- through BattlePetToolTip_ShowLink (GameTooltip:SetHyperlink cannot render
-- them — vendored Blizzard_FrameXML/BattlePetTooltip.lua:13, and the AH
-- caller idiom in Blizzard_AuctionHouseSharedTemplates.lua:25-26), and the
-- leave path must hide BattlePetTooltip alongside GameTooltip.
-- Run: lua tests/unit/bags_item_buttons_tooltip_test.lua

-- Minimal frame fake: records scripts; textures/fontstrings are method sinks.
local function sink()
    local t = {}
    return setmetatable(t, { __index = function() return function() end end })
end
_G.CreateFrame = function()
    local f = { _scripts = {} }
    function f.SetScript(self, which, fn) self._scripts[which] = fn end
    function f.GetScript(self, which) return self._scripts[which] end
    function f.CreateTexture() return sink() end
    function f.CreateFontString() return sink() end
    function f.SetAlpha() end
    function f.SetID() end
    function f.SetAllPoints() end
    function f.HookScript() end
    function f.RegisterForClicks() end
    function f.RegisterForDrag() end
    return f
end

-- Tooltip recorders
local log = {}
_G.GameTooltip = {
    SetOwner = function(_, owner, anchor) log[#log + 1] = "owner:" .. tostring(anchor) end,
    SetHyperlink = function(_, link) log[#log + 1] = "hyperlink:" .. link end,
    SetItemByID = function(_, id) log[#log + 1] = "itemid:" .. id end,
    Show = function() log[#log + 1] = "show" end,
    Hide = function() log[#log + 1] = "gt-hide" end,
}
_G.BattlePetToolTip_ShowLink = function(link) log[#log + 1] = "petlink:" .. link end
_G.BattlePetTooltip = { Hide = function() log[#log + 1] = "pet-hide" end }
local function reset() for i = #log, 1, -1 do log[i] = nil end end
local function seen(entry)
    for _, v in ipairs(log) do if v == entry then return true end end
    return false
end

local ns = {
    UIKit = { CreateBorderLines = function() end, UpdateBorderLines = function() end },
    Helpers = {
        CreateDBGetter = function() return function() return {} end end,
        GetGeneralFont = function() return "font" end,
        GetSkinColors = function() return 1, 1, 1 end,
    },
}
local chunk = assert(loadfile("QUI_Bags/bags/views/item_buttons.lua"))
chunk("QUI", ns)
local ItemButtons = ns.Bags.ItemButtons

-- Test 1: shared tooltip helper exists and routes by link type.
assert(type(ItemButtons.ShowItemTooltip) == "function", "ShowItemTooltip helper missing")
assert(type(ItemButtons.HideItemTooltip) == "function", "HideItemTooltip helper missing")

local PET = "|cff0070dd|Hbattlepet:1234:25:3:1546:276:244|h[Pet]|h|r"
local SWORD = "|cffa335ee|Hitem:19019::::::::60:::::|h[Sword]|h|r"

-- battlepet link → ShowLink path, GameTooltip owner set first (the pet
-- tooltip anchors itself to GameTooltip's point), no SetHyperlink/Show.
reset()
ItemButtons.ShowItemTooltip({}, PET, nil)
assert(seen("petlink:" .. PET), "battlepet link must route to BattlePetToolTip_ShowLink")
assert(seen("owner:ANCHOR_RIGHT"), "GameTooltip owner must be set before ShowLink (anchor source)")
assert(not seen("hyperlink:" .. PET), "battlepet link must NOT go through SetHyperlink")

-- battlepet link wins even when an itemID (the cage, 82800) is supplied —
-- SetItemByID(82800) would show the generic cage tooltip.
reset()
ItemButtons.ShowItemTooltip({}, PET, 82800)
assert(seen("petlink:" .. PET), "battlepet link must outrank the cage itemID")
assert(not seen("itemid:82800"), "cage itemID must not be used when a pet link exists")

-- normal link: itemID preferred (search rows), hyperlink fallback.
reset()
ItemButtons.ShowItemTooltip({}, SWORD, 19019)
assert(seen("itemid:19019") and seen("show"), "itemID path must SetItemByID + Show")
reset()
ItemButtons.ShowItemTooltip({}, SWORD, nil)
assert(seen("hyperlink:" .. SWORD) and seen("show"), "link path must SetHyperlink + Show")

-- hide helper hides BOTH tooltips (a zombie BattlePetTooltip otherwise
-- survives leaving the button).
reset()
ItemButtons.HideItemTooltip()
assert(seen("gt-hide") and seen("pet-hide"), "leave must hide GameTooltip AND BattlePetTooltip")

-- Test 2: cached buttons route through the helper.
local btn = ItemButtons.CreateCached({})
assert(btn._scripts.OnEnter and btn._scripts.OnLeave, "cached button scripts missing")
reset()
btn._link = PET
btn._scripts.OnEnter(btn)
assert(seen("petlink:" .. PET), "cached button OnEnter must route battlepet links to ShowLink")
assert(not seen("hyperlink:" .. PET), "cached button must not SetHyperlink a battlepet link")
reset()
btn._link = SWORD
btn._scripts.OnEnter(btn)
assert(seen("hyperlink:" .. SWORD), "cached button OnEnter must SetHyperlink normal links")
reset()
btn._scripts.OnLeave(btn)
assert(seen("gt-hide") and seen("pet-hide"), "cached button OnLeave must hide both tooltips")

-- Regression: CreateLive must hide the template's BattlepayItemTexture.
-- ContainerFrame.xml ships it VISIBLE (the only overlay with no hidden=/
-- alpha=0 attribute); stock bags hide it on every UpdateNewItem pass, which
-- Dress replaces — leaving it shown made every item wear the store
-- highlight permanently ("everything looks new", surviving reloads).
local battlepayHidden = false
local prevCreateFrame = _G.CreateFrame
_G.CreateFrame = function(frameType, name, parent, template)
    local f = prevCreateFrame(frameType, name, parent, template)
    f.SetBagID = function() end
    if template == "ContainerFrameItemButtonTemplate" then
        f.IconBorder = { SetAlpha = function() end }
        f.BattlepayItemTexture = { Hide = function() battlepayHidden = true end }
    end
    return f
end
ItemButtons.CreateLive({}, 0)
assert(battlepayHidden, "CreateLive must hide the default-visible BattlepayItemTexture")
_G.CreateFrame = prevCreateFrame

print("OK: bags_item_buttons_tooltip_test")
