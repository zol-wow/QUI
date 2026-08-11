local ADDON_NAME, ns = ...

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local type = type
local UnitExists = UnitExists

local QUI_UF = ns.QUI_UnitFrames
if not QUI_UF then return end

local GetUnitSettings = QUI_UF._GetUnitSettings
local UpdateFrame = QUI_UF._UpdateFrame

local bossEngageFrame

local AURA_ANCHOR_FRAMEPOINT = {
    TOPLEFT     = { "BOTTOMLEFT",  "TOPLEFT",     1 },
    TOPRIGHT    = { "BOTTOMRIGHT", "TOPRIGHT",   -1 },
    BOTTOMLEFT  = { "TOPLEFT",     "BOTTOMLEFT",  1 },
    BOTTOMRIGHT = { "TOPRIGHT",    "BOTTOMRIGHT", -1 },
}

local function MapAuraAnchorToFramePoint(anchor)
    local map = AURA_ANCHOR_FRAMEPOINT[anchor]
    if not map then return nil, nil, nil end
    return map[1], map[2], map[3]
end

local AuraSkin     = (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
local AuraGlue     = ns.AuraGlue
local AuraSlots    = ns.AuraSlots
local AuraElements = ns.AuraElements
local function ResolveAuraDeps()
    AuraSkin     = AuraSkin     or (ns.Addon and ns.Addon.AuraSkin) or (_G.QUI and _G.QUI.AuraSkin)
    AuraGlue     = AuraGlue     or ns.AuraGlue
    AuraSlots    = AuraSlots    or ns.AuraSlots
    AuraElements = AuraElements or ns.AuraElements
    return AuraSkin and AuraGlue and AuraSlots and AuraElements
end

local function DefaultUnitAuraBucket()
    local E = AuraElements or ns.AuraElements
    if not E then return {} end
    local debuff = E.NewFilterStripElement("HARMFUL")
    debuff.id = "debuffs"; debuff.enabled = false
    debuff.anchor = "TOPLEFT"; debuff.growDirection = "RIGHT"
    debuff.iconSize = 22; debuff.maxIcons = 4; debuff.iconsPerRow = 0
    debuff.spacing = 2; debuff.offsetX = 0; debuff.offsetY = 0
    debuff.rightClickCancel = false
    debuff.duration = { show = false, fontSize = 10, anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    debuff.stack    = { show = true,  fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    local buff = E.NewFilterStripElement("HELPFUL")
    buff.id = "buffs"; buff.enabled = false
    buff.anchor = "BOTTOMLEFT"; buff.growDirection = "RIGHT"
    buff.iconSize = 22; buff.maxIcons = 4; buff.iconsPerRow = 0
    buff.spacing = 2; buff.offsetX = 0; buff.offsetY = 0
    buff.duration = { show = true, fontSize = 12, anchor = "CENTER", offsetX = 0, offsetY = 0, color = { 1, 1, 1, 1 } }
    buff.stack    = { show = true, fontSize = 10, anchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 1, color = { 1, 1, 1, 1 } }
    return { debuff, buff }
end

local UnitFrameAuras = ns.QUI_UnitFrameAuras or {}
ns.QUI_UnitFrameAuras = UnitFrameAuras
UnitFrameAuras.DefaultUnitAuraBucket = DefaultUnitAuraBucket

local function GetFrameAuraSettings(frame)
    if not frame then return nil end
    local unitKey = frame.unitKey or QUI_UF.GetFrameUnit(frame)
    local settings = GetUnitSettings and GetUnitSettings(unitKey)
    return settings and settings.auras or nil
end

local _activeElems = {}
local function ResolveContainerElements(frame)
    for i = #_activeElems, 1, -1 do _activeElems[i] = nil end
    local auras = GetFrameAuraSettings(frame)
    if not auras then return _activeElems end
    AuraElements = AuraElements or ns.AuraElements
    if not AuraElements then return _activeElems end
    AuraElements.EnsureSeeded(auras, DefaultUnitAuraBucket)
    local elements = AuraElements.ActiveElementsForSpec(auras, nil)
    for i = 1, #elements do
        local e = elements[i]
        if e.mode == "filterStrip"
            or (e.mode == "tracked" and e.displayType ~= "healthTint" and e.displayType ~= "border") then
            _activeElems[#_activeElems + 1] = e
        end
    end
    return _activeElems
end

local function ElementProfileFor(element)
    local attachPoint = (MapAuraAnchorToFramePoint(element.anchor or "TOPLEFT"))
    return AuraGlue.ElementProfile(element, {
        attachPoint = attachPoint,
        wrap = ((attachPoint or ""):find("BOTTOM", 1, true) and "UP" or "DOWN"),
    })
end

local function AnchorElementContainer(container, frame, element)
    local _, framePoint, borderOffsetX = MapAuraAnchorToFramePoint(element.anchor or "TOPLEFT")
    framePoint = framePoint or "TOPLEFT"
    local profile = ElementProfileFor(element)
    container:ClearAllPoints()
    container:SetPoint(AuraSkin.LayoutAnchor(profile), frame, framePoint,
        (borderOffsetX or 0) + (element.offsetX or 0), (element.offsetY or 0))
end

local function ApplyElementPass(frame, allowCreate)
    if not frame or not QUI_UF.GetFrameUnit(frame) then return end
    if not ResolveAuraDeps() then return end
    local AuraSurface = ns.AuraSurface
    if not AuraSurface then return end

    local unitKey = frame.unitKey or QUI_UF.GetFrameUnit(frame)
    local elems = ResolveContainerElements(frame)

    local previewKey = unitKey
    if type(previewKey) == "string" and previewKey:match("^boss%d+$") then previewKey = "boss" end
    local previewMode = QUI_UF.auraPreviewMode
    local buffPreviewActive = previewMode and previewMode[previewKey .. "_buff"]
    local debuffPreviewActive = previewMode and previewMode[previewKey .. "_debuff"]

    AuraSurface.ApplyElementPass(frame, elems, {
        unit = QUI_UF.GetFrameUnit(frame),
        allowCreate = allowCreate == true,
        cancelEligible = (unitKey == "player"),
        profileFor = ElementProfileFor,
        anchorContainer = function(container, host, element)
            AnchorElementContainer(container, host, element)
        end,
        skip = function(element)
            local isDebuff = (element.auraType == "HARMFUL")
            return (isDebuff and debuffPreviewActive)
                or ((not isDebuff) and buffPreviewActive) or false
        end,
        onIncomplete = function(host)
            AuraGlue.QueueRegenWork(host, function(f) ApplyElementPass(f, true) end)
        end,
    })
end

local function ApplyContainerConfig(frame)
    ApplyElementPass(frame, true)
end
QUI_UF.ApplyContainerConfig = ApplyContainerConfig

local function UpdateAuras(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) then return end
    if InCombatLockdown() then
        local ok = ns.SafeCall("best-effort-style", ApplyElementPass, frame, true)
        if not ok then
            AuraGlue = AuraGlue or ns.AuraGlue
            if AuraGlue then
                AuraGlue.QueueRegenWork(frame, function(f) ApplyElementPass(f, true) end)
            end
        end
        return
    end
    ApplyElementPass(frame, true)
end
QUI_UF.UpdateAuras = UpdateAuras

local function RefreshAllAuraContainers()
    local frames = QUI_UF and QUI_UF.frames
    if not frames then return end
    for _, frame in pairs(frames) do
        UpdateAuras(frame)
    end
end
ns.QUI_RefreshUnitFrameAuras = RefreshAllAuraContainers

local function SuppressContainerForPreview(frame)
    if not frame then return end
    UpdateAuras(frame)
end

local function PreviewPolarityFlags(unitKey)
    local key = unitKey
    if type(key) == "string" and key:match("^boss%d+$") then key = "boss" end
    local pm = QUI_UF.auraPreviewMode
    if not pm then return false, false end
    return pm[key .. "_buff"] == true, pm[key .. "_debuff"] == true
end

local function PreviewResolve(element)
    local _, framePoint, borderOffsetX = MapAuraAnchorToFramePoint(element.anchor or "TOPLEFT")
    return ElementProfileFor(element), framePoint or "TOPLEFT",
        (borderOffsetX or 0) + (element.offsetX or 0), (element.offsetY or 0)
end

local function RefreshAuraPreviewForFrame(frame, unitKey)
    if not frame then return end
    SuppressContainerForPreview(frame)
    local Preview = ns.AuraPreview
    if not Preview then return end
    local buffActive, debuffActive = PreviewPolarityFlags(unitKey)
    if not (buffActive or debuffActive) then
        Preview.Hide(frame)
        return
    end
    local elems = ResolveContainerElements(frame)
    Preview.Show(frame, elems, {
        resolve = PreviewResolve,
        only = function(e)
            if e.auraType == "HARMFUL" then return debuffActive end
            return buffActive
        end,
    })
end

local function RefreshBossFrameForEngage(frame)
    if not frame or not QUI_UF.GetFrameUnit(frame) then return end

    if UnitExists(QUI_UF.GetFrameUnit(frame)) then
        UpdateFrame(frame)
    end
    UpdateAuras(frame)
end

local function EnsureBossEngageFrame()
    if bossEngageFrame then return end

    bossEngageFrame = CreateFrame("Frame")
    bossEngageFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    bossEngageFrame:SetScript("OnEvent", function()
        local frames = QUI_UF.frames
        if not frames then return end

        for i = 1, 5 do
            RefreshBossFrameForEngage(frames["boss" .. i])
        end
    end)
end

local function SetupAuraTracking(frame)
    if not frame then return end

    local unit = QUI_UF.GetFrameUnit(frame)

    if unit == "target" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    elseif unit == "focus" then
        frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    elseif unit == "pet" then
        frame:RegisterUnitEvent("UNIT_PET", "player")
    elseif unit == "targettarget" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        frame:RegisterEvent("UNIT_TARGET")
    elseif unit:match("^boss%d+$") then
        EnsureBossEngageFrame()
    end

    local oldOnEvent = frame:GetScript("OnEvent")
    frame:SetScript("OnEvent", function(self, event, arg1, ...)
        if oldOnEvent then
            oldOnEvent(self, event, arg1, ...)
        end

        local frameUnit = QUI_UF.GetFrameUnit(self)
        if event == "PLAYER_TARGET_CHANGED" then
            if frameUnit == "target" or frameUnit == "targettarget" then
                UpdateAuras(self)
            end
        elseif event == "PLAYER_FOCUS_CHANGED" and frameUnit == "focus" then
            UpdateAuras(self)
        elseif event == "UNIT_PET" and frameUnit == "pet" then
            UpdateAuras(self)
        elseif event == "UNIT_TARGET" and arg1 == "target" and frameUnit == "targettarget" then
            UpdateAuras(self)
        end
    end)

    UpdateAuras(frame)

    C_Timer.After(0.2, function()
        UpdateAuras(frame)
    end)
end

QUI_UF.SetupAuraTracking = SetupAuraTracking

function QUI_UF:ShowAuraPreview(unitKey, auraType)
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = true
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame and self.previewMode[bossKey] then
                self:ShowAuraPreviewForFrame(frame, "boss", auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = true

    self:ShowAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:ShowAuraPreviewForFrame(frame, unitKey, _auraType)
    RefreshAuraPreviewForFrame(frame, unitKey)
end

function QUI_UF:HideAuraPreview(unitKey, auraType)
    if unitKey == "boss" then
        local previewKey = "boss_" .. auraType
        self.auraPreviewMode[previewKey] = false
        for i = 1, 5 do
            local bossKey = "boss" .. i
            local frame = self.frames[bossKey]
            if frame then
                self:HideAuraPreviewForFrame(frame, bossKey, auraType)
            end
        end
        return
    end

    local frame = self.frames[unitKey]
    if not frame then return end

    local previewKey = unitKey .. "_" .. auraType
    self.auraPreviewMode[previewKey] = false

    self:HideAuraPreviewForFrame(frame, unitKey, auraType)
end

function QUI_UF:HideAuraPreviewForFrame(frame, unitKey, _auraType)
    RefreshAuraPreviewForFrame(frame, unitKey)
end
