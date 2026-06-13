--- QUI Info Bar — shared data-shape helpers.
---
--- Lives in core (loaded at login, before BOTH consumers) because the two
--- consumers load in different contexts that have no common addon ancestor:
---   * QUI_InfoBar/infobar/contextmenu.lua  — via QUI_InfoBar.toc (LoD)
---   * QUI_InfoBar/infobar/settings/infobar_content.lua — via QUI_Options.toc (LoD)
--- An addon-level shared file is nil in whichever addon happens not to be
--- loaded; only a core symbol is guaranteed present for both.

local _, ns = ...

local Shared = ns.QUI_InfoBarShared or {}
ns.QUI_InfoBarShared = Shared

-- Per-widget boolean/scalar overrides. Sub-table guards only: AceDB defaults
-- supply every scalar, so writing them back here only seeds an absent entry —
-- it never pins shipped defaults into an existing profile. Self-guards
-- db.widgetSettings so either caller (the context menu, which has no prior
-- EnsureInfoBarConfig pass, or the settings page, which does) is safe.
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
