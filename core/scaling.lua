--- QUI Scaling Utils
--- Uses LibPixelPerfect-1.0 for pixel-perfect scaling

local ADDON_NAME, ns = ...

local QUICore = ns.Addon or (QUI and QUI.QUICore)
if not QUICore then
    print("|cFFFF0000[QUI] ERROR: scaling.lua loaded before quicore_main.lua!|r")
    return
end

local LibPP = LibStub and LibStub("LibPixelPerfect-1.0", true)
if not LibPP then
    print("|cFFFF0000[QUI] ERROR: LibPixelPerfect-1.0 not found!|r")
    return
end

local format = string.format
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetScreenWidth, GetScreenHeight = GetScreenWidth, GetScreenHeight

--------------------------------------------------------------------------------
-- Core Scaling (LibPixelPerfect)
--------------------------------------------------------------------------------

--- Scale a value to pixel-perfect size
--- @param x number Value to scale
--- @return number Scaled value
function QUICore:Scale(x)
    if x == 0 then return 0 end
    return LibPP.PScale(x)
end

--- Set pixel-perfect size on a frame
--- @param frame Frame The frame to size
--- @param width number Width in pixels
--- @param height number Height in pixels
function QUICore:SetSize(frame, width, height)
    LibPP.PSize(frame, width, height)
end

--- Set pixel-perfect width on a frame
--- @param frame Frame The frame to size
--- @param width number Width in pixels
function QUICore:SetWidth(frame, width)
    LibPP.PWidth(frame, width)
end

--- Set pixel-perfect height on a frame
--- @param frame Frame The frame to size
--- @param height number Height in pixels
function QUICore:SetHeight(frame, height)
    LibPP.PHeight(frame, height)
end

--------------------------------------------------------------------------------
-- UI Scale Management
--------------------------------------------------------------------------------

local function GetUIScale(self)
    if self.db and self.db.profile and self.db.profile.general then
        return self.db.profile.general.uiScale or 1.0
    end
    return 1.0
end

--- Get smart default scale based on screen resolution
function QUICore:GetSmartDefaultScale()
    local _, screenHeight = GetPhysicalScreenSize()
    if screenHeight >= 2160 then return 0.53 end     -- 4K
    if screenHeight >= 1440 then return 0.64 end     -- 1440p
    return 1.0                                        -- 1080p or lower
end

--- Apply UI scale (defers if in combat)
function QUICore:ApplyUIScale()
    if InCombatLockdown() then
        if not self._UIScalePending then
            self._UIScalePending = true
            self:RegisterEvent('PLAYER_REGEN_ENABLED', function()
                self._UIScalePending = nil
                self:UnregisterEvent('PLAYER_REGEN_ENABLED')
                self:ApplyUIScale()
            end)
        end
        return
    end

    local scaleToApply = GetUIScale(self)
    if scaleToApply <= 0 then
        scaleToApply = self:GetSmartDefaultScale()
        if self.db and self.db.profile and self.db.profile.general then
            self.db.profile.general.uiScale = scaleToApply
        end
    end

    local success = pcall(function() UIParent:SetScale(scaleToApply) end)
    if not success then
        if not self._UIScalePending then
            self._UIScalePending = true
            self:RegisterEvent('PLAYER_REGEN_ENABLED', function()
                self._UIScalePending = nil
                self:UnregisterEvent('PLAYER_REGEN_ENABLED')
                self:ApplyUIScale()
            end)
        end
        return
    end

    self.uiscale = UIParent:GetScale()
    self.screenWidth, self.screenHeight = GetScreenWidth(), GetScreenHeight()
end

--------------------------------------------------------------------------------
-- Event Handling & Initialization
--------------------------------------------------------------------------------

function QUICore:PixelScaleChanged(event)
    if event == 'UI_SCALE_CHANGED' then
        self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
        self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
    end
    self:ApplyUIScale()
end

function QUICore:InitializePixelPerfect()
    self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
    self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
    self:RegisterEvent('UI_SCALE_CHANGED', 'PixelScaleChanged')
end
