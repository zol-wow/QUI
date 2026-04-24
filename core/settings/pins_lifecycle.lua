local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Pins = Settings.Pins
if not Pins then
    return
end

local Lifecycle = {}

function Lifecycle:OnNewProfile(event, db, profileName)
    if Pins and type(Pins.HandleProfileEvent) == "function" then
        Pins:HandleProfileEvent(event, db, profileName)
    end
end

function Lifecycle:OnProfileDeleted(event, db, profileName)
    if Pins and type(Pins.DropProfile) == "function" then
        Pins:DropProfile(profileName, db)
    end
end

local function RegisterCallbacks(core)
    local db = core and core.db
    if not db or type(db.RegisterCallback) ~= "function" or Pins._lifecycleRegistered then
        return
    end

    db.RegisterCallback(Lifecycle, "OnNewProfile", "OnNewProfile")
    db.RegisterCallback(Lifecycle, "OnProfileDeleted", "OnProfileDeleted")
    Pins._lifecycleRegistered = true
end

if ns.Addon and type(ns.Addon.RegisterPostInitialize) == "function" then
    ns.Addon:RegisterPostInitialize(RegisterCallbacks)
end
