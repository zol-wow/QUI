local function sink()
    return setmetatable({}, { __index = function() return function() end end })
end

local created = {}
_G.CreateFrame = function(_, _, _, template)
    local f = { _scripts = {}, _template = template }
    function f.SetScript(self, which, fn) self._scripts[which] = fn end
    function f.GetScript(self, which) return self._scripts[which] end
    function f.HookScript(self, which, fn) self._scripts["hook:" .. which] = fn end
    function f.CreateTexture() return sink() end
    function f.CreateFontString() return sink() end
    function f.SetBagID() end
    function f.GetBagID() return 0 end
    function f.GetID() return 1 end
    function f.ClearNormalTexture() end
    function f.SetAlpha() end
    function f.SetAllPoints() end
    function f.SetPoint() end
    function f.SetID() end
    function f.RegisterForClicks() end
    function f.RegisterForDrag() end
    if template == "ContainerFrameItemButtonTemplate" then
        f.IconBorder = sink()
        f.BattlepayItemTexture = sink()
        f.Cooldown = sink()
        f.JunkIcon = sink()
        f.IconQuestTexture = sink()
        f.ItemContextOverlay = sink()
        f.NewItemTexture = sink()
    end
    created[#created + 1] = f
    return f
end

local overlayLog = {}
_G.SetItemButtonOverlay = function(button, itemIDOrLink, quality)
    overlayLog[#overlayLog + 1] = { op = "set", button = button, link = itemIDOrLink, quality = quality }
end
_G.ClearItemButtonOverlay = function(button)
    overlayLog[#overlayLog + 1] = { op = "clear", button = button }
end
_G.SetItemButtonTexture = function() end
_G.SetItemButtonCount = function() end
_G.SetItemButtonDesaturated = function() end
_G.CooldownFrame_Set = function() end
_G.GameTooltip = sink()
_G.C_Container = {
    GetContainerItemCooldown = function() return 0, 0, 0 end,
    GetContainerItemInfo = function() return { isLocked = false } end,
    GetContainerItemEquipmentSetInfo = function() return false end,
}

local settings = {
    appearance = { corners = { tr1 = "crafting_quality" } },
    behavior = { junk = {} },
}

local ns = {
    UIKit = { CreateBorderLines = function() end, UpdateBorderLines = function() end },
    Helpers = {
        CreateDBGetter = function() return function() return settings end end,
        GetGeneralFont = function() return "font" end,
        GetSkinColors = function() return 1, 1, 1 end,
    },
    SafeCall = function(_, fn, ...) return pcall(fn, ...) end,
}

local chunk = assert(loadfile("QUI_Bags/bags/views/item_buttons.lua"))
chunk("QUI", ns)
local ItemButtons = ns.Bags.ItemButtons

local fails = 0
local function check(name, ok, detail)
    if ok then print("  ok  " .. name)
    else fails = fails + 1; print("FAIL  " .. name .. (detail and ("  " .. detail) or "")) end
end

local function reset() for i = #overlayLog, 1, -1 do overlayLog[i] = nil end end
local function last() return overlayLog[#overlayLog] end

local button = ItemButtons.CreateLive({}, 0)

check("live buttons opt out of Blizzard's profession quality overlay",
    button.noProfessionQualityOverlay == true)

local COSMETIC = "|cffa335ee|Hitem:190622::::::::80:::::|h[Cosmetic]|h|r"

reset()
ItemButtons.Dress(button, { icon = 1, quality = 4, link = COSMETIC })
local rec = last()
check("an occupied slot hands its link to SetItemButtonOverlay",
    rec ~= nil and rec.op == "set" and rec.link == COSMETIC and rec.quality == 4,
    rec and ("op=" .. rec.op) or "no overlay call")

reset()
ItemButtons.Dress(button, { icon = 1, quality = 1 })
rec = last()
check("a linkless entry clears instead of calling with nil",
    rec ~= nil and rec.op == "clear",
    rec and ("op=" .. rec.op .. " link=" .. tostring(rec.link)) or "no overlay call")

reset()
ItemButtons.Dress(button, nil)
rec = last()
check("an empty slot clears the overlay", rec ~= nil and rec.op == "clear",
    rec and ("op=" .. rec.op) or "no overlay call")

_G.GetGuildBankItemInfo = function() return nil, nil, false end

for _, case in ipairs({
    { "cached", ItemButtons.CreateCached, function(b, e) ItemButtons.DressCached(b, e) end },
    { "guild", ItemButtons.CreateGuildLive, function(b, e) ItemButtons.DressGuildLive(b, 1, 1, e) end },
}) do
    local label, create, dress = case[1], case[2], case[3]
    local b = create({})

    check(label .. " buttons own an IconOverlay texture", b.IconOverlay ~= nil)
    check(label .. " buttons opt out of the profession quality overlay",
        b.noProfessionQualityOverlay == true)

    reset()
    dress(b, { icon = 1, quality = 4, link = COSMETIC })
    local r = last()
    check(label .. " buttons hand their link to SetItemButtonOverlay",
        r ~= nil and r.op == "set" and r.link == COSMETIC and r.quality == 4,
        r and ("op=" .. r.op) or "no overlay call")

    reset()
    dress(b, nil)
    r = last()
    check(label .. " buttons clear the overlay when the slot empties",
        r ~= nil and r.op == "clear", r and ("op=" .. r.op) or "no overlay call")
end

if fails > 0 then
    print(("FAILED %d check(s)"):format(fails))
    os.exit(1)
end
print("PASS bags_cosmetic_overlay_test")
