--[[
    QUI Action Bars Live Preview Driver

    Drives the Action Bars tile preview pane: owns the preview-button
    mocks (frame + icon + normal/gloss/backdrop + hotkey/name/count
    fontstrings + Cooldown child), the OnUpdate ticker, and the per-button
    cycle script that walks each button through idle / cooldown swipe /
    ready_glow / push_flash / charges phases. The cycle is layered on top
    of the existing live-mirror behavior: real spell textures and
    hotkey/macro/count text come from the selected real bar's runtime
    state; cooldown/glow/charges/push are simulated.

    Public surface:
        ns.QUI_ActionBarsPreviewDriver.Build(host)
        ns.QUI_ActionBarsPreviewDriver.Refresh()
        ns.QUI_ActionBarsPreviewDriver.SetSelectedBar(barKey)
        ns.QUI_ActionBarsPreviewDriver.Teardown()
        ns.QUI_ActionBarsPreviewDriver.IsPreviewable(barKey)

    Invariants:
        * No game events are registered. Cycle is time-driven.
        * Driver never wraps or replaces real LibActionButton buttons.
        * LibCustomGlow keys are scoped to "_QUIActionBarsPreviewGlow".
        * Driver does not modify the live action bar.
]]

local _, ns = ...

local QUI = QUI
local Helpers = ns.Helpers
local GetCore = Helpers and Helpers.GetCore
local Shared  = ns.QUI_Options
local GetDB   = Shared and Shared.GetDB

local function CJKFont(fs, p, s, f)
    if ns.Helpers and ns.Helpers.ApplyFontWithFallback then
        ns.Helpers.ApplyFontWithFallback(fs, p, s, f)
    else
        fs:SetFont(p, s, f)
    end
end

local ActionBarsPreviewDriver = {}
ns.QUI_ActionBarsPreviewDriver = ActionBarsPreviewDriver

---------------------------------------------------------------------------
-- Constants (migrated from action_bars_content.lua in T2)
---------------------------------------------------------------------------
local BAR_OFFSETS = {
    bar1 = 0,    bar2 = 60,   bar3 = 48,   bar4 = 24,
    bar5 = 36,   bar6 = 144,  bar7 = 156,  bar8 = 168,
}
local BAR_BINDING_PREFIXES = {
    bar1 = "ACTIONBUTTON",
    bar2 = "MULTIACTIONBAR1BUTTON",
    bar3 = "MULTIACTIONBAR2BUTTON",
    bar4 = "MULTIACTIONBAR3BUTTON",
    bar5 = "MULTIACTIONBAR4BUTTON",
    bar6 = "MULTIACTIONBAR5BUTTON",
    bar7 = "MULTIACTIONBAR6BUTTON",
    bar8 = "MULTIACTIONBAR7BUTTON",
}
local PREVIEW_TEXTURE_PATH = (Helpers and Helpers.AssetPath or [[Interface\AddOns\QUI\assets\]]) .. [[iconskin\]]
local PREVIEW_TEXTURES = {
    normal = PREVIEW_TEXTURE_PATH .. "Normal",
    gloss  = PREVIEW_TEXTURE_PATH .. "Gloss",
}
local MAX_PREVIEW_BUTTONS = 12
local SAMPLE_PREVIEW_KEYBINDS = { "1", "2", "3", "4", "R", "F", "C", "V", "Q", "E", "T", "G" }

---------------------------------------------------------------------------
-- Live-mirror helpers (migrated from action_bars_content.lua in T2)
---------------------------------------------------------------------------
local function FormatPreviewKeybind(keybind)
    if QUI and QUI.FormatKeybind then
        return QUI.FormatKeybind(keybind)
    end
    if ns and ns.FormatKeybind then
        return ns.FormatKeybind(keybind)
    end
    if not keybind then return nil end

    local upper = keybind:upper()
    upper = upper:gsub(" ", "")

    upper = upper:gsub("MOUSEWHEELUP", "WU")
    upper = upper:gsub("MOUSEWHEELDOWN", "WD")
    upper = upper:gsub("MIDDLEMOUSE", "B3")
    upper = upper:gsub("MIDDLEBUTTON", "B3")
    upper = upper:gsub("BUTTON(%d+)", "B%1")

    upper = upper:gsub("SHIFT%-", "S")
    upper = upper:gsub("CTRL%-", "C")
    upper = upper:gsub("ALT%-", "A")
    upper = upper:gsub("^S%-(.+)", "S%1")
    upper = upper:gsub("^C%-(.+)", "C%1")
    upper = upper:gsub("^A%-(.+)", "A%1")

    upper = upper:gsub("NUMPADPLUS", "N+")
    upper = upper:gsub("NUMPADMINUS", "N-")
    upper = upper:gsub("NUMPADMULTIPLY", "N*")
    upper = upper:gsub("NUMPADDIVIDE", "N/")
    upper = upper:gsub("NUMPADPERIOD", "N.")
    upper = upper:gsub("NUMPADENTER", "NE")

    upper = upper:gsub("NUMPAD", "N")
    upper = upper:gsub("CAPSLOCK", "CAP")
    upper = upper:gsub("DELETE", "DEL")
    upper = upper:gsub("ESCAPE", "ESC")
    upper = upper:gsub("BACKSPACE", "BS")
    upper = upper:gsub("SPACE", "SP")
    upper = upper:gsub("INSERT", "INS")
    upper = upper:gsub("PAGEUP", "PU")
    upper = upper:gsub("PAGEDOWN", "PD")
    upper = upper:gsub("HOME", "HM")
    upper = upper:gsub("END", "ED")
    upper = upper:gsub("PRINTSCREEN", "PS")
    upper = upper:gsub("SCROLLLOCK", "SL")
    upper = upper:gsub("PAUSE", "PA")
    upper = upper:gsub("TILDE", "`")
    upper = upper:gsub("GRAVE", "`")

    upper = upper:gsub("UPARROW", "UP")
    upper = upper:gsub("DOWNARROW", "DN")
    upper = upper:gsub("LEFTARROW", "LF")
    upper = upper:gsub("RIGHTARROW", "RT")

    upper = upper:gsub("SEMICOLON", ";")
    upper = upper:gsub("APOSTROPHE", "'")
    upper = upper:gsub("LEFTBRACKET", "[")
    upper = upper:gsub("RIGHTBRACKET", "]")
    upper = upper:gsub("BACKSLASH", "\\")
    upper = upper:gsub("MINUS", "-")
    upper = upper:gsub("EQUALS", "=")
    upper = upper:gsub("COMMA", ",")
    upper = upper:gsub("^PERIOD$", ".")
    upper = upper:gsub("SLASH", "/")

    if #upper > 4 then
        upper = upper:sub(1, 4)
    end

    return upper
end

local function IsSecretValue(value)
    return Helpers and Helpers.IsSecretValue and Helpers.IsSecretValue(value) or false
end

local IsPreviewSecretValue = IsSecretValue

local function HasPreviewTextValue(value)
    if IsSecretValue(value) then
        return true
    end
    if value == nil then return false end
    return value ~= ""
end

local function ResolveContext()
    -- Mirrors content.lua's local — pure helper, duplication intentional.
    local db = GetDB and GetDB()
    if not db or not db.actionBars then return nil end
    return {
        db = db,
        actionBars = db.actionBars,
        global = db.actionBars.global,
        fade = db.actionBars.fade,
        bars = db.actionBars.bars,
    }
end

local function GetPreviewEffectiveSettings(barKey)
    local ctx = ResolveContext()
    if not ctx then return nil, nil end

    local effective = {}
    if ctx.global then
        for key, value in pairs(ctx.global) do
            effective[key] = value
        end
    end

    local barDB = ctx.bars and ctx.bars[barKey]
    if barDB then
        for key, value in pairs(barDB) do
            effective[key] = value
        end
    end

    return effective, barDB
end

local function GetPreviewSlot(barKey, index)
    local buttons = ns.ActionBarsOwned
        and ns.ActionBarsOwned.nativeButtons
        and ns.ActionBarsOwned.nativeButtons[barKey]
    local button = buttons and buttons[index]
    local liveAction = button and button.action
    if Helpers.SafeValue then
        liveAction = Helpers.SafeValue(liveAction, nil)
    end
    local numericAction = liveAction and tonumber(liveAction)
    if numericAction and numericAction > 0 then
        return numericAction
    end

    local offset = BAR_OFFSETS[barKey] or 0
    return offset + index
end

local function GetPreviewSourceButton(barKey, index)
    local buttons = ns.ActionBarsOwned
        and ns.ActionBarsOwned.nativeButtons
        and ns.ActionBarsOwned.nativeButtons[barKey]
    return buttons and buttons[index] or nil
end

local function GetPreviewActionSlot(slot, sourceButton)
    local liveAction = sourceButton and sourceButton.action
    if Helpers.SafeValue then
        liveAction = Helpers.SafeValue(liveAction, nil)
    end

    local numericAction = liveAction and tonumber(liveAction)
    if numericAction and numericAction > 0 then
        return numericAction
    end

    return slot
end

local function GetPreviewDisplayedTexture(slot, sourceButton)
    local icon = sourceButton and (sourceButton.icon or sourceButton.Icon)
    if icon and icon.IsShown and icon:GetObjectType() == "Texture" and icon:IsShown() and icon.GetTexture then
        local displayed = icon:GetTexture()
        if displayed then
            return displayed
        end
    end

    return slot and GetActionTexture and GetActionTexture(slot) or nil
end

local function GetPreviewFontSettings()
    local fontPath = (QUI and QUI.GUI and type(QUI.GUI.GetFontPath) == "function" and QUI.GUI:GetFontPath())
        or (QUI and QUI.GUI and QUI.GUI.FONT_PATH)
        or [[Interface\AddOns\QUI\assets\Quazii.ttf]]
    local outline = "OUTLINE"
    local core = GetCore and GetCore()
    local general = core and core.db and core.db.profile and core.db.profile.general
    if general then
        if general.font and ns.LSM then
            fontPath = ns.LSM:Fetch("font", general.font) or fontPath
        end
        outline = general.fontOutline or outline
    end
    return fontPath, outline
end

local function GetPreviewBindingText(barKey, index, sourceButton)
    local hotkey = sourceButton and (sourceButton.HotKey or sourceButton.hotKey)
    local displayed = hotkey and hotkey.GetText and hotkey:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    local prefix = BAR_BINDING_PREFIXES[barKey]
    if not prefix or not GetBindingKey then return nil end

    local binding = GetBindingKey(prefix .. index)
    return FormatPreviewKeybind(binding)
end

local function GetPreviewMacroText(slot, sourceButton)
    local actionSlot = GetPreviewActionSlot(slot, sourceButton)
    local displayed = sourceButton and sourceButton.Name and sourceButton.Name.GetText and sourceButton.Name:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    if not actionSlot or not GetActionText then return nil end

    local ok, text = pcall(GetActionText, actionSlot)
    if not ok then return nil end

    if IsPreviewSecretValue(text) then
        return text
    end
    if type(text) == "string" and text ~= "" then
        return text
    end
    return nil
end

local function GetPreviewCountText(slot, sourceButton)
    local actionSlot = GetPreviewActionSlot(slot, sourceButton)
    local displayed = sourceButton and sourceButton.Count and sourceButton.Count.GetText and sourceButton.Count:GetText() or nil
    if IsPreviewSecretValue(displayed) then
        return displayed
    end
    if type(displayed) == "string" and displayed ~= "" then
        return displayed
    end

    if not actionSlot or not (C_ActionBar and C_ActionBar.GetActionDisplayCount) then
        return nil
    end

    local ok, count = pcall(C_ActionBar.GetActionDisplayCount, actionSlot)
    if not ok then return nil end

    if IsSecretValue(count) then
        return count
    else
        if count == nil or count == "" or count == 0 or count == "0" then
            return nil
        end

        return tostring(count)
    end
end

-- Derive horizontal/vertical justification from the anchor point name and
-- apply the (defaulted-to-white) text color. Shared by SetPreviewTextStyle and
-- SetPreviewCooldownTextStyle, which applied this identical block.
local function ApplyJustifyAndColor(fontString, point, color)
    if point:find("LEFT") then
        fontString:SetJustifyH("LEFT")
    elseif point:find("RIGHT") then
        fontString:SetJustifyH("RIGHT")
    else
        fontString:SetJustifyH("CENTER")
    end

    if point:find("TOP") then
        fontString:SetJustifyV("TOP")
    elseif point:find("BOTTOM") then
        fontString:SetJustifyV("BOTTOM")
    else
        fontString:SetJustifyV("MIDDLE")
    end

    local r = color and color[1] or 1
    local g = color and color[2] or 1
    local b = color and color[3] or 1
    local a = color and color[4] or 1
    fontString:SetTextColor(r, g, b, a)
end

local function SetPreviewTextStyle(fontString, button, text, fontPath, outline, fontSize, color, anchor, offsetX, offsetY)
    if not fontString then return end
    local isSecretText = IsSecretValue(text)
    if isSecretText then
        -- Secret text can be passed directly to SetText below, but must not be
        -- inspected in Lua.
    elseif text == nil or text == "" then
        fontString:SetText("")
        fontString:SetAlpha(0)
        fontString:Hide()
        return
    elseif type(text) ~= "string" then
        text = tostring(text)
    end

    local width = math.max((button:GetWidth() or 0) - 4, 1)
    local height = math.max((fontSize or 10) + 4, 1)
    local point = anchor or "CENTER"

    CJKFont(fontString, fontPath, fontSize or 10, outline or "OUTLINE")
    fontString:SetText(text)
    fontString:SetWidth(width)
    fontString:SetHeight(height)
    fontString:ClearAllPoints()
    fontString:SetPoint(point, button, point, offsetX or 0, offsetY or 0)

    ApplyJustifyAndColor(fontString, point, color)
    fontString:SetAlpha(1)
    fontString:Show()
end

local function SetPreviewCooldownTextStyle(cooldown, button, settings, fontPath, outline)
    if not cooldown or not settings then return end

    local showCooldownText = settings.showCooldownText ~= false
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(not showCooldownText)
    end

    if not cooldown.GetCountdownFontString then return end
    local fontString = cooldown:GetCountdownFontString()
    if not fontString then return end

    if not showCooldownText then
        fontString:SetAlpha(0)
        return
    end

    local fontSize = settings.cooldownTextFontSize or 14
    local width = math.max((button:GetWidth() or 0) - 4, 1)
    local height = math.max(fontSize + 4, 1)
    local point = settings.cooldownTextAnchor or "CENTER"
    local color = settings.cooldownTextColor

    CJKFont(fontString, fontPath, fontSize, outline or "OUTLINE")
    fontString:SetWidth(width)
    fontString:SetHeight(height)
    fontString:ClearAllPoints()
    fontString:SetPoint(point, button, point, settings.cooldownTextOffsetX or 0, settings.cooldownTextOffsetY or 0)

    ApplyJustifyAndColor(fontString, point, color)
    fontString:SetAlpha(1)
    fontString:Show()
end

---------------------------------------------------------------------------
-- Preview-scoped glow helper
-- Uses LibCustomGlow with a preview-only key so preview glows can never
-- collide with runtime glow state on the same spell icon (runtime uses
-- a different key on real action buttons).
---------------------------------------------------------------------------
local PREVIEW_GLOW_KEY = "_QUIActionBarsPreviewGlow"

local function GetLCG()
    return LibStub and LibStub("LibCustomGlow-1.0", true) or nil
end

local function StartGlow(pb, settings)
    local LCG = GetLCG()
    if not LCG or not pb or not pb.frame then return end
    local style     = settings and settings.glowStyle or "pixel"
    local color     = settings and settings.glowColor or { 1, 1, 0, 1 }
    local lines     = settings and settings.glowLines or 8
    local frequency = settings and settings.glowFrequency or 0.25
    local thickness = settings and settings.glowThickness or 2
    local scale     = settings and settings.glowScale or 1

    if style == "pixel" then
        LCG.PixelGlow_Start(pb.frame, color, lines, frequency, nil, thickness, 0, 0, true, PREVIEW_GLOW_KEY)
    elseif style == "autocast" then
        LCG.AutoCastGlow_Start(pb.frame, color, lines, frequency, scale, 0, 0, PREVIEW_GLOW_KEY)
    else
        LCG.ButtonGlow_Start(pb.frame, color, frequency)
    end
end

local function StopGlow(pb)
    local LCG = GetLCG()
    if not LCG or not pb or not pb.frame then return end
    -- Stop every style defensively — the user may have changed glowStyle
    -- mid-cycle and we don't know which one is currently active.
    if LCG.PixelGlow_Stop    then LCG.PixelGlow_Stop(pb.frame, PREVIEW_GLOW_KEY)    end
    if LCG.AutoCastGlow_Stop then LCG.AutoCastGlow_Stop(pb.frame, PREVIEW_GLOW_KEY) end
    if LCG.ButtonGlow_Stop   then LCG.ButtonGlow_Stop(pb.frame)                    end
end

---------------------------------------------------------------------------
-- Driver state
---------------------------------------------------------------------------
local state = {
    host             = nil,
    ticker           = nil,
    previewButtons   = {},   -- array of preview button records
    buttonState      = {},   -- per-button cycle records (keyed by button frame)
    selectedBar      = "bar1",
    glowOwnerIdx     = 1,
    glowOwnerT       = 0,
    chargeOwnerIdx   = 1,
    chargeOwnerT     = 0,
}

---------------------------------------------------------------------------
-- Per-button cycle state
---------------------------------------------------------------------------
local function InitButtonState(pb)
    state.buttonState[pb.frame] = {
        phaseIdx     = 1,                          -- entry phase index
        t            = math.random() * 5,          -- random phase offset (staggers cycles)
        cooldownDur  = 4 + math.random() * 8,      -- 4–12s randomized per button
        chargeMax    = math.random(2, 4),          -- 2–4 charges when this button is the charge-owner
    }
end

---------------------------------------------------------------------------
-- Cycle script catalog
-- Each preview button advances independently with a random initial phase
-- offset, so the panel always shows a mix of states at any given moment.
-- ready_glow and charges are gated by global owner indexes (see T6, T7);
-- non-owner buttons in those phases look like idle.
---------------------------------------------------------------------------
local ACTION_BUTTON_PHASES = {
    { phase = "idle",        duration = 0.6  },
    { phase = "cooldown",    duration = 7    },   -- per-button override via buttonState.cooldownDur
    { phase = "ready_glow",  duration = 1.5  },
    { phase = "push_flash",  duration = 0.15 },
    { phase = "charges",     duration = 2.5  },
}

local function PhaseDuration(phaseIdx, bs)
    local phase = ACTION_BUTTON_PHASES[phaseIdx]
    if not phase then return 1 end
    -- The "cooldown" phase uses per-button randomized duration so cycles stagger.
    if phase.phase == "cooldown" then
        return bs.cooldownDur or phase.duration
    end
    return phase.duration
end

---------------------------------------------------------------------------
-- Glow-owner rotation
-- Only one preview button glows at a time. Owner advances every 1.5s.
---------------------------------------------------------------------------
local function AdvanceGlowOwner(elapsed)
    if #state.previewButtons == 0 then return end
    state.glowOwnerT = state.glowOwnerT + elapsed
    if state.glowOwnerT < 1.5 then return end
    state.glowOwnerT = 0

    -- Stop glow on previous owner
    local prev = state.previewButtons[state.glowOwnerIdx]
    if prev then StopGlow(prev) end

    -- Advance index, start glow on new owner if it has a texture
    state.glowOwnerIdx = (state.glowOwnerIdx % #state.previewButtons) + 1
    local nextButton = state.previewButtons[state.glowOwnerIdx]
    if nextButton and nextButton.icon and nextButton.icon:GetTexture() then
        local settings = GetPreviewEffectiveSettings(state.selectedBar) or {}
        StartGlow(nextButton, settings)
    end
end

---------------------------------------------------------------------------
-- Charge-owner rotation
-- Only one preview button displays charge text at a time. Owner advances
-- every 2.5s. Prevents preview-looks-like-every-spell-has-charges.
---------------------------------------------------------------------------
local function AdvanceChargeOwner(elapsed)
    if #state.previewButtons == 0 then return end
    state.chargeOwnerT = state.chargeOwnerT + elapsed
    if state.chargeOwnerT < 2.5 then return end
    state.chargeOwnerT = 0

    -- Hide charge text on previous owner
    local prev = state.previewButtons[state.chargeOwnerIdx]
    if prev and prev.count then
        prev.count:SetText("")
        prev.count:Hide()
    end

    -- Advance index. The owning button shows charges during its `charges` phase.
    state.chargeOwnerIdx = (state.chargeOwnerIdx % #state.previewButtons) + 1
end

---------------------------------------------------------------------------
-- Per-button phase application (T5: idle + cooldown; T6 adds ready_glow;
-- T7 adds charges; T8 adds push_flash)
---------------------------------------------------------------------------
local function ApplyPhase(pb, bs, phaseName, phaseT)
    if not pb.cooldown or not pb.icon then return end

    if phaseName == "idle" then
        pb.cooldown:Clear()
        pb.cooldown:Hide()
        pb.icon:SetDesaturated(false)
    elseif phaseName == "cooldown" then
        -- Re-arm only on phase entry; calling SetCooldown every frame would
        -- reset start to GetTime() each frame and freeze the swipe at frame 0.
        if phaseT < 0.05 then
            pb.cooldown:Show()
            pb.cooldown:SetCooldown(GetTime(), bs.cooldownDur or 7)
        end
        pb.icon:SetDesaturated(true)
    elseif phaseName == "ready_glow" then
        pb.cooldown:Clear()
        pb.cooldown:Hide()
        pb.icon:SetDesaturated(false)
        -- Glow is owned by the rotating glowOwner, not every button.
    elseif phaseName == "push_flash" then
        pb.cooldown:Clear()
        pb.cooldown:Hide()
        pb.icon:SetDesaturated(false)
        -- Skip the flash entirely when an active tint is already coloring the
        -- icon — flashing on top of a tint looks like the tint blinks.
        if bs.tintActive then return end
        -- Brief dim on the normal-texture overlay, restored at the end of the phase.
        if pb.normal then
            local PHASE_DUR = 0.15
            if phaseT < PHASE_DUR * 0.5 then
                -- First half: dim
                pb.normal:SetVertexColor(0.3, 0.3, 0.3, 1)
            else
                -- Second half: restore
                pb.normal:SetVertexColor(0, 0, 0, 1)
            end
        end
    elseif phaseName == "charges" then
        pb.cooldown:Clear()
        pb.cooldown:Hide()
        pb.icon:SetDesaturated(false)
        -- Charge text only shown when this button is the current charge-owner.
        if pb.idx == state.chargeOwnerIdx and pb.count then
            local total = bs.chargeMax or 3
            local remaining = math.max(0, total - math.floor(phaseT * (total / 2.5)))
            if remaining > 0 then
                pb.count:SetText(tostring(remaining))
                pb.count:Show()
            else
                pb.count:SetText("")
                pb.count:Hide()
            end
        end
    end
end

local function AdvanceButton(pb, elapsed)
    local bs = state.buttonState[pb.frame]
    if not bs then return end

    -- Empty slots (no live texture) skip the cycle and stay in idle. This
    -- avoids cycling cooldown / glow on slots with no spell, which would
    -- look broken. The texture is set every Refresh — read it here.
    local tex = pb.icon and pb.icon:GetTexture()
    if not tex then
        ApplyPhase(pb, bs, "idle", 0)
        return
    end

    bs.phaseIdx = bs.phaseIdx or 1
    bs.t = (bs.t or 0) + elapsed

    local phaseDur = PhaseDuration(bs.phaseIdx, bs)
    if bs.t >= phaseDur then
        bs.t = 0
        bs.phaseIdx = (bs.phaseIdx % #ACTION_BUTTON_PHASES) + 1
    end

    local phaseName = ACTION_BUTTON_PHASES[bs.phaseIdx].phase
    ApplyPhase(pb, bs, phaseName, bs.t)
end

---------------------------------------------------------------------------
-- Public surface
---------------------------------------------------------------------------

function ActionBarsPreviewDriver.Build(host)
    if state.ticker then return end  -- idempotent
    state.host = host

    local previewHost = CreateFrame("Frame", nil, host)
    previewHost:SetPoint("TOPLEFT",  host, "TOPLEFT",  12, -30)
    previewHost:SetPoint("TOPRIGHT", host, "TOPRIGHT", -12, -30)
    previewHost:SetPoint("BOTTOM",   host, "BOTTOM",   0,  12)
    state.previewHost = previewHost

    -- Build MAX_PREVIEW_BUTTONS preview-button records. Each bundles the
    -- visual pieces QUI's real SkinButton applies (backdrop, icon, normal,
    -- gloss, hotkey/name/count fontstrings). Cooldown child is attached
    -- in Task 4.
    for i = 1, MAX_PREVIEW_BUTTONS do
        local b = CreateFrame("Frame", nil, previewHost)

        local backdrop = b:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetAllPoints(b)
        backdrop:SetColorTexture(0, 0, 0, 1)

        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(b)

        local normal = b:CreateTexture(nil, "OVERLAY", nil, 1)
        normal:SetAllPoints(b)
        normal:SetTexture(PREVIEW_TEXTURES.normal)
        normal:SetVertexColor(0, 0, 0, 1)

        local gloss = b:CreateTexture(nil, "OVERLAY", nil, 2)
        gloss:SetAllPoints(b)
        gloss:SetTexture(PREVIEW_TEXTURES.gloss)
        gloss:SetBlendMode("ADD")
        gloss:Hide()

        local hotkey = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hotkey:SetWordWrap(false)
        hotkey:SetShadowOffset(1, -1)
        if hotkey.SetMaxLines then hotkey:SetMaxLines(1) end

        local name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetWordWrap(false)
        name:SetShadowOffset(1, -1)
        if name.SetMaxLines then name:SetMaxLines(1) end

        local count = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        count:SetWordWrap(false)
        count:SetShadowOffset(1, -1)
        if count.SetMaxLines then count:SetMaxLines(1) end

        local cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        cooldown:SetAllPoints(b)
        cooldown:SetDrawSwipe(true)
        cooldown:SetHideCountdownNumbers(false)
        cooldown:SetSwipeTexture("Interface\\Buttons\\WHITE8X8")
        cooldown:SetSwipeColor(0, 0, 0, 0.8)
        cooldown:SetDrawBling(false)
        cooldown:EnableMouse(false)
        cooldown:Hide()

        state.previewButtons[i] = {
            frame    = b,
            icon     = icon,
            backdrop = backdrop,
            normal   = normal,
            gloss    = gloss,
            hotkey   = hotkey,
            name     = name,
            count    = count,
            cooldown = cooldown,
            idx      = i,
        }
        InitButtonState(state.previewButtons[i])
    end

    state.ticker = CreateFrame("Frame", nil, host)
    state.ticker:SetScript("OnUpdate", function(_, elapsed)
        for _, pb in ipairs(state.previewButtons) do
            AdvanceButton(pb, elapsed)
        end
        AdvanceGlowOwner(elapsed)
        AdvanceChargeOwner(elapsed)
    end)
end

function ActionBarsPreviewDriver.Refresh()
    if not state.host or #state.previewButtons == 0 then return end

    local settings, barDB = GetPreviewEffectiveSettings(state.selectedBar)
    settings = settings or {}

    local layout = barDB and barDB.ownedLayout or {}
    local requestedVisible = math.max(1, math.min(layout.iconCount or MAX_PREVIEW_BUTTONS, MAX_PREVIEW_BUTTONS))
    local previewSlots = {}
    local hasAnyTexture = false

    for i = 1, requestedVisible do
        local sourceButton = GetPreviewSourceButton(state.selectedBar, i)
        local slot = GetPreviewSlot(state.selectedBar, i)
        local tex = GetPreviewDisplayedTexture(slot, sourceButton)
        if tex then
            hasAnyTexture = true
        end

        previewSlots[i] = {
            index = i,
            slot = slot,
            sourceButton = sourceButton,
            texture = tex,
            hiddenEmpty = settings.hideEmptySlots and not tex,
        }
    end

    -- Keep one placeholder visible on completely empty bars so the tile
    -- preview does not disappear while tuning layout settings.
    if not hasAnyTexture and previewSlots[1] then
        previewSlots[1].hiddenEmpty = false
    end

    local visibleCount = requestedVisible
    local buttonSize = math.max(20, layout.buttonSize or 30)
    local buttonSpacing = layout.buttonSpacing or 0
    local columns = math.max(1, math.min(layout.columns or visibleCount, visibleCount))
    local isVertical = layout.orientation == "vertical"
    local growLeft = layout.growLeft == true
    local growUp = layout.growUp == true
    local xStep = buttonSize + buttonSpacing
    local yStep = buttonSize + buttonSpacing
    local positions = {}
    local minX, maxX, minY, maxY

    for i = 1, visibleCount do
        local primary = (i - 1) % columns
        local secondary = math.floor((i - 1) / columns)
        local col = isVertical and secondary or primary
        local row = isVertical and primary or secondary
        local x = col * xStep
        local y = row * yStep

        if growLeft then
            x = -x
        end
        if not growUp then
            y = -y
        end

        positions[i] = { x = x, y = y }
        minX = (not minX or x < minX) and x or minX
        maxX = (not maxX or x > maxX) and x or maxX
        minY = (not minY or y < minY) and y or minY
        maxY = (not maxY or y > maxY) and y or maxY
    end

    local centerX = ((minX or 0) + (maxX or 0)) / 2
    local centerY = ((minY or 0) + (maxY or 0)) / 2
    local skinEnabled = settings.skinEnabled ~= false
    local zoom = skinEnabled and (settings.iconZoom or 0.05) or 0
    local showBackdrop = skinEnabled and settings.showBackdrop ~= false
    local backdropAlpha = settings.backdropAlpha or 0.2
    local showGloss = skinEnabled and settings.showGloss ~= false
    local glossAlpha = settings.glossAlpha or 0.3
    local showBorders = skinEnabled and settings.showBorders ~= false
    local rangeColor = settings.rangeColor or { 0.8, 0.1, 0.1, 1 }
    local usabColor = settings.usabilityColor or { 0.4, 0.4, 0.4, 1 }
    local manaColor = settings.manaColor or { 0.5, 0.5, 1.0, 1 }
    local fontPath, outline = GetPreviewFontSettings()
    local hasVisibleKeybind = false

    for i = 1, visibleCount do
        local slotInfo = previewSlots[i]
        if slotInfo then
            slotInfo.binding = GetPreviewBindingText(state.selectedBar, slotInfo.index, slotInfo.sourceButton)
            slotInfo.macro = GetPreviewMacroText(slotInfo.slot, slotInfo.sourceButton)
            slotInfo.count = GetPreviewCountText(slotInfo.slot, slotInfo.sourceButton)
            hasVisibleKeybind = hasVisibleKeybind or (not slotInfo.hiddenEmpty and HasPreviewTextValue(slotInfo.binding))
        end
    end

    if settings.showKeybinds and not hasVisibleKeybind then
        for i = 1, visibleCount do
            local slotInfo = previewSlots[i]
            if slotInfo and slotInfo.texture and not HasPreviewTextValue(slotInfo.binding) then
                slotInfo.binding = SAMPLE_PREVIEW_KEYBINDS[i] or SAMPLE_PREVIEW_KEYBINDS[((i - 1) % #SAMPLE_PREVIEW_KEYBINDS) + 1]
            end
        end
    end

    for i = 1, #state.previewButtons do
        local pb = state.previewButtons[i]
        local slotInfo = previewSlots[i]

        if not slotInfo then
            pb.frame:Hide()
            pb.hotkey:Hide()
            pb.name:Hide()
            pb.count:Hide()
        else
            local pos = positions[i]
            local tex = slotInfo.texture
            pb.frame:SetSize(buttonSize, buttonSize)
            pb.frame:ClearAllPoints()
            pb.frame:SetPoint("CENTER", state.previewHost, "CENTER", pos.x - centerX, pos.y - centerY)

            if slotInfo.hiddenEmpty then
                pb.frame:Hide()
                pb.hotkey:Hide()
                pb.name:Hide()
                pb.count:Hide()
            else
                pb.frame:Show()

                if tex then
                    pb.icon:SetTexture(tex)
                    pb.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
                    pb.icon:Show()

                    local isUsable, notEnoughMana, inRange = true, false, true
                    if IsUsableAction and slotInfo.slot then
                        isUsable, notEnoughMana = IsUsableAction(slotInfo.slot)
                    end
                    if IsActionInRange and slotInfo.slot then
                        local rangeState = IsActionInRange(slotInfo.slot)
                        inRange = not (rangeState == false or rangeState == 0)
                    end

                    if settings.rangeIndicator and not inRange then
                        pb.icon:SetVertexColor(rangeColor[1], rangeColor[2], rangeColor[3], 1)
                    elseif settings.usabilityIndicator and notEnoughMana then
                        pb.icon:SetVertexColor(manaColor[1], manaColor[2], manaColor[3], 1)
                    elseif settings.usabilityIndicator and not isUsable then
                        pb.icon:SetVertexColor(usabColor[1], usabColor[2], usabColor[3], 1)
                    else
                        pb.icon:SetVertexColor(1, 1, 1, 1)
                    end
                    pb.icon:SetAlpha(1)

                    -- Record tint-active state for the cycle's push_flash phase
                    -- (push_flash skips when a tint is already coloring the icon).
                    local bs = state.buttonState[pb.frame]
                    if bs then
                        bs.tintActive = (settings.rangeIndicator and not inRange)
                                      or (settings.usabilityIndicator and (notEnoughMana or not isUsable))
                                      or false
                    end
                else
                    pb.icon:SetTexture(nil)
                    pb.icon:SetTexCoord(0, 1, 0, 1)
                    pb.icon:SetVertexColor(1, 1, 1, 1)
                    pb.icon:SetAlpha(0)
                    pb.icon:Hide()
                end

                if showBackdrop then
                    pb.backdrop:SetAlpha(backdropAlpha)
                    pb.backdrop:Show()
                else
                    pb.backdrop:Hide()
                end

                if showBorders then
                    pb.normal:Show()
                else
                    pb.normal:Hide()
                end

                if showGloss then
                    pb.gloss:SetVertexColor(1, 1, 1, glossAlpha)
                    pb.gloss:Show()
                else
                    pb.gloss:Hide()
                end

                if not skinEnabled then
                    pb.backdrop:Hide()
                    pb.normal:Hide()
                    pb.gloss:Hide()
                    pb.icon:SetTexCoord(0, 1, 0, 1)
                end

                local bindingText = slotInfo.binding
                if settings.hideEmptyKeybinds and not tex then
                    bindingText = nil
                end

                SetPreviewTextStyle(
                    pb.hotkey, pb.frame, settings.showKeybinds and bindingText or nil,
                    fontPath, outline, settings.keybindFontSize or 11, settings.keybindColor,
                    settings.keybindAnchor or "TOPRIGHT",
                    settings.keybindOffsetX or 0, settings.keybindOffsetY or 0
                )
                SetPreviewTextStyle(
                    pb.name, pb.frame, settings.showMacroNames and slotInfo.macro or nil,
                    fontPath, outline, settings.macroNameFontSize or 10, settings.macroNameColor,
                    settings.macroNameAnchor or "BOTTOM",
                    settings.macroNameOffsetX or 0, settings.macroNameOffsetY or 0
                )
                SetPreviewTextStyle(
                    pb.count, pb.frame, settings.showCounts and slotInfo.count or nil,
                    fontPath, outline, settings.countFontSize or 14, settings.countColor,
                    settings.countAnchor or "BOTTOMRIGHT",
                    settings.countOffsetX or 0, settings.countOffsetY or 0
                )
                SetPreviewCooldownTextStyle(pb.cooldown, pb.frame, settings, fontPath, outline)
            end
        end
    end
end

function ActionBarsPreviewDriver.SetSelectedBar(barKey)
    if not barKey then return end
    state.selectedBar = barKey

    -- Bar changed → reset all per-button cycle state (different bar, different spells).
    state.buttonState = {}
    for _, pb in ipairs(state.previewButtons) do
        InitButtonState(pb)
    end
    state.glowOwnerIdx   = 1
    state.glowOwnerT     = 0
    state.chargeOwnerIdx = 1
    state.chargeOwnerT   = 0

    if ActionBarsPreviewDriver.Refresh then
        ActionBarsPreviewDriver.Refresh()
    end
end

function ActionBarsPreviewDriver.Teardown()
    for _, pb in ipairs(state.previewButtons) do
        StopGlow(pb)
        if pb.cooldown then pb.cooldown:Clear(); pb.cooldown:Hide() end
    end
    if state.ticker then state.ticker:SetScript("OnUpdate", nil) end
    state.ticker = nil  -- clear so Build's `if state.ticker then return end` guard lets it rebuild
    state.previewButtons = {}
    state.buttonState    = {}
    state.glowOwnerIdx   = 1
    state.glowOwnerT     = 0
    state.chargeOwnerIdx = 1
    state.chargeOwnerT   = 0
end

function ActionBarsPreviewDriver.IsPreviewable(barKey)
    return BAR_OFFSETS[barKey] ~= nil
end
