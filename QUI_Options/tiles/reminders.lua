local _, ns = ...

ns.QUI_RemindersTile = {}

function ns.QUI_RemindersTile.Register(frame)
    local Opts = ns.QUI_Options
    if not Opts or type(Opts.RegisterFeatureTile) ~= "function" then return end

    Opts.RegisterFeatureTile(frame, {
        id = "reminders",
        icon = "R",
        name = ns.L["Reminders"],
        moduleFeatureId = "moduleAddon_QUI_Reminders",
        subPages = {
            {
                id = "defensiveReminders",
                name = ns.L["Defensive Reminders"],
                sectionNav = true,
                featureId = "remindersPage",
                searchContext = {
                    tileId = "reminders", tabName = ns.L["Reminders"],
                    subPageIndex = 1, subTabName = ns.L["Defensive Reminders"],
                },
            },
            {
                id = "spellReminders",
                name = ns.L["Spell Reminders"],
                featureId = "spellRemindersPage",
                searchContext = {
                    tileId = "reminders", tabName = ns.L["Reminders"],
                    subPageIndex = 2, subTabName = ns.L["Spell Reminders"],
                },
            },
        },
    })
end
