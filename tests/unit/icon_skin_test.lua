-- tests/unit/icon_skin_test.lua
-- Run: lua5.1 tests/unit/icon_skin_test.lua
-- icon_skin: skin registry + applier. Pure-logic parts only (registration,
-- list, preset lookup, region application onto a stub button).

local ns = { Helpers = {} }
-- Helpers.GetSkinBorderColor is consulted for border tint; stub it.
ns.Helpers.GetSkinBorderColor = function() return 0, 0, 0, 1 end

local IconSkin = assert(loadfile("core/icon_skin.lua"))("QUI", ns)
assert(IconSkin == ns.IconSkin, "module must publish ns.IconSkin")

-- 1. Built-in skins are registered and listed in stable order.
local list = IconSkin.GetSkinList()
assert(type(list) == "table", "GetSkinList returns a table")
local names = {}
for _, n in ipairs(list) do names[n] = true end
assert(names["Default"], "Default skin registered")
assert(names["Flat"] and names["Minimal"] and names["Gloss"], "all built-ins registered")

-- 2. Unknown skin name resolves to Default (graceful fallback).
assert(IconSkin.Resolve("Default"), "Default resolves")
assert(IconSkin.Resolve("does-not-exist") == IconSkin.Resolve("Default"),
    "unknown skin falls back to Default")

-- 3. RegisterSkin adds a custom skin that then appears in the list.
IconSkin.RegisterSkin("MyTest", { border = true, borderSize = 2, gloss = false,
    backdropAlpha = 1, glossAlpha = 0, pushed = "qui", zoom = 0 })
local found = false
for _, n in ipairs(IconSkin.GetSkinList()) do if n == "MyTest" then found = true end end
assert(found, "custom skin appears in list")

-- 4. ApplySkin writes the preset's flags onto a normalized region/button stub
--    without touching protected APIs. Use a fake button + region table.
local applied = {}
local function FakeTex()
    return {
        Show = function() applied.shown = true end,
        Hide = function() applied.hidden = true end,
        SetAlpha = function(_, a) applied.alpha = a end,
        SetVertexColor = function(_, r, g, b, a) applied.vc = { r, g, b, a } end,
        SetTexture = function(_, t) applied.tex = t end,
    }
end
local regions = { Border = FakeTex(), Gloss = FakeTex(), Backdrop = FakeTex() }
IconSkin.ApplySkin({}, regions, "Minimal")
-- Minimal has gloss=false → gloss region hidden.
assert(applied.hidden, "Minimal hides the gloss region")

-- GlossTexture exposed for surfaces that add a gloss overlay.
assert(type(IconSkin.GlossTexture) == "string" and IconSkin.GlossTexture:find("iconskin") ~= nil,
    "IconSkin.GlossTexture must be a path string containing 'iconskin'")

print("icon_skin_test OK")
