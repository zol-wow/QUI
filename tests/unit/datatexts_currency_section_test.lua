-- tests/unit/datatexts_currency_section_test.lua
-- Run: lua tests/unit/datatexts_currency_section_test.lua
-- TDD for the shared Currencies order/visibility section
-- (ns.QUI_BuildCurrencyOrderSection in datatexts_providers.lua), consumed by
-- the datatext panel AND Info Bar settings pages. The row checkbox is the
-- QUI toggle widget whose surface is SetValue(val, skipCallback)/GetValue/
-- onChange — NOT a Blizzard CheckButton: it has no SetChecked/GetChecked.
-- Guards the in-game crash where the row code called r._cb:SetChecked()
-- ("attempt to call a nil value", truncating every section after it on the
-- page — Micro Menu/Travel gone, section nav never qualifying). The headless
-- search-cache harness never executes this section (no default profile
-- places a currencies widget), so this test is the only automated coverage.
--
-- Covers: order normalization (legacy numeric entries, stale IDs dropped,
-- newly tracked appended, enabled seeded), row render state through the
-- toggle API, the toggle write path (explicit false + refresh/notify), and
-- arrow reorder driving the REAL OnClick handler — including the row-reuse
-- cid rebind (a reused row must write the currency it NOW displays, not the
-- one it was built with).

---------------------------------------------------------------------------
-- Widget stubs: explicit methods only. NO catch-all __index — a call to a
-- method the real kit doesn't expose (SetChecked!) is a hard nil-call
-- error, exactly like in-game.
---------------------------------------------------------------------------
local function MakeFontString()
    local fs = { _text = "" }
    function fs:SetText(t) self._text = t end
    function fs:SetPoint() end
    function fs:SetTextColor() end
    function fs:SetJustifyH() end
    function fs:SetWidth() end
    function fs:SetWordWrap() end
    return fs
end

local createdFrames = {}

local function MakeFrame()
    local f = { _shown = true, _scripts = {}, _alpha = 1 }
    function f:SetHeight(h) self._height = h end
    function f:SetSize() end
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:Show() self._shown = true end
    function f:Hide() self._shown = false end
    function f:SetAlpha(a) self._alpha = a end
    function f:SetScript(ev, fn) self._scripts[ev] = fn end
    function f:SetNormalFontObject() end
    function f:SetText() end
    function f:GetFontString() return MakeFontString() end
    function f:CreateFontString() return MakeFontString() end
    return f
end

_G.CreateFrame = function(...)
    local f = MakeFrame()
    createdFrames[#createdFrames + 1] = f
    return f
end

---------------------------------------------------------------------------
-- GUI stub: CreateFormCheckbox mirrors the REAL toggle container surface
-- (framework.lua CreateFormToggle): .label fontstring, SetValue with the
-- BindWidgetMethod calling convention (tolerates : and . style), GetValue,
-- onChange fired on simulated user click. Deliberately NO SetChecked.
---------------------------------------------------------------------------
local rowCbs = {}
local GUI = {}
function GUI:CreateFormCheckbox(_parent, label, _dbKey, _dbTable, onChange)
    local c = MakeFrame()
    -- real toggle: .label exists ONLY in labeled mode; the section uses
    -- BARE mode (nil label) and must not touch c.label
    if label then c.label = MakeFontString() end
    c.checked = false
    c.SetValue = function(selfOrVal, ...)
        local val, skip
        if selfOrVal == c then val, skip = ... else val = selfOrVal; skip = (...) end
        c.checked = val and true or false
        if not skip and onChange then onChange(c.checked) end
    end
    c.GetValue = function() return c.checked end
    -- the real toggle's internal OnClick path: flip + fire onChange
    c._click = function()
        c.checked = not c.checked
        if onChange then onChange(c.checked) end
    end
    rowCbs[#rowCbs + 1] = c
    return c
end

-- Track-a-currency dropdown stub: records options + the select callback so
-- the test can drive a selection.
local trackDDs = {}
function GUI:CreateFormDropdown(_parent, _label, options, _dbKey, _dbTable, onSelect)
    local d = MakeFrame()
    d._options = options
    d._select = onSelect
    d.SetValue = function() end
    trackDDs[#trackDDs + 1] = d
    return d
end

---------------------------------------------------------------------------
-- WoW surface + provider plumbing, then load the production file. The
-- RegisterAfterLoad stub invokes the registration callback immediately so
-- the export lands on ns.
---------------------------------------------------------------------------
local TRACKED = {
    { currencyTypesID = 2706, name = "Whelpling Crest", quantity = 5 },
    { currencyTypesID = 2245, name = "Flightstone", quantity = 100 },
    { currencyTypesID = 1191, name = "Valor", quantity = 0 },
}
-- Full currency list (the Currency tab): tracked entries carry
-- isShowInBackpack=true, headers are skipped, untracked owned currencies are
-- the track-dropdown pool. GetCurrencyListInfo MayReturnNothing past the end.
local CURRENCY_LIST = {
    { isHeader = true, name = "Dragonflight" },
    { currencyID = 2706, name = "Whelpling Crest", isShowInBackpack = true },
    { currencyID = 2245, name = "Flightstone", isShowInBackpack = true },
    { currencyID = 1191, name = "Valor", isShowInBackpack = true },
    { currencyID = 3008, name = "Untracked Shard", isShowInBackpack = false },
}
local backpackByIDCalls = {}
_G.C_CurrencyInfo = {
    GetBackpackCurrencyInfo = function(i) return TRACKED[i] end,
    GetCurrencyListSize = function() return #CURRENCY_LIST end,
    GetCurrencyListInfo = function(i) return CURRENCY_LIST[i] end,
    SetCurrencyBackpackByID = function(id, backpack)
        backpackByIDCalls[#backpackByIDCalls + 1] = { id = id, backpack = backpack }
    end,
}

local ns = {
    Settings = {
        ProviderPanels = {
            RegisterAfterLoad = function(_, cb)
                cb({
                    GUI = GUI,
                    U = {},
                    NotifyProviderFor = function() end,
                    RegisterShared = function() end,
                })
            end,
        },
    },
}

(dofile("tests/helpers/locale.lua"))(ns)
local chunk = assert(loadfile("QUI_Datatexts/datatexts/settings/datatexts_providers.lua"))
chunk("QUI", ns)
assert(type(ns.QUI_BuildCurrencyOrderSection) == "function",
    "datatexts_providers must export ns.QUI_BuildCurrencyOrderSection")

---------------------------------------------------------------------------
-- Build the section against a capturing layout.
---------------------------------------------------------------------------
local placed, headers = {}, {}
local L = {
    headerAt = function(text) headers[#headers + 1] = text end,
    placeCustom = function(frame, height) placed[#placed + 1] = { frame = frame, height = height } end,
}

local refreshes, notifies = 0, 0
-- legacy numeric entry + stale ID + "none" sentinel; 2245/1191 newly tracked
local dtGlobal = { currencyOrder = { 2706, "424242", "none" }, currencyEnabled = {} }

ns.QUI_BuildCurrencyOrderSection(L, MakeFrame(), {
    dtGlobal = dtGlobal,
    refresh = function() refreshes = refreshes + 1 end,
    notify = function() notifies = notifies + 1 end,
})

-- Section 1: order normalization + enabled seeding.
assert(headers[1] == "Currencies", "section must render the Currencies header")
assert(#dtGlobal.currencyOrder == 3, "order must hold exactly the 3 tracked IDs")
assert(dtGlobal.currencyOrder[1] == "2706",
    "legacy numeric entry must normalize to string and keep its slot")
assert(dtGlobal.currencyOrder[2] == "2245" and dtGlobal.currencyOrder[3] == "1191",
    "newly tracked currencies must append in backpack order")
for _, cid in ipairs(dtGlobal.currencyOrder) do
    assert(dtGlobal.currencyEnabled[cid] == true, "enabled must seed true for " .. cid)
end
assert(#placed == 2, "section must place the row frame + the footer note")

-- Section 2: rows rendered through the toggle API (reaching here at all
-- means no SetChecked nil-call), names on row-owned fontstrings + state set.
assert(#rowCbs == 3, "one checkbox per tracked currency, got " .. #rowCbs)
local rows = {}
for _, f in ipairs(createdFrames) do
    if f._name then rows[#rows + 1] = f end
end
assert(#rows == 3, "3 row frames must carry a _name fontstring, got " .. #rows)
assert(rows[1]._name._text == "Whelpling Crest", "row 1 must show the currency name")
assert(rows[2]._name._text == "Flightstone", "row 2 must show the appended currency")
assert(rowCbs[1].checked == true, "row 1 toggle must render enabled")

-- Section 3: user toggle writes the cid (explicit false) and fires
-- refresh + notify exactly once each.
rowCbs[1]._click() -- uncheck Whelpling Crest
assert(dtGlobal.currencyEnabled["2706"] == false, "uncheck must write explicit false")
assert(refreshes == 1 and notifies == 1,
    "toggle must refresh+notify once, got " .. refreshes .. "/" .. notifies)

-- Section 4: reorder via the REAL down-arrow OnClick. Arrow buttons are the
-- only created frames carrying an OnClick script; creation order per row is
-- up then down, so OnClick frames are { up1, down1, up2, down2, up3, down3 }.
local arrows = {}
for _, f in ipairs(createdFrames) do
    if f._scripts.OnClick then arrows[#arrows + 1] = f end
end
assert(#arrows == 6, "3 rows must own 6 arrow buttons, got " .. #arrows)
arrows[2]._scripts.OnClick() -- row 1 down-arrow: swap rows 1 and 2
assert(dtGlobal.currencyOrder[1] == "2245" and dtGlobal.currencyOrder[2] == "2706",
    "down-arrow must swap order slots 1 and 2")
assert(refreshes == 2 and notifies == 2, "reorder must refresh+notify")
-- Reused rows must be re-labeled in place by RebuildCurrencyRows...
assert(rows[1]._name._text == "Flightstone", "reused row 1 must re-label to the swapped-in currency")
assert(rows[2]._name._text == "Whelpling Crest", "reused row 2 must re-label to the swapped-out currency")
-- ...and the cid rebind means the reused row writes ITS currency now.
assert(rowCbs[1].checked == true, "Flightstone renders enabled after the swap")
rowCbs[1]._click() -- uncheck Flightstone via the reused row-1 checkbox
assert(dtGlobal.currencyEnabled["2245"] == false,
    "reused row must write the currency it now displays (cid rebind)")
assert(dtGlobal.currencyEnabled["2706"] == false, "prior uncheck must be untouched")

-- Section 5: a second config table (the bags.currencyBar shape) lists the
-- SAME backpack-tracked pool but edits independently — its order/enabled
-- seed from the pool, an explicit false carried in (e.g. from the legacy-set
-- migration) survives, and toggling here never touches the first config.
local cbsBefore = #rowCbs
local cbarCfg = { currencyOrder = {}, currencyEnabled = { ["2245"] = false } }
ns.QUI_BuildCurrencyOrderSection(L, MakeFrame(), {
    dtGlobal = cbarCfg,
    refresh = function() end,
    notify = function() end,
})
assert(#cbarCfg.currencyOrder == 3, "second config must seed the same tracked pool")
assert(cbarCfg.currencyEnabled["2706"] == true, "unseen entries seed true")
assert(cbarCfg.currencyEnabled["2245"] == false, "a pre-existing explicit false must survive seeding")
assert(#rowCbs == cbsBefore + 3, "one checkbox per tracked currency")
rowCbs[cbsBefore + 1]._click() -- uncheck 2706 in the SECOND config
assert(cbarCfg.currencyEnabled["2706"] == false, "toggle must write the second config")
assert(dtGlobal.currencyEnabled["2706"] == false and dtGlobal.currencyEnabled["1191"] == true,
    "the first config must be untouched by the second config's toggle")

-- Section 6: the track-a-currency dropdown — options are the visible
-- currency-list entries that are NOT headers and NOT already backpack-
-- tracked (placeholder first); selecting one calls SetCurrencyBackpackByID
-- and fires refresh+notify so the section rebuilds with the new row.
local dd = trackDDs[1]
assert(dd, "the section must build a track-a-currency dropdown")
assert(dd._options[1].value == "", "first option is the placeholder")
assert(#dd._options == 2 and dd._options[2].value == 3008 and dd._options[2].text == "Untracked Shard",
    "options must list only owned-but-untracked currencies (headers + tracked excluded)")
local refsBefore, notsBefore = refreshes, notifies
dd._select(3008)
assert(#backpackByIDCalls == 1 and backpackByIDCalls[1].id == 3008 and backpackByIDCalls[1].backpack == true,
    "selecting must call SetCurrencyBackpackByID(id, true)")
assert(refreshes == refsBefore + 1 and notifies == notsBefore + 1,
    "tracking must refresh + notify (structural rebuild picks up the new row)")
dd._select("") -- placeholder re-select must be a no-op
assert(#backpackByIDCalls == 1, "placeholder select must not track anything")

print("OK: datatexts_currency_section_test")
