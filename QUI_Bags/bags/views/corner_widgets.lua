---------------------------------------------------------------------------
-- Bags views: per-corner icon widgets.
--
-- Each button corner (tl/tr/bl/br) carries a primary + fallback widget
-- pick (appearance.corners.tl1/tl2/...; scalar keys by design — array
-- defaults resurrect removed entries at login, the AceDB array-prefix
-- landmine). The first widget that yields content for the item renders;
-- "none" and inapplicable widgets fall through.
--
-- Widget facts come from the shared cache layer: Details.Build supplies
-- ilvl/bindType/expacID/equipLoc through ItemInfo (async-aware — a miss
-- re-renders on the next refresh once item data loads). Live-only facts
-- (junk, equipment set) are computed by the dress path and passed in ctx.
--
-- Select is PURE (ctx in, payload out) — TDD'd in
-- tests/unit/bags_corner_widgets_test.lua.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...
local Bags = ns.Bags or {}; ns.Bags = Bags
local Helpers = ns.Helpers

local CornerWidgets = {}
Bags.CornerWidgets = CornerWidgets

-- expacID (GetItemInfo returns[15]) → short label
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

--- ctx = { entry, details, isJunk, inSet, qualityColorText,
---         craftQualityAtlas (tier badge atlas, dress-path supplied) }
--- Resolver returns { text, r, g, b } | { atlas } | nil (inapplicable).
CornerWidgets.Resolvers = {
    crafting_quality = function(ctx)
        -- profession quality tier badge (reagent r1–r5 / crafted gear rank);
        -- the dress path resolves the atlas via C_TradeSkillUI (live fact —
        -- the pure core only consumes it)
        if ctx.craftQualityAtlas then return { atlas = ctx.craftQualityAtlas } end
    end,
    quantity = function(ctx)
        local c = ctx.entry and ctx.entry.count
        if c and c > 1 then
            return { text = tostring(c), r = 1, g = 1, b = 1 }
        end
    end,
    item_level = function(ctx)
        local d = ctx.details
        -- equippables only: ilvl on consumables/reagents is API filler
        if d and d.ilvl and d.ilvl > 1 and d.equipLoc and d.equipLoc ~= "" then
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
        -- ItemConstantsDocumentation Enum.ItemBind: 2 = OnEquip;
        -- 7/8/9 = ToWoWAccount/ToBnetAccount/ToBnetAccountUntilEquipped.
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

--- Pure core: first applicable of (primary, fallback). "none"/nil/unknown
--- ids fall through.
function CornerWidgets.Select(id1, id2, ctx)
    if not ctx then return nil end
    local resolver = id1 and CornerWidgets.Resolvers[id1]
    local payload = resolver and resolver(ctx)
    if payload then return payload end
    resolver = id2 and CornerWidgets.Resolvers[id2]
    return resolver and resolver(ctx) or nil
end

---------------------------------------------------------------------------
-- Renderer (frame-facing)
---------------------------------------------------------------------------
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

--- Render all four corners for a button. ctx nil (empty slot) hides all.
function CornerWidgets.Apply(button, ctx, appearance)
    local corners = appearance and appearance.corners
    local fontSize = (appearance and appearance.cornerFontSize) or 11
    for _, c in ipairs(CORNERS) do
        local payload
        if ctx and corners then
            payload = CornerWidgets.Select(corners[c.key .. "1"], corners[c.key .. "2"], ctx)
        end
        local slot = button._quiCorners and button._quiCorners[c.key]
        if payload then
            slot = slot or EnsureCorner(button, c)
            if payload.text then
                slot.fs:SetFont(Helpers.GetGeneralFont() or STANDARD_TEXT_FONT,
                    fontSize, "OUTLINE")
                slot.fs:SetText(payload.text)
                slot.fs:SetTextColor(payload.r or 1, payload.g or 1, payload.b or 1)
                slot.fs:Show()
                slot.tex:Hide()
            else
                slot.tex:SetAtlas(payload.atlas)
                slot.tex:Show()
                slot.fs:Hide()
            end
        elseif slot then
            slot.fs:Hide()
            slot.tex:Hide()
        end
    end
end
