local ADDON_NAME, ns = ...

local SettingsBuilders = {}
ns.SettingsBuilders = SettingsBuilders

local function GetGUI()
    return _G.QUI and _G.QUI.GUI
end

local function ShowProviderUnavailable(parent, message)
    if not parent then return 80 end

    local GUI = GetGUI()
    local label
    if GUI and GUI.CreateLabel then
        label = GUI:CreateLabel(parent, message or "Settings are still initializing.", 11, GUI.Colors and GUI.Colors.textMuted)
    else
        label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetText(message or "Settings are still initializing.")
        label:SetTextColor(0.65, 0.65, 0.65, 1)
    end

    label:SetPoint("TOPLEFT", 0, -8)
    label:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if label.SetJustifyH then
        label:SetJustifyH("LEFT")
    end
    if parent.SetHeight then
        parent:SetHeight(80)
    end
    return 80
end

local function GetProvider(providerKey)
    local settingsPanel = ns.QUI_LayoutMode_Settings
    if not settingsPanel or not settingsPanel._providers then
        return nil
    end
    return settingsPanel._providers[providerKey]
end

local function WithSuppressedPosition(includePosition, fn)
    local U = ns.QUI_LayoutMode_Utils
    local original = U and U.BuildPositionCollapsible
    local function ErrorHandler(err)
        local message = tostring(err)
        if type(_G.debugstack) == "function" then
            message = message .. "\n" .. _G.debugstack(2, 20, 20)
        end
        return message
    end

    if U and includePosition == false then
        U.BuildPositionCollapsible = function() end
    end

    local ok, result = xpcall(fn, ErrorHandler)

    if U and original then
        U.BuildPositionCollapsible = original
    end

    if not ok then
        geterrorhandler()(result)
        return nil
    end

    return result
end

local function BuildViaProvider(providerKey, parent, width, options)
    local provider = GetProvider(providerKey)
    if not provider or type(provider.build) ~= "function" then
        return ShowProviderUnavailable(parent, "Settings are still initializing. Please reopen this tab in a moment.")
    end

    local targetWidth = width or (parent and parent.GetWidth and parent:GetWidth()) or 400
    local height = WithSuppressedPosition(options and options.includePosition, function()
        return provider.build(parent, providerKey, targetWidth)
    end)

    if not height and parent and parent.GetHeight then
        height = parent:GetHeight()
    end
    if parent and parent.SetHeight and height then
        parent:SetHeight(math.max(height, 80))
    end
    return height or 80
end

function SettingsBuilders.BuildXPTrackerSettings(parent, width, options)
    return BuildViaProvider("xpTracker", parent, width, options)
end

function SettingsBuilders.BuildTooltipSettings(parent, width, options)
    return BuildViaProvider("tooltipAnchor", parent, width, options)
end

function SettingsBuilders.BuildChatSettings(parent, width, options)
    return BuildViaProvider("chatFrame1", parent, width, options)
end

function SettingsBuilders.BuildSkyridingSettings(parent, width, options)
    return BuildViaProvider("skyriding", parent, width, options)
end

function SettingsBuilders.BuildPartyKeystonesSettings(parent, width, options)
    return BuildViaProvider("partyKeystones", parent, width, options)
end

function SettingsBuilders.BuildMissingRaidBuffsSettings(parent, width, options)
    return BuildViaProvider("missingRaidBuffs", parent, width, options)
end

function SettingsBuilders.BuildMinimapSettings(parent, width, options)
    return BuildViaProvider("minimap", parent, width, options)
end

function SettingsBuilders.BuildDatatextSettings(parent, width, options)
    return BuildViaProvider("datatextPanel", parent, width, options)
end

function SettingsBuilders.BuildBuffDebuffSettings(kind, parent, width, options)
    local providerKey = kind == "debuff" and "debuffFrame" or "buffFrame"
    return BuildViaProvider(providerKey, parent, width, options)
end

function SettingsBuilders.BuildGroupFrameSettings(contextMode, parent, width, options)
    local providerKey = contextMode == "raid" and "raidFrames" or "partyFrames"
    return BuildViaProvider(providerKey, parent, width, options)
end
