local ADDON_NAME, ns = ...
local Helpers = ns.Helpers

local GetSettings = Helpers.CreateDBGetter("general")

local function FindDriverIndexByName(name)
    if not name or name == "" then return nil end
    if type(Sound_GameSystem_GetNumOutputDrivers) ~= "function"
        or type(Sound_GameSystem_GetOutputDriverNameByIndex) ~= "function" then
        return nil
    end
    local count = Sound_GameSystem_GetNumOutputDrivers() or 0
    for index = 0, count - 1 do
        if Sound_GameSystem_GetOutputDriverNameByIndex(index) == name then
            return index
        end
    end
    return nil
end

local function ApplyPreferredDevice()
    local settings = GetSettings()
    local preferred = settings and settings.audioOutputDevice
    if not preferred or preferred == "" then return end

    local index = FindDriverIndexByName(preferred)
    if not index then return end

    local current = tonumber(GetCVar("Sound_OutputDriverIndex"))
    if current == index then return end

    pcall(SetCVar, "Sound_OutputDriverIndex", index)
end
ns.ApplyPreferredAudioDevice = ApplyPreferredDevice

local function GetAudioDeviceOptions()
    local options = { { value = "", text = ns.L["Off (don't lock)"] } }
    if type(Sound_GameSystem_GetNumOutputDrivers) == "function"
        and type(Sound_GameSystem_GetOutputDriverNameByIndex) == "function" then
        local count = Sound_GameSystem_GetNumOutputDrivers() or 0
        for index = 0, count - 1 do
            local name = Sound_GameSystem_GetOutputDriverNameByIndex(index)
            if name and name ~= "" then
                options[#options + 1] = { value = name, text = name }
            end
        end
    end
    return options
end
ns.GetAudioDeviceOptions = GetAudioDeviceOptions

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("SOUND_DEVICE_UPDATE")
watcher:SetScript("OnEvent", function()
    ApplyPreferredDevice()
end)

if ns.WhenLoggedIn then
    ns.WhenLoggedIn(ApplyPreferredDevice)
end

if ns.Registry then
    ns.Registry:Register("audioDeviceLock", {
        refresh = ApplyPreferredDevice,
        priority = 30,
        group = "qol",
        importCategories = { "qol" },
    })
end
