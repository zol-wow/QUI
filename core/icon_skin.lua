local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local IconSkin = { skins = {}, order = {} }
ns.IconSkin = IconSkin

IconSkin.GlossTexture = ((Helpers and Helpers.AssetPath) or "Interface\\AddOns\\QUI\\assets\\") .. "iconskin\\Gloss"
IconSkin.FlashTexture = ((Helpers and Helpers.AssetPath) or "Interface\\AddOns\\QUI\\assets\\") .. "iconskin\\Flash"

function IconSkin.RegisterSkin(name, textureSet)
    assert(type(name) == "string" and name ~= "", "skin needs a name")
    assert(type(textureSet) == "table", "skin needs a textureSet table")
    if not IconSkin.skins[name] then
        IconSkin.order[#IconSkin.order + 1] = name
    end
    IconSkin.skins[name] = textureSet
end

function IconSkin.Resolve(name)
    return IconSkin.skins[name] or IconSkin.skins["Default"]
end

function IconSkin.GetSkinList()
    local out = {}
    for i, n in ipairs(IconSkin.order) do out[i] = n end
    return out
end

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

IconSkin.RegisterSkin("Default", { border = true,  borderSize = 1, gloss = true,  glossAlpha = 0.5, backdropAlpha = 1,   pushed = "qui",   zoom = 0.08 })
IconSkin.RegisterSkin("Flat",    { border = true,  borderSize = 1, gloss = false, glossAlpha = 0,   backdropAlpha = 1,   pushed = "qui",   zoom = 0.08 })
IconSkin.RegisterSkin("Minimal", { border = true,  borderSize = 1, gloss = false, glossAlpha = 0,   backdropAlpha = 0,   pushed = "off",      zoom = 0.06 })
IconSkin.RegisterSkin("Gloss",   { border = true,  borderSize = 1, gloss = true,  glossAlpha = 0.9, backdropAlpha = 1,   pushed = "blizzard", zoom = 0.08 })

return IconSkin
