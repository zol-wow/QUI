local ADDON_NAME, ns = ...

local Helpers = ns.Helpers
local LSM = ns.LSM
local GetDB = Helpers.CreateDBGetter("quiGroupFrames")
local TruncateUTF8 = Helpers.TruncateUTF8
local ApplyFontWithFallback = Helpers.ApplyFontWithFallback

local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local RegisterUnitWatch = RegisterUnitWatch
local UnregisterUnitWatch = UnregisterUnitWatch
local UnitName = UnitName
local UnitClass = UnitClass
local UnitHealthPercent = UnitHealthPercent
local issecretvalue = _G.issecretvalue
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local CurveConstants = CurveConstants
local C_Timer = C_Timer

local MAX_PARTY = 4
local TICK_INTERVAL = 0.2
local FALLBACK_COLOR = { 0.6, 0.6, 0.6 }

local PT = {
    frames = {},
    pendingAnchor = false,
    ticker = nil,
    eventFrame = nil,
    lastGF = nil,
}
ns.QUI_GroupFramePartyTargets = PT

local SetTargetWatch

local function GetConfig()
    local db = GetDB()
    if not db or not db.enabled then return nil end
    local party = db.party
    return party and party.targetFrames, party
end

local function ResolveFont(general)
    local fontName = general and general.font or "Quazii"
    return LSM:Fetch("font", fontName) or STANDARD_TEXT_FONT
end

local function ResolveTexture(general)
    local texName = general and general.texture or "Quazii v5"
    return LSM:Fetch("statusbar", texName)
end

local function CreateCompanion(index)
    local frame = CreateFrame("Button", nil, UIParent,
        "SecureUnitButtonTemplate, BackdropTemplate")
    frame:Hide()

    local unit = "party" .. index .. "target"
    frame.ptUnit = unit
    frame:SetAttribute("unit", unit)
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")
    frame:RegisterForClicks("AnyUp")

    frame._quiBackdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    }
    frame:SetBackdrop(frame._quiBackdrop)
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    local hb = CreateFrame("StatusBar", nil, frame)
    hb:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    hb:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    hb:SetMinMaxValues(0, 100)
    hb:SetValue(100)
    hb:EnableMouse(false)
    frame.healthBar = hb

    local name = hb:CreateFontString(nil, "OVERLAY")
    name:SetPoint("LEFT", hb, "LEFT", 3, 0)
    name:SetPoint("RIGHT", hb, "RIGHT", -3, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetTextColor(1, 1, 1, 1)
    frame.nameText = name

    return frame
end

local function EnsureWatched(frame)
    if not frame._ptWatched then
        RegisterUnitWatch(frame)
        frame._ptWatched = true
    end
end

local function StyleCompanion(frame, cfg, general)
    local w = cfg.width or 120
    local h = cfg.height or 24
    frame:SetSize(w, h)

    local tex = ResolveTexture(general)
    if tex then frame.healthBar:SetStatusBarTexture(tex) end

    local fontPath = ResolveFont(general)
    local fontSize = (general and general.fontSize) or 11
    local outline = (general and general.fontOutline) or "OUTLINE"
    ApplyFontWithFallback(frame.nameText, fontPath, fontSize, outline)
    frame.nameText:SetShown(cfg.showName ~= false)
end

local function RenderCompanion(frame)
    local unit = frame.ptUnit
    if not unit then return end

    frame.healthBar:SetValue(UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))

    frame.nameText:SetText(TruncateUTF8(UnitName(unit), 12))

    local r, g, b = FALLBACK_COLOR[1], FALLBACK_COLOR[2], FALLBACK_COLOR[3]
    local _, class = UnitClass(unit)
    -- @secret-policy: collapse-only — fixed fallback color
    if issecretvalue and issecretvalue(class) then class = nil end
    if class then
        local cc = RAID_CLASS_COLORS[class]
        if cc then r, g, b = cc.r, cc.g, cc.b end
    end
    if r ~= frame._lr or g ~= frame._lg or b ~= frame._lb then
        frame._lr, frame._lg, frame._lb = r, g, b
        frame.healthBar:SetStatusBarColor(r, g, b, 1)
    end
end

local function Tick()
    for i = 1, MAX_PARTY do
        local f = PT.frames[i]
        if f and f:IsShown() then
            RenderCompanion(f)
        end
    end
end

local function StartTicker()
    if not PT.ticker then
        PT.ticker = C_Timer.NewTicker(TICK_INTERVAL, Tick)
    end
end

local function StopTicker()
    if PT.ticker then
        PT.ticker:Cancel()
        PT.ticker = nil
    end
end

local function ApplyAnchor(frame, memberFrame, cfg)
    local gap = cfg.anchorGap or 2
    local side = cfg.anchorTo or "BOTTOM"
    frame:ClearAllPoints()
    if side == "TOP" then
        frame:SetPoint("BOTTOM", memberFrame, "TOP", 0, gap)
    elseif side == "RIGHT" then
        frame:SetPoint("LEFT", memberFrame, "RIGHT", gap, 0)
    elseif side == "LEFT" then
        frame:SetPoint("RIGHT", memberFrame, "LEFT", -gap, 0)
    else
        frame:SetPoint("TOP", memberFrame, "BOTTOM", 0, -gap)
    end
end

function PT:Reanchor(QUI_GF)
    if QUI_GF then self.lastGF = QUI_GF end
    QUI_GF = QUI_GF or self.lastGF
    local cfg = GetConfig()
    if not cfg or not cfg.enabled or not QUI_GF then return end

    if InCombatLockdown() then
        self.pendingAnchor = true
        return
    end
    self.pendingAnchor = false

    local map = QUI_GF.unitFrameMap
    for i = 1, MAX_PARTY do
        local frame = self.frames[i]
        if frame then
            local list = map and map["party" .. i]
            local memberFrame = list and list[1]
            if memberFrame then
                ApplyAnchor(frame, memberFrame, cfg)
            else
                frame:ClearAllPoints()
                frame:SetPoint("CENTER", UIParent, "CENTER")
            end
        end
    end
end

function PT:Configure(QUI_GF)
    if QUI_GF then self.lastGF = QUI_GF end
    local cfg, party = GetConfig()
    local general = party and party.general

    if not cfg or not cfg.enabled then
        self:Teardown()
        return
    end

    if InCombatLockdown() then
        self.pendingAnchor = true
        return
    end

    for i = 1, MAX_PARTY do
        local frame = self.frames[i]
        if not frame then
            frame = CreateCompanion(i)
            self.frames[i] = frame
        end
        StyleCompanion(frame, cfg, general)
    end

    self:Reanchor(QUI_GF)
    for i = 1, MAX_PARTY do
        EnsureWatched(self.frames[i])
    end
    SetTargetWatch(true)
    StartTicker()
end

function PT:Teardown()
    StopTicker()
    SetTargetWatch(false)
    if InCombatLockdown() then
        self.pendingAnchor = true
        return
    end
    for i = 1, MAX_PARTY do
        local frame = self.frames[i]
        if frame then
            if frame._ptWatched then
                UnregisterUnitWatch(frame)
                frame._ptWatched = false
            end
            frame:Hide()
        end
    end
end

local function OnEvent(_, event, arg1)
    if event == "PLAYER_REGEN_ENABLED" then
        if PT.pendingAnchor then
            PT.pendingAnchor = false
            PT:Configure(PT.lastGF)
        end
    elseif event == "UNIT_TARGET" then
        if type(arg1) == "string" then
            local index = arg1:match("^party(%d)$")
            index = index and tonumber(index)
            local frame = index and PT.frames[index]
            if frame and frame:IsShown() then
                RenderCompanion(frame)
            end
        end
    end
end

local function EnsureEventFrame()
    if PT.eventFrame then return end
    local ef = CreateFrame("Frame")
    ef:SetScript("OnEvent", OnEvent)
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    PT.eventFrame = ef
end

function SetTargetWatch(active)
    EnsureEventFrame()
    if active and not PT.targetWatch then
        PT.eventFrame:RegisterUnitEvent("UNIT_TARGET", "party1", "party2", "party3", "party4")
        PT.targetWatch = true
    elseif not active and PT.targetWatch then
        PT.eventFrame:UnregisterEvent("UNIT_TARGET")
        PT.targetWatch = false
    end
end

EnsureEventFrame()
