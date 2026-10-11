local ADDON_NAME, ns = ...
local Helpers = ns.Helpers
local SATIN = Helpers.AssetPath .. "appearance\\Satin.tga"
local ICON_FINISH = Helpers.AssetPath .. "appearance\\SatinIcon.tga"
local finishByTexture = Helpers.CreateStateTable()

function Helpers.IsSatinStyle()
    local profile = Helpers.GetProfile()
    local general = profile and profile.general
    return not general or general.visualStyle == nil or general.visualStyle == "Satin"
end

function Helpers.GetStyledBarTexture(path)
    if not Helpers.IsSatinStyle() or type(path) ~= "string" then return path, false end
    local normalized = path:lower():gsub("/", "\\")
    local assets = Helpers.AssetPath:lower()
    local builtin = normalized == "interface\\buttons\\white8x8"
        or normalized == "interface\\targetingframe\\ui-statusbar"
        or normalized == assets .. "square.tga"
        or normalized == SATIN:lower()
        or (normalized:sub(1, #assets) == assets
            and normalized:sub(#assets + 1):match("^quazii[_%w]*%.tga$") ~= nil)
    if builtin then return SATIN, true end
    return path, false
end

local function SyncFinishVisibility(finish, texture)
    if not finish.enabled then return end
    local overlay = finish.texture
    local alpha = 1
    if texture.GetAlpha then alpha = texture:GetAlpha() end
    if texture.IsShown then
        local shown = texture:IsShown()
        if Helpers.IsSecretValue(shown) then
            overlay:Show()
            overlay:SetAlphaFromBoolean(shown, alpha, 0)
        else
            overlay:SetAlpha(alpha)
            overlay:SetShown(shown)
        end
    else
        overlay:SetAlpha(alpha)
        overlay:Show()
    end
end

local function ApplyFinish(parent, texture, enabled)
    if not texture then return end
    local finish = finishByTexture[texture]
    local maskCount
    if enabled and texture.GetNumMaskTextures then
        maskCount = texture:GetNumMaskTextures()
        if Helpers.IsSecretValue(maskCount) then enabled = false end -- @secret-policy: reject-secret-hierarchy
    end
    if not enabled then
        if finish then
            finish.enabled = false
            finish.texture:Hide()
        end
        return
    end
    if not finish then
        if not parent or not parent.CreateTexture then return end
        local overlay = parent:CreateTexture(nil, "ARTWORK", nil, 2)
        overlay:SetTexture(ICON_FINISH)
        overlay:SetAllPoints(texture)
        if ns.UIKit and ns.UIKit.DisablePixelSnap then
            ns.UIKit.DisablePixelSnap(overlay)
        end
        finish = { texture = overlay, enabled = true, masks = {} }
        finishByTexture[texture] = finish
        if hooksecurefunc then
            hooksecurefunc(texture, "Hide", function() overlay:Hide() end)
            hooksecurefunc(texture, "Show", function()
                SyncFinishVisibility(finish, texture)
            end)
            if texture.SetShown then
                hooksecurefunc(texture, "SetShown", function()
                    SyncFinishVisibility(finish, texture)
                end)
            end
            if texture.SetAlpha then
                hooksecurefunc(texture, "SetAlpha", function() SyncFinishVisibility(finish, texture) end)
            end
            if texture.AddMaskTexture then
                hooksecurefunc(texture, "AddMaskTexture", function(_, mask)
                    if Helpers.IsSecretValue(mask) then
                        finish.enabled = false -- @secret-policy: hide-finish-when-mask-unreadable
                        overlay:Hide()
                        return
                    end
                    if not finish.masks[mask] then
                        finish.masks[mask] = true
                        overlay:AddMaskTexture(mask)
                    end
                end)
                hooksecurefunc(texture, "RemoveMaskTexture", function(_, mask)
                    if Helpers.IsSecretValue(mask) then
                        finish.enabled = false -- @secret-policy: hide-finish-when-mask-unreadable
                        overlay:Hide()
                        return
                    end
                    finish.masks[mask] = nil
                    overlay:RemoveMaskTexture(mask)
                end)
            end
        end
    end
    finish.enabled = true
    local overlay = finish.texture
    if texture.GetDrawLayer then
        local layer, level = texture:GetDrawLayer()
        if Helpers.HasSecretValue(layer, level) then
            overlay:SetDrawLayer("ARTWORK", 2)
        else
            overlay:SetDrawLayer(layer, math.min((level or 0) + 1, 7))
        end
    end
    if maskCount then
        for i = 1, maskCount do
            local mask = texture:GetMaskTexture(i)
            if Helpers.IsSecretValue(mask) then
                finish.enabled = false -- @secret-policy: hide-finish-when-mask-unreadable
                overlay:Hide()
                return
            end
            if not finish.masks[mask] then
                finish.masks[mask] = true
                overlay:AddMaskTexture(mask)
            end
        end
    end
    SyncFinishVisibility(finish, texture)
end

function Helpers.ApplyBarStyle(bar, path)
    local styled = Helpers.GetStyledBarTexture(path)
    bar:SetStatusBarTexture(styled)
end

function Helpers.ApplyTextureStyle(_parent, texture, path)
    local styled = Helpers.GetStyledBarTexture(path)
    texture:SetTexture(styled)
end

function Helpers.ApplyIconStyle(parent, texture, skinName)
    ApplyFinish(parent, texture, Helpers.IsSatinStyle() and (skinName == nil or skinName == "Default"))
end

function Helpers.GetWindowColors(moduleSettings, prefix)
    if type(moduleSettings) ~= "table" then moduleSettings = nil end
    local r, g, b, a = Helpers.GetSkinBorderColor(moduleSettings, prefix)
    local br, bg, bb, ba = Helpers.GetSkinBgColorWithOverride(moduleSettings, prefix)
    if not Helpers.IsSatinStyle() then return r, g, b, a, br, bg, bb, ba end
    local profile = Helpers.GetProfile()
    local general = profile and profile.general
    local source = general and (general.skinBorderColorSource
        or (general.skinBorderUseClassColor and "class")) or "theme"
    local keys = Helpers.GetBorderKeys(prefix)
    local localSource = moduleSettings and moduleSettings[keys.source]
    local localColor = moduleSettings and (moduleSettings.useClassColorBorder
        or moduleSettings.borderUseClassColor or moduleSettings.useAccentColorBorder)
    if (source == nil or source == "theme") and not localColor
        and (localSource == nil or localSource == "inherit") then
        r, g, b = 0.2824, 0.3294, 0.3098
    end
    local p = type(prefix) == "string" and prefix or ""
    local overrideKey = p ~= "" and (p .. "BgOverride") or "bgOverride"
    local backgroundOverride = moduleSettings and moduleSettings[overrideKey]
    local configured = general and general.skinBgColor
    if not backgroundOverride and (not configured
        or (configured[1] == 0.05 and configured[2] == 0.05 and configured[3] == 0.05)) then
        br, bg, bb = 0.0745, 0.1059, 0.1176
    end
    return r, g, b, a, br, bg, bb, ba
end
