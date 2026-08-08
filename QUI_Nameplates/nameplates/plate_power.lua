local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local UIKit = ns.UIKit
local QUICore = ns.Addon

local type = type
local pcall = pcall
local CreateFrame = CreateFrame
local GetTime = GetTime
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetRuneCooldown = GetRuneCooldown
local GetShapeshiftFormID = GetShapeshiftFormID

local NPPower = {}
NP.Power = NPPower

local WHITE8X8 = "Interface\\Buttons\\WHITE8x8"
local MAX_PIPS = 10
local CAT_FORM_ID = 1

local CLASS_POWER = {
    ROGUE       = { type = Enum and Enum.PowerType and Enum.PowerType.ComboPoints },
    DRUID       = { type = Enum and Enum.PowerType and Enum.PowerType.ComboPoints, requiresCatForm = true },
    PALADIN     = { type = Enum and Enum.PowerType and Enum.PowerType.HolyPower },
    MONK        = { type = Enum and Enum.PowerType and Enum.PowerType.Chi },
    WARLOCK     = { type = Enum and Enum.PowerType and Enum.PowerType.SoulShards },
    MAGE        = { type = Enum and Enum.PowerType and Enum.PowerType.ArcaneCharges },
    EVOKER      = { type = Enum and Enum.PowerType and Enum.PowerType.Essence },
    DEATHKNIGHT = { runes = true },
}

function NPPower.GetClassPowerSpec(classToken)
    if type(classToken) ~= "string" then return nil end
    return CLASS_POWER[classToken]
end

function NPPower.ResolvePips(cur, max)
    if type(cur) ~= "number" or type(max) ~= "number" then return nil end
    if max <= 0 or max > MAX_PIPS then return nil end
    if cur < 0 then cur = 0 end
    if cur > max then cur = max end
    return cur, max
end

local PREVIEW_FALLBACK_FILLED = 3
local PREVIEW_FALLBACK_COUNT = 5

local live = nil
local previewRows = setmetatable({}, { __mode = "k" })
local attachedPlate = nil
local playerClass = nil

local function GetPowerSettings(plate)
    local s = NP.GetTypeSettings(plate)
    return (s and s.power) or {}
end

local function ResolvePlayerClass()
    if playerClass then return playerClass end
    if type(UnitClass) ~= "function" then return nil end
    local ok, _, token = pcall(UnitClass, "player")
    playerClass = ok and NP.Plain(token, "string") or nil
    return playerClass
end

local function NewInstance(parent)
    local inst = { pips = {} }
    inst.row = CreateFrame("Frame", nil, parent or UIParent)
    inst.row:SetSize(1, 1)
    inst.row:Hide()
    for i = 1, MAX_PIPS do
        local pip = inst.row:CreateTexture(nil, "OVERLAY", nil, 4)
        pip:SetTexture(WHITE8X8)
        pip:Hide()
        inst.pips[i] = pip
    end
    return inst
end

local function EnsureRow()
    if not live then live = NewInstance(UIParent) end
    return live
end

local function ClassColor()
    local token = ResolvePlayerClass()
    local colors = _G.RAID_CLASS_COLORS
    local c = token and colors and colors[token]
    if c then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

local function LayoutPips(inst, count, power)
    local size = power.size or 10
    local spacing = power.spacing or 3
    if inst._layoutCount == count and inst._layoutSize == size
        and inst._layoutSpacing == spacing then
        return
    end
    inst._layoutCount = count
    inst._layoutSize = size
    inst._layoutSpacing = spacing
    local total = (count * size) + ((count - 1) * spacing)
    QUICore:SetPixelPerfectSize(inst.row, total, size)
    for i = 1, MAX_PIPS do
        local pip = inst.pips[i]
        pip:ClearAllPoints()
        if i <= count then
            QUICore:SetPixelPerfectSize(pip, size, size)
            pip:SetPoint("LEFT", inst.row, "LEFT",
                QUICore:Pixels((i - 1) * (size + spacing), inst.row), 0)
            pip:Show()
        else
            pip:Hide()
        end
    end
end

local function PaintPips(inst, filled, count)
    local r, g, b = ClassColor()
    for i = 1, count do
        local pip = inst.pips[i]
        if i <= filled then
            pip:SetVertexColor(r, g, b, 1)
        else
            pip:SetVertexColor(0.15, 0.15, 0.15, 0.9)
        end
    end
end

local function AnchorRow(inst, plate, power)
    local anchorTo = plate.castBar or plate.healthBar
    if not anchorTo then return false end
    inst._layoutCount = nil
    inst.row:SetParent(plate)
    inst.row:ClearAllPoints()
    inst.row:SetPoint("TOP", anchorTo, "BOTTOM", 0,
        QUICore:Pixels(power.offsetY or -2, plate))
    return true
end

local function ReadyRuneCount()
    if type(GetRuneCooldown) ~= "function" then return nil end
    local ready = 0
    for i = 1, 6 do
        local ok, start, duration = pcall(GetRuneCooldown, i)
        start = ok and NP.Plain(start, "number") or nil
        duration = ok and NP.Plain(duration, "number") or nil
        if start ~= nil then
            if start == 0 or (duration ~= nil and (start + duration) <= GetTime()) then
                ready = ready + 1
            end
        end
    end
    return ready, 6
end

local function ReadCurrentPips()
    local token = ResolvePlayerClass()
    local spec = NPPower.GetClassPowerSpec(token)
    if not spec then return nil end

    if spec.runes then
        local ready, total = ReadyRuneCount()
        return NPPower.ResolvePips(ready, total)
    end

    if spec.requiresCatForm then
        if type(GetShapeshiftFormID) ~= "function" then return nil end
        local okForm, form = pcall(GetShapeshiftFormID)
        if not (okForm and NP.Plain(form, "number") == CAT_FORM_ID) then return nil end
    end

    if spec.type == nil then return nil end
    local okCur, cur = pcall(UnitPower, "player", spec.type)
    local okMax, max = pcall(UnitPowerMax, "player", spec.type)
    cur = okCur and NP.Plain(cur, "number") or nil
    max = okMax and NP.Plain(max, "number") or nil
    return NPPower.ResolvePips(cur, max)
end

local function HideRow()
    if live and live.row then live.row:Hide() end
end

function NPPower.Update()
    if not attachedPlate then
        HideRow()
        return
    end
    local power = GetPowerSettings(attachedPlate)
    if power.enabled ~= true then
        HideRow()
        return
    end
    local filled, count = ReadCurrentPips()
    if filled == nil then
        HideRow()
        return
    end
    local inst = EnsureRow()
    LayoutPips(inst, count, power)
    PaintPips(inst, filled, count)
    inst.row:Show()
end

function NPPower.RenderPreview(plate)
    if not plate then return end
    local power = GetPowerSettings(plate)
    local inst = previewRows[plate]

    if power.enabled ~= true then
        if inst and inst.row then inst.row:Hide() end
        return
    end

    if not inst then
        inst = NewInstance(plate)
        previewRows[plate] = inst
        plate.npPowerPreviewRow = inst.row
    end

    local filled, count = ReadCurrentPips()
    if filled == nil then
        filled, count = PREVIEW_FALLBACK_FILLED, PREVIEW_FALLBACK_COUNT
    end

    if not AnchorRow(inst, plate, power) then
        inst.row:Hide()
        return
    end
    LayoutPips(inst, count, power)
    PaintPips(inst, filled, count)
    inst.row:Show()
end

function NPPower.Detach(plate)
    if plate ~= nil and plate ~= attachedPlate then return end
    attachedPlate = nil
    HideRow()
end

function NPPower.AttachToTarget()
    local plate = NP.Extras and NP.Extras.ResolvePlateFor and NP.Extras.ResolvePlateFor("target")
    if not plate or not plate.unit then
        attachedPlate = nil
        HideRow()
        return
    end
    local power = GetPowerSettings(plate)
    if power.enabled ~= true then
        attachedPlate = nil
        HideRow()
        return
    end
    attachedPlate = plate
    local inst = EnsureRow()
    AnchorRow(inst, plate, power)
    NPPower.Update()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
eventFrame:RegisterUnitEvent("UNIT_MAXPOWER", "player")
eventFrame:RegisterEvent("RUNE_POWER_UPDATE")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        playerClass = nil
    end
    if not NP.IsEnabled() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        NPPower.AttachToTarget()
        return
    end
    if attachedPlate then
        NPPower.Update()
    else
        HideRow()
    end
end)
