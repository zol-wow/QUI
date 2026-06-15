--[[
    QUI Group Frames - Settings Preview Driver

    Renders the docked group-frame settings preview: a mock unit-frame roster
    that reflects every group setting live and animates via one OnUpdate ticker.
    Aura elements are rendered through the REAL renderer
    (ns.QUI_GroupFrameAuraRender) fed fabricated matches, so the preview can
    never drift from the live aura code.

    Public surface (also published as the 3 _G.QUI_*GroupFramePreview seams):
        ns.QUI_GroupFramesPreview.Build(host)
        ns.QUI_GroupFramesPreview.Refresh(contextMode)
        ns.QUI_GroupFramesPreview.Teardown()

    Invariants: registers no game events; never touches real party/raid frames;
    no WoW API call at file scope (loads under a bare test ns).
]]
local _, ns = ...

local Driver = ns.QUI_GroupFramesPreview or {}
ns.QUI_GroupFramesPreview = Driver

---------------------------------------------------------------------------
-- FAKE DATA POOLS (preview only — not gameplay data)
---------------------------------------------------------------------------
local PREVIEW_BUFF_ICONS   = { 136034, 135940, 136081, 135932, 136063 }
local PREVIEW_DEBUFF_ICONS = { 136207, 136130, 136067, 135813, 136118 }
local FAKE_DURATIONS = { 8, 15, 30, 45, 60 }
local DISPEL_CYCLE   = { "Magic", "Curse", "Disease", "Poison" }

local _fakeInstance = 0
local function NextInstanceID()
    _fakeInstance = _fakeInstance + 1
    return _fakeInstance
end

-- Real spell icon when the client is present; nil under a bare test ns.
local function ResolveSpellIcon(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and tex then return tex end
    end
    return nil
end

-- now is injected so the builders are pure/testable (callers pass GetTime()).
local function MakeFakeAura(icon, index, harmful, now, spellId)
    local duration = FAKE_DURATIONS[((index - 1) % #FAKE_DURATIONS) + 1]
    local phase = ((index - 1) % 5) / 5          -- 0,.2,.4,.6,.8 — staggered fill
    local remaining = duration * (1 - phase)
    return {
        auraInstanceID = NextInstanceID(),
        icon           = icon,
        spellId        = spellId or (3000 + index),
        name           = harmful and "Preview Debuff" or "Preview Buff",
        duration       = duration,
        expirationTime = now + remaining,
        dispelName     = harmful and DISPEL_CYCLE[((index - 1) % #DISPEL_CYCLE) + 1] or nil,
        isBossAura     = false,
        isHelpful      = not harmful,
        isHarmful      = harmful,
    }
end

---------------------------------------------------------------------------
-- PURE PREVIEW HELPERS (no WoW API — math/table logic, unit-tested directly)
---------------------------------------------------------------------------

-- Raid preview frame-count tiers (multiples of 5, matching the step-5 sliders so
-- a slider value always renders 1:1; odd stored values snap to the nearest tier).
local RAID_COUNT_TIERS = { 5, 10, 15, 20, 25, 30, 35, 40 }

-- Snap an arbitrary raid count to the nearest tier. nil -> 25 (default).
-- Clamps to [5,40]; ties round UP to the larger tier.
function Driver._SnapRaidCount(n)
    n = tonumber(n)
    if not n then return 25 end
    if n <= RAID_COUNT_TIERS[1] then return RAID_COUNT_TIERS[1] end
    local last = RAID_COUNT_TIERS[#RAID_COUNT_TIERS]
    if n >= last then return last end
    local best, bestDist = RAID_COUNT_TIERS[1], math.huge
    for _, tier in ipairs(RAID_COUNT_TIERS) do
        local dist = math.abs(tier - n)
        -- Tiers are ascending, so on an exact tie (dist == bestDist) the later,
        -- larger tier wins -> ties round up.
        if dist < bestDist or (dist == bestDist and tier > best) then
            best, bestDist = tier, dist
        end
    end
    return best
end

-- Preview focus-filter keys. Each maps to an element group gated in the preview
-- ON TOP OF the normal config gates. Default all-on.
local FILTER_KEYS = { "threat", "dispel", "auras", "indicators", "highlights" }

-- Normalize an arbitrary filter table to exactly FILTER_KEYS, defaulting any
-- missing key to true and dropping unknown keys.
function Driver._NormalizeFilter(tbl)
    tbl = tbl or {}
    local out = {}
    for _, k in ipairs(FILTER_KEYS) do
        out[k] = (tbl[k] ~= false)
    end
    return out
end

-- True unless the filter explicitly disables this key.
function Driver._FilterAllows(filter, key)
    if not filter then return true end
    return filter[key] ~= false
end

local INDICATOR_TOGGLE_KEYS = {
    "showRoleIcon", "showReadyCheck", "showResurrection", "showSummonPending",
    "showLeaderIcon", "showTargetMarker", "showPhaseIcon",
}

-- Whether the underlying config feature(s) behind a focus chip are enabled.
-- Surface uses this to grey chips the user can't usefully preview.
function Driver._ChipEnabledInConfig(vdb, chipKey)
    vdb = vdb or {}
    local ind = vdb.indicators or {}
    local healer = vdb.healer or {}
    if chipKey == "threat" then
        return ind.showThreatBorder ~= false
    elseif chipKey == "dispel" then
        local d = healer.dispelOverlay
        return (d ~= nil) and (d.enabled ~= false)
    elseif chipKey == "auras" then
        local a = vdb.auras
        return (a ~= nil) and (a.enabled ~= false)
    elseif chipKey == "indicators" then
        for _, k in ipairs(INDICATOR_TOGGLE_KEYS) do
            if ind[k] then return true end
        end
        return false
    elseif chipKey == "highlights" then
        if healer.targetHighlight and healer.targetHighlight.enabled then return true end
        if vdb.privateAuras and vdb.privateAuras.enabled then return true end
        if healer.defensiveIndicator and healer.defensiveIndicator.enabled then return true end
        if vdb.pets and vdb.pets.enabled then return true end
        if vdb.name and vdb.name.showName then return true end
        if vdb.health and vdb.health.showHealthText then return true end
        return false
    end
    return false
end

-- Frame level for the indicator host sub-frame. Aura icons render at frame+8 and
-- aura bars at frame+9; +12 keeps corner indicators visible above them in the
-- preview.
local INDICATOR_HOST_OFFSET = 12
function Driver._IndicatorHostLevel(baseLevel)
    return (tonumber(baseLevel) or 0) + INDICATOR_HOST_OFFSET
end

function Driver._BuildFilterStripMatches(element, now)
    local harmful = element.auraType == "HARMFUL"
    local pool = harmful and PREVIEW_DEBUFF_ICONS or PREVIEW_BUFF_ICONS
    local maxIcons = tonumber(element.maxIcons) or 0
    local count = (maxIcons > 0) and math.min(maxIcons, #pool) or #pool
    if count < 1 then count = 1 end
    local out = {}
    for i = 1, count do
        out[i] = MakeFakeAura(pool[((i - 1) % #pool) + 1], i, harmful, now)
    end
    return out
end

function Driver._BuildTrackedMatches(element, now)
    local out = {}
    local spells = element.spells
    if type(spells) == "table" then
        for i, sid in ipairs(spells) do
            local icon = ResolveSpellIcon(sid)
                or PREVIEW_BUFF_ICONS[((i - 1) % #PREVIEW_BUFF_ICONS) + 1]
            out[sid] = MakeFakeAura(icon, i, false, now, sid)
        end
    end
    return out
end

---------------------------------------------------------------------------
-- GRID MATH — replicate the secure-header anchor layout (offsets from the
-- roster root's TOP-LEFT; +x right, +y up; y negative = downward).
---------------------------------------------------------------------------
local function ResolveGrow(layout)
    local g = layout and layout.growDirection
    if g == "UP" or g == "DOWN" or g == "LEFT" or g == "RIGHT" then return g end
    if layout and layout.orientation == "HORIZONTAL" then return "RIGHT" end
    return "DOWN"
end

function Driver._ComputeGridPositions(contextMode, count, layout, w, h)
    layout = layout or {}
    local grow = ResolveGrow(layout)
    local horizontal = (grow == "LEFT" or grow == "RIGHT")
    local spacing = tonumber(layout.spacing) or 0
    local isRaid = (contextMode == "raid")

    local perGroup, colSpacing, groupGrow
    if isRaid then
        if (layout.groupBy or "GROUP") == "NONE" then
            perGroup = tonumber(layout.unitsPerFlat) or 5
            colSpacing = spacing
        else
            perGroup = 5
            colSpacing = tonumber(layout.groupSpacing) or 10
        end
        groupGrow = layout.groupGrowDirection or "RIGHT"
    else
        perGroup = 5            -- party: single group, count <= 5
        colSpacing = spacing
        groupGrow = "RIGHT"
    end
    if perGroup < 1 then perGroup = 1 end

    local positions = {}
    for i = 1, count do
        local gi = math.floor((i - 1) / perGroup)   -- group index (0-based)
        local si = (i - 1) % perGroup               -- slot index within group
        local slotStep  = si * ((horizontal and w or h) + spacing)
        local groupStep = gi * ((horizontal and h or w) + colSpacing)
        local x, y = 0, 0
        if horizontal then
            x = (grow == "RIGHT") and slotStep or -slotStep
            y = -groupStep                                  -- columnAnchorPoint TOP
        else
            y = (grow == "UP") and slotStep or -slotStep
            x = (groupGrow == "LEFT") and -groupStep or groupStep
        end
        positions[i] = { x = x, y = y, w = w, h = h }
    end
    return positions
end

---------------------------------------------------------------------------
-- ROSTER — deterministic fake members for the mock grid.
---------------------------------------------------------------------------
local FAKE_CLASSES = { "WARRIOR","PALADIN","PRIEST","DRUID","SHAMAN","MAGE",
    "ROGUE","HUNTER","WARLOCK","DEATHKNIGHT","MONK","DEMONHUNTER","EVOKER" }
local FAKE_NAMES = { "Tankthor","Healena","Pwnadin","Natureza","Shamwow","Frostina",
    "Stabsworth","Bowmaster","Felcaster","Lichking","Mistpaw","Demonbane","Scalewing",
    "Ironwall","Lightbeam","Shadowmend","Wildgrowth","Totemist","Arcanist","Backstab",
    "Marksman","Doomcall","Runeblade","Zenmaster","Havocwing","Breathfire","Shieldwall",
    "Holylight","Mindblast","Starfall","Lavaflow","Pyrolust","Ambusher","Snipeshot",
    "Soulburn","Froststorm","Tigerpaw","Vengewing","Glimmora","Bulwark" }
local FAKE_ROLES_PARTY = { "TANK","HEALER","DAMAGER","DAMAGER","DAMAGER" }
local HP_PATTERN = { 100,85,65,45,92,78,30,95,88,55, 72,100,80,60,90,75,40,98,82,68,
    100,100,70,50,95,85,35,100,77,62, 88,42,100,73,56,91,100,83,47,100 }

local function RoleForIndex(contextMode, i)
    if contextMode == "raid" then
        if i <= 2 then return "TANK" elseif i <= 6 then return "HEALER" else return "DAMAGER" end
    end
    return FAKE_ROLES_PARTY[((i - 1) % #FAKE_ROLES_PARTY) + 1]
end

function Driver._BuildRoster(contextMode, count)
    local out = {}
    for i = 1, count do
        out[i] = {
            name      = FAKE_NAMES[((i - 1) % #FAKE_NAMES) + 1],
            class     = FAKE_CLASSES[((i - 1) % #FAKE_CLASSES) + 1],
            role      = RoleForIndex(contextMode, i),
            healthPct = HP_PATTERN[((i - 1) % #HP_PATTERN) + 1],
        }
    end
    return out
end

---------------------------------------------------------------------------
-- DRIVER STATE + MOCK FRAME FACTORY
---------------------------------------------------------------------------
local MAX_AURA_PREVIEW_FRAMES = 5

local state = {
    host       = nil,   -- panel.contentHost from the surface
    root       = nil,   -- roster root frame (the measured previewCell)
    frames     = {},    -- all mock unit frames
    auraFrames = {},    -- subset that renders aura elements
    ticker     = nil,
    contextMode = "party",
    onBuilt    = nil,   -- observer fn from the surface
    clock      = 0,
}
Driver._state = state   -- exposed for later tasks in this file

local function EnsureRoot()
    if state.root and state.root:GetParent() == state.host then return state.root end
    if state.root then state.root:Hide(); state.root:SetParent(nil) end
    state.root = CreateFrame("Frame", nil, state.host)
    state.root:SetPoint("TOPLEFT", state.host, "TOPLEFT", 0, 0)
    state.root:SetSize(1, 1)
    return state.root
end
Driver._EnsureRoot = EnsureRoot

-- Build ONE mock unit frame with the regions the preview styles + the members
-- the aura renderer reads (.unit/.healthBar/._healthPct/._isVerticalFill/._bottomPad).
local function CreateMockFrame(parent, fakeUnitToken)
    local f = CreateFrame("Button", nil, parent, "BackdropTemplate")
    f.unit = fakeUnitToken                  -- any non-nil string; the renderer needs .unit
    f._bottomPad = 0

    f.healthBar = CreateFrame("StatusBar", nil, f)
    f.healthBar:SetMinMaxValues(0, 100)
    f.healthBar:SetValue(100)

    f.powerBar = CreateFrame("StatusBar", nil, f)
    f.powerBar:SetMinMaxValues(0, 100)
    f.powerBar:SetValue(80)

    f.nameText   = f:CreateFontString(nil, "OVERLAY")
    f.healthText = f.healthBar:CreateFontString(nil, "OVERLAY")

    -- Indicator host: a sub-frame above the aura sub-frames so corner indicators
    -- (role/leader/readyCheck/targetMarker/phase/res/summon) are never buried by
    -- the child health bar or the aura icons. See Driver._IndicatorHostLevel.
    f._indHost = CreateFrame("Frame", nil, f)
    f._indHost:SetAllPoints(f)
    f._indHost:SetFrameLevel(Driver._IndicatorHostLevel(f:GetFrameLevel()))
    return f
end
Driver._CreateMockFrame = CreateMockFrame

---------------------------------------------------------------------------
-- SETTINGS STYLING
---------------------------------------------------------------------------
local WHITE8X8 = "Interface\\Buttons\\WHITE8x8"

-- Dispel-type seed mirrors the settings UI's 4-color palette (no Bleed) so the
-- preview border colors match what the dispel-overlay tab pickers default to.
local DISPEL_SEED = {
    Magic   = { 0.2, 0.6, 1.0 },
    Curse   = { 0.6, 0.0, 1.0 },
    Disease = { 0.6, 0.4, 0.0 },
    Poison  = { 0.0, 0.6, 0.0 },
}

-- Role atlases mirror the live builder (ns.QUI_GroupFrameRoleAtlas / ROLE_ATLAS).
local ROLE_ATLAS = {
    TANK    = "roleicon-tiny-tank",
    HEALER  = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}
local ROLE_TOGGLE_KEY = {
    TANK    = "showRoleTank",
    HEALER  = "showRoleHealer",
    DAMAGER = "showRoleDPS",
}

local function GetGFDB()
    local H = ns.Helpers
    local prof = H and H.GetProfile and H.GetProfile()
    return prof and prof.quiGroupFrames or nil
end
Driver._GetGFDB = GetGFDB

local function GetContextDB(gfdb, contextMode)
    if not gfdb then return nil end
    return (contextMode == "raid" and gfdb.raid) or gfdb.party or gfdb
end
Driver._GetContextDB = GetContextDB

local function StatusBarTexture(general)
    local sm = ns.LSM
    local name = (general and general.texture) or "Quazii v5"
    return (sm and sm.Fetch and sm:Fetch("statusbar", name, true))
        or "Interface\\TargetingFrame\\UI-StatusBar"
end

local function FontPath(general)
    local sm = ns.LSM
    local name = (general and general.font) or "Quazii"
    return (sm and sm.Fetch and sm:Fetch("font", name)) or "Fonts\\FRIZQT__.TTF"
end

local function ClassColor(class)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b
    end
    return 0.6, 0.6, 0.6
end

-- Add bottomPad to a Y offset whenever the anchor is a BOTTOM* point (mirrors the
-- live builder's BottomPadY so indicators clear the power bar).
local function BottomPadY(anchor, offY, bottomPad)
    if anchor and anchor:find("BOTTOM") then return (offY or 0) + (bottomPad or 0) end
    return offY or 0
end

-- appearance/general backdrop: borderSize, darkMode + dark/default bg color/opacity.
local function ApplyAppearance(f, general)
    local borderPx = tonumber(general.borderSize) or 1
    local hasBorder = borderPx > 0
    f:SetBackdrop({
        bgFile = WHITE8X8,
        edgeFile = hasBorder and WHITE8X8 or nil,
        edgeSize = hasBorder and borderPx or nil,
    })
    local bg, bgOpacity
    if general.darkMode then
        bg = general.darkModeBgColor or { 0.25, 0.25, 0.25, 1 }
        bgOpacity = tonumber(general.darkModeBgOpacity) or 1
    else
        bg = general.defaultBgColor or { 0.1, 0.1, 0.1, 0.9 }
        bgOpacity = tonumber(general.defaultBgOpacity) or 1
    end
    f:SetBackdropColor(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, (bg[4] or 1) * bgOpacity)
    if hasBorder then
        f:SetBackdropBorderColor(0, 0, 0, 1)
    end
    f._borderPx = hasBorder and borderPx or 0
end

-- health bar fill + color (general.texture/useClassColor/darkMode*/defaultHealthOpacity)
-- + health.healthFillDirection (drives f._isVerticalFill + the StatusBar orientation).
local function ApplyHealthBar(f, member, general, health)
    local hb = f.healthBar
    local border = f._borderPx or 0
    local bottomPad = f._bottomPad or 0
    hb:ClearAllPoints()
    hb:SetPoint("TOPLEFT", f, "TOPLEFT", border, -border)
    hb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -border, bottomPad)
    hb:SetStatusBarTexture(StatusBarTexture(general))
    local vertical = (health.healthFillDirection == "VERTICAL")
    hb:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
    f._isVerticalFill = vertical
    f._baseHealthPct = member.healthPct
    f._healthPct = member.healthPct
    hb:SetMinMaxValues(0, 100)
    hb:SetValue(member.healthPct)
    local healthOpacity = general.darkMode
        and (tonumber(general.darkModeHealthOpacity) or 1)
        or (tonumber(general.defaultHealthOpacity) or 1)
    hb:SetAlpha(healthOpacity)
    local r, g, b = 0.2, 0.8, 0.2
    if general.useClassColor then
        r, g, b = ClassColor(member.class)
    elseif general.darkMode and general.darkModeHealthColor then
        local c = general.darkModeHealthColor; r, g, b = c[1] or r, c[2] or g, c[3] or b
    end
    hb:SetStatusBarColor(r, g, b, 1)
end

-- name text (name.showName/nameFontSize/nameAnchor/nameJustify/maxNameLength/
--            nameOffsetX/Y/nameTextUseClassColor/nameTextColor)
local function ApplyName(f, member, nameCfg, font, fontSize, allowed)
    if allowed == false then
        if f.nameText then f.nameText:Hide() end
        return
    end
    local nt = f.nameText
    if nameCfg.showName == false then nt:Hide(); return end
    nt:Show()
    nt:SetFont(font, tonumber(nameCfg.nameFontSize) or fontSize, "OUTLINE")
    local label = member.name
    local maxLen = tonumber(nameCfg.maxNameLength) or 0
    if maxLen > 0 then label = label:sub(1, maxLen) end
    nt:SetText(label)
    nt:SetJustifyH(nameCfg.nameJustify or "LEFT")
    nt:ClearAllPoints()
    local anchor = nameCfg.nameAnchor or "TOPLEFT"
    nt:SetPoint(anchor, f, anchor,
        tonumber(nameCfg.nameOffsetX) or 0,
        BottomPadY(anchor, tonumber(nameCfg.nameOffsetY) or 0, f._bottomPad))
    if nameCfg.nameTextUseClassColor then
        nt:SetTextColor(ClassColor(member.class))
    elseif nameCfg.nameTextColor then
        local c = nameCfg.nameTextColor; nt:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
    else
        nt:SetTextColor(1, 1, 1)
    end
end

-- role icon (indicators.showRoleIcon + showRoleTank/Healer/DPS + size/anchor/offset)
local function ApplyRoleIcon(f, member, ind, allowed)
    if allowed == false then
        if f._roleIcon then f._roleIcon:Hide() end
        return
    end
    f._indHost:SetFrameLevel(Driver._IndicatorHostLevel(f:GetFrameLevel()))
    f._roleIcon = f._roleIcon or f._indHost:CreateTexture(nil, "OVERLAY")
    local toggleKey = ROLE_TOGGLE_KEY[member.role]
    local show = ind.showRoleIcon and ROLE_ATLAS[member.role]
        and (not toggleKey or ind[toggleKey] ~= false)
    if not show then f._roleIcon:Hide(); return end
    local sz = tonumber(ind.roleIconSize) or 12
    f._roleIcon:SetSize(sz, sz)
    f._roleIcon:ClearAllPoints()
    local anchor = ind.roleIconAnchor or "TOPLEFT"
    f._roleIcon:SetPoint(anchor, f, anchor,
        tonumber(ind.roleIconOffsetX) or 0,
        BottomPadY(anchor, tonumber(ind.roleIconOffsetY) or 0, f._bottomPad))
    f._roleIcon:SetAtlas(ROLE_ATLAS[member.role])
    f._roleIcon:SetAlpha(1)
    f._roleIcon:Show()
end

-- power bar (power.showPowerBar/powerBarHeight/powerBarOnlyHealers/powerBarOnlyTanks/
--            powerBarUsePowerColor/powerBarColor). Hides the bar for roles that
-- don't match the only-Healers/only-Tanks filter.
local function ApplyPowerBar(f, member, power, general)
    local pb = f.powerBar
    if power.showPowerBar == false then pb:Hide(); f._bottomPad = 0; return end
    local onlyHealers = power.powerBarOnlyHealers
    local onlyTanks = power.powerBarOnlyTanks
    if onlyHealers or onlyTanks then
        local ok = (onlyHealers and member.role == "HEALER")
            or (onlyTanks and member.role == "TANK")
        if not ok then pb:Hide(); f._bottomPad = 0; return end
    end
    local border = f._borderPx or 0
    local h = tonumber(power.powerBarHeight) or 4
    f._bottomPad = border + h + 1
    pb:ClearAllPoints()
    pb:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", border, border)
    pb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -border, border)
    pb:SetHeight(h)
    pb:SetStatusBarTexture(StatusBarTexture(general))
    pb:SetMinMaxValues(0, 100)
    pb:SetValue(80)
    -- Default mana-blue stands in for the live power-type color; when the user
    -- opts OUT of power-type coloring, honor the configured custom color.
    local r, g, b = 0.2, 0.4, 0.8
    if not power.powerBarUsePowerColor and power.powerBarColor then
        local c = power.powerBarColor; r, g, b = c[1] or r, c[2] or g, c[3] or b
    end
    pb:SetStatusBarColor(r, g, b, 1)
    pb:Show()
end

-- Build the configured health-text string from a percent + a fake max HP.
local function FormatHealthText(style, pct, hideSymbol)
    local FAKE_MAX = 100000
    local hp = math.floor(FAKE_MAX * (pct / 100) + 0.5)
    if style == "absolute" then
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        return abbr and abbr(hp) or tostring(hp)
    elseif style == "both" then
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        local hpStr = abbr and abbr(hp) or tostring(hp)
        return hpStr .. (hideSymbol and (" | %d"):format(pct) or (" | %d%%"):format(pct))
    elseif style == "deficit" then
        local miss = FAKE_MAX - hp
        local abbr = AbbreviateNumbers or AbbreviateLargeNumbers
        if miss <= 0 then return "" end
        return "-" .. (abbr and abbr(miss) or tostring(miss))
    end
    return hideSymbol and ("%d"):format(pct) or ("%d%%"):format(pct)
end

-- health text (health.showHealthText/healthDisplayStyle/healthFontSize/healthAnchor/
--   healthJustify/healthOffsetX/Y/healthTextColor + hideHealthPercentSymbol). Also
-- publishes f._UpdateHealthText(pct) so the live ticker can refresh the string.
local function ApplyHealthText(f, health, font, allowed)
    if allowed == false then
        if f.healthText then f.healthText:Hide() end
        return
    end
    local ht = f.healthText
    if health.showHealthText == false then
        ht:Hide()
        f._UpdateHealthText = nil
        return
    end
    ht:Show()
    ht:SetFont(font, tonumber(health.healthFontSize) or 12, "OUTLINE")
    ht:SetJustifyH(health.healthJustify or "RIGHT")
    ht:ClearAllPoints()
    local anchor = health.healthAnchor or "RIGHT"
    ht:SetPoint(anchor, f, anchor,
        tonumber(health.healthOffsetX) or 0,
        BottomPadY(anchor, tonumber(health.healthOffsetY) or 0, f._bottomPad))
    local tc = health.healthTextColor
    if tc then ht:SetTextColor(tc[1] or 1, tc[2] or 1, tc[3] or 1, tc[4] or 1)
    else ht:SetTextColor(1, 1, 1, 1) end
    local style = health.healthDisplayStyle or "percent"
    local hideSymbol = health.hideHealthPercentSymbol
    ht:SetText(FormatHealthText(style, f._healthPct or 100, hideSymbol))
    f._UpdateHealthText = function(pct)
        ht:SetText(FormatHealthText(style, pct or 0, hideSymbol))
    end
end

-- portrait (portrait.showPortrait/portraitSide/portraitSize) — a side-attached
-- bordered frame matching the live builder.
local function ApplyPortrait(f, portrait)
    if not portrait.showPortrait then
        if f._portrait then f._portrait:Hide() end
        return
    end
    f._portrait = f._portrait or CreateFrame("Frame", nil, f, "BackdropTemplate")
    local p = f._portrait
    local sz = tonumber(portrait.portraitSize) or 30
    p:SetSize(sz, sz)
    p:ClearAllPoints()
    if (portrait.portraitSide or "LEFT") == "LEFT" then
        p:SetPoint("RIGHT", f, "LEFT", 0, 0)
    else
        p:SetPoint("LEFT", f, "RIGHT", 0, 0)
    end
    p:SetBackdrop({ edgeFile = WHITE8X8, edgeSize = 1 })
    p:SetBackdropBorderColor(0, 0, 0, 1)
    f._portraitTex = f._portraitTex or p:CreateTexture(nil, "ARTWORK")
    f._portraitTex:ClearAllPoints()
    f._portraitTex:SetPoint("TOPLEFT", 1, -1)
    f._portraitTex:SetPoint("BOTTOMRIGHT", -1, 1)
    f._portraitTex:SetColorTexture(0.15, 0.15, 0.2, 1)
    p:Show()
end

-- Health overlays: absorbs / healAbsorbs / healPrediction — simple colored
-- textures sized to a fraction of the health bar (the live bars are StatusBars,
-- but a static preview only needs a representative tint).
local function MakeOverlayTex(f, key, layer)
    f[key] = f[key] or f.healthBar:CreateTexture(nil, layer or "ARTWORK")
    return f[key]
end

local function ApplyHealthOverlays(f, member, absorbs, healAbsorbs, healPrediction)
    -- Heal prediction (peeks out past the fill from the right, ~20% width)
    local hp = MakeOverlayTex(f, "_healPredTex", "ARTWORK")
    if healPrediction and healPrediction.enabled then
        local r, g, b = 0.2, 1, 0.2
        if healPrediction.useClassColor then r, g, b = ClassColor(member.class)
        elseif healPrediction.color then local c = healPrediction.color; r, g, b = c[1] or r, c[2] or g, c[3] or b end
        hp:SetColorTexture(r, g, b, tonumber(healPrediction.opacity) or 0.5)
        hp:ClearAllPoints()
        hp:SetPoint("TOPLEFT", f.healthBar, "TOPLEFT", 0, 0)
        hp:SetPoint("BOTTOMRIGHT", f.healthBar, "BOTTOMLEFT", (f.healthBar:GetWidth() or 100) * 0.2, 0)
        hp:Show()
    else
        hp:Hide()
    end
    -- Absorbs (reverse-fill tint from the right, ~25% width)
    local ab = MakeOverlayTex(f, "_absorbTex", "OVERLAY")
    if absorbs and absorbs.enabled then
        local r, g, b = 1, 1, 1
        if absorbs.useClassColor then r, g, b = ClassColor(member.class)
        elseif absorbs.color then local c = absorbs.color; r, g, b = c[1] or r, c[2] or g, c[3] or b end
        ab:SetColorTexture(r, g, b, tonumber(absorbs.opacity) or 0.3)
        ab:ClearAllPoints()
        ab:SetPoint("TOPRIGHT", f.healthBar, "TOPRIGHT", 0, 0)
        ab:SetPoint("BOTTOMLEFT", f.healthBar, "BOTTOMRIGHT", -(f.healthBar:GetWidth() or 100) * 0.25, 0)
        ab:Show()
    else
        ab:Hide()
    end
    -- Heal absorbs (reverse-fill tint from the right, ~15% width)
    local ha = MakeOverlayTex(f, "_healAbsorbTex", "OVERLAY")
    if healAbsorbs and healAbsorbs.enabled then
        local r, g, b = 0.5, 0.1, 0.1
        if healAbsorbs.color then local c = healAbsorbs.color; r, g, b = c[1] or r, c[2] or g, c[3] or b end
        ha:SetColorTexture(r, g, b, tonumber(healAbsorbs.opacity) or 0.6)
        ha:ClearAllPoints()
        ha:SetPoint("TOPRIGHT", f.healthBar, "TOPRIGHT", 0, 0)
        ha:SetPoint("BOTTOMLEFT", f.healthBar, "BOTTOMRIGHT", -(f.healthBar:GetWidth() or 100) * 0.15, 0)
        ha:Show()
    else
        ha:Hide()
    end
end

-- Single indicator-icon helper: size + anchor + offset, with a sample atlas/texture.
local function PlaceIndicator(f, key, ind, showKey, prefix, defaultSize, defaultAnchor)
    f[key] = f[key] or f._indHost:CreateTexture(nil, "OVERLAY")
    local tex = f[key]
    if ind[showKey] == false or not ind[showKey] then tex:Hide(); return tex end
    local sz = tonumber(ind[prefix .. "Size"]) or defaultSize
    tex:SetSize(sz, sz)
    tex:ClearAllPoints()
    local anchor = ind[prefix .. "Anchor"] or defaultAnchor
    tex:SetPoint(anchor, f, anchor,
        tonumber(ind[prefix .. "OffsetX"]) or 0,
        BottomPadY(anchor, tonumber(ind[prefix .. "OffsetY"]) or 0, f._bottomPad))
    tex:Show()
    return tex
end

-- indicators: readyCheck / resurrection / summon / leader / targetMarker / phase.
-- Shows every enabled one on the frame so the layout is fully visible in preview.
local function ApplyIndicators(f, ind, allowed)
    if allowed == false then
        for _, k in ipairs({ "_readyCheckIcon", "_resIcon", "_summonIcon",
                             "_leaderIcon", "_targetMarker", "_phaseIcon" }) do
            if f[k] then f[k]:Hide() end
        end
        return
    end
    f._indHost:SetFrameLevel(Driver._IndicatorHostLevel(f:GetFrameLevel()))
    local rc = PlaceIndicator(f, "_readyCheckIcon", ind, "showReadyCheck", "readyCheck", 16, "CENTER")
    if rc:IsShown() then rc:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready") end

    local res = PlaceIndicator(f, "_resIcon", ind, "showResurrection", "resurrection", 16, "CENTER")
    if res:IsShown() then res:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez") end

    local sum = PlaceIndicator(f, "_summonIcon", ind, "showSummonPending", "summon", 20, "CENTER")
    if sum:IsShown() then sum:SetAtlas("RaidFrame-Icon-SummonPending") end

    local ldr = PlaceIndicator(f, "_leaderIcon", ind, "showLeaderIcon", "leader", 12, "TOP")
    if ldr:IsShown() then ldr:SetAtlas("groupfinder-icon-leader") end

    local tm = PlaceIndicator(f, "_targetMarker", ind, "showTargetMarker", "targetMarker", 14, "TOPRIGHT")
    if tm:IsShown() then
        tm:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        if SetRaidTargetIconTexture then SetRaidTargetIconTexture(tm, 8) end -- 8 = skull sample
    end

    local ph = PlaceIndicator(f, "_phaseIcon", ind, "showPhaseIcon", "phase", 16, "BOTTOMLEFT")
    if ph:IsShown() then ph:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon") end
end

-- threat (indicators.showThreatBorder/threatBorderSize/threatColor/threatFillOpacity)
-- — a colored backdrop border + fill tint on a representative frame.
local function ApplyThreat(f, ind, isSample)
    f._threatBorder = f._threatBorder or CreateFrame("Frame", nil, f, "BackdropTemplate")
    local tb = f._threatBorder
    if ind.showThreatBorder == false or not isSample then tb:Hide(); return end
    local sz = tonumber(ind.threatBorderSize) or 3
    tb:ClearAllPoints()
    tb:SetPoint("TOPLEFT", -1, 1)
    tb:SetPoint("BOTTOMRIGHT", 1, -1)
    tb:SetFrameLevel(f:GetFrameLevel() + 3)
    local c = ind.threatColor or { 1, 0, 0, 0.8 }
    tb:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = sz })
    tb:SetBackdropColor(c[1] or 1, c[2] or 0, c[3] or 0, tonumber(ind.threatFillOpacity) or 0)
    tb:SetBackdropBorderColor(c[1] or 1, c[2] or 0, c[3] or 0, c[4] or 0.8)
    tb:Show()
end

-- target highlight (healer.targetHighlight.enabled/.color/.fillOpacity) — tint one
-- frame as "the current target".
local function ApplyTargetHighlight(f, healer, isTarget)
    f._targetHL = f._targetHL or CreateFrame("Frame", nil, f, "BackdropTemplate")
    local th = f._targetHL
    local cfg = healer and healer.targetHighlight
    if not cfg or cfg.enabled == false or not isTarget then th:Hide(); return end
    th:ClearAllPoints()
    th:SetPoint("TOPLEFT", -1, 1)
    th:SetPoint("BOTTOMRIGHT", 1, -1)
    th:SetFrameLevel(f:GetFrameLevel() + 4)
    local c = cfg.color or { 1, 1, 1, 0.6 }
    th:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 2 })
    th:SetBackdropColor(c[1] or 1, c[2] or 1, c[3] or 1, tonumber(cfg.fillOpacity) or 0)
    th:SetBackdropBorderColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 0.6)
    th:Show()
end

-- dispel overlay (healer.dispelOverlay.enabled/.borderSize/.opacity/.fillOpacity/
--   .colors.Magic|Curse|Disease|Poison) — a colored border on a representative frame.
local function ApplyDispelOverlay(f, healer, dispelType)
    f._dispelOverlay = f._dispelOverlay or CreateFrame("Frame", nil, f, "BackdropTemplate")
    local ov = f._dispelOverlay
    local cfg = healer and healer.dispelOverlay
    if not cfg or cfg.enabled == false or not dispelType then ov:Hide(); return end
    local colors = cfg.colors or {}
    local c = colors[dispelType] or DISPEL_SEED[dispelType] or { 0.2, 0.6, 1.0 }
    local sz = tonumber(cfg.borderSize) or 3
    ov:ClearAllPoints()
    ov:SetAllPoints(f)
    ov:SetFrameLevel(f:GetFrameLevel() + 6)
    ov:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = sz })
    ov:SetBackdropColor(c[1] or 0.2, c[2] or 0.6, c[3] or 1, tonumber(cfg.fillOpacity) or 0)
    ov:SetBackdropBorderColor(c[1] or 0.2, c[2] or 0.6, c[3] or 1, tonumber(cfg.opacity) or 1)
    ov:Show()
end

-- private auras (privateAuras.enabled/maxPerFrame/iconSize/growDirection/spacing/
--   anchor/anchorOffsetX/Y/borderScale/showCountdown/showCountdownNumbers/
--   reverseSwipe/textScale) — a small fake icon strip via the shared slot math.
local function ApplyPrivateAuras(f, pa, allowed)
    f._paIcons = f._paIcons or {}
    -- Only the representative aura-preview frames show private auras. Otherwise
    -- every one of the (up to 40) raid frames renders maxPerFrame icons, which
    -- both explodes the count past the unit total and pushes the docked preview
    -- window far wider than it should be.
    if allowed == false or not pa or not pa.enabled or not f._isAuraPreview then
        for _, ic in ipairs(f._paIcons) do ic:Hide() end
        return
    end
    local slotFn = ns.QUI_GroupFrameIconLayout and ns.QUI_GroupFrameIconLayout.CalculateSlotOffset
    local maxSlots = tonumber(pa.maxPerFrame) or 2
    local iconSize = tonumber(pa.iconSize) or 20
    local spacing = tonumber(pa.spacing) or 2
    local direction = pa.growDirection or "RIGHT"
    local anchor = pa.anchor or "RIGHT"
    local offX = tonumber(pa.anchorOffsetX) or -2
    local offY = BottomPadY(anchor, tonumber(pa.anchorOffsetY) or 0, f._bottomPad)
    local textScale = tonumber(pa.textScale) or 1
    if textScale <= 0 then textScale = 1 end
    local borderScale = tonumber(pa.borderScale) or 1
    local showCountdown = pa.showCountdown ~= false
    local reverseSwipe = pa.reverseSwipe == true
    for i = 1, math.max(maxSlots, #f._paIcons) do
        local ic = f._paIcons[i]
        if i <= maxSlots then
            if not ic then
                ic = CreateFrame("Frame", nil, f)
                ic._tex = ic:CreateTexture(nil, "OVERLAY")
                ic._tex:SetAllPoints()
                ic._border = ic:CreateTexture(nil, "BACKGROUND")
                ic._count = ic:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                ic._cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
                ic._cd:SetAllPoints()
                f._paIcons[i] = ic
            end
            ic:SetFrameLevel(f:GetFrameLevel() + 10)
            -- Mirror the live RegisterAnchor: textScale scales the WHOLE container
            -- (so BOTH the stack count and the duration countdown number shrink,
            -- since Blizzard's private-aura text has no sizing API), and the icon +
            -- border are divided by textScale so they stay at their configured pixel
            -- size. Previously only ic._count was scaled, so the duration number
            -- never tracked Text Scale in the preview.
            ic:SetScale(textScale)
            ic:SetSize(iconSize / textScale, iconSize / textScale)
            ic._tex:SetColorTexture(0.8, 0.2, 0.2, 0.6)
            ic._border:ClearAllPoints()
            local bpad = math.max(borderScale, 0) / textScale
            ic._border:SetPoint("TOPLEFT", -bpad, bpad)
            ic._border:SetPoint("BOTTOMRIGHT", bpad, -bpad)
            ic._border:SetColorTexture(0, 0, 0, 1)
            ic._count:ClearAllPoints()
            ic._count:SetPoint("BOTTOMRIGHT", 0, 0)
            ic._count:SetText((pa.showCountdownNumbers ~= false) and "3" or "")
            -- showCountdown gates the swipe spiral; reverseSwipe flips its sweep.
            if ic._cd then
                if ic._cd.SetReverse then ic._cd:SetReverse(reverseSwipe) end
                if showCountdown then
                    if ic._cd.SetHideCountdownNumbers then
                        ic._cd:SetHideCountdownNumbers(pa.showCountdownNumbers == false)
                    end
                    if ic._cd.SetCooldown then ic._cd:SetCooldown(GetTime and GetTime() or 0, 8) end
                    ic._cd:Show()
                else
                    if ic._cd.Clear then ic._cd:Clear() end
                    ic._cd:Hide()
                end
            end
            ic:ClearAllPoints()
            local sx, sy = 0, 0
            if slotFn then sx, sy = slotFn(i, iconSize, spacing, direction, maxSlots) end
            -- Offsets are screen px, divided into the container's scaled space (live
            -- SetupPrivateAuras does the same) so position is unchanged by textScale.
            ic:SetPoint(anchor, f, anchor, (offX + sx) / textScale, (offY + sy) / textScale)
            ic:Show()
        elseif ic then
            ic:Hide()
        end
    end
end

-- defensive (healer.defensiveIndicator.enabled/maxIcons/iconSize/reverseSwipe/
--   growDirection/spacing/position/offsetX/Y) — a small fake icon strip.
local DEF_GROW = {
    RIGHT  = function(s, sp) return s + sp, 0 end,
    LEFT   = function(s, sp) return -(s + sp), 0 end,
    CENTER = function(s, sp) return s + sp, 0 end,
    UP     = function(s, sp) return 0, s + sp end,
    DOWN   = function(s, sp) return 0, -(s + sp) end,
}
local function ApplyDefensive(f, healer, allowed, font)
    if allowed == false then
        if f._defIcons then for _, ic in ipairs(f._defIcons) do ic:Hide() end end
        return
    end
    f._defIcons = f._defIcons or {}
    local cfg = healer and healer.defensiveIndicator
    -- Same as private auras: limit to the aura-preview frames so the strip isn't
    -- repeated across all 40 raid frames.
    if not cfg or not cfg.enabled or not f._isAuraPreview then
        for _, ic in ipairs(f._defIcons) do ic:Hide() end
        return
    end
    local maxIcons = tonumber(cfg.maxIcons) or 3
    local iconSize = tonumber(cfg.iconSize) or 16
    local spacing = tonumber(cfg.spacing) or 2
    local position = cfg.position or "CENTER"
    local offX = tonumber(cfg.offsetX) or 0
    local offY = tonumber(cfg.offsetY) or 0
    local growDir = cfg.growDirection or "RIGHT"
    local growFn = DEF_GROW[growDir] or DEF_GROW.RIGHT
    local stepX, stepY = growFn(iconSize, spacing)
    local centerOffX = 0
    if growDir == "CENTER" then
        local totalSpan = maxIcons * iconSize + math.max(maxIcons - 1, 0) * spacing
        centerOffX = -totalSpan / 2
    end
    local reverseSwipe = cfg.reverseSwipe ~= false
    local samples = { 136120, 135936, 136097, 135940, 136112 }
    for i = 1, math.max(maxIcons, #f._defIcons) do
        local ic = f._defIcons[i]
        if i <= maxIcons then
            if not ic then
                -- A Frame (not a bare texture) so a Cooldown swipe can demo reverseSwipe.
                ic = CreateFrame("Frame", nil, f)
                ic._icon = ic:CreateTexture(nil, "OVERLAY")
                ic._icon:SetAllPoints()
                ic._cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
                ic._cd:SetAllPoints()
                f._defIcons[i] = ic
            end
            ic:SetFrameLevel(f:GetFrameLevel() + 10)
            ic:SetSize(iconSize, iconSize)
            ic._icon:SetTexture(samples[((i - 1) % #samples) + 1])
            if ic._cd then
                if ic._cd.SetReverse then ic._cd:SetReverse(reverseSwipe) end
                if ic._cd.SetCooldown then ic._cd:SetCooldown(GetTime and GetTime() or 0, 12) end
                -- Mirror the live frame's countdown-text sizing so the slider gives
                -- immediate preview feedback. Same secret-safe reference pattern: show
                -- the native count, then set the font on GetCountdownFontString(),
                -- every pass. (Preview value isn't secret, but we keep the path
                -- identical to live.)
                local defFontSize = tonumber(cfg.durationTextSize) or 12
                if ic._cd.GetCountdownFontString then
                    if ic._cd.SetHideCountdownNumbers then
                        pcall(ic._cd.SetHideCountdownNumbers, ic._cd, false)
                    end
                    local okT, cdText = pcall(ic._cd.GetCountdownFontString, ic._cd)
                    if okT and cdText and cdText.SetFont then
                        cdText:SetFont(font, defFontSize, "OUTLINE")
                    end
                end
            end
            ic:ClearAllPoints()
            -- Lift above the power bar on BOTTOM* positions, mirroring the live
            -- UpdateDefensiveIndicator fix (groupframes.lua) and every other
            -- preview element that routes its Y through BottomPadY.
            ic:SetPoint(position, f, position,
                offX + centerOffX + stepX * (i - 1),
                BottomPadY(position, offY, f._bottomPad) + stepY * (i - 1))
            ic:Show()
        elseif ic then
            ic:Hide()
        end
    end
end

-- range fade (range.enabled/outOfRangeAlpha) — apply reduced alpha to demo frames.
local function ApplyRangeFade(f, range, outOfRange)
    if range and range.enabled and outOfRange then
        f:SetAlpha(tonumber(range.outOfRangeAlpha) or 0.4)
    else
        f:SetAlpha(1)
    end
end

-- pets (pets.enabled/width/height/anchorTo) — one attached mock pet frame.
local function ApplyPets(f, pets, hasPet)
    if not pets or not pets.enabled or not hasPet then
        if f._petFrame then f._petFrame:Hide() end
        return
    end
    f._petFrame = f._petFrame or CreateFrame("Frame", nil, f, "BackdropTemplate")
    local pet = f._petFrame
    pet:SetSize(tonumber(pets.width) or 80, tonumber(pets.height) or 16)
    pet:ClearAllPoints()
    local anchorTo = pets.anchorTo or "BOTTOM"
    if anchorTo == "RIGHT" then
        pet:SetPoint("TOPLEFT", f, "TOPRIGHT", 2, 0)
    elseif anchorTo == "LEFT" then
        pet:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
    else
        pet:SetPoint("TOP", f, "BOTTOM", 0, -2)
    end
    pet:SetBackdrop({ bgFile = WHITE8X8, edgeFile = WHITE8X8, edgeSize = 1 })
    pet:SetBackdropColor(0.15, 0.3, 0.15, 0.9)
    pet:SetBackdropBorderColor(0, 0, 0, 1)
    pet._bar = pet._bar or pet:CreateTexture(nil, "ARTWORK")
    pet._bar:ClearAllPoints()
    pet._bar:SetPoint("TOPLEFT", 1, -1)
    pet._bar:SetPoint("BOTTOMRIGHT", -1, 1)
    pet._bar:SetColorTexture(0.2, 0.7, 0.2, 1)
    pet:Show()
end

-- Orchestrator: style a mock frame from EVERY group-frame setting. Decomposed into
-- per-subsystem Apply* calls to stay under the Lua 5.1 200-local / 60-upvalue caps.
-- `member._sampleTarget/._sampleThreat/._sampleDispel/._samplePet/._sampleOOR` are
-- representative flags set by the roster builder so a single frame demos the
-- "current target", threat, a dispellable debuff, a pet and an out-of-range fade.
local function ApplyFrameSettings(f, member, vdb, gfdb, contextMode)
    local general = vdb.general or {}
    local health  = vdb.health or {}
    local font = FontPath(general)
    local fontSize = tonumber(general.fontSize) or 11
    local F = Driver._state.filter or Driver._NormalizeFilter(nil)

    -- Backdrop + power FIRST: power establishes f._bottomPad, which the health bar
    -- and BOTTOM-anchored text/indicators read.
    ApplyAppearance(f, general)
    ApplyPowerBar(f, member, vdb.power or {}, general)
    ApplyHealthBar(f, member, general, health)
    ApplyName(f, member, vdb.name or {}, font, fontSize, F.highlights ~= false)
    ApplyHealthText(f, health, font, F.highlights ~= false)
    ApplyPortrait(f, vdb.portrait or {})
    ApplyHealthOverlays(f, member, vdb.absorbs, vdb.healAbsorbs, vdb.healPrediction)
    ApplyRoleIcon(f, member, vdb.indicators or {}, F.indicators ~= false)
    ApplyIndicators(f, vdb.indicators or {}, F.indicators ~= false)
    ApplyThreat(f, vdb.indicators or {}, member._sampleThreat == true and F.threat ~= false)
    ApplyTargetHighlight(f, vdb.healer, member._sampleTarget == true and F.highlights ~= false)
    ApplyDispelOverlay(f, vdb.healer, (F.dispel ~= false) and member._sampleDispel or nil)
    ApplyPrivateAuras(f, vdb.privateAuras, F.highlights ~= false)
    ApplyDefensive(f, vdb.healer, F.highlights ~= false, font)
    ApplyPets(f, vdb.pets, member._samplePet == true and F.highlights ~= false)
    ApplyRangeFade(f, vdb.range, member._sampleOOR == true)
end
Driver._ApplyFrameSettings = ApplyFrameSettings

---------------------------------------------------------------------------
-- ASSEMBLY: aura render, lifecycle, ticker, spotlight, seams
---------------------------------------------------------------------------
local state = Driver._state
local AURA_PREVIEW_LIMIT = 5

-- AURA ELEMENTS via the REAL renderer with fabricated matches ---------------
local function GetPreviewSpecID()
    local idx = GetSpecialization and GetSpecialization()
    if idx and GetSpecializationInfo then return (GetSpecializationInfo(idx)) end
    return nil
end

local function RenderFrameAuras(f, auras, now)
    local Render = ns.QUI_GroupFrameAuraRender
    local Model  = ns.QUI_GroupFramesAuraModel
    if not Render or not Model or not Model.ActiveElementsForSpec then return end
    if auras and Model.EnsureSeeded then Model.EnsureSeeded(auras) end
    if not auras or auras.enabled == false then
        if Render.ReleaseAll then Render:ReleaseAll(f) end
        f._previewAuraWork = nil
        f._previewAuraIDs = nil
        return
    end
    -- Preview the bucket the EDITOR is on (per-context), not the player's live
    -- spec -- otherwise editing "All Specs" while your current spec has its own
    -- bucket shows the wrong auras. nil (no editor push yet) falls back to live
    -- spec so the preview is sensible before the auras tab is ever opened.
    local bucketKey = state.previewBucket and state.previewBucket[state.contextMode]
    if bucketKey == nil then bucketKey = GetPreviewSpecID() end
    local elements = Model.ActiveElementsForSpec(auras, bucketKey)
    local work, current = {}, {}
    for _, element in ipairs(elements) do
        local matches
        if element.mode == "filterStrip" then
            matches = Driver._BuildFilterStripMatches(element, now)
        else
            matches = Driver._BuildTrackedMatches(element, now)
        end
        work[#work + 1] = { element = element, matches = matches }
        current[element.id] = true
        Render:Dispatch(f, element, matches)
    end
    local prev = f._previewAuraIDs
    if prev then
        for id in pairs(prev) do
            if not current[id] then Render:Release(f, id) end
        end
    end
    f._previewAuraWork = work
    f._previewAuraIDs = current
end

-- FRAME DIMENSIONS (mirror groupframes.lua GetFrameDimensions) --------------
local function GetMockDimensions(vdb, contextMode, count)
    local dims = vdb.dimensions or {}
    if contextMode ~= "raid" then
        return tonumber(dims.partyWidth) or 150, tonumber(dims.partyHeight) or 80
    end
    if count <= 15 then
        return tonumber(dims.smallRaidWidth) or 180, tonumber(dims.smallRaidHeight) or 36
    elseif count <= 25 then
        return tonumber(dims.mediumRaidWidth) or 160, tonumber(dims.mediumRaidHeight) or 30
    end
    return tonumber(dims.largeRaidWidth) or 140, tonumber(dims.largeRaidHeight) or 24
end

-- Teardown helper: hide every pooled frame (frames are POOLED, never destroyed,
-- so a refresh reuses them rather than orphaning the old set).
local function ReleaseFrames()
    local Render = ns.QUI_GroupFrameAuraRender
    for _, f in ipairs(state.framePool or {}) do
        if Render and Render.ReleaseAll then Render:ReleaseAll(f) end
        f:Hide()
    end
    state.frames = {}
    state.auraFrames = {}
end

-- Pick representative frames to demo single-frame features (threat/target/
-- dispel/pet/out-of-range). Match the value each Apply* function checks for.
local function AssignSampleFlags(roster, count)
    if count >= 1 then roster[1]._sampleTarget = true; roster[1]._samplePet = true end
    if count >= 2 then roster[2]._sampleThreat = true end
    if count >= 3 then roster[3]._sampleDispel = "Magic" end
    if count >= 4 then roster[4]._sampleOOR = true end
end

-- ANIMATION TICKER ---------------------------------------------------------
local function OscillateHealth(base, phase, clock)
    local v = base + math.sin((clock + phase) * 0.6) * 18
    if v < 1 then v = 1 elseif v > 100 then v = 100 end
    return v
end

local function LoopMatchSet(matches, now)
    for _, data in pairs(matches) do
        if type(data) == "table" and data.expirationTime and data.duration then
            if data.expirationTime - now <= 0 then
                data.expirationTime = now + data.duration
            end
        end
    end
end

local function AdvanceAuras(now)
    local Render = ns.QUI_GroupFrameAuraRender
    if not Render then return end
    for _, f in ipairs(state.auraFrames) do
        local work = f._previewAuraWork
        if work then
            for _, w in ipairs(work) do
                LoopMatchSet(w.matches, now)
                Render:Dispatch(f, w.element, w.matches)
            end
        end
    end
end

function Driver._EnsureTicker()
    if state.ticker then
        -- The options window (and our host) is rebuilt on theme change; re-parent
        -- so the OnUpdate keeps firing instead of riding a torn-down host.
        if state.host and state.ticker:GetParent() ~= state.host then
            state.ticker:SetParent(state.host)
        end
        state.ticker:Show()
        return state.ticker
    end
    state.ticker = CreateFrame("Frame", nil, state.host)
    state.ticker._auraAccum = 0
    state.ticker:SetScript("OnUpdate", function(self, elapsed)
        local Render = ns.QUI_GroupFrameAuraRender
        state.clock = state.clock + elapsed
        local now = (GetTime and GetTime()) or state.clock
        for _, f in ipairs(state.frames) do
            local pct = OscillateHealth(f._baseHealthPct or 100, f._phase or 0, state.clock)
            f._healthPct = pct
            if f.healthBar then f.healthBar:SetValue(pct) end
            if Render and f._quiAuraRenderHealthTintColor and Render.SyncHealthBarTint then
                Render:SyncHealthBarTint(f, pct, true)
            end
            if f._UpdateHealthText then f._UpdateHealthText(pct) end
        end
        self._auraAccum = self._auraAccum + elapsed
        if self._auraAccum >= 0.1 then
            self._auraAccum = 0
            AdvanceAuras(now)
        end
    end)
    return state.ticker
end

-- SPOTLIGHT (raid only) — a separate mock cluster shown when enabled.
-- gridRight = horizontal extent of the main grid (root is sized 1x1, so we
-- must NOT read root:GetWidth()).
function Driver._RenderSpotlight(root, vdb, gfdb, now, gridRight)
    state.spotlightFrames = state.spotlightFrames or {}
    for _, f in ipairs(state.spotlightFrames) do f:Hide(); f:SetParent(nil) end
    state.spotlightFrames = {}

    local sp = vdb.spotlight
    if not sp or sp.enabled ~= true then return end

    local w = tonumber(sp.frameWidth) or 180
    local h = tonumber(sp.frameHeight) or 36
    local spacing = tonumber(sp.spacing) or 2
    local grow = sp.growDirection or "DOWN"
    local sample
    if (sp.filterMode or "ROLE") == "NAME" then
        sample = { { role = "DAMAGER", class = "MAGE",  name = "Pinned1", healthPct = 90 },
                   { role = "DAMAGER", class = "ROGUE", name = "Pinned2", healthPct = 70 } }
    else
        sample = {}
        if sp.filterTank ~= false then
            sample[#sample+1] = { role = "TANK", class = "WARRIOR", name = "Ironwall", healthPct = 88 }
        end
        if sp.filterHealer then
            sample[#sample+1] = { role = "HEALER", class = "PRIEST", name = "Healena", healthPct = 76 }
        end
        if #sample == 0 then
            sample[1] = { role = "TANK", class = "PALADIN", name = "Lightbeam", healthPct = 82 }
        end
    end

    local startX = (tonumber(gridRight) or 200) + 30
    for i, m in ipairs(sample) do
        local f = Driver._CreateMockFrame(root, "quiPreviewSpot" .. i)
        f._phase = i * 0.9
        f:SetSize(w, h)
        local step = (i - 1) * (h + spacing)
        local oy = (grow == "UP") and step or -step
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", root, "TOPLEFT", startX, oy - 4)
        f:Show()
        Driver._ApplyFrameSettings(f, m, vdb, gfdb, "raid")
        state.spotlightFrames[i] = f
    end
end

-- LIFECYCLE ----------------------------------------------------------------
function Driver.Refresh(contextMode)
    if not state.host then return end
    state.contextMode = (contextMode == "raid") and "raid" or "party"
    state.filter = Driver._NormalizeFilter(state.filter)
    local gfdb = Driver._GetGFDB()
    local vdb = Driver._GetContextDB(gfdb, state.contextMode)
    if not vdb then return end

    local count = 5
    if state.contextMode == "raid" then
        local tm = (gfdb and gfdb.testMode) or {}
        count = Driver._SnapRaidCount(tm.raidCount)
    end

    local root = Driver._EnsureRoot()
    -- Mock frames are POOLED, not recreated each refresh. Refresh fires on every
    -- settings onChange (every slider tick); creating fresh frames would orphan
    -- the old ones (WoW frames can't be destroyed) and leak. Reuse pool[1..count]
    -- and hide the surplus.
    state.framePool = state.framePool or {}
    state.frames = {}
    state.auraFrames = {}

    local roster = Driver._BuildRoster(state.contextMode, count)
    AssignSampleFlags(roster, count)
    local w, h = GetMockDimensions(vdb, state.contextMode, count)
    local layout = vdb.layout or {}
    local positions = Driver._ComputeGridPositions(state.contextMode, count, layout, w, h)

    local pad = 4
    local minX, maxX, maxY = math.huge, -math.huge, -math.huge
    for i = 1, count do
        local px, py = positions[i].x, positions[i].y
        if px < minX then minX = px end
        if px > maxX then maxX = px end
        if py > maxY then maxY = py end
    end
    if minX == math.huge then minX = 0 end
    if maxX == -math.huge then maxX = 0 end
    if maxY == -math.huge then maxY = 0 end

    local Render = ns.QUI_GroupFrameAuraRender
    local now = (GetTime and GetTime()) or 0
    for i = 1, count do
        local f = state.framePool[i]
        if not f then
            f = Driver._CreateMockFrame(root, "quiPreview" .. i)
            state.framePool[i] = f
        elseif f:GetParent() ~= root then
            f:SetParent(root)
        end
        f._isAuraPreview = (i <= AURA_PREVIEW_LIMIT)
        f._phase = (i - 1) * 0.7
        f:SetSize(w, h)
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", root, "TOPLEFT",
            (positions[i].x - minX) + pad, (positions[i].y - maxY) - pad)
        f:Show()
        Driver._ApplyFrameSettings(f, roster[i], vdb, gfdb, state.contextMode)
        state.frames[i] = f
        if i <= AURA_PREVIEW_LIMIT then
            state.auraFrames[#state.auraFrames + 1] = f
            RenderFrameAuras(f, (state.filter and state.filter.auras == false) and nil or vdb.auras, now)
        end
    end
    -- Hide pooled frames beyond the current count (e.g. raid 25 -> party 5).
    for i = count + 1, #state.framePool do
        local f = state.framePool[i]
        if f then
            if Render and Render.ReleaseAll then Render:ReleaseAll(f) end
            f:Hide()
        end
    end

    -- Always call _RenderSpotlight: on party (or raid with spotlight disabled)
    -- it self-guards and clears any stale spotlight frames left from a prior
    -- raid refresh, so a raid->party switch doesn't leave them on screen.
    local gridRight = (maxX - minX) + w + pad
    Driver._RenderSpotlight(root, vdb, gfdb, now, gridRight)

    root:SetSize(1, 1)   -- the surface measures the descendant union, not root size
    if state.onBuilt then
        state.onBuilt(nil, { previewCell = root })
    end
end

-- Lightweight refresh used by the aura editor: re-dispatch ONLY the aura
-- preview tiles, skipping the full per-tile restyle in Refresh (up to 40 tiles
-- × ~15 Apply* subsystems). The aura editor only mutates aura element config --
-- never tile geometry/health/etc -- so the heavy restyle is wasted work on
-- every keystroke/slider tick. Falls back to a full Refresh when the preview
-- has not been built yet (no aura tiles to reuse).
function Driver.RefreshAuras()
    if not state.host then return end
    if not state.auraFrames or #state.auraFrames == 0 then
        Driver.Refresh(state.contextMode)
        return
    end
    local gfdb = Driver._GetGFDB()
    local vdb = Driver._GetContextDB(gfdb, state.contextMode)
    if not vdb then return end
    local now = (GetTime and GetTime()) or 0
    local auras = (state.filter and state.filter.auras == false) and nil or vdb.auras
    for _, f in ipairs(state.auraFrames) do
        RenderFrameAuras(f, auras, now)
    end
end

function Driver.Build(host)
    state.host = host
    Driver._EnsureRoot()
    Driver._EnsureTicker()
    Driver.Refresh(state.contextMode)
end

function Driver.Teardown()
    ReleaseFrames()
    if state.spotlightFrames then
        for _, f in ipairs(state.spotlightFrames) do f:Hide(); f:SetParent(nil) end
        state.spotlightFrames = {}
    end
    if state.root then state.root:Hide() end
    if state.ticker then state.ticker:Hide() end
end

-- GLOBAL SEAMS — the options surface calls these (replaces the old composer
-- definitions). Guarded callers tolerate nil before this LOD file loads.
_G.QUI_BuildGroupFramePreview = function(host, contextMode)
    Driver.Build(host)
    Driver.Refresh(contextMode)
end
-- Refresh coalescer: a single discrete settings change can fan out into several
-- onChange pings within one frame (editor rebuild + per-widget callbacks +
-- section reflow). Collapse them into one rebuild on the next frame. A queued
-- full refresh supersedes an aura-only one.
local function FlushPreviewRefresh()
    state._refreshScheduled = false
    local kind = state._pendingRefresh
    state._pendingRefresh = nil
    local cm = state._pendingContext
    state._pendingContext = nil
    if kind == "full" then
        Driver.Refresh(cm or state.contextMode)
    elseif kind == "auras" then
        Driver.RefreshAuras()
    end
end

local function ScheduleRefresh(kind, contextMode)
    if contextMode then state._pendingContext = contextMode end
    if kind == "full" or state._pendingRefresh == "full" then
        state._pendingRefresh = "full"
    else
        state._pendingRefresh = "auras"
    end
    if state._refreshScheduled then return end
    state._refreshScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, FlushPreviewRefresh)
    else
        FlushPreviewRefresh()
    end
end

-- aurasOnly=true requests the lightweight aura-tile-only rebuild (see
-- Driver.RefreshAuras); omitted/false does the full per-tile restyle. Kept a
-- single seam (no new _G global) for the assignment ratchet.
-- bucketKey (optional): the spec bucket the auras editor currently has selected
-- ("*" = All Specs, or a specID). Set synchronously here so the coalesced flush
-- reads the latest; omitted/nil leaves the prior binding untouched.
_G.QUI_RefreshGroupFramePreview = function(contextMode, aurasOnly, bucketKey)
    if bucketKey ~= nil then
        local cm = (contextMode == "raid") and "raid" or "party"
        state.previewBucket = state.previewBucket or {}
        state.previewBucket[cm] = bucketKey
    end
    ScheduleRefresh(aurasOnly and "auras" or "full", contextMode or state.contextMode)
end
_G.QUI_SetGroupFramePreviewObserver = function(fn)
    state.onBuilt = fn
end
_G.QUI_SetGroupFramePreviewFilter = function(tbl)
    state.filter = Driver._NormalizeFilter(tbl)
    Driver.Refresh(state.contextMode)
end
_G.QUI_GetGroupFramePreviewFilter = function()
    return Driver._NormalizeFilter(state.filter)
end

return Driver
