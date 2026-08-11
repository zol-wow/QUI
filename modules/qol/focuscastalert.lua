local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local UIKit = ns.UIKit

local DEFAULT_SETTINGS = {
    enabled = false,
    text = ns.L["Focus is casting. Kick!"],
    anchorTo = "screen",
    offsetX = 0,
    offsetY = -120,
    font = "",
    fontSize = 26,
    fontOutline = "OUTLINE",
    textColor = {1, 0.2, 0.2, 1},
    useClassColor = false,
    soundEnabled = false,
    sound = "None",
}

local FALLBACK_FONT_PATH = "Fonts\\FRIZQT__.TTF"
local FALLBACK_FONT_OUTLINE = "OUTLINE"

local SafeToString = Helpers.SafeToString

local INTERRUPT_SPELLS_BY_CLASS = {
    DEATHKNIGHT = {{id = 47528,  cd = 15}},
    DEMONHUNTER = {{id = 183752, cd = 15}},
    DRUID       = {{id = 106839, cd = 15},
                   {id = 78675,  cd = 60}},
    EVOKER      = {{id = 351338, cd = 20}},
    HUNTER      = {{id = 147362, cd = 24}},
    MAGE        = {{id = 2139,   cd = 24}},
    MONK        = {{id = 116705, cd = 15}},
    PALADIN     = {{id = 96231,  cd = 15}},
    PRIEST      = {{id = 15487,  cd = 30}},
    ROGUE       = {{id = 1766,   cd = 15}},
    SHAMAN      = {{id = 57994,  cd = 30}},
    WARLOCK     = {{id = 19647,  cd = 24}},
    WARRIOR     = {{id = 6552,   cd = 15}},
}

local INTERRUPT_SPELL_LOOKUP = {}
for _, spells in pairs(INTERRUPT_SPELLS_BY_CLASS) do
    for _, spell in ipairs(spells) do
        INTERRUPT_SPELL_LOOKUP[spell.id] = spell.cd
    end
end

local state = {
    frame = nil,
    text = nil,
    ticker = nil,
    preview = false,
    rawNotInterruptible = nil,
    castEvidence = nil,
    interruptCasts = {},
}

local function CopyColor(color)
    if type(color) ~= "table" then
        return {1, 1, 1, 1}
    end
    return {color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1}
end

local function GetGeneralDB()
    return Helpers.GetModuleDB("general")
end

local function GetSettings()
    local general = GetGeneralDB()
    if not general then
        return nil
    end

    if type(general.focusCastAlert) ~= "table" then
        general.focusCastAlert = {}
    end

    local settings = general.focusCastAlert
    Helpers.EnsureDefaults(settings, DEFAULT_SETTINGS)

    if type(settings.textColor) ~= "table" then
        settings.textColor = CopyColor(DEFAULT_SETTINGS.textColor)
    end
    return settings
end

local function GetAnchorFrame(anchorTo)
    if anchorTo == "essential" then
        return _G.QUI_GetCDMViewerFrame and _G.QUI_GetCDMViewerFrame("essential")
    end

    if anchorTo == "focus" then
        return ns.QUI_UnitFrames and ns.QUI_UnitFrames.frames and ns.QUI_UnitFrames.frames.focus
    end

    return nil
end

local function PositionAlertFrame()
    if not state.frame then
        return
    end

    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor("focusCastAlert") then return end

    local settings = GetSettings()
    local offsetX = (settings and settings.offsetX) or DEFAULT_SETTINGS.offsetX
    local offsetY = (settings and settings.offsetY) or DEFAULT_SETTINGS.offsetY
    local anchorTo = (settings and settings.anchorTo) or DEFAULT_SETTINGS.anchorTo

    state.frame:ClearAllPoints()

    if anchorTo == "screen" then
        state.frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
        return
    end

    local anchorFrame = GetAnchorFrame(anchorTo)
    if anchorFrame and anchorFrame:IsShown() then
        state.frame:SetPoint("CENTER", anchorFrame, "CENTER", offsetX, offsetY)
    else
        state.frame:SetPoint("CENTER", UIParent, "CENTER", offsetX, offsetY)
    end
end

local function IsSpellKnownForPlayer(spellID)
    if type(IsSpellKnownOrOverridesKnown) == "function" then
        local ok, known = ns.SafeCall("chain-next", IsSpellKnownOrOverridesKnown, spellID)
        if ok then return known end
    end

    if C_SpellBook and type(C_SpellBook.IsSpellKnown) == "function" then
        local ok, known = ns.SafeCall("chain-next", C_SpellBook.IsSpellKnown, spellID)
        if ok then return known end
    end

    if type(IsPlayerSpell) == "function" then
        local ok, known = ns.SafeCall("chain-next", IsPlayerSpell, spellID)
        if ok then return known end
    end

    if type(IsSpellKnown) == "function" then
        local ok, known = ns.SafeCall("chain-next", IsSpellKnown, spellID)
        if ok then return known end
    end

    return false
end

local function OnPlayerInterruptCast(spellID)
    if Helpers.IsSecretValue(spellID) then return end
    if spellID == nil then return end
    local cd = INTERRUPT_SPELL_LOOKUP[spellID]
    if cd then
        state.interruptCasts[spellID] = GetTime()
    end
end

local function IsInterruptReady()
    local _, classToken = UnitClass("player")
    -- @secret-policy: collapse-only — unknown class = no interrupt tracking
    if Helpers.IsSecretValue(classToken) then classToken = nil end
    local interruptSpells = INTERRUPT_SPELLS_BY_CLASS[classToken or ""]
    if not interruptSpells then
        return false
    end

    local now = GetTime()
    for _, spell in ipairs(interruptSpells) do
        if IsSpellKnownForPlayer(spell.id) then
            local castTime = state.interruptCasts[spell.id]
            if not castTime then
                return true
            end
            if now - castTime >= spell.cd then
                return true
            end
        end
    end

    return false
end

local function IsFocusCasting()
    if not UnitExists("focus") then return false end
    if not UnitCanAttack("player", "focus") then return false end

    local castName = UnitCastingInfo("focus")
    local channelName = UnitChannelInfo("focus")
    if Helpers.IsSecretValue(castName) or Helpers.IsSecretValue(channelName) then
        return state.castEvidence ~= nil
    end
    if not castName and not channelName then
        return false
    end

    return true
end

local function CaptureNotInterruptibleFlag()
    local evidence = state.castEvidence
    if evidence == "channel" then
        local _, _, _, _, _, _, notInterruptible = UnitChannelInfo("focus")
        state.rawNotInterruptible = notInterruptible
        return
    end
    if evidence == "cast" then
        local _, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("focus")
        state.rawNotInterruptible = notInterruptible
        return
    end

    local name, _, _, _, _, _, notInterruptible = UnitChannelInfo("focus")
    if Helpers.IsSecretValue(name) then
        state.rawNotInterruptible = nil -- @secret-policy: skip-capture-when-unknown
        return
    end
    if name then
        state.rawNotInterruptible = notInterruptible
        return
    end

    name, _, _, _, _, _, _, notInterruptible = UnitCastingInfo("focus")
    if Helpers.IsSecretValue(name) then
        state.rawNotInterruptible = nil -- @secret-policy: skip-capture-when-unknown
        return
    end
    if not name then
        state.rawNotInterruptible = nil
        return
    end

    state.rawNotInterruptible = notInterruptible
end

local function IsEventUnitFocus(event, unit)
    if event == "PLAYER_FOCUS_CHANGED" then
        return true
    end
    return unit == "focus"
end

local function MaybePlayInterruptSound()
    if state.soundPlayed then return end
    local settings = GetSettings()
    if not settings or not settings.enabled or not settings.soundEnabled then return end
    local soundName = settings.sound
    if not soundName or soundName == "None" or soundName == "" then return end

    local raw = state.rawNotInterruptible
    if Helpers.IsSecretValue(raw) then return end
    if raw == nil then return end
    if raw ~= false then return end

    if not IsInterruptReady() then return end
    local LSM = ns.LSM
    local path = LSM and LSM:Fetch("sound", soundName)
    if path and type(path) == "string" then
        PlaySoundFile(path, "Master")
        state.soundPlayed = true
    end
end

local function HandleEventState(event, unit, spellID)
    if not IsEventUnitFocus(event, unit) then
        return
    end

    if event == "PLAYER_FOCUS_CHANGED" then
        state.castEvidence = nil
        state.rawNotInterruptible = nil
        state.soundPlayed = nil
        CaptureNotInterruptibleFlag()
        return
    end

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        state.castEvidence = (event == "UNIT_SPELLCAST_CHANNEL_START") and "channel" or "cast"
        state.rawNotInterruptible = nil
        state.soundPlayed = nil
        CaptureNotInterruptibleFlag()
        return
    end

    if event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        state.rawNotInterruptible = true
        return
    end

    if event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        state.rawNotInterruptible = false
        MaybePlayInterruptSound()
        return
    end

    if event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            state.castEvidence = "channel"
        end
        CaptureNotInterruptibleFlag()
        return
    end

    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        state.castEvidence = nil
        state.rawNotInterruptible = nil
        state.soundPlayed = nil
        return
    end

    CaptureNotInterruptibleFlag()
end

local function SafePlaceholder(value, fallback)
    if Helpers.IsSecretValue(value) then return fallback end
    if value == nil then return fallback end
    local str = SafeToString(value, fallback)
    return str ~= "" and str or fallback
end

local function ApplyAlertText(template)
    local text = SafeToString(template, "")
    if text == "" then
        text = DEFAULT_SETTINGS.text
    end

    local hasUnit = text:find("{unit}", 1, true)
    local hasSpell = text:find("{spell}", 1, true)

    if not hasUnit and not hasSpell then
        state.text:SetText(text)
        return
    end

    local unitName
    if hasUnit then
        unitName = UnitName("focus")
        if Helpers.IsSecretValue(unitName) then
        elseif unitName == nil then
            unitName = ns.L["Focus"]
        end
    end

    local rawSpellName
    if hasSpell then
        if state.castEvidence == "channel" then
            rawSpellName = UnitChannelInfo("focus")
        else
            rawSpellName = UnitCastingInfo("focus")
            if Helpers.IsSecretValue(rawSpellName) then
            elseif rawSpellName == nil then
                rawSpellName = UnitChannelInfo("focus")
            end
        end
        if Helpers.IsSecretValue(rawSpellName) then
        elseif rawSpellName == nil then
            rawSpellName = ""
        end
    end

    if not Helpers.IsSecretValue(unitName) and not Helpers.IsSecretValue(rawSpellName) then
        if hasUnit then
            text = text:gsub("{unit}", SafePlaceholder(unitName, ns.L["Focus"]):gsub("%%", "%%%%"))
        end
        if hasSpell then
            text = text:gsub("{spell}", SafePlaceholder(rawSpellName, ""):gsub("%%", "%%%%"))
        end
        state.text:SetText(text)
        return
    end

    local args = {}
    local replacements = {}
    if hasUnit then
        local s, e = text:find("{unit}", 1, true)
        replacements[#replacements + 1] = {s = s, e = e, value = unitName}
    end
    if hasSpell then
        local s, e = text:find("{spell}", 1, true)
        replacements[#replacements + 1] = {s = s, e = e, value = rawSpellName}
    end
    table.sort(replacements, function(a, b) return a.s < b.s end)

    local segments = {}
    local cursor = 1
    for _, r in ipairs(replacements) do
        if r.s > cursor then
            segments[#segments + 1] = text:sub(cursor, r.s - 1):gsub("%%", "%%%%")
        end
        segments[#segments + 1] = "%s"
        args[#args + 1] = r.value
        cursor = r.e + 1
    end
    if cursor <= #text then
        segments[#segments + 1] = text:sub(cursor):gsub("%%", "%%%%")
    end

    local fmt = table.concat(segments)
    local ok = ns.SafeCallMethod("sink-forward", state.text, "SetFormattedText", fmt, unpack(args))
    if not ok then
        local fallback = template
        if hasUnit then fallback = fallback:gsub("{unit}", SafePlaceholder(unitName, ns.L["Focus"])) end
        if hasSpell then fallback = fallback:gsub("{spell}", "") end
        state.text:SetText(fallback)
    end
end

local function ApplyTextStyle()
    if not state.text then return end

    local settings = GetSettings()
    local fontPath
    if settings and settings.font and settings.font ~= "" and UIKit and UIKit.ResolveFontPath then
        fontPath = UIKit.ResolveFontPath(settings.font)
    else
        fontPath = Helpers.GetGeneralFont()
    end
    if not fontPath then
        fontPath = FALLBACK_FONT_PATH
    end

    local fontSize = tonumber((settings and settings.fontSize) or DEFAULT_SETTINGS.fontSize) or DEFAULT_SETTINGS.fontSize
    local fontOutline = (settings and settings.fontOutline)
    if fontOutline == nil then
        fontOutline = Helpers.GetGeneralFontOutline() or DEFAULT_SETTINGS.fontOutline
    end
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(state.text, fontPath, fontSize, fontOutline)
    else
        local fontSet = state.text:SetFont(fontPath, fontSize, fontOutline)
        if not fontSet then
            state.text:SetFont(FALLBACK_FONT_PATH, fontSize, FALLBACK_FONT_OUTLINE)
        end
    end

    local color
    if settings and settings.useClassColor then
        local r, g, b = Helpers.GetPlayerClassColor()
        color = {r, g, b, 1}
    else
        color = (settings and settings.textColor) or DEFAULT_SETTINGS.textColor
    end
    state.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
end

local function CreateAlertFrame()
    if state.frame then return end

    local frame = CreateFrame("Frame", "QUI_FocusCastAlertFrame", UIParent)
    frame:SetSize(500, 60)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetJustifyV("MIDDLE")
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(text, FALLBACK_FONT_PATH, DEFAULT_SETTINGS.fontSize, FALLBACK_FONT_OUTLINE)
    else
        text:SetFont(FALLBACK_FONT_PATH, DEFAULT_SETTINGS.fontSize, FALLBACK_FONT_OUTLINE)
    end
    text:SetText(DEFAULT_SETTINGS.text)

    state.frame = frame
    state.text = text

    PositionAlertFrame()
    ApplyTextStyle()
end

local function ApplyInterruptAlpha()
    local raw = state.rawNotInterruptible
    if Helpers.IsSecretValue(raw) then
        if state.frame.SetAlphaFromBoolean then
            state.frame:SetAlphaFromBoolean(raw, 0, 1)
        else
            state.frame:SetAlpha(0)
        end
        return
    end
    if raw == nil then
        state.frame:SetAlpha(0)
        return
    end

    if state.frame.SetAlphaFromBoolean then
        state.frame:SetAlphaFromBoolean(raw, 0, 1)
    else
        state.frame:SetAlpha(raw and 0 or 1)
    end
end

local function UpdateAlert()
    if not state.frame then
        CreateAlertFrame()
    end

    local settings = GetSettings()
    if not settings then
        state.frame:Hide()
        return
    end

    if state.preview then
        PositionAlertFrame()
        ApplyTextStyle()
        ApplyAlertText(settings.text)
        state.frame:SetAlpha(1)
        state.frame:Show()
        return
    end

    if not settings.enabled then
        state.frame:Hide()
        return
    end

    if not IsFocusCasting() then
        state.frame:Hide()
        return
    end

    PositionAlertFrame()
    ApplyTextStyle()

    if not IsInterruptReady() then
        state.frame:Hide()
        return
    end

    ApplyAlertText(settings.text)
    state.frame:Show()
    ApplyInterruptAlpha()
    MaybePlayInterruptSound()
end

local function StartTicker()
    if not state.ticker then
        state.ticker = C_Timer.NewTicker(0.25, UpdateAlert)
    end
end

local function StopTicker()
    if state.ticker then
        state.ticker:Cancel()
        state.ticker = nil
    end
end

local function ShouldRunTicker()
    local settings = GetSettings()
    return state.preview or (settings and settings.enabled)
end

local function RefreshFocusCastAlert()
    CreateAlertFrame()
    CaptureNotInterruptibleFlag()
    UpdateAlert()
end

local function TogglePreview(show)
    state.preview = show and true or false
    if state.preview then
        StartTicker()
    else
        StopTicker()
    end
    RefreshFocusCastAlert()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_START", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "focus")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
eventFrame:SetScript("OnEvent", function(self, event, unit, castGUID, spellID, ...)
    if event == "ADDON_LOADED" then
        if unit ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        RefreshFocusCastAlert()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        CaptureNotInterruptibleFlag()
        UpdateAlert()
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        OnPlayerInterruptCast(spellID)
        UpdateAlert()
        return
    end

    HandleEventState(event, unit, spellID)

    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        if ShouldRunTicker() then
            StartTicker()
        end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        StopTicker()
    elseif event == "PLAYER_FOCUS_CHANGED" then
        StopTicker()
        if IsFocusCasting() then
            if ShouldRunTicker() then
                StartTicker()
            end
        end
    end

    UpdateAlert()
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(function()
        CaptureNotInterruptibleFlag()
        UpdateAlert()
    end)
end

_G.QUI_RefreshFocusCastAlert = RefreshFocusCastAlert
_G.QUI_ToggleFocusCastAlertPreview = TogglePreview

if ns.Registry then
    ns.Registry:Register("focusCastAlert", {
        refresh = _G.QUI_RefreshFocusCastAlert,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end
