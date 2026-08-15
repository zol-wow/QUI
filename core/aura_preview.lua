local ADDON_NAME, ns = ...
local P = ns.AuraPreview or {}
ns.AuraPreview = P
_G.QUI = _G.QUI or {}
_G.QUI.AuraPreview = P

local PLACEHOLDER_ICON = 134400
local SAMPLE_BUFF_ICONS = { 136034, 135940, 136081, 135932, 136063 }
local SAMPLE_DEBUFF_ICONS = { 136207, 136130, 136067, 135813, 136118 }

local function AuraSkin()
    return ns.AuraSkin or (ns.Addon and ns.Addon.AuraSkin)
end

local function ResolveSpellIcon(spellID)
    if type(spellID) ~= "number" then return nil end
    if not (C_Spell and C_Spell.GetSpellTexture) then return nil end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok then return tex end
    return nil
end

local function SampleSpellIDs(element)
    if element.mode == "tracked" then
        local spells = element.spells
        if type(spells) == "table" and #spells > 0 then return spells end
        return nil
    end
    if element.filterMode ~= "whitelist" then return nil end
    local wl = element.whitelist
    if type(wl) ~= "table" then return nil end
    local out = {}
    for sid, on in pairs(wl) do
        local n = tonumber(sid)
        if on and n then out[#out + 1] = n end
    end
    if #out == 0 then return nil end
    table.sort(out)
    return out
end

function P.SampleIcon(element, index)
    if type(element) ~= "table" then return PLACEHOLDER_ICON end
    local spells = SampleSpellIDs(element)
    if spells then
        local tex = ResolveSpellIcon(spells[((index - 1) % #spells) + 1])
        if tex then return tex end
    end
    local list = (element.auraType == "HARMFUL") and SAMPLE_DEBUFF_ICONS or SAMPLE_BUFF_ICONS
    return list[((index - 1) % #list) + 1]
end

local function ColorComponents(color)
    if type(color) ~= "table" then return nil end
    return color.r or color[1], color.g or color[2], color.b or color[3],
        color.a or color[4] or 1
end

local function DefaultDispelColor(_element, index, profile)
    local G = ns.AuraGlue or (_G.QUI and _G.QUI.AuraGlue)
    local cycle = G and G.DISPEL_TYPES
    if not cycle or #cycle == 0 then return nil end
    local dispelType = cycle[((index - 1) % #cycle) + 1]
    local custom = profile and type(profile.dispelColors) == "table"
        and profile.dispelColors[dispelType] or nil
    return ColorComponents(custom or G.DISPEL_DEFAULT_COLORS[dispelType])
end

local function SetRegionShown(region, shown)
    if not region then return end
    if shown then
        if region.Show then region:Show() end
    elseif region.Hide then
        region:Hide()
    end
end

local function HidePreviewFrame(frame)
    local Skin = AuraSkin()
    if Skin and Skin.ReleasePreviewButton then Skin.ReleasePreviewButton(frame) end
    frame:Hide()
end

local function AcquireIcon(host, pool, index, profile, richIcon)
    local f = pool[index]
    if not f then
        f = CreateFrame("Frame", nil, host)
        pool[index] = f
    end

    local Skin = AuraSkin()
    if richIcon and Skin and Skin.WirePreviewButton then
        Skin.WirePreviewButton(f, profile)
        f._quiRichPreview = true
        SetRegionShown(f._previewSwatch, false)
        SetRegionShown(f.Icon, true)
        SetRegionShown(f._quiBorder, not f._quiBridged)
        f._tex = f.Icon
    else
        if f._quiRichPreview then
            if Skin and Skin.ReleasePreviewButton then Skin.ReleasePreviewButton(f) end
            SetRegionShown(f.Icon, false)
            SetRegionShown(f._quiBorder, false)
            SetRegionShown(f._quiBackdrop, false)
            SetRegionShown(f._quiGloss, false)
            SetRegionShown(f._quiDispel, false)
            SetRegionShown(f._quiPandemic, false)
            SetRegionShown(f._quiDuration, false)
            SetRegionShown(f._quiCount, false)
            SetRegionShown(f._quiCooldown, false)
            SetRegionShown(f._quiDurationBar, false)
            f._quiRichPreview = nil
        end
        if not f._previewSwatch then
            f._previewSwatch = f:CreateTexture(nil, "ARTWORK")
            f._previewSwatch:SetAllPoints(f)
        end
        f._tex = f._previewSwatch
        SetRegionShown(f._previewSwatch, true)
    end
    f:Show()
    return f
end

local function ApplyIconSample(frame, element, profile, index, opts)
    local tex = (opts and opts.icon and opts.icon(element, index))
        or P.SampleIcon(element, index)
    frame._tex:SetTexture(tex)
    frame._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local duration = 10 + ((index - 1) % 3) * 5
    local now = (GetTime and GetTime()) or 0
    local cd = frame._quiCooldown
    if cd then
        SetRegionShown(cd, true)
        if cd.SetCooldown then cd:SetCooldown(now - duration * 0.35, duration) end
    end
    if frame._quiDuration and frame._quiDuration.SetText then
        frame._quiDuration:SetText(tostring(math.floor(duration * 0.65)))
    end
    if frame._quiCount and frame._quiCount.SetText then
        frame._quiCount:SetText("2")
    end
    local fill = frame._quiDurationBar
    if fill and fill.SetMinMaxValues and fill.SetValue then
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(profile.reverseSwipe and 0.35 or 0.65)
    end

    local dispel = frame._quiDispel
    local mode = profile.dispelBorderMode
    local r, g, b, a
    if profile.showDispelBorder ~= false
        and (element.auraType == "HARMFUL" or mode == "all" or mode == "stealable") then
        local resolve = (opts and opts.dispelColor) or DefaultDispelColor
        r, g, b, a = resolve(element, index, profile)
    end
    if dispel and r ~= nil then
        if dispel.SetVertexColor then dispel:SetVertexColor(r, g or 1, b or 1, a or 1) end
        SetRegionShown(dispel, true)
    else
        SetRegionShown(dispel, false)
    end

    local pandemic = frame._quiPandemic
    if pandemic then
        local glow = profile.pandemicGlow
        SetRegionShown(pandemic, type(glow) == "table" and type(glow.color) == "table")
    end
end

local function DefaultResolve(element)
    local G = ns.AuraGlue
    if not (G and G.ElementProfile) then return nil end
    return G.ElementProfile(element), element.anchor or "TOPLEFT",
        element.offsetX or 0, element.offsetY or 0
end

local function LayoutElement(host, pool, poolCursor, element, resolve, opts)
    local p, framePoint, offX, offY, pinCorner = resolve(element)
    if not p then return poolCursor end
    local anchorTo = (opts and opts.anchorTo) or host

    local count
    if element.mode == "tracked" then
        local spells = element.spells
        local n = (type(spells) == "table") and #spells or 0
        local cap = element.maxIcons
        count = (cap and cap > 0 and cap < n) and cap or n
    else
        count = p.maxIcons
    end
    if count > 40 then count = 40 end
    if count < 1 then return poolCursor end

    local grow = p.grow
    local column = (grow == "UP" or grow == "DOWN")
    local left = (grow == "LEFT")
    local up
    if column then up = (grow == "UP") else up = (p.wrap == "UP") end
    local corner = pinCorner or ((up and "BOTTOM" or "TOP") .. (left and "RIGHT" or "LEFT"))

    local perRow = (p.maxPerRow and p.maxPerRow > 0) and p.maxPerRow or count
    if column then perRow = 1 end
    local centered = (grow == "CENTER")

    local size, gap = p.iconSize, p.spacing
    local displayType = (element.mode == "tracked") and element.displayType or nil
    local isBar = (displayType == "bar")
    local isSwatch = isBar or (displayType == "square")
    local barVertical = isBar and element.bar and element.bar.orientation == "VERTICAL"
    local barLong = isBar and ((element.bar and element.bar.length) or 48) or size
    local barThick = isBar and ((element.bar and element.bar.thickness) or 12) or size
    local w = barVertical and barThick or barLong
    local h = barVertical and barLong or barThick
    local stepX = w + gap
    local stepY = h + gap
    local color = element.color

    for i = 1, count do
        poolCursor = poolCursor + 1
        local f = AcquireIcon(host, pool, poolCursor, p, not isSwatch)
        f:SetSize(w, h)
        if isSwatch then
            f._tex:SetTexCoord(0, 1, 0, 1)
            f._tex:SetColorTexture((color and color[1]) or 1, (color and color[2]) or 1,
                (color and color[3]) or 1, (color and color[4]) or 1)
        else
            ApplyIconSample(f, element, p, i, {
                icon = opts and opts.icon,
                dispelColor = opts and opts.dispelColor,
            })
        end
        local row = math.floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        local dx
        if centered then
            local lineCount = perRow
            local remaining = count - row * perRow
            if remaining < perRow then lineCount = remaining end
            local lineSpan = lineCount * w + math.max(lineCount - 1, 0) * gap
            dx = col * stepX - lineSpan / 2
        else
            dx = (col * stepX) * (left and -1 or 1)
        end
        local dy = (row * stepY) * (up and 1 or -1)
        f:ClearAllPoints()
        f:SetPoint(corner, anchorTo, framePoint, offX + dx, offY + dy)
        f:SetAlpha(element.enabled ~= false and 1 or 0.35)
    end
    return poolCursor
end

function P.Show(hostFrame, elements, opts)
    local pool = hostFrame._quiAuraPreview
    if not pool then
        pool = {}
        hostFrame._quiAuraPreview = pool
    end
    local resolve = (opts and opts.resolve) or DefaultResolve
    local cursor = 0
    for i = 1, #elements do
        local e = elements[i]
        local render = (e.mode == "filterStrip")
            or (e.mode == "tracked" and e.displayType ~= "healthTint" and e.displayType ~= "border")
        if render and opts and opts.only then render = opts.only(e) end
        if render then
            cursor = LayoutElement(hostFrame, pool, cursor, e, resolve, opts)
        end
    end
    for i = cursor + 1, #pool do HidePreviewFrame(pool[i]) end
end

function P.Hide(hostFrame)
    local pool = hostFrame._quiAuraPreview
    if not pool then return end
    for i = 1, #pool do HidePreviewFrame(pool[i]) end
end

return P
