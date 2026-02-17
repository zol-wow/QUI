--- QUI Scaling Utils
--- Pixel-perfect scaling with frame-aware math
---
--- The WoW UI coordinate system uses virtual units where the screen height equals
--- 768 / uiScale. Physical screen pixels don't always align with these virtual units,
--- causing borders, sizes, and gaps to render inconsistently (e.g., a "1 pixel" border
--- sometimes renders as 2 pixels, or a 300px frame is actually 299 or 301 pixels).
---
--- This module provides functions that snap all dimensions and positions to the
--- physical pixel grid, ensuring:
---   - 1 pixel always means exactly 1 physical screen pixel
---   - 300 pixels always means exactly 300 physical screen pixels
---   - Positions land on pixel boundaries so borders and gaps are consistent
---
--- Key concept: "pixel size" = the virtual-coordinate size of 1 physical screen pixel
--- for a given frame, calculated as: 768 / (physicalScreenHeight * effectiveScale)
---
--- Functions come in two families:
---   Pixel-count input (I want N physical pixels):
---     Scale(n, frame), Pixels(n, frame), SetPixelPerfectSize, SetPixelPerfectPoint
---   Virtual-coord input (snap existing value to grid):
---     PixelRound(v, frame), PixelFloor(v, frame), PixelCeil(v, frame), SetSnappedPoint

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
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetScreenWidth, GetScreenHeight = GetScreenWidth, GetScreenHeight

--- Cached physical screen height (updated on UI_SCALE_CHANGED).
local cachedPhysicalHeight = select(2, GetPhysicalScreenSize())

--------------------------------------------------------------------------------
-- Pixel Math Core
--------------------------------------------------------------------------------

--- Get the virtual-coordinate size of 1 physical screen pixel for a given frame.
--- This is the fundamental unit for all pixel-perfect calculations.
---
--- The formula: pixelSize = 768 / (physicalScreenHeight * frame:GetEffectiveScale())
---
--- A frame's effective scale is the product of its own scale and all ancestor scales.
--- Using the correct frame (not just UIParent) matters when frames in the hierarchy
--- have been scaled with SetScale().
---
--- @param frame? Frame The frame context (defaults to UIParent)
--- @return number The size of 1 physical pixel in the frame's coordinate space
function QUICore:GetPixelSize(frame)
    local es = (frame or UIParent):GetEffectiveScale()
    if es == 0 then return 1 end
    if cachedPhysicalHeight == 0 then return 1 end
    return 768 / (cachedPhysicalHeight * es)
end

--- Convert a physical pixel count to virtual coordinate units for a given frame.
--- Use this when you want "exactly N physical pixels" in a frame's coordinate space.
---
--- Example: self:Pixels(1, myFrame) returns the exact size of 1 physical pixel
--- Example: self:Pixels(300, myFrame) returns exactly 300 physical pixels
---
--- @param n number Number of physical pixels desired
--- @param frame? Frame The frame context (defaults to UIParent)
--- @return number Virtual coordinate size equal to exactly N physical pixels
function QUICore:Pixels(n, frame)
    if n == 0 then return 0 end
    return n * self:GetPixelSize(frame)
end

--- Snap a virtual-coordinate value to the nearest physical pixel boundary.
--- Use this when you have a value in virtual coordinates (e.g., from a database
--- setting or calculation) and need it to land exactly on a pixel boundary.
---
--- @param value number The value in virtual coordinates
--- @param frame? Frame The frame context (defaults to UIParent)
--- @return number The value snapped to the nearest pixel boundary
function QUICore:PixelRound(value, frame)
    if value == 0 then return 0 end
    local px = self:GetPixelSize(frame)
    return Round(value / px) * px
end

--- Floor a virtual-coordinate value down to the nearest pixel boundary.
--- @param value number The value in virtual coordinates
--- @param frame? Frame The frame context (defaults to UIParent)
--- @return number The value floored to the nearest pixel boundary
function QUICore:PixelFloor(value, frame)
    if value == 0 then return 0 end
    local px = self:GetPixelSize(frame)
    return floor(value / px) * px
end

--- Ceil a virtual-coordinate value up to the nearest pixel boundary.
--- @param value number The value in virtual coordinates
--- @param frame? Frame The frame context (defaults to UIParent)
--- @return number The value ceiled to the nearest pixel boundary
function QUICore:PixelCeil(value, frame)
    if value == 0 then return 0 end
    local px = self:GetPixelSize(frame)
    return ceil(value / px) * px
end

--------------------------------------------------------------------------------
-- Scaling (Legacy + Frame-Aware)
--------------------------------------------------------------------------------

--- Scale a pixel count to virtual coordinates, snapped to the pixel grid.
--- Uses the given frame's effective scale (or UIParent if omitted).
---
--- @param x number Number of physical pixels desired
--- @param frame? Frame Optional frame for frame-aware scaling (defaults to UIParent)
--- @return number Virtual coordinate value representing exactly x physical pixels
function QUICore:Scale(x, frame)
    if x == 0 then return 0 end
    return self:Pixels(x, frame)
end

--- Set pixel-perfect size on a frame using UIParent's scale.
--- For frame-aware sizing, use SetPixelPerfectSize instead.
--- @param frame Frame The frame to size
--- @param width number Width in physical pixels
--- @param height number Height in physical pixels
function QUICore:SetSize(frame, width, height)
    if not frame then return end
    local px = self:GetPixelSize()
    frame:SetSize(Round(width) * px, Round(height) * px)
end

--- Set pixel-perfect width on a frame using UIParent's scale.
--- @param frame Frame The frame to size
--- @param width number Width in physical pixels
function QUICore:SetWidth(frame, width)
    if not frame then return end
    local px = self:GetPixelSize()
    frame:SetWidth(Round(width) * px)
end

--- Set pixel-perfect height on a frame using UIParent's scale.
--- @param frame Frame The frame to size
--- @param height number Height in physical pixels
function QUICore:SetHeight(frame, height)
    if not frame then return end
    local px = self:GetPixelSize()
    frame:SetHeight(Round(height) * px)
end

--------------------------------------------------------------------------------
-- Frame-Aware Pixel-Perfect Sizing
--------------------------------------------------------------------------------

--- Set frame size to exactly widthPixels x heightPixels physical screen pixels.
--- Uses the frame's own effective scale for accurate pixel mapping.
---
--- Unlike SetSize() which always uses UIParent's scale, this accounts for any
--- intermediate scaling in the frame's parent chain.
---
--- @param frame Frame The frame to size
--- @param widthPixels number Desired width in physical pixels
--- @param heightPixels number Desired height in physical pixels
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

--- Set frame width to exactly widthPixels physical screen pixels.
--- @param frame Frame The frame to size
--- @param widthPixels number Desired width in physical pixels
function QUICore:SetPixelPerfectWidth(frame, widthPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    frame:SetWidth(Round(widthPixels) * px)
end

--- Set frame height to exactly heightPixels physical screen pixels.
--- @param frame Frame The frame to size
--- @param heightPixels number Desired height in physical pixels
function QUICore:SetPixelPerfectHeight(frame, heightPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    frame:SetHeight(Round(heightPixels) * px)
end

--------------------------------------------------------------------------------
-- Pixel-Perfect Positioning
--------------------------------------------------------------------------------

--- SetPoint with offsets specified in physical pixel counts, snapped to grid.
--- The offsets are in physical pixels (e.g., 5 means 5 physical pixels right/up).
---
--- @param frame Frame The frame to position
--- @param point string Anchor point (e.g., "TOPLEFT")
--- @param relativeTo Frame|nil The reference frame (nil for parent)
--- @param relativePoint string The reference point on relativeTo
--- @param xPixels? number X offset in physical pixels (default 0)
--- @param yPixels? number Y offset in physical pixels (default 0)
function QUICore:SetPixelPerfectPoint(frame, point, relativeTo, relativePoint, xPixels, yPixels)
    if not frame then return end
    local px = self:GetPixelSize(frame)
    local x = xPixels and Round(xPixels) * px or 0
    local y = yPixels and Round(yPixels) * px or 0
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

--- Snap existing virtual-coordinate offsets to the nearest pixel boundary.
--- Use this when you have offsets in virtual coordinates (e.g., from the database
--- or a calculation) that need to be pixel-aligned.
---
--- Unlike SetPixelPerfectPoint where offsets are pixel counts, here the offsets
--- are already in virtual coordinates and just need to be snapped to the grid.
---
--- @param frame Frame The frame to position
--- @param point string Anchor point
--- @param relativeTo Frame|nil The reference frame
--- @param relativePoint string The reference point on relativeTo
--- @param offsetX? number X offset in virtual coordinates (will be snapped)
--- @param offsetY? number Y offset in virtual coordinates (will be snapped)
function QUICore:SetSnappedPoint(frame, point, relativeTo, relativePoint, offsetX, offsetY)
    if not frame then return end
    -- If frame has an active anchoring override, reapply the override position
    -- (modules call ClearAllPoints before SetSnappedPoint, so the override was just cleared)
    local anchoring = ns.QUI_Anchoring
    if anchoring and anchoring.overriddenFrames and anchoring.overriddenFrames[frame] then
        local overrideKey = anchoring.overriddenFrames[frame]
        if overrideKey and QUICore.db and QUICore.db.profile then
            local anchoringDB = QUICore.db.profile.frameAnchoring
            if anchoringDB and anchoringDB[overrideKey] then
                anchoring:ApplyFrameAnchor(overrideKey, anchoringDB[overrideKey])
            end
        end
        return
    end
    local px = self:GetPixelSize(frame)
    local x = offsetX and Round(offsetX / px) * px or 0
    local y = offsetY and Round(offsetY / px) * px or 0
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
end

--- Snap a frame's current position to the pixel grid after a drag operation.
--- Call this after StopMovingOrSizing() to ensure the frame lands on pixel
--- boundaries, preventing ±1px size rendering errors.
---
--- Returns the snapped anchor data so callers can save it to the database.
---
--- @param frame Frame The frame to snap
--- @return string? point Anchor point
--- @return Frame? relativeTo Relative frame
--- @return string? relativePoint Relative anchor
--- @return number? x Snapped X offset
--- @return number? y Snapped Y offset
function QUICore:SnapFramePosition(frame)
    if not frame then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint()
    if not point then return end
    x = self:PixelRound(x or 0, frame)
    y = self:PixelRound(y or 0, frame)
    frame:ClearAllPoints()
    frame:SetPoint(point, relativeTo, relativePoint, x, y)
    return point, relativeTo, relativePoint, x, y
end

--------------------------------------------------------------------------------
-- Pixel-Perfect Backdrop
--------------------------------------------------------------------------------

--- Apply a backdrop with an exact N-pixel border using the frame's own scale.
--- Guarantees the border is exactly borderPixels physical pixels thick.
---
--- @param frame Frame The frame (must inherit BackdropTemplate)
--- @param borderPixels? number Border thickness in physical pixels (default 1)
--- @param bgFile? string Background texture path (nil for border-only)
--- @param r? number Border color red (0-1)
--- @param g? number Border color green (0-1)
--- @param b? number Border color blue (0-1)
--- @param a? number Border color alpha (0-1, default 1)
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

--------------------------------------------------------------------------------
-- Texel Snapping
--------------------------------------------------------------------------------

--- Apply pixel-grid snapping to a frame for crisp texture rendering.
--- Calls SetSnapToPixelGrid(true) and SetTexelSnappingBias(0) if available.
--- These are WoW 12.0+ APIs that prevent sub-pixel texture blurring.
---
--- @param frame Frame The frame (or texture) to snap
function QUICore:ApplyPixelSnapping(frame)
    if not frame then return end
    if frame.SetSnapToPixelGrid then frame:SetSnapToPixelGrid(true) end
    if frame.SetTexelSnappingBias then frame:SetTexelSnappingBias(0) end
end

--------------------------------------------------------------------------------
-- Font Registry
--------------------------------------------------------------------------------

--- Weak-keyed registry of FontStrings for scale-change refresh.
local fontRegistry = setmetatable({}, { __mode = "k" })

--- Internal: resolve font parameters and apply a pixel-snapped font to a FontString.
--- Does NOT write to the registry — callers handle registration separately.
local function applyFontInternal(self, fontString, frame, size, fontPath, flags)
    local Helpers = ns.Helpers
    local path = fontPath or (Helpers and Helpers.GetGeneralFont and Helpers.GetGeneralFont()) or "Fonts\\FRIZQT__.TTF"
    local outline = flags or (Helpers and Helpers.GetGeneralFontOutline and Helpers.GetGeneralFontOutline()) or "OUTLINE"
    local sz = (type(size) == "number" and size > 0) and size or 12

    -- Snap font size to pixel grid using the same formula as PixelRound
    local px = self:GetPixelSize(frame)
    sz = Round(sz / px) * px

    local ok = fontString:SetFont(path, sz, outline)
    return ok
end

--- Apply a font to a FontString with pixel-perfect size snapping, and register
--- it for automatic refresh on UI scale changes.
---
--- Font size is snapped to the physical pixel grid using GetPixelSize(), the same
--- formula used by PixelRound and all other snapping functions in this module.
--- This prevents fractional-pixel font heights that cause blurry text.
---
--- @param fontString FontString The FontString to configure
--- @param frame? Frame The reference frame for effective scale (defaults to UIParent)
--- @param size? number Font size in points (default 12)
--- @param fontPath? string Font file path (default: user's configured general font)
--- @param flags? string Font flags like "OUTLINE" (default: user's configured outline)
function QUICore:ApplyFont(fontString, frame, size, fontPath, flags)
    if not fontString or not fontString.SetFont then return end

    local ok = applyFontInternal(self, fontString, frame, size, fontPath, flags)
    if not ok then return end

    -- Register for scale-change refresh (stores original values, not snapped)
    fontRegistry[fontString] = { frame = frame, size = size, fontPath = fontPath, flags = flags }
end

--- Re-apply pixel-snapped fonts to all registered FontStrings.
--- Called automatically after UI scale is applied. Can also be called manually
--- after font settings change.
function QUICore:RefreshAllFonts()
    for fs, data in pairs(fontRegistry) do
        applyFontInternal(self, fs, data.frame, data.size, data.fontPath, data.flags)
    end
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

--- Get the pixel-perfect scale for the current screen resolution.
--- At this scale, 1 virtual unit = 1 physical pixel, eliminating all rounding.
--- Formula: 768 / physicalScreenHeight
--- @return number The pixel-perfect scale value
function QUICore:GetPixelPerfectScale()
    if cachedPhysicalHeight == 0 then return 1 end
    return 768 / cachedPhysicalHeight
end

--- Get smart default scale based on screen resolution
function QUICore:GetSmartDefaultScale()
    if cachedPhysicalHeight >= 2160 then return 0.53 end     -- 4K
    if cachedPhysicalHeight >= 1440 then return 0.64 end     -- 1440p
    return 1.0                                                -- 1080p or lower
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
    self:RefreshAllFonts()  -- Re-snap all registered fonts to new pixel grid
end

--------------------------------------------------------------------------------
-- Event Handling & Initialization
--------------------------------------------------------------------------------

function QUICore:PixelScaleChanged(event)
    if event == 'UI_SCALE_CHANGED' then
        self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
        self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
        -- Update the module-level cache
        cachedPhysicalHeight = self.physicalHeight
    end
    self:ApplyUIScale()
end

function QUICore:InitializePixelPerfect()
    self.physicalWidth, self.physicalHeight = GetPhysicalScreenSize()
    self.resolution = format('%dx%d', self.physicalWidth, self.physicalHeight)
    cachedPhysicalHeight = self.physicalHeight
    self:RegisterEvent('UI_SCALE_CHANGED', 'PixelScaleChanged')
end
