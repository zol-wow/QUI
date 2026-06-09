local ADDON_NAME, ns = ...

-- First-launch starter-profile wiring (runs inside QUI_Options because the
-- import engine — core/profile_io.lua — and the Coco import string only load
-- here). All decision/orchestration logic lives in the unit-tested, pure
-- ns.FirstRun.Run (core/first_run.lua); this file only supplies real runtime
-- dependencies once login is complete.

-- Defensive: headless tooling (e.g. the search-cache generator) loads the
-- QUI_Options TOC scripts with a bare ns and without bootstrap.lua's shared-ns
-- metatable, so WhenLoggedIn is absent there. Returning here also keeps the
-- StaticPopupDialogs registration below out of any non-client context.
if type(ns.WhenLoggedIn) ~= "function" then return end

-- C_UI.Reload() (what ReloadUI wraps) is PROTECTED: an addon can only trigger
-- it from a hardware event, so we cannot reload automatically at login. This
-- popup's button click IS that hardware event — the blessed pattern used by
-- Blizzard's own StaticPopupDialogs["TOO_MANY_LUA_ERRORS"] (OnAccept -> ReloadUI).
StaticPopupDialogs["QUI_FIRSTRUN_RELOAD"] = {
    text = "Welcome to QUI!\n\nThe Coco starter profile has been installed. A UI reload is required for it to apply correctly.",
    button1 = "Reload Now",
    button2 = "Later",
    OnAccept = function() ReloadUI() end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
}

ns.WhenLoggedIn(function()
    local FirstRun = ns.FirstRun
    local core = ns.Addon
    if not FirstRun or not core or not core.db then return end

    local key = FirstRun.STARTER_PRESET_KEY
    local preset = QUI.imports and QUI.imports[key]

    FirstRun.Run({
        freshInstall = ns._freshInstall,
        db           = core.db,
        importData   = preset and preset.data or nil,
        importFn     = function(data, target)
            -- pcall so a downstream refresh error during the login-time import
            -- can't leave firstRunComplete unset (which would retry the import
            -- every login). A thrown error is treated as a failed import.
            local pok, importOK = pcall(core.ImportProfileFromString, core, data, target)
            return pok and importOK
        end,
        promptReload = function()
            if StaticPopup_Show then StaticPopup_Show("QUI_FIRSTRUN_RELOAD") end
        end,
        notify       = print,
    })
end)
