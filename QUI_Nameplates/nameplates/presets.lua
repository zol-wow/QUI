local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local type = type
local pairs = pairs
local pcall = pcall
local rawget = rawget
local wipe = wipe
local CreateFrame = CreateFrame

local NPPresets = {}
NP.Presets = NPPresets

local EXCLUDED_KEYS = {
    enabled = true,
    specPresets = true,
    specAutoSwitch = true,
}
NPPresets.EXCLUDED_KEYS = EXCLUDED_KEYS

local CopyDeep = NP.CopyDeep
NPPresets.CopyDeep = CopyDeep
local IsArrayLike = NP.IsArrayLike

local function MergeDeep(target, patch)
    for k, v in pairs(patch) do
        if type(v) == "table" and not IsArrayLike(v) then
            if type(target[k]) ~= "table" then target[k] = {} end
            MergeDeep(target[k], v)
        else
            target[k] = CopyDeep(v)
        end
    end
end

function NPPresets.Snapshot(settings)
    settings = settings or NP.GetSettings()
    local shipped = ns.defaults and ns.defaults.profile and ns.defaults.profile.nameplates
    local snap = type(shipped) == "table" and CopyDeep(shipped) or {}
    MergeDeep(snap, settings)
    for k in pairs(EXCLUDED_KEYS) do
        snap[k] = nil
    end
    return snap
end

function NPPresets.ApplySnapshot(settings, snap)
    if type(settings) ~= "table" or type(snap) ~= "table" then return false end
    local complete = NPPresets.Snapshot(snap)
    for k in pairs(settings) do
        if not EXCLUDED_KEYS[k] and complete[k] == nil then
            settings[k] = nil
        end
    end
    for k, v in pairs(complete) do
        if type(v) == "table" then
            local target = rawget(settings, k)
            if type(target) ~= "table" then
                settings[k] = CopyDeep(v)
            else
                wipe(target)
                for k2, v2 in pairs(CopyDeep(v)) do
                    target[k2] = v2
                end
            end
        else
            settings[k] = v
        end
    end
    return true
end

local STARTER_STYLES = {
    compact = {
        health = { width = 160, height = 14 },
        castbar = { height = 12 },
        name = { size = 10 },
        healthText = { style = "none" },
    },
    chunky = {
        health = { width = 240, height = 32 },
        castbar = { height = 20 },
        name = { size = 13 },
        healthText = { style = "both" },
    },
}
NPPresets.STARTER_STYLES = STARTER_STYLES

function NPPresets.GetStarterStyleKeys()
    return { "default", "compact", "chunky" }
end

function NPPresets.ApplyStyleTable(styleKey)
    local settings = NP.GetSettings()
    if type(settings) ~= "table" then return false end

    NP.NormalizeTypes(settings)

    if styleKey == "default" then
        local shipped = ns.defaults and ns.defaults.profile and ns.defaults.profile.nameplates
        if type(shipped) ~= "table" then return false end
        return NPPresets.ApplySnapshot(settings, shipped)
    end

    local patch = STARTER_STYLES[styleKey]
    if type(patch) ~= "table" then return false end

    if type(settings.types) ~= "table" then return false end

    for _, typeKey in ipairs(NP.PlateType.ORDER) do
        local target = settings.types[typeKey]
        if type(target) == "table" then
            for k, v in pairs(patch) do
                if not EXCLUDED_KEYS[k] then
                    if type(v) == "table" then
                        if type(target[k]) ~= "table" then target[k] = {} end
                        MergeDeep(target[k], v)
                    else
                        target[k] = v
                    end
                end
            end
        end
    end
    return true
end

NPPresets.ROLES = { "TANK", "HEALER", "DAMAGER" }
local VALID_ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function GetGlobalDB()
    local db = _G.QUI and _G.QUI.db
    return db and db.global or nil
end

function NPPresets.PeekProfileStore()
    local g = GetGlobalDB()
    return g and g.nameplateProfiles or nil
end

function NPPresets.GetProfileStore()
    local g = GetGlobalDB()
    if not g then return nil end
    local store = g.nameplateProfiles
    if type(store) ~= "table" then
        store = {}
        g.nameplateProfiles = store
    end
    return store
end

function NPPresets.PeekAssignments()
    local g = GetGlobalDB()
    return g and g.nameplateProfileAssignments or nil
end

function NPPresets.GetAssignments()
    local g = GetGlobalDB()
    if not g then return nil end
    local assignments = g.nameplateProfileAssignments
    if type(assignments) ~= "table" then
        assignments = { autoSwitch = false }
        g.nameplateProfileAssignments = assignments
    end
    if type(assignments.specs) ~= "table" then assignments.specs = {} end
    if type(assignments.roles) ~= "table" then assignments.roles = {} end
    return assignments
end

local function GetCharDB()
    local db = _G.QUI and _G.QUI.db
    return db and db.char or nil
end

local function SetLastApplied(name)
    local char = GetCharDB()
    if char then char.nameplateActiveProfile = name end
end

function NPPresets.GetLastAppliedProfile()
    local char = GetCharDB()
    local name = char and char.nameplateActiveProfile or nil
    if NPPresets.HasProfile(name) then return name end
    return nil
end

local function TablesEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do
        if not TablesEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

-- "Modified" = the live settings no longer match the stored snapshot of the
-- last-applied profile (edits after apply, or the profile was overwritten).
function NPPresets.IsActiveProfileModified()
    local name = NPPresets.GetLastAppliedProfile()
    if not name then return false end
    local store = NPPresets.PeekProfileStore()
    return not TablesEqual(NPPresets.Snapshot(NP.GetSettings()), store[name])
end

function NPPresets.ListProfileNames()
    local names = {}
    local store = NPPresets.PeekProfileStore()
    if store then
        for name, snap in pairs(store) do
            if type(name) == "string" and type(snap) == "table" then
                names[#names + 1] = name
            end
        end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return names
end

function NPPresets.HasProfile(name)
    if type(name) ~= "string" or name == "" then return false end
    local store = NPPresets.PeekProfileStore()
    return store ~= nil and type(store[name]) == "table"
end

-- "__none" is the options UI's dropdown sentinel for "no profile"; a profile
-- carrying that literal name would be unselectable and unassignable.
NPPresets.RESERVED_NAME = "__none"

function NPPresets.SaveProfile(name)
    if type(name) ~= "string" then return false end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or name == NPPresets.RESERVED_NAME then return false end
    local store = NPPresets.GetProfileStore()
    if not store then return false end
    store[name] = NPPresets.Snapshot(NP.GetSettings())
    SetLastApplied(name)
    return true, name
end

function NPPresets.ApplyProfile(name)
    if not NPPresets.HasProfile(name) then return false end
    local store = NPPresets.PeekProfileStore()
    local ok = NPPresets.ApplySnapshot(NP.GetSettings(), store[name])
    if ok then
        SetLastApplied(name)
        if ns.QUI_RefreshNameplates then
            ns.QUI_RefreshNameplates()
        end
    end
    return ok
end

function NPPresets.RenameProfile(oldName, newName)
    if not NPPresets.HasProfile(oldName) then return false end
    if type(newName) ~= "string" then return false end
    newName = newName:gsub("^%s+", ""):gsub("%s+$", "")
    if newName == "" or newName == oldName or newName == NPPresets.RESERVED_NAME then return false end
    if NPPresets.HasProfile(newName) then return false end
    local store = NPPresets.PeekProfileStore()
    store[newName] = store[oldName]
    store[oldName] = nil
    local assignments = NPPresets.PeekAssignments()
    if assignments then
        for _, map in pairs({ assignments.specs, assignments.roles }) do
            if type(map) == "table" then
                for key, assigned in pairs(map) do
                    if assigned == oldName then map[key] = newName end
                end
            end
        end
    end
    local char = GetCharDB()
    if char and char.nameplateActiveProfile == oldName then
        char.nameplateActiveProfile = newName
    end
    return true, newName
end

function NPPresets.DeleteProfile(name)
    if not NPPresets.HasProfile(name) then return false end
    local store = NPPresets.PeekProfileStore()
    store[name] = nil
    local char = GetCharDB()
    if char and char.nameplateActiveProfile == name then
        char.nameplateActiveProfile = nil
    end
    local assignments = NPPresets.PeekAssignments()
    if assignments then
        for _, map in pairs({ assignments.specs, assignments.roles }) do
            if type(map) == "table" then
                for key, assigned in pairs(map) do
                    if assigned == name then map[key] = nil end
                end
            end
        end
    end
    return true
end

function NPPresets.AssignSpec(specID, name)
    if type(specID) ~= "number" or specID <= 0 then return false end
    if name ~= nil and not NPPresets.HasProfile(name) then return false end
    local assignments = NPPresets.GetAssignments()
    if not assignments then return false end
    assignments.specs[specID] = name
    return true
end

function NPPresets.AssignRole(role, name)
    if not VALID_ROLES[role] then return false end
    if name ~= nil and not NPPresets.HasProfile(name) then return false end
    local assignments = NPPresets.GetAssignments()
    if not assignments then return false end
    assignments.roles[role] = name
    return true
end

function NPPresets.GetSpecAssignment(specID)
    local assignments = NPPresets.PeekAssignments()
    local name = assignments and type(assignments.specs) == "table" and assignments.specs[specID] or nil
    if NPPresets.HasProfile(name) then return name end
    return nil
end

function NPPresets.GetRoleAssignment(role)
    local assignments = NPPresets.PeekAssignments()
    local name = assignments and type(assignments.roles) == "table" and assignments.roles[role] or nil
    if NPPresets.HasProfile(name) then return name end
    return nil
end

function NPPresets.IsAutoSwitchEnabled()
    local assignments = NPPresets.PeekAssignments()
    return assignments ~= nil and assignments.autoSwitch == true
end

function NPPresets.SetAutoSwitch(enabled)
    local assignments = NPPresets.GetAssignments()
    if not assignments then return false end
    assignments.autoSwitch = enabled == true
    return true
end

function NPPresets.GetCurrentSpecID()
    if not GetSpecialization or not GetSpecializationInfo then return nil end
    local ok, specIndex = pcall(GetSpecialization)
    specIndex = ok and NP.Plain(specIndex, "number") or nil
    if not specIndex or specIndex <= 0 then return nil end
    local ok2, specID = pcall(GetSpecializationInfo, specIndex)
    specID = ok2 and NP.Plain(specID, "number") or nil
    if specID and specID > 0 then return specID end
    return nil
end

function NPPresets.GetCurrentRole()
    if not GetSpecialization or not GetSpecializationRole then return nil end
    local ok, specIndex = pcall(GetSpecialization)
    specIndex = ok and NP.Plain(specIndex, "number") or nil
    if not specIndex or specIndex <= 0 then return nil end
    local ok2, role = pcall(GetSpecializationRole, specIndex)
    role = ok2 and NP.Plain(role, "string") or nil
    if role and VALID_ROLES[role] then return role end
    return nil
end

local function AutoSwitch()
    if not NP.IsEnabled() then return end
    if not NPPresets.IsAutoSwitchEnabled() then return end

    local specID = NPPresets.GetCurrentSpecID()
    local name = specID and NPPresets.GetSpecAssignment(specID) or nil
    if not name then
        local role = NPPresets.GetCurrentRole()
        name = role and NPPresets.GetRoleAssignment(role) or nil
    end
    if name then
        NPPresets.ApplyProfile(name)
    end
end
NPPresets.AutoSwitch = AutoSwitch

local eventFrame = CreateFrame("Frame")
if eventFrame.RegisterUnitEvent then
    eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
else
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        if arg1 == true then
            AutoSwitch()
        end
        return
    end
    if arg1 ~= nil and arg1 ~= "player" then return end
    AutoSwitch()
end)
