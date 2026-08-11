local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local CreateFrame = CreateFrame

local NPFriendly = {}
NP.Friendly = NPFriendly

function NPFriendly.GetEffectiveMode(friendlySettings, context)
    friendlySettings = friendlySettings or {}
    if friendlySettings.enabled == false then return "off" end
    if context and context.inInstance == true then
        local instanceMode = friendlySettings.showInInstances
        if instanceMode == false or instanceMode == "never" or instanceMode == nil then
            return "off"
        end
    end
    return "show"
end

function NPFriendly.InstanceForcesNameOnly(friendlySettings, context)
    friendlySettings = friendlySettings or {}
    if not (context and context.inInstance == true) then return false end
    return friendlySettings.showInInstances == "nameonly"
end

local function EffectiveMode()
    local s = NP.GetSettings()
    return NPFriendly.GetEffectiveMode(s.friendly, NP.Extras.GetContext())
end
NPFriendly.EffectiveMode = EffectiveMode

local function ApplyModeCVars()
    if not NP.IsEnabled() then return end
    local NPCVars = ns.QUI_NameplatesCVars
    if not NPCVars then return end

    local friendlyType = NP.GetTypeSettings({ npType = "friendly" })
    local s = NP.GetSettings()
    local nameOnly = NP.ResolveRenderMode(friendlyType) == "nameonly"
        or NPFriendly.InstanceForcesNameOnly(s and s.friendly, NP.Extras.GetContext())

    NPCVars.Set("nameplateShowOnlyNameForFriendlyPlayerUnits", nameOnly and 1 or 0)

    local classColors = friendlyType and friendlyType.name
        and friendlyType.name.classColorPlayers ~= false
    NPCVars.Set("nameplateUseClassColorForFriendlyPlayerUnitNames", classColors and 1 or 0)

    NPCVars.ApplyFriendlyVisibility()
end
NPFriendly.ApplyModeCVars = ApplyModeCVars

function NPFriendly.Reevaluate()
    if not NP.IsEnabled() then return end
    ApplyModeCVars()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:SetScript("OnEvent", function()
    NPFriendly.Reevaluate()
end)
