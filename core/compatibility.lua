local ADDON_NAME, ns = ...

local DeepCopy = ns.Helpers.DeepCopy
local GLOBAL_SHIPPED_DEFAULTS_KEY = "_shippedProfileDefaults"
ns.Compatibility = ns.Compatibility or {}

local StampOldDefaults

local function DeepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not DeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

local function PinDefaultsRecursive(shadowNode, currentNode, rawNode)
    for key, shadowVal in pairs(shadowNode) do
        local currentVal = (type(currentNode) == "table") and currentNode[key] or nil
        local rawVal = rawget(rawNode, key)

        if currentVal == nil then
        elseif type(shadowVal) == "table" and type(currentVal) == "table" then
            if type(rawVal) == "table" then
                PinDefaultsRecursive(shadowVal, currentVal, rawVal)
            end
        else
            if rawVal == nil and not DeepEqual(shadowVal, currentVal) then
                rawset(rawNode, key, DeepCopy(shadowVal))
            end
        end
    end
end

local function PinTrackedDefaults(rawProfile, fallbackShadow)
    local profileShadow = rawget(rawProfile, "_shippedDefaults")
    local shadow = type(profileShadow) == "table" and profileShadow or fallbackShadow
    if type(shadow) ~= "table" then return end
    if not (ns.defaults and ns.defaults.profile) then return end
    PinDefaultsRecursive(shadow, ns.defaults.profile, rawProfile)
end

local function GetGlobalShippedDefaultsSnapshot(db)
    local global = db and db.global
    local shadow = global and global[GLOBAL_SHIPPED_DEFAULTS_KEY]
    return type(shadow) == "table" and shadow or nil
end

local function WriteGlobalShippedDefaultsSnapshot(db)
    if not db then return end
    if not (ns.defaults and ns.defaults.profile) then return end

    if not db.global then
        db.global = {}
    end

    local existing = db.global[GLOBAL_SHIPPED_DEFAULTS_KEY]
    if type(existing) == "table" and DeepEqual(existing, ns.defaults.profile) then
        return
    end

    db.global[GLOBAL_SHIPPED_DEFAULTS_KEY] = DeepCopy(ns.defaults.profile)
end

local function PruneShippedDefaultsSnapshot(rawProfile)
    if type(rawProfile) ~= "table" then return end
    rawset(rawProfile, "_shippedDefaults", nil)
end

local function PruneShippedDefaultsSnapshotAll(db)
    if not db then return end

    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        for _, rawProfile in pairs(profiles) do
            PruneShippedDefaultsSnapshot(rawProfile)
        end
        return
    end

    PruneShippedDefaultsSnapshot(db.profile)
end

local function RunShippedDefaultsMaintenance(db)
    StampOldDefaults(db)
    PruneShippedDefaultsSnapshotAll(db)
    WriteGlobalShippedDefaultsSnapshot(db)
end

ns.Compatibility.RunShippedDefaultsMaintenance = RunShippedDefaultsMaintenance

local function StampOldDefaultsOnRawProfile(rawProfile, fallbackShadow)
    if not rawProfile then return end

    local currentVersion = rawProfile._defaultsVersion or 0
    if currentVersion >= 3 then
        PinTrackedDefaults(rawProfile, fallbackShadow)
        return
    end

    local hasData = false
    for k in pairs(rawProfile) do
        if k ~= "_defaultsVersion" then
            hasData = true
            break
        end
    end
    if not hasData then
        rawset(rawProfile, "_defaultsVersion", 3)
        return
    end

    if currentVersion >= 2 then
        local rawGF = rawget(rawProfile, "quiGroupFrames")
        if type(rawGF) == "table" and rawget(rawGF, "enabled") == nil then
            rawset(rawGF, "enabled", true)
        end
    end

    PinTrackedDefaults(rawProfile, fallbackShadow)

    rawset(rawProfile, "_defaultsVersion", 3)
end

function StampOldDefaults(db)
    if not db then return end

    local fallbackShadow = GetGlobalShippedDefaultsSnapshot(db)
    local profiles = db.sv and db.sv.profiles
    if type(profiles) == "table" then
        for _, rawProfile in pairs(profiles) do
            StampOldDefaultsOnRawProfile(rawProfile, fallbackShadow)
        end
        return
    end

    StampOldDefaultsOnRawProfile(db.profile, fallbackShadow)
end

local function ReseedStarterFlaggedProfiles(db)
    if not db or not db.sv or type(db.sv.profiles) ~= "table" then return end
    if not ns.ApplyNewProfileSeed then return end
    for _, rawProfile in pairs(db.sv.profiles) do
        if type(rawProfile) == "table" and rawget(rawProfile, "_needsStarterReseed") then
            ns.ApplyNewProfileSeed(rawProfile)
            rawset(rawProfile, "_needsStarterReseed", nil)
        end
    end
end

function QUI:BackwardsCompat()
    local skipTierPass = ns._startupTierPassDone
    ns._startupTierPassDone = nil

    if not skipTierPass and self.db then
        RunShippedDefaultsMaintenance(self.db)
    end

    if not skipTierPass and ns.Migrations and ns.Migrations.Run then
        ns.Migrations.Run(self.db)
    end

    ReseedStarterFlaggedProfiles(self.db)

    if not self.db.global then
        self:DebugPrint("DB Global not found")
        self.db.global = {
            isDone = false,
            lastVersion = 0,
            imports = {}
        }
    end

    if not self.db.global.lastVersion then
        self.db.global.lastVersion = 0
    end
    if not self.db.global.imports then
        self.db.global.imports = {}
    end

    if not self.db.global.specTrackerSpells then
        self.db.global.specTrackerSpells = {}
    end

    if self.db.char then
        if not self.db.char.debug then
            self.db.char.debug = { reload = false }
        end

        if self.db.char.lastVersion and not self.db.global.lastVersion then
            self:DebugPrint("Last version found in char profile, but not global.")
            self.db.global.lastVersion = self.db.char.lastVersion
            self.db.char.lastVersion = nil
        end
    end

    if self.db and self.db.sv and type(self.db.sv.chars) == "table" then
        for _, rawChar in pairs(self.db.sv.chars) do
            if type(rawChar) == "table" then
                rawset(rawChar, "devOptionsV2", nil)
            end
        end
    elseif self.db and self.db.char then
        self.db.char.devOptionsV2 = nil
    end
end
