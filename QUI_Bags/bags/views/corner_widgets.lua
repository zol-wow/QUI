local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers

local function CJKFont(fs, p, s, f)
    if Bags.CJKFont then return Bags.CJKFont(fs, p, s, f) end
    fs:SetFont(p, s, f)
end

local CornerWidgets = {}
Bags.CornerWidgets = CornerWidgets

local EXPANSION_SHORT = {
    [0] = "Cls", "TBC", "WLK", "Cat", "MoP", "WoD", "Leg", "BfA", "SL", "DF",
    "TWW", "Mid",
}

local function TextColor(ctx)
    if ctx.qualityColorText and Bags.ItemButtons then
        return Bags.ItemButtons.GetQualityColor((ctx.entry and ctx.entry.quality) or 1)
    end
    return 1, 1, 1
end

CornerWidgets.Resolvers = {
    crafting_quality = function(ctx)
        if ctx.craftQualityAtlas then return { atlas = ctx.craftQualityAtlas } end
    end,
    upgrade_track = function(ctx)
        local u = ctx.upgradeTrack
        if u then return { text = u.text, r = u.r, g = u.g, b = u.b } end
    end,
    quantity = function(ctx)
        local c = ctx.entry and ctx.entry.count
        if c and c > 1 then
            return { text = tostring(c), r = 1, g = 1, b = 1 }
        end
    end,
    item_level = function(ctx)
        local d = ctx.details
        if d and d.ilvl and d.ilvl > 1 and d.isEquippable then
            local r, g, b = TextColor(ctx)
            return { text = tostring(d.ilvl), r = r, g = g, b = b }
        end
    end,
    junk = function(ctx)
        if ctx.isJunk then return { atlas = "bags-junkcoin" } end
    end,
    equipment_set = function(ctx)
        if ctx.inSet then return { atlas = "questlog-icon-setting" } end
    end,
    binding = function(ctx)
        local d = ctx.details
        if not d or d.isBound then return nil end
        local bt = d.bindType
        if bt == 2 then
            local r, g, b = TextColor(ctx)
            return { text = "BoE", r = r, g = g, b = b }
        elseif bt == 7 or bt == 8 or bt == 9 then
            local r, g, b = TextColor(ctx)
            return { text = "BoA", r = r, g = g, b = b }
        end
    end,
    expansion = function(ctx)
        local d = ctx.details
        local short = d and d.expacID and EXPANSION_SHORT[d.expacID]
        if short then return { text = short, r = 0.8, g = 0.8, b = 0.8 } end
    end,
}

function CornerWidgets.Select(id1, id2, ctx)
    if not ctx then return nil end
    local resolver = id1 and CornerWidgets.Resolvers[id1]
    local payload = resolver and resolver(ctx)
    if payload then return payload end
    resolver = id2 and CornerWidgets.Resolvers[id2]
    return resolver and resolver(ctx) or nil
end

local CORNERS = {
    { key = "tl", point = "TOPLEFT",     x = 2,  y = -1, justify = "LEFT" },
    { key = "tr", point = "TOPRIGHT",    x = -2, y = -1, justify = "RIGHT" },
    { key = "bl", point = "BOTTOMLEFT",  x = 2,  y = 1,  justify = "LEFT" },
    { key = "br", point = "BOTTOMRIGHT", x = -2, y = 1,  justify = "RIGHT" },
}

local function EnsureCorner(button, c)
    local store = button._quiCorners
    if not store then
        store = {}
        button._quiCorners = store
    end
    local slot = store[c.key]
    if not slot then
        local fs = button:CreateFontString(nil, "OVERLAY")
        fs:SetPoint(c.point, button, c.point, c.x, c.y)
        fs:SetJustifyH(c.justify)
        local tex = button:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetPoint(c.point, button, c.point, c.x, c.y)
        tex:SetSize(12, 12)
        slot = { fs = fs, tex = tex }
        store[c.key] = slot
    end
    return slot
end

function CornerWidgets.Apply(button, ctx, appearance)
    local corners = appearance and appearance.corners
    local fontSize = (appearance and appearance.cornerFontSize) or 11
    local iconSize = (appearance and appearance.cornerIconSize) or 12
    for _, c in ipairs(CORNERS) do
        local payload
        if ctx and corners then
            payload = CornerWidgets.Select(corners[c.key .. "1"], corners[c.key .. "2"], ctx)
        end
        local slot = button._quiCorners and button._quiCorners[c.key]
        if payload then
            slot = slot or EnsureCorner(button, c)
            if payload.text then
                CJKFont(slot.fs, Helpers.GetGeneralFont() or STANDARD_TEXT_FONT,
                    fontSize, "OUTLINE")
                slot.fs:SetText(payload.text)
                slot.fs:SetTextColor(payload.r or 1, payload.g or 1, payload.b or 1)
                slot.fs:Show()
                slot.tex:Hide()
            else
                slot.tex:SetAtlas(payload.atlas)
                slot.tex:SetSize(iconSize, iconSize)
                slot.tex:Show()
                slot.fs:Hide()
            end
        elseif slot then
            slot.fs:Hide()
            slot.tex:Hide()
        end
    end
end
