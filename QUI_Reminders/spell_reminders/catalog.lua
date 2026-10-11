local _, ns = ...
local M = ns.SpellReminderModel

-- Buff IDs, which can differ from the spell that applies them. The client
-- resolves localized names/icons; labels here disambiguate shared spell names.
M.buffs = {
    { 51271, "DEATHKNIGHT" }, { 42650, "DEATHKNIGHT" },
    { 162264, "DEMONHUNTER" }, { 1217607, "DEMONHUNTER" },
    { 102560, "DRUID" }, { 194223, "DRUID" }, { 106951, "DRUID" },
    { 375087, "EVOKER" },
    { 19574, "HUNTER" }, { 288613, "HUNTER" }, { 1250646, "HUNTER" },
    { 365362, "MAGE" }, { 190319, "MAGE" }, { 1247908, "MAGE" },
    { 1249625, "MONK" }, { 1248992, "MONK" },
    { 31884, "PALADIN" }, { 194249, "PRIEST" },
    { 1249810, "ROGUE" }, { 121471, "ROGUE" }, { 13750, "ROGUE" },
    { 1219480, "SHAMAN" }, { 114051, "SHAMAN" },
    { 1276166, "WARLOCK" }, { 266087, "WARLOCK" }, { 417282, "WARLOCK" },
    { 107574, "WARRIOR" }, { 1719, "WARRIOR" },
    { 1236994, "POTION", true }, { 1236616, "POTION", true },
}

function M.BuffIDs(pi, scope)
    local ids = {}
    local function Add(id, default)
        local enabled = pi.spells[id]
        if enabled == nil then enabled = default end
        local scopes = pi.separateBuffs and pi.spellScopes[id]
        if scopes and scopes[scope] ~= nil then enabled = scopes[scope] end
        if enabled then ids[id] = true end
    end
    for _, buff in ipairs(M.buffs) do Add(buff[1], not buff[3]) end
    for _, id in ipairs(pi.customSpells) do Add(id, true) end
    return ids
end
