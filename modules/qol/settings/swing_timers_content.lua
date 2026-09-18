local _, ns = ...

local SwingTimers = ns.SwingTimers
if not SwingTimers then return end

local GUI = QUI.GUI
local Shared = ns.QUI_Options
local Registry = ns.Settings.Registry
local Schema = ns.Settings.Schema

local function Row(parent, label, widget)
    return Shared.BuildSettingRow(parent, label, widget)
end

local function BuildEnable(L)
    L.headerAt(ns.L["General"])
    local section = L.sectionAt()
    local state = { enabled = SwingTimers.IsEnabled() }
    local enabled = GUI:CreateFormCheckbox(section.frame, nil, "enabled", state, function(value)
        SwingTimers.SetEnabled(value)
    end, { description = ns.L["Enable Forever's native swing timers for your equipped weapons."] })
    section.AddRow(Row(section.frame, ns.L["Enable Swing Timers"], enabled))
    L.closeSection(section)
end

local function BuildBar(L, entry, includeSize)
    local db = SwingTimers.GetSettings(entry.key)
    if not db then return end

    if includeSize then GUI:SetSearchSection(ns.L[entry.label]) end
    L.headerAt(ns.L[entry.label])
    local section = L.sectionAt()
    if includeSize then
        local width = GUI:CreateFormSlider(section.frame, nil, 80, 800, 1, "width", db, SwingTimers.Refresh,
            { description = ns.L["Swing timer width in pixels."] })
        local height = GUI:CreateFormSlider(section.frame, nil, 8, 80, 1, "height", db, SwingTimers.Refresh,
            { description = ns.L["Swing timer height in pixels."] })
        section.AddRow(Row(section.frame, ns.L["Width"], width), Row(section.frame, ns.L["Height"], height))
    end

    local texture = GUI:CreateFormDropdown(section.frame, nil, Shared.GetTextureList(), "texture", db, SwingTimers.Refresh,
        { description = ns.L["Status bar texture used for the swing timer fill."] })
    local fontSize = GUI:CreateFormSlider(section.frame, nil, 6, 32, 1, "fontSize", db, SwingTimers.Refresh,
        { description = ns.L["Font size for the weapon label and remaining swing time."] })
    section.AddRow(Row(section.frame, ns.L["Bar Texture"], texture))
    section.AddRow(Row(section.frame, ns.L["Font Size"], fontSize))

    local showTitle = GUI:CreateFormCheckbox(section.frame, nil, "showTitle", db, SwingTimers.Refresh,
        { description = ns.L["Show the weapon label on the swing timer."] })
    local showTime = GUI:CreateFormCheckbox(section.frame, nil, "showTime", db, SwingTimers.Refresh,
        { description = ns.L["Show the remaining time until the next swing."] })
    section.AddRow(Row(section.frame, ns.L["Show Title"], showTitle), Row(section.frame, ns.L["Show Time"], showTime))

    local visibility = GUI:CreateFormDropdown(section.frame, nil, {
        { value = 0, text = ns.L["Always"] },
        { value = 1, text = ns.L["In Combat"] },
        { value = 2, text = ns.L["Hidden"] },
    }, "visibility", db, SwingTimers.Refresh,
        { description = ns.L["When to show this swing timer during gameplay. Layout Mode always previews all three bars."] })
    section.AddRow(Row(section.frame, ns.L["Visibility"], visibility))
    L.closeSection(section)
end

local function BuildPage(content)
    local L = ns.QUI_SettingsLayoutShared.MakeLayout(content)
    BuildEnable(L)
    for _, entry in ipairs(SwingTimers.entries) do
        BuildBar(L, entry, true)
    end
    return L.finish()
end

Registry:RegisterFeature(Schema.Feature({
    id = "swingTimersPage",
    category = "gameplay",
    nav = { tileId = "gameplay", subPageIndex = 10 },
    getDB = function(profile) return profile and profile.swingTimers end,
    sections = {
        Schema.Section({ id = "settings", kind = "page", minHeight = 80, build = BuildPage }),
    },
}))

for _, entry in ipairs(SwingTimers.entries) do
    local barEntry = entry
    Registry:RegisterFeature(Schema.Feature({
        id = barEntry.key,
        moverKey = barEntry.key,
        category = "gameplay",
        nav = { tileId = "gameplay", subPageIndex = 10 },
        getDB = function(profile) return profile and profile.swingTimers and profile.swingTimers[barEntry.key] end,
        apply = SwingTimers.Refresh,
        render = {
            layout = function(content)
                local U = ns.QUI_LayoutMode_Utils
                local L = ns.QUI_SettingsLayoutShared.MakeLayout(content)
                BuildEnable(L)
                BuildBar(L, barEntry, false)
                local db = SwingTimers.GetSettings(barEntry.key)
                if not db then return L.finish() end

                local previous = U._layoutModePositionOnly
                U._layoutModePositionOnly = false
                local ok, err = xpcall(function()
                    U.BuildPositionCollapsible(content, barEntry.key, nil, L.sections, L.relayoutSections)
                    U.BuildSizeCollapsible(content, {
                        minW = 80, maxW = 800, minH = 8, maxH = 80,
                        getSize = function() return db.width, db.height end,
                        setSize = function(width, height)
                            db.width, db.height = width, height
                            SwingTimers.Refresh()
                        end,
                        widthDescription = ns.L["Swing timer width in pixels."],
                        heightDescription = ns.L["Swing timer height in pixels."],
                    }, L.sections, L.relayoutSections)
                    U.BuildOpenFullSettingsLink(content, barEntry.key, L.sections, L.relayoutSections)
                    L.relayoutSections()
                end, function(message) return message end)
                U._layoutModePositionOnly = previous
                if not ok then geterrorhandler()(err) end
                return content:GetHeight()
            end,
        },
    }))
end
