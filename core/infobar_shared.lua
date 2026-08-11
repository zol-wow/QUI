local _, ns = ...

local Shared = ns.QUI_InfoBarShared or {}
ns.QUI_InfoBarShared = Shared

function Shared.EnsureWidgetSettings(db, widgetId)
    if not db.widgetSettings then db.widgetSettings = {} end
    if not db.widgetSettings[widgetId] then
        db.widgetSettings[widgetId] = { shortLabel = false, noLabel = false,
            minWidth = 0, xOffset = 0, hideIcon = false, clickThrough = false }
    end
    local ws = db.widgetSettings[widgetId]
    if ws.shortLabel == nil then ws.shortLabel = false end
    if ws.noLabel == nil then ws.noLabel = false end
    if ws.minWidth == nil then ws.minWidth = 0 end
    if ws.xOffset == nil then ws.xOffset = 0 end
    if ws.hideIcon == nil then ws.hideIcon = false end
    if ws.clickThrough == nil then ws.clickThrough = false end
    return ws
end
