-- QUI_Reminders/reminders/callout.lua -- the on-screen "press this" display.
--
-- One frame, QUI_RemindersCallout: a skinned icon with a text line on the side
-- the user picked. It is movable in Layout Mode and anchorable like every other
-- QUI frame, previews from the settings page, and fades itself out once the
-- linger time is up. It shows what the engine hands it and decides nothing.
local _, ns = ...

local Helpers = ns.Helpers

local Callout = {}
ns.RemindersCallout = Callout

local FRAME_NAME = "QUI_RemindersCallout"
local ANCHOR_KEY = "remindersCallout"
local FADE_SECONDS = 0.35
local DEFAULT_ICON_SIZE = 56
local DEFAULT_TEXT_SIZE = 18
local TEXT_GAP = 6
local TEXT_WIDTH = 180
local FALLBACK_ICON = 134400

local GetDB = Helpers.CreateDBGetter("reminders")

local frame
local hideAt
local fading = false
local previewActive = false

local function DisplaySettings()
    local db = GetDB()
    local d = db and db.display
    if type(d) ~= "table" then d = {} end
    return d, db
end

local function Position()
    if not frame then return end
    if _G.QUI_HasFrameAnchor and _G.QUI_HasFrameAnchor(ANCHOR_KEY) then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
end

local function StopIconGlow()
    if frame and ns.IconGlow and ns.IconGlow.Stop then
        ns.IconGlow.Stop(frame.iconFrame)
    end
end

local function StartIconGlow()
    if not (frame and ns.IconGlow and ns.IconGlow.Start) then return end
    local d = DisplaySettings()
    if d.glow == false then return end
    local color = d.glowColor
    if type(color) ~= "table" then color = { 1, 0.85, 0.2, 1 } end
    ns.IconGlow.Start(frame.iconFrame, {
        source = "QUI", style = "Pixel", color = color,
        lines = 8, frequency = 0.25, thickness = 2,
    })
end

local function OnUpdate(_, elapsed)
    if previewActive or not hideAt then return end
    local now = GetTime()
    if now < hideAt then return end
    fading = true
    local alpha = frame:GetAlpha() - (elapsed / FADE_SECONDS)
    if alpha <= 0 then
        Callout.Hide()
        return
    end
    frame:SetAlpha(alpha)
end

local function Register()
    if _G.QUI_RegisterFrameResolver then
        _G.QUI_RegisterFrameResolver(ANCHOR_KEY, {
            displayName = ns.L["Reminder Callout"],
            category = "QoL",
            order = 17,
            resolver = function() return _G[FRAME_NAME] end,
        })
    end
    local um = ns.QUI_LayoutMode
    if um and type(um.RegisterElement) == "function" then
        um:RegisterElement({
            key = ANCHOR_KEY,
            label = ns.L["Reminder Callout"],
            group = ns.L["QoL"],
            order = 9.5,
            frame = FRAME_NAME,
            dbGetter = function() return GetDB() end,
            enabledField = "enabled",
            refresh = "QUI_RefreshReminders",
            previewOn = function() Callout.SetPreview(true) end,
            previewOff = function() Callout.SetPreview(false) end,
        })
    end
end

local function Build()
    if frame then return frame end
    if type(CreateFrame) ~= "function" then return nil end
    frame = CreateFrame("Frame", FRAME_NAME, UIParent)
    frame:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    local iconFrame = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    iconFrame:SetSize(DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
    local SkinBase = ns.SkinBase
    if SkinBase and SkinBase.CreateBackdrop then
        SkinBase.CreateBackdrop(iconFrame, 0, 0, 0, 1, 0, 0, 0, 0)
    end
    local tex = iconFrame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetJustifyH("CENTER")
    text:SetWordWrap(false)

    frame.iconFrame = iconFrame
    frame.iconTex = tex
    frame.text = text
    frame:SetScript("OnUpdate", OnUpdate)

    Register()
    Position()
    if _G.QUI_ApplyFrameAnchor then _G.QUI_ApplyFrameAnchor(ANCHOR_KEY) end
    return frame
end

function Callout.GetFrame()
    return Build()
end

-- Re-read display settings: sizes, font, which side the text sits on.
function Callout.Refresh()
    local f = Build()
    if not f then return end
    local d = DisplaySettings()
    local size = tonumber(d.iconSize) or DEFAULT_ICON_SIZE
    local textSize = tonumber(d.textSize) or DEFAULT_TEXT_SIZE
    local side = d.textSide or "BOTTOM"
    local showIcon = d.showIcon ~= false
    local showText = d.showText ~= false

    f.iconFrame:SetSize(size, size)
    f.iconFrame:SetShown(showIcon)
    if Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(f.text, Helpers.GetGeneralFont(), textSize, Helpers.GetGeneralFontOutline())
    end
    local color = d.textColor
    if type(color) == "table" then
        f.text:SetTextColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    else
        f.text:SetTextColor(1, 1, 1, 1)
    end
    f.text:SetShown(showText)

    local iconW = showIcon and size or 0
    local textW = showText and TEXT_WIDTH or 0
    local textH = showText and (textSize + 4) or 0
    local width, height
    f.iconFrame:ClearAllPoints()
    f.text:ClearAllPoints()
    f.text:SetWidth(TEXT_WIDTH)
    if side == "LEFT" or side == "RIGHT" then
        width = iconW + (showText and (TEXT_GAP + textW) or 0)
        height = math.max(iconW, textH, 1)
        if side == "LEFT" then
            f.iconFrame:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            f.text:SetPoint("RIGHT", f.iconFrame, "LEFT", -TEXT_GAP, 0)
            f.text:SetJustifyH("RIGHT")
        else
            f.iconFrame:SetPoint("LEFT", f, "LEFT", 0, 0)
            f.text:SetPoint("LEFT", f.iconFrame, "RIGHT", TEXT_GAP, 0)
            f.text:SetJustifyH("LEFT")
        end
    else
        width = math.max(iconW, textW, 1)
        height = iconW + (showText and (TEXT_GAP + textH) or 0)
        f.text:SetJustifyH("CENTER")
        if side == "TOP" then
            f.iconFrame:SetPoint("BOTTOM", f, "BOTTOM", 0, 0)
            f.text:SetPoint("BOTTOM", f.iconFrame, "TOP", 0, TEXT_GAP)
        else
            f.iconFrame:SetPoint("TOP", f, "TOP", 0, 0)
            f.text:SetPoint("TOP", f.iconFrame, "BOTTOM", 0, -TEXT_GAP)
        end
    end
    f:SetSize(math.max(width, 1), math.max(height, 1))
    Position()
end

-- entry = { name, icon } as produced by RemindersDefensives.Describe.
-- opts.duration is how long it stays before fading; opts.text overrides the name.
function Callout.Show(entry, opts)
    local f = Build()
    if not f or type(entry) ~= "table" then return false end
    Callout.Refresh()
    f.iconTex:SetTexture(entry.icon or FALLBACK_ICON)
    f.text:SetText((opts and opts.text) or entry.name or "")
    f:SetAlpha(1)
    f:Show()
    fading = false
    local linger = tonumber(opts and opts.duration) or 4
    hideAt = GetTime() + math.max(linger, 0.5)
    StartIconGlow()
    return true
end

function Callout.Hide()
    hideAt = nil
    fading = false
    if not frame then return end
    StopIconGlow()
    frame:Hide()
    frame:SetAlpha(1)
end

function Callout.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Callout.IsFading()
    return fading
end

-- Layout Mode / settings preview: a sample callout that stays until turned off.
local function PreviewEntry()
    local D = ns.RemindersDefensives
    local db = GetDB()
    local specID = D and D.PlayerSpecID and D.PlayerSpecID()
    local list = db and db.priorities and specID and db.priorities[specID]
    if D and type(list) == "table" then
        for i = 1, #list do
            local entry = D.Describe(list[i])
            if entry then return entry end
        end
    end
    return { name = ns.L["Defensive"], icon = FALLBACK_ICON }
end

function Callout.SetPreview(on)
    previewActive = on and true or false
    if previewActive then
        local f = Build()
        if not f then return end
        Callout.Refresh()
        local entry = PreviewEntry()
        f.iconTex:SetTexture(entry.icon or FALLBACK_ICON)
        f.text:SetText(entry.name or "")
        f:SetAlpha(1)
        f:Show()
        hideAt = nil
        fading = false
        StartIconGlow()
    else
        Callout.Hide()
    end
end

function Callout.IsPreviewActive()
    return previewActive
end

function Callout.TogglePreview()
    Callout.SetPreview(not previewActive)
    return previewActive
end

Callout.ANCHOR_KEY = ANCHOR_KEY
Callout.FRAME_NAME = FRAME_NAME
