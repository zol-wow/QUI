local ADDON_NAME, ns = ...

local QUICore = ns.Addon or (QUI and QUI.QUICore)
if not QUICore then
    print("|cFFFF0000[QUI] ERROR: scaling.lua loaded before main.lua!|r")
    return
end

local format = string.format
local floor = math.floor
local ceil = math.ceil
local max = math.max
local Round = Round or function(x) return floor(x + 0.5) end
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetScreenWidth, GetScreenHeight = GetScreenWidth, GetScreenHeight

local cachedPhysicalHeight = select(2, GetPhysicalScreenSize())

function QUICore:PushPixelReference(frame)
    self._pixelRefDepth = (self._pixelRefDepth or 0) + 1
    self._pixelRef = frame or false
end

function QUICore:PopPixelReference()
    local depth = (self._pixelRefDepth or 0) - 1
    if depth <= 0 then
        depth = 0
        self._pixelRef = nil
    end
    self._pixelRefDepth = depth
end

function QUICore:GetPixelSize(frame)
    local ref = self._pixelRef
    if ref ~= nil then frame = ref or nil end

    local es
    if frame then
        local ok, val = pcall(frame.GetEffectiveScale, frame)
        if ok and not (issecretvalue and issecretvalue(val)) then es = val end
    end
    if not es then
        local ok2, val2 = pcall(UIParent.GetEffectiveScale, UIParent)
        if ok2 and not (issecretvalue and issecretvalue(val2)) then es = val2 end
    end
    if not es then return 1 end
    if es == 0 then return 1 end
    if cachedPhysicalHeight == 0 then return 1 end
    return 768 / (cachedPhysicalHeight * es)
end

function QUICore:Pixels(n, frame)
    if n == 0 then return 0 end
    return n * self:GetPixelSize(frame)
end

function QUICore:PixelRound(value, frame)
    if value == 0 then return 0 end
    local px = self:GetPixelSize(frame)
    return Round(value / px) * px
end

function QUICore:Scale(x, frame)
    return self:Pixels(x, frame)
end

function QUICore:SetPixelPerfectSize(frame, widthPixels, heightPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    if widthPixels and heightPixels then
        frame:SetSize(Round(widthPixels) * px, Round(heightPixels) * px)
    elseif widthPixels then
        frame:SetWidth(Round(widthPixels) * px)
    elseif heightPixels then
        frame:SetHeight(Round(heightPixels) * px)
    end
end

function QUICore:SetPixelPerfectHeight(frame, heightPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    frame:SetHeight(Round(heightPixels) * px)
end

function QUICore:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    local x = xPixels and Round(xPixels) * px or 0
    local y = yPixels and Round(yPixels) * px or 0
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

function QUICore:SetSnappedPoint(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    if not frame then return end
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.layoutOwnedFrames and anchoring.layoutOwnedFrames[frame] then
        local layoutKey = anchoring.layoutOwnedFrames[frame]
        if layoutKey and QUICore.db and QUICore.db.profile then
            local anchoringDB = QUICore.db.profile.frameAnchoring
            if anchoringDB and anchoringDB[layoutKey] then
                anchoring:ApplyFrameAnchor(layoutKey, anchoringDB[layoutKey])
            end
        end
        return
    end
    local px = self:GetPixelSize(frame)
    local x = offsetX and Round(offsetX / px) * px or 0
    local y = offsetY and Round(offsetY / px) * px or 0
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

function QUICore:SnapFramePosition(frame)
    if not frame then return end
    if InCombatLockdown() then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if ns.Helpers.HasSecretValue(point, relativeTo, relativePoint, x, y) then return end
    if not point then return end
    x = self:PixelRound(x or 0, frame)
    y = self:PixelRound(y or 0, frame)
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    return point, relativeTo, relativePoint, x, y
end

function QUICore:SetPixelPerfectBackdrop(frame, borderPixels, bgFile, r, g, b, a)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    local edgeSize = max(1, Round(borderPixels or 1)) * px
    local backdrop = {
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = edgeSize,
    }
    if bgFile then
        backdrop.bgFile = bgFile
        backdrop.insets = {
            left = edgeSize,
            right = edgeSize,
            top = edgeSize,
            bottom = edgeSize,
        }
    end
    frame:SetBackdrop(backdrop)
    if r then
        frame:SetBackdropBorderColor(r, g, b, a or 1)
    end
end

function QUICore:ApplyPixelSnapping(frame)
    if not frame then return end
    if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(true) end
    if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
end

local fontRegistry = ns.Helpers.CreateStateTable()

local function applyFontInternal(self, fontString, frame, size, fontPath, flags)
    local Helpers = ns.Helpers
    local path = fontPath or (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF"
    local outline = flags or (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local sz = (type(size) == "number" and size > 0) and size or 12

    local px = self:GetPixelSize(frame)
    sz = Round(sz / px) * px

    if Helpers and Helpers.ApplyFontWithFallback then
        Helpers.ApplyFontWithFallback(fontString, path, sz, outline)
        return fontString:GetFont() ~= nil
    end

    local ok = fontString:SetFont(path, sz, outline)
    return ok
end

function QUICore:ApplyFont(fontString, frame, size, fontPath, flags)
    if not fontString or not fontString.SetFont then return end

    local ok = applyFontInternal(self, fontString, frame, size, fontPath, flags)
    if not ok then return end

    fontRegistry[fontString] = { frame = frame, size = size, fontPath = fontPath, flags = flags }
end

function QUICore:RefreshAllFonts()
    for fs, data in pairs(fontRegistry) do
        applyFontInternal(self, fs, data.frame, data.size, data.fontPath, data.flags)
    end
end

function QUICore:CleanupFontRegistry()
    wipe(fontRegistry)
end

local function GetUIScale(self)
    if self.db and self.db.profile and self.db.profile.general then
        return self.db.profile.general.uiScale or 1.0
    end
    return 1.0
end

function QUICore:GetPixelPerfectScale()
    if cachedPhysicalHeight == 0 then return 1 end
    return 768 / cachedPhysicalHeight
end

function QUICore:GetSmartDefaultScale()
    if cachedPhysicalHeight >= 2160 then return 0.53 end
    if cachedPhysicalHeight >= 1440 then return 0.64 end
    return 1.0
end

local function DeferUIScaleToRegen(self)
    if not self._UIScalePending then
        self._UIScalePending = true
        self:RegisterEvent('PLAYER_REGEN_ENABLED', function()
            self._UIScalePending = nil
            self:UnregisterEvent('PLAYER_REGEN_ENABLED')
            self:ApplyUIScale()
        end)
    end
end

function QUICore:ApplyUIScale()
    if InCombatLockdown() and not ns._inInitSafeWindow then
        DeferUIScaleToRegen(self)
        return
    end

    local scaleToApply = GetUIScale(self)
    if scaleToApply <= 0 then
        scaleToApply = self:GetSmartDefaultScale()
        if self.db and self.db.profile and self.db.profile.general then
            self.db.profile.general.uiScale = scaleToApply
        end
    end

    local success = ns.SafeCallMethod("defer-ooc", UIParent, "SetScale", scaleToApply)
    if not success then
        DeferUIScaleToRegen(self)
        return
    end

    self.uiscale = UIParent:GetScale()
    self.screenWidth, self.screenHeight = GetScreenWidth(), GetScreenHeight()
    self:RefreshAllFonts()
    local UIKit = ns.UIKit
    if UIKit then
        if UIKit.QueueScaleRefresh then
            UIKit.QueueScaleRefresh(2)
        elseif UIKit.RefreshScaleBoundWidgets then
            UIKit.RefreshScaleBoundWidgets()
        end
    end
end

function QUICore:PixelScaleChanged(event)
    if event == 'UI_SCALE_CHANGED' or event == 'DISPLAY_SIZE_CHANGED' then
        self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
        self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
        cachedPhysicalHeight = self.physicalHeight
    end
    self:ApplyUIScale()
end

function QUICore:InitializePixelPerfect()
    self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
    self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
    cachedPhysicalHeight = self.physicalHeight
    self:RegisterEvent('UI_SCALE_CHANGED', 'PixelScaleChanged')
    self:RegisterEvent('DISPLAY_SIZE_CHANGED', 'PixelScaleChanged')
end
