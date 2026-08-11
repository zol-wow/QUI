local ADDON_NAME, ns = ...

local seedTable = {
    aura       = { "buff", "debuff", "raid buff", "custom tracker", "tracker" },
    bar        = { "action bar", "castbar", "power bar", "health bar" },
    timer      = { "cooldown", "duration" },
    party      = { "group", "click-cast", "click cast" },
    raid       = { "group", "raid buff", "raid frame" },
    color      = { "class color", "health color", "castbar color", "text color" },
    font       = { "text", "size" },
    position   = { "anchor", "offset", "layout" },
    cooldown   = { "cdm", "timer" },
    cdm        = { "cooldown", "cooldown manager" },
    keybind    = { "keybinding", "bind" },
    tooltip    = { "hover", "inspect" },
    chat       = { "channel", "message" },
    skyriding  = { "dragonriding", "flying" },
    minimap    = { "map", "datatext" },
    datatext   = { "minimap", "info" },
    infobar    = { "info bar", "data bar", "top bar", "bottom bar", "datatext" },
}

local expanded = {}
local function add(a, b)
    expanded[a] = expanded[a] or {}
    for _, existing in ipairs(expanded[a]) do
        if existing == b then return end
    end
    table.insert(expanded[a], b)
end
for key, syns in pairs(seedTable) do
    for _, syn in ipairs(syns) do
        add(key, syn)
        add(syn, key)
    end
end

local function Expand(term)
    term = (term or ""):lower()
    local out = { term }
    local syns = expanded[term]
    if syns then
        for _, s in ipairs(syns) do
            table.insert(out, s)
        end
    end
    return out
end

ns.QUI_SearchSynonyms = { Expand = Expand, _raw = expanded }
