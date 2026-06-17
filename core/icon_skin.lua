-- core/icon_skin.lua
---------------------------------------------------------------------------
-- QUI Icon Skin Registry
-- Built-in icon "skins" are presets over the existing texture-set knobs
-- (border on/off + size, gloss on/off + alpha, backdrop alpha, pushed mode,
-- texcoord zoom). No new art files. Surfaces map their button's regions into
-- a normalized table once, then call ApplySkin(button, regions, skinName).
-- Skins are also registered as an LSM media-type ("qui-iconskin") in
-- core/media.lua so they appear in dropdowns and third parties can add more.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local IconSkin = { skins = {}, order = {} }
ns.IconSkin = IconSkin

-- Shared gloss-overlay atlas (same texture the action bars use). Surfaces that
-- add a gloss overlay create their texture with this path; ApplySkin only
-- toggles its visibility/alpha per preset.
IconSkin.GlossTexture = ((Helpers and Helpers.AssetPath) or "Interface\\AddOns\\QUI\\assets\\") .. "iconskin\\Gloss"

--- Register a skin preset. textureSet fields:
---   border(bool), borderSize(number), gloss(bool), glossAlpha(0-1),
---   backdropAlpha(0-1), pushed("qui"|"blizzard"|"off"), zoom(0-1)
function IconSkin.RegisterSkin(name, textureSet)
    assert(type(name) == "string" and name ~= "", "skin needs a name")
    assert(type(textureSet) == "table", "skin needs a textureSet table")
    if not IconSkin.skins[name] then
        IconSkin.order[#IconSkin.order + 1] = name
    end
    IconSkin.skins[name] = textureSet
end

--- Resolve a skin name to its preset table, falling back to Default.
function IconSkin.Resolve(name)
    return IconSkin.skins[name] or IconSkin.skins["Default"]
end

--- Stable-ordered list of registered skin names (registration order).
function IconSkin.GetSkinList()
    local out = {}
    for i, n in ipairs(IconSkin.order) do out[i] = n end
    return out
end

--- Apply a skin's preset to a button via its normalized region table.
--- regions = { Icon, Normal, Border, Backdrop, Gloss, Highlight, Pushed,
---             Checked, Flash, Cooldown } (any subset; nil regions skipped).
--- Pure visual writes only — no protected API calls (combat-safe).
function IconSkin.ApplySkin(button, regions, skinName)
    local s = IconSkin.Resolve(skinName)
    if not regions then return end

    if regions.Border then
        if s.border then
            local r, g, b, a = 0, 0, 0, 1
            if Helpers and Helpers.GetSkinBorderColor then
                r, g, b, a = Helpers.GetSkinBorderColor(nil, nil)
            end
            regions.Border:SetVertexColor(r, g, b, a)
            regions.Border:Show()
        else
            regions.Border:Hide()
        end
    end

    if regions.Gloss then
        if s.gloss then
            regions.Gloss:SetAlpha(s.glossAlpha or 1)
            regions.Gloss:Show()
        else
            regions.Gloss:Hide()
        end
    end

    if regions.Backdrop then
        regions.Backdrop:SetAlpha(s.backdropAlpha or 1)
        if (s.backdropAlpha or 0) > 0 then regions.Backdrop:Show() else regions.Backdrop:Hide() end
    end
end

-- Built-in skins (presets only — surfaces decide which regions exist).
IconSkin.RegisterSkin("Default", { border = true,  borderSize = 1, gloss = true,  glossAlpha = 0.5, backdropAlpha = 1,   pushed = "qui",      zoom = 0.08 })
IconSkin.RegisterSkin("Flat",    { border = true,  borderSize = 1, gloss = false, glossAlpha = 0,   backdropAlpha = 1,   pushed = "qui",      zoom = 0.08 })
IconSkin.RegisterSkin("Minimal", { border = true,  borderSize = 1, gloss = false, glossAlpha = 0,   backdropAlpha = 0,   pushed = "off",      zoom = 0.06 })
IconSkin.RegisterSkin("Gloss",   { border = true,  borderSize = 1, gloss = true,  glossAlpha = 0.9, backdropAlpha = 1,   pushed = "blizzard", zoom = 0.08 })

return IconSkin
