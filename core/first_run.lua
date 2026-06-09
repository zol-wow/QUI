local ADDON_NAME, ns = ...

-- First-run / fresh-install starter-profile logic.
--
-- This module is intentionally PURE and dependency-injected so it can be unit
-- tested headlessly. It holds NO reference to the import engine or any
-- QUI_Options symbol — the engine, the Coco import string, ReloadUI and
-- C_Timer are passed in by the QUI_Options wiring (QUI_Options/first_run.lua).
--
-- Division of responsibility:
--   * core/init.lua            captures the fresh-install signal (QUI_DB == nil)
--                              before AceDB:New and publishes ns._freshInstall.
--   * core/first_run.lua       (this file) decides + orchestrates, pure.
--   * QUI_Options/first_run.lua wires real dependencies at PLAYER_LOGIN.

local FirstRun = {}
ns.FirstRun = FirstRun

-- The bundled preset installed on first launch (QUI._presetProfiles key) and
-- the profile it is written into (the AceDB default profile, overwritten in
-- place so the active profile stays "Default").
FirstRun.STARTER_PRESET_KEY = "CocoProfile"
FirstRun.STARTER_TARGET = "Default"

-- Pure: the account has never run QUI if neither saved variable exists yet.
-- Must be evaluated BEFORE AceDB:New / the QuaziiUI_DB alias populate QUI_DB.
function FirstRun.IsFreshInstall(quiDB, quaziiDB)
    return quiDB == nil and quaziiDB == nil
end

-- Pure: only auto-install on a confirmed fresh install that has not already
-- run the first-run flow.
function FirstRun.ShouldInstall(freshInstall, marker)
    return freshInstall == true and not marker
end

-- Orchestrate the first-run install. Dependency-injected for testability.
--
-- deps = {
--   freshInstall = boolean,                  -- ns._freshInstall from init.lua
--   db           = AceDB object,             -- requires db.global
--   importData   = string|nil,               -- Coco profile export string
--   importFn     = function(data, target) -> ok, msg,
--   promptReload = function(),               -- show the reload popup (its
--                                            -- button click performs ReloadUI)
--   notify       = function(msg),            -- print
-- }
--
-- A UI reload (C_UI.Reload) is a PROTECTED call that addons may only trigger
-- from a hardware event, so we cannot reload automatically. On success we show
-- a popup (promptReload) whose button click does the reload.
--
-- Returns true only when the import succeeded (the reload popup is then shown).
function FirstRun.Run(deps)
    if type(deps) ~= "table" then return false end

    local db = deps.db
    if not db or type(db.global) ~= "table" then return false end

    if not FirstRun.ShouldInstall(deps.freshInstall, db.global.firstRunComplete) then
        return false
    end

    local data = deps.importData
    local ok = false
    if type(data) == "string" and data ~= "" and type(deps.importFn) == "function" then
        ok = deps.importFn(data, FirstRun.STARTER_TARGET) and true or false
    end

    -- Seal the marker either way: never retry on a later login (the import
    -- string is shipped by us, so a failure means a real problem, not a
    -- transient one — re-running every login would just loop).
    db.global.firstRunComplete = true

    if ok then
        if deps.notify then
            deps.notify("|cff60A5FAQUI:|r Installed the Coco starter profile. A UI reload is required to finish — see the popup.")
        end
        if deps.promptReload then
            deps.promptReload()
        end
    else
        if deps.notify then
            deps.notify("|cff60A5FAQUI:|r Could not install the starter profile; using QUI defaults.")
        end
    end

    return ok
end
