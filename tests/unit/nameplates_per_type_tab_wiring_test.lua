local env = dofile("tools/_addon_env.lua")
local ns = env.LoadCore()

local function fail(msg)
    print("FAIL: nameplates_per_type_tab_wiring_test - " .. msg)
    os.exit(1)
end

local function test(name, fn)
    print(name)
    fn()
    print("  ok")
end

local function NewMockFontString()
    local fs = {}
    function fs:SetPoint() end
    function fs:ClearAllPoints() end
    function fs:SetJustifyH() end
    function fs:SetText(t) self._text = t end
    function fs:GetText() return self._text end
    function fs:SetTextColor() end
    function fs:GetStringHeight() return 14 end
    return fs
end

local function NewMockFrame()
    local f = { _height = 0, _width = 0 }
    function f:SetPoint() end
    function f:ClearAllPoints() end
    function f:SetHeight(h) self._height = h end
    function f:GetHeight() return self._height end
    function f:SetWidth(w) self._width = w end
    function f:GetWidth() return self._width end
    function f:SetSize(w, h) self._width = w; self._height = h end
    function f:SetAlpha(a) self._alpha = a end
    function f:GetAlpha() return self._alpha end
    function f:CreateFontString() return NewMockFontString() end
    function f:SetScript(event, fn) self._scripts = self._scripts or {}; self._scripts[event] = fn end
    function f:RegisterEvent() end
    function f:RegisterUnitEvent() end
    function f:Show() end
    function f:Hide() end
    function f:SetParent() end
    function f:Disable() end
    function f:Enable() end
    return f
end

CreateFrame = function(_, _, _) return NewMockFrame() end
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_NamePlateManager = { SetNamePlateSimplified = function() end }

local testProfile = { nameplates = { types = {} } }
ns.Helpers = {
    GetProfile = function() return testProfile end,
    GetModuleSettings = function() return testProfile.nameplates end,
}

env.LoadAddonFile("core/settings/util.lua", "QUI", ns)
env.LoadAddonFile("core/settings/schema.lua", "QUI", ns)
env.LoadAddonFile("core/settings/renderer.lua", "QUI", ns)

env.LoadAddonFile("QUI_Nameplates/nameplates/shared.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/plate_type.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/presets.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/settings/nameplates_model.lua", "QUI_Nameplates", ns)
env.LoadAddonFile("QUI_Nameplates/nameplates/settings/nameplates_schema.lua", "QUI_Nameplates", ns)

local invalidateCalls = 0
local repaintCalls = 0
ns.QUI_NameplatesSettingsSurface = {
    InvalidateTabBodies = function() invalidateCalls = invalidateCalls + 1 end,
    RepaintActiveTab = function() repaintCalls = repaintCalls + 1 end,
}

local NP = ns.QUI_Nameplates
local Schema = ns.QUI_NameplatesSettingsSchema

local WIDTHS = {
    petMinion = 111, friendly = 222, bossElite = 333,
    minorTrivial = 444, enemyPlayer = 555, enemyNPC = 666,
}

local db = testProfile.nameplates
for _, key in ipairs(NP.PlateType.ORDER) do
    db.types[key] = {
        health = { width = WIDTHS[key] },
        colors = { hostile = { key .. "-r", key .. "-g", key .. "-b" } },
    }
end

local capturedSliders = {}
local capturedColorPickers = {}
local capturedDropdowns = {}
local capturedCheckboxes = {}
local capturedButtons = {}
local capturedConfirmations = {}
local capturedLabels = {}

local function ResetCaptures()
    capturedSliders = {}
    capturedColorPickers = {}
    capturedDropdowns = {}
    capturedCheckboxes = {}
    capturedButtons = {}
    capturedConfirmations = {}
    capturedLabels = {}
    invalidateCalls = 0
    repaintCalls = 0
end

_G.QUI = _G.QUI or {}
_G.QUI.GUI = {
    CreateFormSlider = function(_self, _parent, _label, _min, _max, _step, dbKey, dbTable)
        capturedSliders[#capturedSliders + 1] = { dbKey = dbKey, dbTable = dbTable }
        return NewMockFrame()
    end,
    CreateFormColorPicker = function(_self, _parent, _label, dbKey, dbTable)
        capturedColorPickers[#capturedColorPickers + 1] = { dbKey = dbKey, dbTable = dbTable }
        return NewMockFrame()
    end,
    CreateFormCheckbox = function(_self, _parent, _label, dbKey, dbTable, refresh)
        capturedCheckboxes[#capturedCheckboxes + 1] = { dbKey = dbKey, dbTable = dbTable, refresh = refresh }
        return NewMockFrame()
    end,
    CreateLabel = function(_self, _parent, _text, _size)
        return NewMockFrame()
    end,
    CreateFormDropdown = function(_self, _parent, _label, options, dbKey, dbTable, refresh, opts)
        capturedDropdowns[#capturedDropdowns + 1] = {
            dbKey = dbKey, dbTable = dbTable, options = options,
            refresh = refresh, description = type(opts) == "table" and opts.description or nil,
        }
        return NewMockFrame()
    end,
    CreateButton = function(_self, _parent, _label, _w, _h, onClick)
        capturedButtons[#capturedButtons + 1] = onClick
        return NewMockFrame()
    end,
    ShowConfirmation = function(_self, opts)
        capturedConfirmations[#capturedConfirmations + 1] = opts
    end,
}

ns.QUI_Options = {
    CreateAccentDotLabel = function(_, _text, _)
        return NewMockFrame()
    end,
    CreateSettingsCardGroup = function(_parent, _yOffset)
        local card = { frame = NewMockFrame() }
        function card.AddRow(...) end
        function card.Finalize() end
        return card
    end,
    BuildSettingRow = function(_parent, labelText, _widget)
        if type(labelText) == "string" then
            capturedLabels[labelText] = (capturedLabels[labelText] or 0) + 1
        end
        return NewMockFrame()
    end,
    GetTextureList = function() return {} end,
    GetFontList = function() return {} end,
}

test("RenderFrameTab threads bossElite's typeKey to the health width slider", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderFrameTab(host, "bossElite")

    local widthCapture
    for _, entry in ipairs(capturedSliders) do
        if entry.dbKey == "width" then widthCapture = entry end
    end
    if not widthCapture then fail("no width slider was captured") end
    if widthCapture.dbTable ~= db.types.bossElite.health then
        fail("width slider bound to the wrong subtree for typeKey=bossElite")
    end
end)

test("RenderFrameTab threads enemyNPC's typeKey to the health width slider", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderFrameTab(host, "enemyNPC")

    local widthCapture
    for _, entry in ipairs(capturedSliders) do
        if entry.dbKey == "width" then widthCapture = entry end
    end
    if not widthCapture then fail("no width slider was captured") end
    if widthCapture.dbTable ~= db.types.enemyNPC.health then
        fail("width slider bound to the wrong subtree for typeKey=enemyNPC")
    end
    if widthCapture.dbTable == db.types.bossElite.health then
        fail("enemyNPC render read bossElite's subtree -- typeKey did not change anything")
    end
end)

test("RenderColorsTab threads the typeKey to the reaction color picker", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderColorsTab(host, "friendly")

    local hostileCapture
    for _, entry in ipairs(capturedColorPickers) do
        if entry.dbKey == "hostile" then hostileCapture = entry end
    end
    if not hostileCapture then fail("no hostile color picker was captured") end
    if hostileCapture.dbTable ~= db.types.friendly.colors then
        fail("reaction color picker bound to the wrong subtree for typeKey=friendly")
    end
end)

local function NoPerTypeSubTable(name)
    for _, key in ipairs(NP.PlateType.ORDER) do
        local perType = db.types[key]
        if perType and perType[name] ~= nil then
            fail(("rendering a global section created types.%s.%s -- it read a per-type table")
                :format(key, name))
        end
    end
end

local function CapturedBy(list, dbKey)
    for _, entry in ipairs(list) do
        if entry.dbKey == dbKey then return entry end
    end
    return nil
end

test("RenderVisibilityTab binds the visibility toggles to the global cvars table", function()
    ResetCaptures()
    local host = NewMockFrame()
    if Schema.RenderVisibilityTab(host) == false then fail("RenderVisibilityTab must render without a typeKey") end

    local toggle = CapturedBy(capturedCheckboxes, "showFriendlyPets")
    if not toggle then fail("no showFriendlyPets toggle was captured") end
    if toggle.dbTable ~= db.cvars then
        fail("the visibility toggle must bind to the global nameplates.cvars table")
    end
    NoPerTypeSubTable("cvars")
end)

test("RenderVisibilityTab binds the friendly master toggle to the global table", function()
    ResetCaptures()
    local host = NewMockFrame()
    if Schema.RenderVisibilityTab(host) == false then fail("RenderVisibilityTab must render") end

    local master = CapturedBy(capturedCheckboxes, "enabled")
    if not master then fail("no friendly master toggle was captured") end
    if master.dbTable ~= db.friendly then
        fail("the friendly master toggle must bind to the global nameplates.friendly table")
    end
    NoPerTypeSubTable("friendly")
end)

test("the Frame tab binds fading and layout to the global tables", function()
    ResetCaptures()
    local host = NewMockFrame()
    if Schema.RenderFrameTab(host, "bossElite") == false then fail("RenderFrameTab must render") end

    local nonTarget = CapturedBy(capturedSliders, "nonTargetAlpha")
    if not nonTarget then fail("no nonTargetAlpha slider was captured") end
    if nonTarget.dbTable ~= db.fading then
        fail("the fading slider must bind to the global nameplates.fading table")
    end

    local targetScale = CapturedBy(capturedSliders, "targetScale")
    if not targetScale then fail("no targetScale slider was captured") end
    if targetScale.dbTable ~= db.layout then
        fail("the target scale slider must bind to the global nameplates.layout table")
    end

    NoPerTypeSubTable("fading")
    NoPerTypeSubTable("layout")
end)

test("the Friendly section keeps mode/showInWorld/showInInstances and drops the four dead controls", function()
    ResetCaptures()
    local host = NewMockFrame()
    if Schema.RenderVisibilityTab(host) == false then fail("RenderVisibilityTab must render") end

    local npcs = CapturedBy(capturedCheckboxes, "showNPCs")
    if not npcs then
        fail("no Friendly NPCs toggle was captured -- nameplateShowFriendlyNpcs would stay derived")
    end
    if npcs.dbTable ~= db.friendly then
        fail("the Friendly NPCs toggle must bind to the global nameplates.friendly table")
    end

    for _, label in ipairs({ ns.L["Friendly Nameplates"], ns.L["Show In World"], ns.L["Show In Instances"], ns.L["Friendly NPCs"] }) do
        if not capturedLabels[label] then
            fail("expected the Friendly section to still render a " .. tostring(label) .. " row")
        end
    end
    for _, label in ipairs({ ns.L["Name Size"], ns.L["Class Color Names"], ns.L["Bar Width"], ns.L["Bar Height"] }) do
        if capturedLabels[label] then
            fail("the dead Friendly control " .. tostring(label) .. " must not render any more")
        end
    end
end)

test("the Copy From dropdown on the Frame tab offers exactly the other five types", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderFrameTab(host, "bossElite")

    local copyDropdown
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "selected" then copyDropdown = entry end
    end
    if not copyDropdown then fail("no Copy From dropdown was captured") end
    if #copyDropdown.options ~= 5 then
        fail("expected 5 copy-from options, got " .. #copyDropdown.options)
    end
    for _, option in ipairs(copyDropdown.options) do
        if option.value == "bossElite" then
            fail("the current type must not appear in its own Copy From list")
        end
        if type(option.text) ~= "string" or option.text == "" then
            fail("copy-from option " .. tostring(option.value) .. " has no label")
        end
    end
end)

test("RenderAurasTab renders Copy From by default, on the main settings panel", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderAurasTab(host, "bossElite")

    local copyDropdown
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "selected" then copyDropdown = entry end
    end
    if not copyDropdown then fail("the main panel's Auras tab must still offer Copy From") end
end)

test("RenderAurasTab suppresses Copy From when hideCopyFrom is true, for the Auras hub page", function()
    ResetCaptures()
    local host = NewMockFrame()
    Schema.RenderAurasTab(host, "bossElite", true)

    local copyDropdown
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "selected" then copyDropdown = entry end
    end
    if copyDropdown then
        fail("the Auras hub page has no type selector -- Copy From must not render there")
    end
    if capturedLabels[ns.L["Copy Settings"]] then
        fail("the Copy Settings header must not render on the Auras hub page either")
    end
end)

test("clicking Apply Copy on the Frame tab confirms, then copies the chosen type's health width", function()
    ResetCaptures()
    db.types.enemyNPC.health.width = WIDTHS.enemyNPC
    local host = NewMockFrame()
    Schema.RenderFrameTab(host, "enemyNPC")

    local copyDropdown
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "selected" then copyDropdown = entry end
    end
    if not copyDropdown then fail("no Copy From dropdown was captured") end
    copyDropdown.dbTable.selected = "petMinion"

    if #capturedButtons ~= 1 then
        fail("expected exactly one Apply Copy button, got " .. #capturedButtons)
    end
    capturedButtons[1]()

    if #capturedConfirmations ~= 1 then
        fail("clicking Apply Copy must open exactly one confirmation dialog")
    end
    local confirmation = capturedConfirmations[1]
    if type(confirmation.message) ~= "string" or confirmation.message == "" then
        fail("confirmation dialog has no message")
    end
    if type(confirmation.onAccept) ~= "function" then
        fail("confirmation dialog has no onAccept handler")
    end

    confirmation.onAccept()

    if db.types.enemyNPC.health.width ~= WIDTHS.petMinion then
        fail("confirming the copy did not overwrite enemyNPC's health width with petMinion's")
    end
    if db.types.bossElite.health.width ~= WIDTHS.bossElite then
        fail("confirming the copy touched an unrelated type")
    end
end)

local function CaptureRenderModeDropdown()
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "renderMode" then return entry end
    end
    return nil
end

local function CaptureRenderModeDropdownFor(typeTable)
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "renderMode" and entry.dbTable == typeTable then return entry end
    end
    return nil
end

test("the Visibility tab carries one render mode dropdown per type, each bound to its own type", function()
    ResetCaptures()
    Schema.RenderVisibilityTab(NewMockFrame())

    local count = 0
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "renderMode" then count = count + 1 end
    end
    if count ~= 6 then
        fail("expected one render mode dropdown per type, got " .. count)
    end

    for _, key in ipairs(NP.PlateType.ORDER) do
        local capture = CaptureRenderModeDropdownFor(db.types[key])
        if not capture then
            fail("no render mode dropdown bound to nameplates.types." .. key
                .. " -- that type could never be set to name-only")
        end
        local seen = {}
        for _, option in ipairs(capture.options or {}) do seen[option.value] = true end
        for _, value in ipairs({ "bars", "simplified", "nameonly" }) do
            if not seen[value] then
                fail("the " .. key .. " render mode dropdown must offer " .. value)
            end
        end
        if #(capture.options or {}) ~= 3 then
            fail("the " .. key .. " dropdown must offer exactly the three modes, got "
                .. #(capture.options or {}))
        end
    end
end)

test("the Frame tab no longer carries a render mode dropdown", function()
    ResetCaptures()
    Schema.RenderFrameTab(NewMockFrame(), "bossElite")
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "renderMode" then
            fail("render mode moved to the Visibility tab -- two controls would fight over it")
        end
    end
end)

test("no per-type Simplified checkbox survives alongside the dropdown", function()
    ResetCaptures()
    Schema.RenderFrameTab(NewMockFrame(), "bossElite")
    for _, entry in ipairs(capturedCheckboxes) do
        if entry.dbKey == "useSimplified" then
            fail("useSimplified must be gone -- two controls would fight over the same look")
        end
    end
end)

test("the Frame tab carries the global simplified scale slider", function()
    ResetCaptures()
    Schema.RenderFrameTab(NewMockFrame(), "bossElite")

    local capture
    for _, entry in ipairs(capturedSliders) do
        if entry.dbKey == "scale" then capture = entry end
    end
    if not capture then
        fail("simplified.scale has no control -- cvars.lua writes the CVar with nothing able to change it")
    end
    if capture.dbTable ~= db.simplified then
        fail("the scale slider must write nameplates.simplified, got a different table")
    end
    if not capturedLabels[ns.L["Simplified Plate Scale"]] then
        fail("the slider must render a labelled row")
    end
end)

test("both render-mode controls survive on a client without the API", function()
    local saved = NP.SIMPLIFIED_AVAILABLE
    NP.SIMPLIFIED_AVAILABLE = false

    ResetCaptures()
    Schema.RenderVisibilityTab(NewMockFrame())
    local capture = CaptureRenderModeDropdownFor(db.types.bossElite)
    if not capture then
        NP.SIMPLIFIED_AVAILABLE = saved
        fail("QUI draws all three modes itself -- gating the dropdown on C_NamePlateManager "
            .. "makes name-only unreachable on that client")
    end

    ResetCaptures()
    Schema.RenderFrameTab(NewMockFrame(), "bossElite")
    local slider
    for _, entry in ipairs(capturedSliders) do
        if entry.dbKey == "scale" then slider = entry end
    end
    NP.SIMPLIFIED_AVAILABLE = saved
    if not slider then
        fail("PinPlateScale applies the simplified scale QUI-side, so its slider must render "
            .. "without C_NamePlateManager too")
    end
end)

test("confirming a Copy From invalidates the other cached tab bodies", function()
    ResetCaptures()
    Schema.RenderFrameTab(NewMockFrame(), "enemyNPC")

    local copyDropdown
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "selected" then copyDropdown = entry end
    end
    if not copyDropdown then fail("no Copy From dropdown was captured") end
    copyDropdown.dbTable.selected = "petMinion"

    capturedButtons[1]()
    if #capturedConfirmations ~= 1 then fail("expected one confirmation dialog") end
    if invalidateCalls ~= 0 then fail("nothing must be invalidated before the user confirms") end

    capturedConfirmations[1].onAccept()
    if invalidateCalls ~= 1 then
        fail("a confirmed copy must invalidate the cached tab bodies, or the other five tabs keep showing pre-copy values")
    end
end)

test("confirming a Starter Style invalidates the other cached tab bodies", function()
    ResetCaptures()
    Schema.RenderGeneralTab(NewMockFrame())

    if #capturedButtons == 0 then fail("the General tab must render Starter Style buttons") end
    capturedButtons[2]()
    if #capturedConfirmations ~= 1 then
        fail("clicking a Starter Style must open exactly one confirmation, got " .. #capturedConfirmations)
    end
    if invalidateCalls ~= 0 then fail("nothing must be invalidated before the user confirms") end

    capturedConfirmations[1].onAccept()
    if invalidateCalls ~= 1 then
        fail("a confirmed starter style must invalidate the cached tab bodies, "
            .. "or the other tabs keep showing pre-style values")
    end
end)

print("OK: nameplates_per_type_tab_wiring_test")

test("toggling a visibility parent repaints the tab so the dithering updates immediately", function()
    ResetCaptures()
    Schema.RenderVisibilityTab(NewMockFrame())

    local master = CapturedBy(capturedCheckboxes, "showEnemies")
    if not master then fail("no enemy master toggle was captured") end
    if type(master.refresh) ~= "function" then
        fail("the enemy master has no refresh callback -- its children could never re-dither")
    end

    master.refresh()
    if repaintCalls < 1 then
        fail("toggling the enemy master must repaint the active tab; the render-time dither "
            .. "otherwise survives in the cached tab body until the user leaves and returns")
    end

    ResetCaptures()
    Schema.RenderVisibilityTab(NewMockFrame())
    local pets = CapturedBy(capturedCheckboxes, "showFriendlyPets")
    if not pets or type(pets.refresh) ~= "function" then
        fail("no refresh callback on the friendly kind toggles")
    end
    pets.refresh()
    if repaintCalls < 1 then
        fail("the friendly kind toggles feed the petMinion dither, so they must repaint too")
    end
end)

test("only the friendly render mode says it does not apply inside instances", function()
    ResetCaptures()
    Schema.RenderVisibilityTab(NewMockFrame())

    local friendly, other
    for _, entry in ipairs(capturedDropdowns) do
        if entry.dbKey == "renderMode" then
            if entry.dbTable == db.types.friendly then
                friendly = entry
            elseif entry.dbTable == db.types.enemyNPC then
                other = entry
            end
        end
    end
    if not friendly or not other then fail("expected both a friendly and an enemyNPC render mode dropdown") end
    if type(friendly.description) ~= "string" or type(other.description) ~= "string" then
        fail("both render mode dropdowns must carry a description")
    end
    if friendly.description == other.description then
        fail("the friendly render mode must state that instances are Blizzard-drawn -- "
            .. "otherwise it reads as though it applies everywhere")
    end
    if not friendly.description:find(ns.L["Show In Instances"], 1, true) then
        fail("the friendly description must point at the Show In Instances setting that governs there")
    end
end)

test("the friendly kind toggles live inside the Friendly Nameplates section, gated by its mode", function()
    ResetCaptures()
    db.friendly = db.friendly or {}
    db.friendly.enabled = true
    Schema.RenderVisibilityTab(NewMockFrame())

    for _, key in ipairs({ "showFriendlyMinions", "showFriendlyPets", "showFriendlyTotems", "showFriendlyGuardians" }) do
        local toggle = CapturedBy(capturedCheckboxes, key)
        if not toggle then
            fail("the friendly kind toggle " .. key .. " must render inside the Friendly section")
        end
        if toggle.dbTable ~= db.cvars then
            fail(key .. " must bind to the global nameplates.cvars table")
        end
    end

    local master = CapturedBy(capturedCheckboxes, "enabled")
    if not master or type(master.refresh) ~= "function" then
        fail("the friendly master toggle must repaint so its children re-dither")
    end
end)
