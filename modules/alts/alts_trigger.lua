local _, ns = ...

_G.QUI_OpenAltsRoster = function()
    local p = QUI and QUI.db and QUI.db.profile
    if p and p.alts and p.alts.enabled == false then return end
    if ns.Alts and ns.Alts.Window then ns.Alts.Window.Toggle() end
end
