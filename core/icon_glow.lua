local ADDON_NAME, ns = ...

local IconGlow = { providers = {}, order = {}, active = setmetatable({}, { __mode = "k" }) }
ns.IconGlow = IconGlow

local LCG

function IconGlow.RegisterProvider(p)
    assert(type(p) == "table" and type(p.name) == "string", "provider needs a name")
    if not IconGlow.providers[p.name] then
        IconGlow.order[#IconGlow.order + 1] = p.name
    end
    IconGlow.providers[p.name] = p
end

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

function IconGlow.Stop(button)
    local name = IconGlow.active[button]
    if not name then return end
    IconGlow.active[button] = nil
    local p = IconGlow.providers[name]
    if p and p.stop then p.stop(button) end
end

function IconGlow.Start(button, opts)
    opts = opts or {}
    local source = opts.source or "Off"
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
        if lib.ButtonGlow_Stop   then lib.ButtonGlow_Stop(button)   end
        if lib.PixelGlow_Stop     then lib.PixelGlow_Stop(button)    end
        if lib.AutoCastGlow_Stop  then lib.AutoCastGlow_Stop(button) end
    end,
})

IconGlow.RegisterProvider({
    name = "Skin",
    isAvailable = function()
        local b = ns.ExternalSkinBridge
        return b ~= nil and b.IsAvailable() and b.SkinProvidesGlow()
    end,
    start = function() end,
    stop  = function() end,
})

return IconGlow
