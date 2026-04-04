local ADDON_NAME, ns = ...

local SettingsBuilders = {}
ns.SettingsBuilders = SettingsBuilders

local surfaceSeq = 0
local providerSurfaces = {}
local pendingProviderRefresh = {}

local function GetGUI()
    return _G.QUI and _G.QUI.GUI
end

local function NextSurfaceId(prefix)
    surfaceSeq = surfaceSeq + 1
    return string.format("%s:%d", prefix or "provider", surfaceSeq)
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

local function ClearHost(parent)
    if not parent then return end

    local GUI = GetGUI()
    if GUI and GUI.CleanupWidgetTree then
        GUI:CleanupWidgetTree(parent)
    end

    for _, child in ipairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    for _, region in ipairs({parent:GetRegions()}) do
        if region.Hide then
            region:Hide()
        end
    end

    if parent.SetHeight then
        parent:SetHeight(1)
    end
end

function SettingsBuilders.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    if not providerKey or not surfaceId or type(refreshFn) ~= "function" then return end
    providerSurfaces[surfaceId] = {
        providerKey = providerKey,
        refreshFn = refreshFn,
        isVisibleFn = isVisibleFn,
    }
end

function SettingsBuilders.UnregisterProviderSurface(surfaceId)
    if not surfaceId then return end
    providerSurfaces[surfaceId] = nil
end

local function FlushProviderRefresh(providerKey)
    local pending = pendingProviderRefresh[providerKey]
    pendingProviderRefresh[providerKey] = nil
    if not pending then return end

    for surfaceId, surface in pairs(providerSurfaces) do
        if surface.providerKey == providerKey and (pending.structural or not pending.skipSurfaceIds[surfaceId]) then
            local isVisible = true
            if surface.isVisibleFn then
                local okVisible, visible = pcall(surface.isVisibleFn)
                isVisible = okVisible and visible ~= false
            end
            if isVisible then
                pcall(surface.refreshFn, {
                    providerKey = providerKey,
                    structural = pending.structural == true,
                })
            end
        end
    end
end

function SettingsBuilders.NotifyProviderChanged(providerKey, opts)
    if not providerKey then return end
    opts = opts or {}

    local pending = pendingProviderRefresh[providerKey]
    if not pending then
        pending = {
            structural = false,
            skipSurfaceIds = {},
        }
        pendingProviderRefresh[providerKey] = pending
        C_Timer.After(0.05, function()
            FlushProviderRefresh(providerKey)
        end)
    end

    if opts.structural then
        pending.structural = true
    end
    if opts.sourceSurfaceId then
        pending.skipSurfaceIds[opts.sourceSurfaceId] = true
    end
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
    if not parent then return 80 end

    ClearHost(parent)

    local provider = GetProvider(providerKey)
    if not provider or type(provider.build) ~= "function" then
        return ShowProviderUnavailable(parent, "Settings are still initializing. Please reopen this tab in a moment.")
    end

    local targetWidth = width or (parent and parent.GetWidth and parent:GetWidth()) or 400
    local surfaceId = parent._quiProviderSurfaceId or NextSurfaceId("options-provider")
    parent._quiProviderSurfaceId = surfaceId
    parent._quiProviderSync = {
        providerKey = providerKey,
        surfaceId = surfaceId,
    }

    local function RefreshSurface()
        local latestWidth = math.max(300, (parent and parent.GetWidth and parent:GetWidth()) or targetWidth or 400)
        return BuildViaProvider(providerKey, parent, latestWidth, options)
    end

    parent._quiProviderSurfaceInfo = {
        providerKey = providerKey,
        surfaceId = surfaceId,
        refreshFn = RefreshSurface,
    }

    SettingsBuilders.RegisterProviderSurface(providerKey, surfaceId, RefreshSurface, function()
        return parent:IsShown()
    end)

    if not parent._quiProviderSurfaceHooks then
        parent._quiProviderSurfaceHooks = true
        parent:HookScript("OnHide", function(self)
            local info = self._quiProviderSurfaceInfo
            if info then
                SettingsBuilders.UnregisterProviderSurface(info.surfaceId)
            end
        end)
        parent:HookScript("OnShow", function(self)
            local info = self._quiProviderSurfaceInfo
            if not info then return end
            SettingsBuilders.RegisterProviderSurface(info.providerKey, info.surfaceId, info.refreshFn, function()
                return self:IsShown()
            end)
        end)
    end

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
