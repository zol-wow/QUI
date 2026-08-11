local ADDON_NAME, ns = ...

local Classification = {}
ns.Classification = Classification

Classification.DATA = {
    worldboss = { atlas = "worldquest-icon-boss",         color = { 1, 0.85, 0 } },
    elite     = { atlas = "nameplates-icon-elite-gold",   color = { 1, 0.84, 0 } },
    rare      = { atlas = "nameplates-icon-elite-silver", color = { 0.7, 0.7, 0.7 } },
    rareelite = { atlas = "nameplates-icon-elite-gold",   color = { 1, 0.5, 0 } },
}

function Classification.Resolve(classification, level)
    local data = Classification.DATA[classification]
    if not data and type(level) == "number" and level == -1 then
        data = Classification.DATA.worldboss
    end
    if not data then return nil end
    return data.atlas, data.color[1], data.color[2], data.color[3]
end
