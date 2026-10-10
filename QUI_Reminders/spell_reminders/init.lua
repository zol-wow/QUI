local _, ns = ...
local R = ns.SpellReminders

-- A load-on-demand addon can start after login, when WhenLoggedIn runs
-- immediately. Initialize only after the tracking implementation has loaded.
ns.WhenLoggedIn(R.Refresh)
ns.Registry:Register("spellReminders", { refresh = function()
    ns.SpellReminderTracking.Reset()
    for _, state in pairs(R.states) do state.status = nil end
    R.Refresh()
end, priority = 35, group = "combat", importCategories = { "trackersTimers" } })
