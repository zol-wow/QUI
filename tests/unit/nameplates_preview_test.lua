local function fail(msg)
    print("FAIL: nameplates_preview_test - " .. msg)
    os.exit(1)
end

local function noop() end

local unpack = unpack or table.unpack

local function NewRegion(parent)
    return {
        _parent = parent, _shown = true, _alpha = 1,
        SetParent = function(self, p) self._parent = p end,
        GetParent = function(self) return self._parent end,
        SetAllPoints = noop, SetPoint = noop, ClearAllPoints = noop,
        SetSize = noop, SetWidth = noop,
        SetHeight = function(self, h) self._h = h end,
        GetTop = function(self) return self._top end,
        GetBottom = function(self) return self._bottom end,
        GetLeft = function(self) return self._left end,
        GetRight = function(self) return self._right end,
        GetAlpha = function(self) return self._alpha end,
        SetColorTexture = noop, SetVertexColor = noop,
        SetAtlas = function(self, atlas) self._atlas = atlas end,
        SetTexture = function(self, t) self._texture = t end,
        SetAlpha = function(self, a) self._alpha = a end,
        SetAlphaFromBoolean = noop,
        SetHorizTile = noop, SetVertTile = noop, SetTexCoord = noop,
        AddMaskTexture = noop, SetBlendMode = noop,
        Show = function(self) self._shown = true end,
        Hide = function(self) self._shown = false end,
        SetText = function(self, t) self._text = t end,
        SetFormattedText = function(self, fmt, ...) self._text = string.format(fmt, ...) end,
        SetTextColor = function(self, r, g, b) self._color = { r, g, b } end,
        SetFont = noop,
        SetJustifyH = noop,
    }
end

local function NewFrame(parent)
    local f = NewRegion(parent)
    f._scripts = {}
    f.SetScript = function(self, k, h) self._scripts[k] = h end
    f.GetScript = function(self, k) return self._scripts[k] end
    f.HookScript = noop
    f.RegisterEvent = noop
    f.RegisterUnitEvent = noop
    f.UnregisterAllEvents = noop
    f.EnableMouse = noop
    f.SetFrameStrata = noop
    f.SetFrameLevel = noop
    f.GetFrameLevel = function() return 1 end
    f.SetScale = function(self, s) self._scale = s end
    f.SetIgnoreParentScale = noop
    f.SetShown = function(self, s) if s then self:Show() else self:Hide() end end
    f.IsShown = function(self) return self._shown end
    f.GetWidth = function(self) return self._w or 700 end
    f.GetHeight = function(self) return self._h or 160 end
    f.CreateTexture = function(self) return NewRegion(self) end
    f.CreateMaskTexture = function(self) return NewRegion(self) end
    f.CreateFontString = function(self) return NewRegion(self) end
    f.SetStatusBarTexture = noop
    f.GetStatusBarTexture = function(self) return self._fill or NewRegion(self) end
    f.SetStatusBarColor = function(self, r, g, b) self._color = { r, g, b } end
    f.SetMinMaxValues = function(self, lo, hi) self._minMax = { lo, hi } end
    f.SetValue = function(self, v) self._value = v end
    f.SetDrawEdge = noop
    f.SetHideCountdownNumbers = noop
    f.SetCooldownFromDurationObject = noop
    f.Clear = noop
    f.GetRegions = function(self) return unpack(self._regions or {}) end
    f.GetChildren = function(self) return unpack(self._children or {}) end
    return f
end

CreateFrame = function(_, _, parent) return NewFrame(parent) end
UIParent = NewFrame(nil)
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = noop } end }
GetTime = function() return 0 end
InCombatLockdown = function() return false end
SetCVar = noop
SetRaidTargetIconTexture = function(tex, i) tex._markIndex = i end
RAID_CLASS_COLORS = {}
C_StringUtil = nil
C_CurveUtil = nil
C_UnitAuras = nil
CreateColor = nil
Enum = {}
UnitCastingInfo = function() return nil end
UnitChannelInfo = function() return nil end
GetPlayerInfoByGUID = function() return nil end
IsPlayerSpell = function() return false end
IsSpellKnown = function() return false end
C_Spell = nil

local typeSettings = {
    health = { width = 210, height = 24, borderSize = 1 },
    healthText = { enabled = true, style = "percent", size = 10 },
    name = { enabled = true, size = 11 },
    castbar = { enabled = true, height = 17, kickTick = true, liftOverlay = true },
    absorbs = { enabled = true },
    colors = { castInterruptible = { 0.7, 0.4, 0.9 } },
    highlight = { targetGlow = true },
    raidMarker = { enabled = true },
    auras = {
        enabled = true,
        elements = {},
    },
}

local settings = {
    enabled = true,
    friendly = { mode = "show" },
    types = {
        enemyNPC = typeSettings,
        bossElite = setmetatable(
            { health = { width = 210, height = 24, borderSize = 1 } },
            { __index = typeSettings }),
        friendly = setmetatable({ renderMode = "nameonly" }, { __index = typeSettings }),
        petMinion = setmetatable({ renderMode = "bars" }, { __index = typeSettings }),
    },
}

local function SetFriendlyLook(mode)
    settings.types.friendly.renderMode = mode
end

local ns = {
    Helpers = {
        IsSecretValue = function() return false end,
        SafeToNumber = function(v, fb) return tonumber(v) or fb or 0 end,
        TruncateUTF8 = function(s) return s end,
        GetModuleSettings = function() return settings end,
        GetProfile = function() return { nameplates = settings } end,
    },
    UIKit = {
        CreateBackground = function(parent) return NewRegion(parent) end,
        CreateBorderLines = noop, UpdateBorderLines = noop,
        CreateText = function(parent) return NewRegion(parent) end,
        ResolveFontPath = function() return "" end,
        CreateIcon = function(parent)
            local f = NewFrame(parent)
            f.texture = NewRegion(f)
            f.border = NewRegion(f)
            return f
        end,
        UpdateIconLayout = noop,
    },
    Addon = {
        Pixels = function(_, v) return v end,
        SetPixelPerfectSize = function(_, f, w, h) f._w, f._h = w, h end,
        ApplyFont = noop,
    },
    L = setmetatable({}, { __index = function(_, k) return k end }),
    AuraEvents = { Subscribe = noop },
    LSM = nil,
}

assert(loadfile("core/classification.lua"))("QUI", ns)
assert(loadfile("core/aura_elements.lua"))("QUI", ns)
assert(loadfile("core/aura_glue.lua"))("QUI", ns)
assert(loadfile("core/aura_preview.lua"))("QUI", ns)
assert(loadfile("core/cast_engine.lua"))("QUI", ns)
for _, file in ipairs({ "shared.lua", "plate_type.lua", "cvars.lua", "plate_colors.lua", "plate_health.lua",
    "plate_castbar.lua", "plate_auras.lua", "plate_extras.lua", "plate_power.lua", "driver.lua" }) do
    assert(loadfile("QUI_Nameplates/nameplates/" .. file))("QUI_Nameplates", ns)
end
assert(loadfile("QUI_Nameplates/nameplates/settings/nameplates_preview_driver.lua"))("QUI_Nameplates", ns)

if not ns.QUI_BuildNameplatePreview then fail("driver must export ns.QUI_BuildNameplatePreview") end

local PreviewDriver = ns.QUI_NameplatesPreviewDriver
if not PreviewDriver then fail("driver must export ns.QUI_NameplatesPreviewDriver") end
if type(PreviewDriver.SetSelectedType) ~= "function" then fail("driver must export SetSelectedType") end

local NP = ns.QUI_Nameplates
local seedBucket = NP.Auras.DefaultNameplateBucket()
seedBucket[1].maxIcons = 2
typeSettings.auras.elements["*"] = seedBucket

local function test(n, f) print(n); f(); print("  ok") end

local host = NewFrame(UIParent)

test("build paints a full mock plate from real builders", function()
    ns.QUI_BuildNameplatePreview(host)
    local NP = ns.QUI_Nameplates
    ns.QUI_RefreshNameplatePreview()
end)

local created = {}
local baseCreate = CreateFrame
CreateFrame = function(kind, name, parent)
    local f = baseCreate(kind, name, parent)
    created[#created + 1] = f
    return f
end
local host2 = NewFrame(UIParent)

test("rebinding to a new host rebuilds; castbar + kick tick painted", function()
    ns.QUI_BuildNameplatePreview(host2)
    local plate
    for _, f in ipairs(created) do
        if f._parent == host2 then plate = f break end
    end
    if not plate then fail("mock plate must build on the new host") end
    if not plate.castBar._shown then fail("castbar must show in the preview") end
    if plate.castBar._value ~= 0.62 then fail("castbar must paint the fake progress") end
    if plate.castSpellText._text ~= "Pyroblast" then fail("spell name must paint") end
    if not plate.kickBar._shown then fail("kick tick must show when enabled") end
    if plate.healthBar._value ~= 65 then fail("health must paint the fake percent") end
    if plate.healthText._text ~= "65%" then fail("health text must honor the style") end
    if plate.nameText._text ~= "Cleave Training Dummy" then fail("name must paint") end
    if not plate.npRaidMarker._shown then fail("raid marker must show when enabled") end
    if plate.npRaidMarker._markIndex ~= 8 then fail("marker must be skull") end
    if not plate.npTargetGlow._shown then fail("target glow must show when enabled") end

    if plate.npLiftOverlay then fail("preview must force the lift overlay off") end
    if plate.castBar._parent ~= plate then fail("castbar must stay parented to the mock plate") end

    local function ShownPreviewIcons()
        local pool = plate._quiAuraPreview or {}
        local n = 0
        for i = 1, #pool do
            if pool[i]._shown then n = n + 1 end
        end
        return n
    end

    if ShownPreviewIcons() ~= 9 then
        fail("all enabled elements must paint (expected 9 icons, got " .. ShownPreviewIcons() .. ")")
    end

    seedBucket[2].enabled = false
    ns.QUI_RefreshNameplatePreview()
    if ShownPreviewIcons() ~= 5 then
        fail("disabling one element must drop only its icons (expected 5, got "
            .. ShownPreviewIcons() .. ")")
    end
    seedBucket[2].enabled = nil
    ns.QUI_RefreshNameplatePreview()
    if ShownPreviewIcons() ~= 9 then fail("re-enabling must restore the element's icons") end

    typeSettings.auras.enableWorld = false
    typeSettings.auras.enableDungeon = false
    typeSettings.auras.enableRaid = false
    ns.QUI_RefreshNameplatePreview()
    if ShownPreviewIcons() ~= 9 then
        fail("preview must ignore the context gate (expected 9, got " .. ShownPreviewIcons() .. ")")
    end
    if #ns.QUI_Nameplates.Auras.ResolveElements(typeSettings) ~= 0 then
        fail("the LIVE resolve must still honor the context gate")
    end
    typeSettings.auras.enableWorld, typeSettings.auras.enableDungeon, typeSettings.auras.enableRaid = nil, nil, nil

    typeSettings.auras.enabled = false
    ns.QUI_RefreshNameplatePreview()
    if ShownPreviewIcons() ~= 0 then fail("the master switch must still blank the preview") end
    typeSettings.auras.enabled = true
    ns.QUI_RefreshNameplatePreview()
end)

test("aura icons anchor to the health bar with the element's own point tuple", function()
    local plate
    for _, f in ipairs(created) do
        if f._parent == host2 then plate = f break end
    end
    local pool = plate._quiAuraPreview
    if not pool or not pool[1] then fail("preview pool must exist after a paint") end
    local point
    pool[1].SetPoint = function(_, p, rel, relP, x, y) point = { p, rel, relP, x, y } end
    ns.QUI_RefreshNameplatePreview()
    if not point then fail("aura icons must be (re)anchored on refresh") end
    if point[1] ~= "TOPLEFT" then
        fail("first icon must pin at the flow corner for grow RIGHT, got " .. tostring(point[1]))
    end
    if point[2] ~= plate.healthBar then
        fail("icons must anchor to plate.healthBar, not the plate")
    end
    if point[3] ~= "TOP" then
        fail("icons must attach to element.anchor (TOP), got " .. tostring(point[3]))
    end
    if point[4] ~= 0 then
        fail("X offset must be element.offsetX (0), got " .. tostring(point[4]))
    end
    if point[5] ~= 20 then
        fail("Y offset must be element.offsetY (20), got " .. tostring(point[5]))
    end
end)

test("settings changes repaint through the refresh export", function()
    local plate
    for _, f in ipairs(created) do
        if f._parent == host2 then plate = f break end
    end
    typeSettings.castbar.enabled = false
    typeSettings.healthText.style = "both"
    ns.QUI_RefreshNameplatePreview()
    if plate.castBar._shown then fail("disabling the castbar must hide it in the preview") end
    if plate.kickBar._shown then fail("kick tick must hide with the castbar") end
    if plate.healthText._text ~= "1.4M | 65%" then
        fail("style 'both' must repaint, got " .. tostring(plate.healthText._text))
    end
end)

test("the mock is never scaled, so it renders 1:1 with a live plate", function()
    local plate
    for _, f in ipairs(created) do
        if f._parent == host2 then plate = f break end
    end
    if plate._scale ~= nil then
        fail("the pop-out panel owns zoom; the mock must stay unscaled, got " .. tostring(plate._scale))
    end

    typeSettings.health.width = 2000
    ns.QUI_RefreshNameplatePreview()
    if plate._scale ~= nil then
        fail("an oversized mock must still not be scaled, got " .. tostring(plate._scale))
    end
    typeSettings.health.width = 210
    ns.QUI_RefreshNameplatePreview()
end)

local previewState = ns.QUI_GetNameplatePreviewStateDefaults()
ns.QUI_SetNameplatePreviewState(previewState)

local stateHost = NewFrame(UIParent)
ns.QUI_BuildNameplatePreview(stateHost)
local statePlate
for _, f in ipairs(created) do
    if f._parent == stateHost then statePlate = f break end
end
if not statePlate then fail("state tests need a mock plate") end

local function Repaint(mutate)
    for k in pairs(previewState) do previewState[k] = nil end
    for k, v in pairs(ns.QUI_GetNameplatePreviewStateDefaults()) do previewState[k] = v end
    if mutate then mutate() end
    ns.QUI_RefreshNameplatePreview()
end

local function ColorOf(bar)
    local c = bar._color or {}
    return string.format("%.2f/%.2f/%.2f", c[1] or -1, c[2] or -1, c[3] or -1)
end

local function Rgb(t)
    return string.format("%.2f/%.2f/%.2f", t[1], t[2], t[3])
end

test("the target highlight follows the Target toggle, not the profile alone", function()
    Repaint()
    if not statePlate.npTargetGlow._shown then fail("Target on must show the wash") end
    Repaint(function() previewState.isTarget = false end)
    if statePlate.npTargetGlow._shown then fail("Target off must hide the wash") end
end)

test("mouseover and execute overlays paint from their toggles", function()
    typeSettings.highlight.mouseoverAlpha = 0.42
    typeSettings.colors.executeEnabled = true
    typeSettings.colors.executeThreshold = 35

    Repaint()
    if statePlate.npHoverHighlight._alpha ~= 0 then fail("mouseover off must stay invisible") end
    if statePlate.npExecuteOverlay._alpha ~= 0 then fail("execute off must stay invisible") end

    Repaint(function() previewState.mouseover = true end)
    if math.abs(statePlate.npHoverHighlight._alpha - 0.42) > 1e-6 then
        fail("mouseover on must paint mouseoverAlpha, got " .. tostring(statePlate.npHoverHighlight._alpha))
    end

    Repaint(function() previewState.execute = true end)
    if (statePlate.npExecuteOverlay._alpha or 0) <= 0 then fail("execute on must paint the overlay") end
    if statePlate.healthBar._value >= 35 then
        fail("execute on must drop the mock below the threshold, got " .. tostring(statePlate.healthBar._value))
    end
    typeSettings.colors.executeEnabled = false
end)

test("the reaction picker and state toggles drive the real colour resolver", function()
    typeSettings.colors.hostile = { 0.39, 0.11, 0.09 }
    typeSettings.colors.neutral = { 0.81, 0.72, 0.19 }
    typeSettings.colors.tapped = { 0.50, 0.50, 0.50 }
    typeSettings.colors.quest = { 1.00, 0.82, 0.00 }
    typeSettings.colors.dpsHasAggro = { 1.00, 0.50, 0.00 }
    typeSettings.colors.oocDarken = true
    typeSettings.colors.oocDarkenFactor = 0.5

    Repaint()
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.hostile) then
        fail("default reaction must resolve hostile, got " .. ColorOf(statePlate.healthBar))
    end

    Repaint(function() previewState.reaction = "neutral" end)
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.neutral) then
        fail("neutral reaction must resolve neutral, got " .. ColorOf(statePlate.healthBar))
    end

    Repaint(function() previewState.reaction = "tapped" end)
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.tapped) then
        fail("tapped reaction must resolve the tapped colour, got " .. ColorOf(statePlate.healthBar))
    end

    Repaint(function() previewState.quest = true end)
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.quest) then
        fail("quest unit must resolve the quest colour, got " .. ColorOf(statePlate.healthBar))
    end

    Repaint(function() previewState.aggro = true end)
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.dpsHasAggro) then
        fail("aggro must resolve the threat colour, got " .. ColorOf(statePlate.healthBar))
    end

    Repaint(function() previewState.inCombat = false end)
    local darkened = { 0.39 * 0.5, 0.11 * 0.5, 0.09 * 0.5 }
    if ColorOf(statePlate.healthBar) ~= Rgb(darkened) then
        fail("out of combat must darken, got " .. ColorOf(statePlate.healthBar))
    end
end)

test("casting toggles drive the castbar through the real interruptible path", function()
    typeSettings.castbar.enabled = true
    typeSettings.colors.castUninterruptible = { 0.45, 0.45, 0.45 }

    Repaint()
    if not statePlate.castBar._shown then fail("casting on must show the castbar") end
    if statePlate.castShield._alpha ~= 0 then fail("interruptible must hide the shield") end

    Repaint(function() previewState.uninterruptible = true end)
    if ColorOf(statePlate.castBar) ~= Rgb(typeSettings.colors.castUninterruptible) then
        fail("uninterruptible must repaint the castbar, got " .. ColorOf(statePlate.castBar))
    end
    if statePlate.castShield._alpha ~= 1 then fail("uninterruptible must show the shield") end

    Repaint(function() previewState.casting = false end)
    if statePlate.castBar._shown then fail("casting off must hide the castbar") end
end)

test("elements whose value only ever came from a live unit now paint", function()
    typeSettings.npcTitle = { enabled = true, size = 9 }
    typeSettings.absorbs.showText = true
    typeSettings.powerBar = { enabled = true, height = 6 }
    typeSettings.healPrediction = { enabled = true }
    typeSettings.castbar.showCastTarget = true
    typeSettings.pvpIcon = { enabled = true, size = 20 }

    Repaint()

    if not statePlate.npTitleText._shown or (statePlate.npTitleText._text or "") == "" then
        fail("npc title must paint when enabled")
    end
    if not statePlate.npAbsorbText._shown or (statePlate.npAbsorbText._text or "") == "" then
        fail("absorb text must paint when enabled")
    end
    if not statePlate.powerBar._shown or not statePlate.powerBar._value then
        fail("power bar must paint when enabled")
    end
    if not statePlate.healPredictBar._shown or not statePlate.healPredictBar._value then
        fail("heal prediction must paint when enabled")
    end
    if not statePlate.castTargetText._shown or (statePlate.castTargetText._text or "") == "" then
        fail("cast target must paint when enabled")
    end
    if not statePlate.npPvpIcon._shown or not statePlate.npPvpIcon._atlas then
        fail("pvp icon must paint when enabled")
    end

    typeSettings.npcTitle.enabled = false
    typeSettings.absorbs.showText = false
    typeSettings.powerBar.enabled = false
    typeSettings.healPrediction.enabled = false
    typeSettings.castbar.showCastTarget = false
    typeSettings.pvpIcon.enabled = false

    Repaint()

    if statePlate.npTitleText._shown then fail("npc title must hide when disabled") end
    if statePlate.npAbsorbText._shown then fail("absorb text must hide when disabled") end
    if statePlate.powerBar._shown then fail("power bar must hide when disabled") end
    if statePlate.healPredictBar._shown then fail("heal prediction must hide when disabled") end
    if statePlate.castTargetText._shown then fail("cast target must hide when disabled") end
    if statePlate.npPvpIcon._shown then fail("pvp icon must hide when disabled") end
end)

test("the simplified strip previews through the shared render-mode function", function()
    typeSettings.level = { enabled = true, size = 9 }
    typeSettings.powerBar = { enabled = true, height = 6 }
    typeSettings.healPrediction = { enabled = true }
    typeSettings.absorbs.enabled = true
    typeSettings.castbar.enabled = true
    Repaint()

    if not statePlate.healthText._shown then fail("fixture: health text must draw before the strip") end
    if not statePlate.npLevelText._shown then fail("fixture: level must draw before the strip") end
    if not statePlate.powerBar._shown then fail("fixture: power bar must draw before the strip") end
    if not statePlate.castBar._shown then fail("fixture: castbar must draw before the strip") end
    if not statePlate.npRaidMarker._shown then fail("fixture: raid marker must draw before the strip") end
    if not statePlate.npTargetGlow._shown then fail("fixture: target wash must draw before the strip") end
    if not statePlate.absorbBar._shown then fail("fixture: absorb bar must draw before the strip") end
    if not statePlate.healPredictBar._shown then fail("fixture: heal prediction must draw before the strip") end

    local function ShownIcons()
        local pool = statePlate._quiAuraPreview or {}
        local n = 0
        for i = 1, #pool do
            if pool[i]._shown then n = n + 1 end
        end
        return n
    end
    local baselineIcons = ShownIcons()
    if baselineIcons == 0 then fail("fixture: auras must draw before the strip") end

    typeSettings.renderMode = "simplified"
    Repaint()

    if statePlate.npRenderMode ~= "simplified" then
        fail("the preview must stamp the simplified render mode, got " .. tostring(statePlate.npRenderMode))
    end
    for _, key in ipairs({ "healthText", "npLevelText", "powerBar", "castBar", "npRaidMarker", "npTargetGlow",
                           "absorbBar", "healPredictBar" }) do
        if statePlate[key]._shown then
            fail(key .. " must stop drawing in the simplified preview")
        end
    end
    if not statePlate.healthBar._shown then fail("the simplified preview must keep its health bar") end
    if not statePlate.nameText._shown then fail("the simplified preview must keep its name") end
    if ShownIcons() ~= 0 then
        fail("a simplified plate draws no auras, so the preview must blank them, got " .. ShownIcons())
    end

    typeSettings.renderMode = "bars"
    Repaint()

    for _, key in ipairs({ "healthText", "npLevelText", "powerBar", "castBar", "npRaidMarker", "npTargetGlow",
                           "absorbBar", "healPredictBar" }) do
        if not statePlate[key]._shown then
            fail(key .. " must come back in the preview when simplified is turned off")
        end
    end
    if ShownIcons() ~= baselineIcons then
        fail("auras must come back when simplified is turned off, got " .. ShownIcons())
    end

    typeSettings.level = nil
    typeSettings.powerBar = nil
    typeSettings.healPrediction = nil
end)

test("class power pips preview from their own row, never the live singleton", function()
    local NPPower = ns.QUI_Nameplates.Power
    if not NPPower or not NPPower.RenderPreview then fail("plate_power must export RenderPreview") end

    typeSettings.power = { enabled = false, size = 10, spacing = 3, offsetY = -2 }
    Repaint()

    if statePlate.npPowerPreviewRow then fail("a disabled class power must not build a row") end

    typeSettings.power.enabled = true
    Repaint()

    local pipRow = statePlate.npPowerPreviewRow
    if not pipRow then fail("enabling class power must build a pip row on the mock") end
    if pipRow._w ~= (5 * 10) + (4 * 3) then
        fail("the row must size to the fallback pip count, got " .. tostring(pipRow._w))
    end
    if not pipRow._shown then fail("the pip row must show when enabled") end
    if pipRow._parent ~= statePlate then fail("the preview row must parent to the mock, not UIParent") end

    NPPower.AttachToTarget()
    if pipRow._parent ~= statePlate then
        fail("the live attach path must not steal the preview row")
    end

    typeSettings.power.enabled = false
    Repaint()
    if pipRow._shown then fail("disabling class power must hide the preview row") end
end)

test("health text honors precision and bothFormat instead of a hardcoded string", function()
    typeSettings.healthText.style = "both"
    typeSettings.healthText.bothFormat = "paren"
    typeSettings.healthText.precision = 1
    Repaint()
    if statePlate.healthText._text ~= "1.4M (65.0%)" then
        fail("both-format must round-trip the real formatter, got " .. tostring(statePlate.healthText._text))
    end
    typeSettings.healthText.style = "percent"
    typeSettings.healthText.bothFormat = "bar"
    typeSettings.healthText.precision = 0
    Repaint()
    if statePlate.healthText._text ~= "65%" then
        fail("percent style must use the real formatter, got " .. tostring(statePlate.healthText._text))
    end
end)

local function SwitchTo(key)
    PreviewDriver.SetSelectedType(key)
    ns.QUI_RefreshNameplatePreview()
end

local function ShownAuraIcons(p)
    local pool = p._quiAuraPreview or {}
    local n = 0
    for i = 1, #pool do
        if pool[i]._shown then n = n + 1 end
    end
    return n
end

test("every selectable type has a fake unit state to preview from", function()
    for _, key in ipairs({ "petMinion", "friendly", "bossElite",
                           "minorTrivial", "enemyPlayer", "enemyNPC" }) do
        local fakeState = PreviewDriver.FAKE_STATE[key]
        if type(fakeState) ~= "table" then fail("no fake state for " .. key) end
    end
end)

test("selecting Friendly previews a friendly plate, not a hostile one", function()
    typeSettings.colors.friendly = { 0.31, 0.80, 0.41 }
    typeSettings.colors.hostile = { 0.39, 0.11, 0.09 }
    typeSettings.colors.classColorEnemyPlayers = false
    SetFriendlyLook("bars")

    Repaint()
    SwitchTo("enemyNPC")
    local hostileColor = ColorOf(statePlate.healthBar)

    SwitchTo("friendly")
    local friendlyColor = ColorOf(statePlate.healthBar)

    if hostileColor == friendlyColor then
        fail("friendly and enemyNPC rendered the same colour at identical strip settings -- "
            .. "the selected type is not reaching the colour resolver")
    end
    if friendlyColor ~= Rgb(typeSettings.colors.friendly) then
        fail("the friendly type must resolve the friendly reaction colour, got " .. friendlyColor)
    end
    if hostileColor ~= Rgb(typeSettings.colors.hostile) then
        fail("enemyNPC must still resolve hostile, got " .. hostileColor)
    end

    SetFriendlyLook("nameonly")
    typeSettings.colors.classColorEnemyPlayers = nil
    SwitchTo("enemyNPC")
end)

test("selecting Enemy Players class-colours the preview at identical strip settings", function()
    UnitClass = function() return "Mage", "MAGE" end
    RAID_CLASS_COLORS.MAGE = { r = 0.25, g = 0.78, b = 0.92 }
    typeSettings.colors.classColorEnemyPlayers = true
    typeSettings.colors.hostile = { 0.39, 0.11, 0.09 }

    Repaint()
    SwitchTo("enemyNPC")
    local npcColor = ColorOf(statePlate.healthBar)

    SwitchTo("enemyPlayer")
    local playerColor = ColorOf(statePlate.healthBar)

    if npcColor == playerColor then
        fail("enemyPlayer rendered identically to enemyNPC -- the type's player-ness never reached the resolver")
    end
    if playerColor ~= Rgb({ 0.25, 0.78, 0.92 }) then
        fail("enemyPlayer must resolve the player's class colour, got " .. playerColor)
    end

    typeSettings.colors.classColorEnemyPlayers = nil
    RAID_CLASS_COLORS.MAGE = nil
    UnitClass = nil
    SwitchTo("enemyNPC")
end)

test("the strip's reaction picker still overrides the type's own reaction", function()
    typeSettings.colors.neutral = { 0.81, 0.72, 0.19 }
    SetFriendlyLook("bars")

    Repaint(function() previewState.reaction = "neutral" end)
    SwitchTo("friendly")
    if ColorOf(statePlate.healthBar) ~= Rgb(typeSettings.colors.neutral) then
        fail("an explicit strip reaction must win over the type's default, got "
            .. ColorOf(statePlate.healthBar))
    end

    SetFriendlyLook("nameonly")
    Repaint()
    SwitchTo("enemyNPC")
end)

test("switching type repaints the mock from that type's config", function()
    settings.types.bossElite.health.width = 300
    settings.types.enemyNPC.health.width = 210

    SwitchTo("bossElite")
    local wide = statePlate.healthBar._w
    SwitchTo("enemyNPC")
    local narrow = statePlate.healthBar._w

    if wide == narrow then
        fail("the preview did not change when the type changed")
    end
    if wide ~= 300 then fail("bossElite must render its own configured width, got " .. tostring(wide)) end
    if narrow ~= 210 then fail("enemyNPC must render its own configured width, got " .. tostring(narrow)) end
end)

test("classification icon reflects the selected type's fake state, not a hardcoded value", function()
    typeSettings.level = typeSettings.level or {}
    typeSettings.level.showClassification = true

    SwitchTo("bossElite")
    if not statePlate.npClassIcon._shown then
        fail("bossElite must show a classification icon for its worldboss fake state")
    end
    local bossAtlas = statePlate.npClassIcon._atlas
    if not bossAtlas then fail("bossElite's classification icon must have resolved an atlas") end

    SwitchTo("enemyNPC")
    if statePlate.npClassIcon._shown then
        fail("enemyNPC's normal fake classification must not show an icon")
    end

    typeSettings.level.showClassification = false
    SwitchTo("enemyNPC")
end)

test("friendly type preview hides auras under the default name-only mode", function()
    SwitchTo("enemyNPC")
    if ShownAuraIcons(statePlate) == 0 then
        fail("sanity: enemyNPC must show its configured aura icons before switching")
    end

    SwitchTo("friendly")
    if ShownAuraIcons(statePlate) ~= 0 then
        fail("friendly must hide auras under the default nameonly mode, like a live friendly plate does")
    end

    SwitchTo("enemyNPC")
    if ShownAuraIcons(statePlate) == 0 then
        fail("switching back to enemyNPC must show the aura icons again")
    end
end)

test("the friendly preview reads the Friendly type's own render mode, not a hardcoded default", function()
    SwitchTo("friendly")
    if ShownAuraIcons(statePlate) ~= 0 then
        fail("friendly must start hidden under the fixture's nameonly mode")
    end

    SetFriendlyLook("bars")
    ns.QUI_RefreshNameplatePreview()
    if ShownAuraIcons(statePlate) == 0 then
        fail("setting the friendly type to bars must let the friendly preview show auras again")
    end

    SetFriendlyLook("nameonly")
    ns.QUI_RefreshNameplatePreview()
    if ShownAuraIcons(statePlate) ~= 0 then
        fail("restoring nameonly must hide auras again")
    end
end)

test("friendly nameonly hides the health/cast bar and recenters the name; bars restores them", function()
    local point
    statePlate.nameText.SetPoint = function(_, p, rel, relP, x, y) point = { p, rel, relP, x, y } end

    SetFriendlyLook("nameonly")
    SwitchTo("friendly")
    if statePlate.healthBar._shown then fail("nameonly must hide the health bar") end
    if statePlate.castBar._shown then fail("nameonly must hide the cast bar") end
    if not point then fail("nameonly must re-anchor the name text") end
    if point[1] ~= "CENTER" or point[2] ~= statePlate or point[3] ~= "CENTER" then
        fail("nameonly must center the name on the plate, got "
            .. tostring(point[1]) .. "/" .. tostring(point[3]))
    end

    SetFriendlyLook("bars")
    ns.QUI_RefreshNameplatePreview()
    if not statePlate.healthBar._shown then fail("bars mode must show the health bar again") end
    if not statePlate.castBar._shown then fail("bars mode must show the cast bar again") end

    SetFriendlyLook("nameonly")
    SwitchTo("enemyNPC")
end)

test("a pet plate previews all three render modes from its own type config", function()
    local point
    statePlate.nameText.SetPoint = function(_, p, rel, relP, x, y) point = { p, rel, relP, x, y } end

    local function SetPetLook(mode)
        settings.types.petMinion.renderMode = mode
        ns.QUI_RefreshNameplatePreview()
    end

    SetPetLook("bars")
    SwitchTo("petMinion")
    if statePlate.npRenderMode ~= "bars" then
        fail("the pet preview must read its own type, got " .. tostring(statePlate.npRenderMode))
    end
    if not statePlate.healthBar._shown then fail("bars must draw the pet health bar") end
    if not statePlate.healthText._shown then fail("bars must draw the pet health text") end
    local barsIcons = ShownAuraIcons(statePlate)
    if barsIcons == 0 then fail("fixture: bars must draw the pet aura icons") end

    SetPetLook("simplified")
    if statePlate.npRenderMode ~= "simplified" then
        fail("expected the pet preview in simplified, got " .. tostring(statePlate.npRenderMode))
    end
    if not statePlate.healthBar._shown then fail("simplified must keep the pet health bar") end
    if statePlate.healthText._shown then fail("simplified must strip the pet health text") end
    if ShownAuraIcons(statePlate) ~= 0 then fail("simplified must blank the pet aura icons") end

    point = nil
    SetPetLook("nameonly")
    if statePlate.npRenderMode ~= "nameonly" then
        fail("a pet set to nameonly must preview nameonly, got " .. tostring(statePlate.npRenderMode))
    end
    if statePlate.healthBar._shown then fail("nameonly must hide the pet health bar") end
    if not statePlate.nameText._shown then fail("nameonly must keep the pet name") end
    if not point or point[1] ~= "CENTER" or point[3] ~= "CENTER" then
        fail("nameonly must recentre the pet name, got " .. tostring(point and point[1]))
    end
    if ShownAuraIcons(statePlate) ~= 0 then fail("nameonly must blank the pet aura icons") end

    SetPetLook("bars")
    if not statePlate.healthBar._shown then fail("returning to bars must restore the pet health bar") end
    if not statePlate.healthText._shown then fail("returning to bars must restore the pet health text") end
    if ShownAuraIcons(statePlate) ~= barsIcons then
        fail("returning to bars must restore the pet aura icons, got " .. ShownAuraIcons(statePlate))
    end

    SwitchTo("enemyNPC")
end)

local function Paint(frame, left, right, top, bottom, eff)
    local region = NewRegion(frame)
    region._left, region._right = left, right
    region._top, region._bottom = top, bottom
    if eff then region.GetEffectiveScale = function() return eff end end
    frame._regions = frame._regions or {}
    frame._regions[#frame._regions + 1] = region
    return region
end

local function MeasureOn(host, plateEff)
    local afterFns = {}
    C_Timer.After = function(_, fn) afterFns[#afterFns + 1] = fn end
    ns.QUI_BuildNameplatePreview(host)
    C_Timer.After = function() end
    if #afterFns == 0 then fail("the measure pass must be deferred a frame") end

    local plate
    for _, f in ipairs(created) do
        if f._parent == host then plate = f break end
    end
    if not plate then fail("mock plate must rebuild on the new host") end

    if plateEff then
        plate.GetEffectiveScale = function() return plateEff end
    end
    plate._children = { plate.healthBar, plate.castBar }
    plate.castBar._shown = true

    local point
    plate.SetPoint = function(_, p, rel, relP, x, y) point = { p, rel, relP, x, y } end

    return plate, afterFns, function() return point end
end

test("the measure pass reports content extent and pins the mock to the host top-left", function()
    local host3 = NewFrame(UIParent)
    host3._left, host3._top = 100, 500
    host3.GetEffectiveScale = function() return 1 end

    local plate, afterFns, GetPoint = MeasureOn(host3)
    Paint(plate.healthBar, 120, 330, 460, 400)
    Paint(plate.castBar, 120, 330, 399, 340)

    plate.absorbBar._left, plate.absorbBar._right = 256, 466
    plate.absorbBar._top, plate.absorbBar._bottom = 460, 400
    Paint(plate.absorbBar, 256, 281, 460, 400)
    plate._children[#plate._children + 1] = plate.absorbBar

    local seen
    ns.QUI_SetNameplatePreviewObserver(function(w, h) seen = { w, h } end)
    for _, fn in ipairs(afterFns) do fn() end
    ns.QUI_SetNameplatePreviewObserver(nil)

    if not seen then fail("driver must report its extent to the observer") end
    if math.abs(seen[1] - 210) > 0.5 or math.abs(seen[2] - 120) > 0.5 then
        fail("an overhanging bar frame must not inflate the extent past what it paints, got "
            .. tostring(seen[1]) .. "x" .. tostring(seen[2]))
    end
    local w, h = ns.QUI_GetNameplatePreviewExtent()
    if math.abs(w - 210) > 0.5 or math.abs(h - 120) > 0.5 then
        fail("driver must publish the same extent it reported")
    end

    local point = GetPoint()
    if not point then fail("mock must be repositioned onto the host origin") end
    if point[1] ~= "TOPLEFT" or point[3] ~= "TOPLEFT" or point[2] ~= host3 then
        fail("mock must anchor TOPLEFT to the panel content host")
    end
    if math.abs(point[4] + 20) > 0.5 or math.abs(point[5] - 40) > 0.5 then
        fail("origin offset must align content with the host corner, got "
            .. tostring(point[4]) .. "," .. tostring(point[5]))
    end
end)

test("a scaled mock is measured in screen pixels, not mock-local units", function()
    local host4 = NewFrame(UIParent)
    host4._left, host4._top = 100, 500
    host4.GetEffectiveScale = function() return 1 end

    local plate, afterFns, GetPoint = MeasureOn(host4, 2)
    Paint(plate.healthBar, 60, 165, 230, 200, 2)
    Paint(plate.castBar, 60, 165, 199.5, 170, 2)
    for _, child in ipairs(plate._children) do
        child.GetEffectiveScale = function() return 2 end
    end

    local seen
    ns.QUI_SetNameplatePreviewObserver(function(w, h) seen = { w, h } end)
    for _, fn in ipairs(afterFns) do fn() end
    ns.QUI_SetNameplatePreviewObserver(nil)

    if not seen then fail("driver must report its extent to the observer") end
    if math.abs(seen[1] - 210) > 0.5 or math.abs(seen[2] - 120) > 0.5 then
        fail("extent must be screen-space content in host units, got "
            .. tostring(seen[1]) .. "x" .. tostring(seen[2]))
    end

    local point = GetPoint()
    if not point then fail("mock must be repositioned onto the host origin") end
    if math.abs(point[4] + 10) > 0.5 or math.abs(point[5] - 20) > 0.5 then
        fail("origin offset must be in the mock's own space, got "
            .. tostring(point[4]) .. "," .. tostring(point[5]))
    end
end)

test("a measure that lands before layout retries instead of giving up", function()
    local host5 = NewFrame(UIParent)
    host5.GetEffectiveScale = function() return 1 end

    local afterFns = {}
    C_Timer.After = function(_, fn) afterFns[#afterFns + 1] = fn end
    ns.QUI_BuildNameplatePreview(host5)

    local plate
    for _, f in ipairs(created) do
        if f._parent == host5 then plate = f break end
    end
    if not plate then fail("mock plate must rebuild on the new host") end
    plate._children = { plate.healthBar }
    plate.castBar._shown = false
    plate.SetPoint = function() end

    local seen
    ns.QUI_SetNameplatePreviewObserver(function(w, h) seen = { w, h } end)

    local drained = 0
    while afterFns[1] do
        local fn = table.remove(afterFns, 1)
        drained = drained + 1
        if drained == 2 then
            host5._left, host5._top = 100, 500
            Paint(plate.healthBar, 100, 310, 500, 460)
        end
        fn()
        if drained > 8 then fail("measure retry must be bounded") end
    end

    C_Timer.After = function() end
    ns.QUI_SetNameplatePreviewObserver(nil)

    if drained < 2 then fail("an unmeasurable first pass must queue another") end
    if not seen then fail("the retry must report once the frames have a rect") end
    if math.abs(seen[1] - 210) > 0.5 or math.abs(seen[2] - 40) > 0.5 then
        fail("retry must report the settled extent, got "
            .. tostring(seen[1]) .. "x" .. tostring(seen[2]))
    end
end)

test("rebuilding on a second host does not strand the first", function()
    local hostA = NewFrame(UIParent)
    local hostB = NewFrame(UIParent)

    local function PlatesOf(host)
        local plates = {}
        for _, f in ipairs(created) do
            if f._parent == host then plates[#plates + 1] = f end
        end
        return plates
    end

    ns.QUI_BuildNameplatePreview(hostA)
    local platesA = PlatesOf(hostA)
    if #platesA ~= 1 then fail("first host must get exactly one plate, got " .. #platesA) end
    local plateA = platesA[1]

    ns.QUI_BuildNameplatePreview(hostB)
    local platesB = PlatesOf(hostB)
    if #platesB ~= 1 then fail("second host must get exactly one plate, got " .. #platesB) end
    local plateB = platesB[1]
    if plateA == plateB then fail("each host must own a distinct plate") end

    ns.QUI_BuildNameplatePreview(hostA)
    local platesA2 = PlatesOf(hostA)
    if #platesA2 ~= 1 then
        fail("hostA must own exactly one plate after a hostA->hostB->hostA cycle, got " .. #platesA2
            .. " -- a revisited band must reuse its plate, not stack a second frozen one underneath")
    end
    if platesA2[1] ~= plateA then
        fail("revisiting hostA must reuse its original plate object")
    end
end)

print("OK: nameplates_preview_test")
