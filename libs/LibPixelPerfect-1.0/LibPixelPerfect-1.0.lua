--@curseforge-project-slug:libpixelperfect-1-0@

---@class LibPixelPerfect
local lib

---@type string, number
local MAJOR, MINOR = "LibPixelPerfect-1.0", 0
if LibStub then
	lib = LibStub:NewLibrary(MAJOR, MINOR)
	if not lib then
        -- The library is already loaded
        return
    end
else
	lib = {}
end

---@type Frame
local parentFrame = UIParent

if not PixelUtil then
    -- PixelUtil is not available, so we cannot proceed.
    -- PixelUtil was added in WoW 8.0.1 (BFA), so any non-Blizzard clients will need a PixelUtil
    -- implementation to use this library.
    --- TODO: Add a fallback or shim so it can work with non-Blizzard clients
    return
end

local GetNearestPixelSize = PixelUtil.GetNearestPixelSize

--- Override the default parent frame for pixel-perfect calculations.
--- @param frame Frame the frame to set as the parent for pixel-perfect calculations.
function lib.SetParentFrame(frame)
    parentFrame = frame
end

--- Scale a pixel value to the nearest pixel size based on the current parent frame's scale.
--- @param originalPixels number The original pixel value to scale. Defaults to 0.
--- @return number scaledPixels the scaled pixel value.
function lib.PScale(originalPixels)
    return GetNearestPixelSize(originalPixels or 0, parentFrame:GetEffectiveScale())
end

--- Set the size of a frame to pixel-perfect dimensions.
--- @param frame Frame The frame to set the size for.
--- @param width number The width in pixels.
--- @param height number The height in pixels.
function lib.PSize(frame, width, height)
    if not frame then
        return
    end
    frame:SetSize(lib.PScale(width), lib.PScale(height))
end

--- Set the width of a frame to a pixel-perfect value.
--- @param frame Frame The frame to set the width for.
--- @param width number The width in pixels.
function lib.PWidth(frame, width)
    frame:SetWidth(lib.PScale(width))
end

--- Set the height of a frame to a pixel-perfect value.
--- @param frame Frame The frame to set the height for.
--- @param height number The height in pixels.
function lib.PHeight(frame, height)
    frame:SetHeight(lib.PScale(height))
end

return lib
