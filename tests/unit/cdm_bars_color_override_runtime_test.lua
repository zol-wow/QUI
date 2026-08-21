local function noop() end
local methods = {
    ClearAllPoints = true,
    Hide = true,
    SetAlpha = true,
    SetFrameLevel = true,
    SetFrameStrata = true,
    SetHeight = true,
    SetLooping = true,
    SetOrientation = true,
    SetPoint = true,
    SetReverseFill = true,
    SetScript = true,
    SetSize = true,
    SetStatusBarTexture = true,
    SetTexCoord = true,
    SetTexture = true,
    SetValue = true,
    Show = true,
}

local function object(fields)
    return setmetatable(fields or {}, {
        __index = function(_, name)
            if name == "GetFrameLevel" then
                return function() return 1 end
            end
            return methods[name] and noop or nil
        end,
    })
end

C_Timer = { After = noop }
function InCombatLockdown() return false end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
RAID_CLASS_COLORS = {
    DEATHKNIGHT = { r = 0.2, g = 0.4, b = 0.8 },
}

function CreateFrame()
    local frame = object()
    function frame:CreateAnimationGroup()
        local group = object()
        function group:CreateAnimation() return object({ SetDuration = noop }) end
        return group
    end
    return frame
end

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        GetSkinBorderColor = function() return 0, 0, 0, 1 end,
    },
    LSM = { Fetch = function() return nil end },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)

local applied
local statusBar = object({
    SetStatusBarColor = function(_, r, g, b, a) applied = { r, g, b, a } end,
})
local bar = object({
    _active = true,
    StatusBar = statusBar,
    _spellEntry = {
        id = 101,
        spellID = 202,
        baseSpellID = 202,
        linkedSpellID = 303,
        linkedSpellIDs = { 404 },
        cooldownID = 505,
    },
})
local settings = {
    barColor = { 1, 1, 1, 1 },
    barOpacity = 0.75,
    borderSize = 0,
    colorOverrides = {
        [101] = { 0.1, 0.8, 0.2, 1 },
    },
    useClassColor = true,
}

ns.CDMBars.ConfigureBar(bar, settings, 215)
assert(applied[1] == 0.1 and applied[2] == 0.8 and applied[3] == 0.2
    and applied[4] == 0.75,
    "ConfigureBar must prefer the configured entry id over class color")

settings.colorOverrides = { [303] = { 0.9, 0.2, 0.7, 1 } }
ns.CDMBars.ConfigureBar(bar, settings, 215)
assert(applied[1] == 0.9 and applied[2] == 0.2 and applied[3] == 0.7
    and applied[4] == 0.75,
    "ConfigureBar must honor a linked runtime spell override")

print("OK: cdm_bars_color_override_runtime_test")
