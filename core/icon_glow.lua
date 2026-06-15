-- core/icon_glow.lua
---------------------------------------------------------------------------
-- QUI Icon Glow Provider Registry
-- Central dispatch for proc / spell-activation / assist glows. Surfaces keep
-- their own trigger logic (which button, when) and call Start/Stop here with
-- the surface's configured source + tuning. The active provider is tracked
-- per button so Stop calls the matching provider's stop fn (LCG button/pixel/
-- autocast stop fns differ — calling the wrong one leaves a stuck glow).
--
-- Built-in providers:
--   "QUI"  -> LibCustomGlow (style: Button|Pixel|AutoCast) + color + tuning
--   "Skin" -> defers to the external skin bridge (no LCG, native art shows)
--   "Off"  -> stop only
-- Additional providers can be registered via RegisterProvider for known libs.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local IconGlow = { providers = {}, order = {}, active = setmetatable({}, { __mode = "k" }) }
ns.IconGlow = IconGlow

local LCG  -- resolved lazily; nil in headless harness

function IconGlow.RegisterProvider(p)
    assert(type(p) == "table" and type(p.name) == "string", "provider needs a name")
    if not IconGlow.providers[p.name] then
        IconGlow.order[#IconGlow.order + 1] = p.name
    end
    IconGlow.providers[p.name] = p
end

--- Names of providers currently usable, plus the always-present "Off".
function IconGlow.GetSourceList()
    local out = {}
    for _, name in ipairs(IconGlow.order) do
        local p = IconGlow.providers[name]
        if p and (not p.isAvailable or p.isAvailable()) then
            out[#out + 1] = name
        end
    end
    out[#out + 1] = "Off"
    return out
end

--- Stop whatever provider is currently active on this button.
function IconGlow.Stop(button)
    local name = IconGlow.active[button]
    if not name then return end
    IconGlow.active[button] = nil
    local p = IconGlow.providers[name]
    if p and p.stop then p.stop(button) end
end

--- Start a glow on button per opts.source / opts.style / opts.color / tuning.
--- Idempotent-ish: switching providers stops the previous one first.
function IconGlow.Start(button, opts)
    opts = opts or {}
    local source = opts.source or "Off"
    -- Stop any previously-active different provider first.
    local prev = IconGlow.active[button]
    if prev and prev ~= source then IconGlow.Stop(button) end

    if source == "Off" then
        IconGlow.Stop(button)
        return
    end
    local p = IconGlow.providers[source]
    if not p or (p.isAvailable and not p.isAvailable()) then
        IconGlow.Stop(button)
        return
    end
    IconGlow.active[button] = source
    if p.start then p.start(button, opts) end
end

----------------------------------------------------------------------------
-- Built-in provider: QUI / LibCustomGlow
----------------------------------------------------------------------------
local function ResolveLCG()
    if LCG == nil and _G.LibStub then
        LCG = _G.LibStub("LibCustomGlow-1.0", true) or false
    end
    return LCG or nil
end

IconGlow.RegisterProvider({
    name = "QUI",
    isAvailable = function() return ResolveLCG() ~= nil end,
    start = function(button, opts)
        local lib = ResolveLCG(); if not lib then return end
        local style = opts.style or "Button"
        if style == "Pixel" and lib.PixelGlow_Start then
            lib.PixelGlow_Start(button, opts.color, opts.lines, opts.frequency,
                opts.length, opts.thickness)
        elseif style == "AutoCast" and lib.AutoCastGlow_Start then
            lib.AutoCastGlow_Start(button, opts.color, opts.particles, opts.scale)
        else
            lib.ButtonGlow_Start(button, opts.color)
        end
    end,
    stop = function(button)
        local lib = ResolveLCG(); if not lib then return end
        -- Stop all LCG variants; only the active one does anything.
        if lib.ButtonGlow_Stop   then lib.ButtonGlow_Stop(button)   end
        if lib.PixelGlow_Stop     then lib.PixelGlow_Stop(button)    end
        if lib.AutoCastGlow_Stop  then lib.AutoCastGlow_Stop(button) end
    end,
})

----------------------------------------------------------------------------
-- Built-in provider: Skin (defer to external skin's own proc art)
-- Availability gated on the bridge reporting the skin supplies a glow.
----------------------------------------------------------------------------
IconGlow.RegisterProvider({
    name = "Skin",
    isAvailable = function()
        local b = ns.ExternalSkinBridge
        return b ~= nil and b.IsAvailable() and b.SkinProvidesGlow()
    end,
    start = function() end,  -- the skin lib draws the glow; nothing to do
    stop  = function() end,
})

return IconGlow
