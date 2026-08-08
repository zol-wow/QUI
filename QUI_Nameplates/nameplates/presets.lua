local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local type = type
local pairs = pairs
local pcall = pcall
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

function NPPresets.Snapshot(settings)
    settings = settings or NP.GetSettings()
    local snap = {}
    for k, v in pairs(settings) do
        if not EXCLUDED_KEYS[k] then
            snap[k] = CopyDeep(v)
        end
    end
    return snap
end

function NPPresets.ApplySnapshot(settings, snap)
    if type(settings) ~= "table" or type(snap) ~= "table" then return false end
    for k, v in pairs(snap) do
        if not EXCLUDED_KEYS[k] then
            if type(v) == "table" then
                if type(settings[k]) ~= "table" then
                    settings[k] = {}
                else
                    wipe(settings[k])
                end
                for k2, v2 in pairs(CopyDeep(v)) do
                    settings[k][k2] = v2
                end
            else
                settings[k] = v
            end
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

local function PresetStore()
    local settings = NP.GetSettings()
    settings.specPresets = settings.specPresets or {}
    return settings.specPresets, settings
end

function NPPresets.HasPreset(specIndex)
    if type(specIndex) ~= "number" then return false end
    local store = PresetStore()
    return type(store[specIndex]) == "table"
end

function NPPresets.SaveForSpec(specIndex)
    if type(specIndex) ~= "number" then return false end
    local store, settings = PresetStore()
    store[specIndex] = NPPresets.Snapshot(settings)
    return true
end

function NPPresets.ClearForSpec(specIndex)
    if type(specIndex) ~= "number" then return false end
    local store = PresetStore()
    store[specIndex] = nil
    return true
end

function NPPresets.ApplyForSpec(specIndex)
    if not NPPresets.HasPreset(specIndex) then return false end
    local store, settings = PresetStore()
    local ok = NPPresets.ApplySnapshot(settings, store[specIndex])
    if ok and ns.QUI_RefreshNameplates then
        ns.QUI_RefreshNameplates()
    end
    return ok
end

NPPresets.ROLES = { "TANK", "HEALER", "DAMAGER" }
local VALID_ROLES = { TANK = true, HEALER = true, DAMAGER = true }

local function PeekRoleStore()
    local db = _G.QUI and _G.QUI.db
    local g = db and db.global
    return g and g.nameplateRolePresets or nil
end
NPPresets.PeekRoleStore = PeekRoleStore

function NPPresets.GetRoleStore()
    local db = _G.QUI and _G.QUI.db
    local g = db and db.global
    if not g then return nil end
    g.nameplateRolePresets = g.nameplateRolePresets or { autoSwitch = false }
    return g.nameplateRolePresets
end

function NPPresets.HasRolePreset(role)
    if not VALID_ROLES[role] then return false end
    local store = PeekRoleStore()
    return store ~= nil and type(store[role]) == "table"
end

function NPPresets.SaveForRole(role)
    if not VALID_ROLES[role] then return false end
    local store = NPPresets.GetRoleStore()
    if not store then return false end
    store[role] = NPPresets.Snapshot(NP.GetSettings())
    return true
end

function NPPresets.ClearForRole(role)
    if not VALID_ROLES[role] then return false end
    local store = NPPresets.GetRoleStore()
    if not store then return false end
    store[role] = nil
    return true
end

function NPPresets.ApplyForRole(role)
    if not NPPresets.HasRolePreset(role) then return false end
    local store = PeekRoleStore()
    local ok = NPPresets.ApplySnapshot(NP.GetSettings(), store[role])
    if ok and ns.QUI_RefreshNameplates then
        ns.QUI_RefreshNameplates()
    end
    return ok
end

function NPPresets.GetCurrentSpec()
    if not GetSpecialization then return nil end
    local ok, spec = pcall(GetSpecialization)
    spec = ok and NP.Plain(spec, "number") or nil
    if spec and spec > 0 then return spec end
    return nil
end

function NPPresets.GetCurrentRole()
    local spec = NPPresets.GetCurrentSpec()
    if not spec or not GetSpecializationRole then return nil end
    local ok, role = pcall(GetSpecializationRole, spec)
    role = ok and NP.Plain(role, "string") or nil
    if role and VALID_ROLES[role] then return role end
    return nil
end

local function AutoSwitch()
    if not NP.IsEnabled() then return end

    local settings = NP.GetSettings()
    if settings.specAutoSwitch == true then
        local spec = NPPresets.GetCurrentSpec()
        if spec and NPPresets.HasPreset(spec) then
            NPPresets.ApplyForSpec(spec)
            return
        end
    end

    local store = PeekRoleStore()
    if store and store.autoSwitch == true then
        local role = NPPresets.GetCurrentRole()
        if role and NPPresets.HasRolePreset(role) then
            NPPresets.ApplyForRole(role)
        end
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
