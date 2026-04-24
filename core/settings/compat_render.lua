local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local CompatRender = Settings.CompatRender or {}
Settings.CompatRender = CompatRender

local function GetBuilders()
    return ns.SettingsBuilders
end

local function ClearFrame(frame)
    if not frame then
        return
    end

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            if child.Hide then child:Hide() end
            if child.ClearAllPoints then child:ClearAllPoints() end
            if child.SetParent then child:SetParent(nil) end
        end
    end

    if frame.GetRegions then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region.Hide then region:Hide() end
            if region.SetParent then region:SetParent(nil) end
        end
    end
end

function CompatRender.WithTileLayout(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithTileLayout) == "function" then
        return builders.WithTileLayout(fn)
    end

    return fn()
end

function CompatRender.WithOnlySections(whitelist, fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithOnlySections) == "function" then
        return builders.WithOnlySections(whitelist, fn)
    end

    return fn()
end

function CompatRender.BuildProvider(providerKey, parent, width, options)
    local builders = GetBuilders()
    if not builders or type(builders.BuildProvider) ~= "function" then
        return nil
    end

    return builders.BuildProvider(providerKey, parent, width, options)
end

function CompatRender.WithSuppressedPosition(includePosition, fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithSuppressedPosition) == "function" then
        return builders.WithSuppressedPosition(includePosition, fn)
    end

    return fn()
end

function CompatRender.NotifyProviderChanged(providerKey, opts)
    local builders = GetBuilders()
    if builders and type(builders.NotifyProviderChanged) == "function" then
        builders.NotifyProviderChanged(providerKey, opts)
    end
end

function CompatRender.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    local builders = GetBuilders()
    if builders and type(builders.RegisterProviderSurface) == "function" then
        builders.RegisterProviderSurface(providerKey, surfaceId, refreshFn, isVisibleFn)
    end
end

function CompatRender.UnregisterProviderSurface(surfaceId)
    local builders = GetBuilders()
    if builders and type(builders.UnregisterProviderSurface) == "function" then
        builders.UnregisterProviderSurface(surfaceId)
    end
end

function CompatRender.WithOnlyPosition(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local builders = GetBuilders()
    if builders and type(builders.WithOnlyPosition) == "function" then
        return builders.WithOnlyPosition(fn)
    end

    return fn()
end

function CompatRender.GetProviderLabel(providerKey, fallback)
    local builders = GetBuilders()
    local labels = builders and builders.PROVIDER_LABELS
    if type(labels) == "table" and type(labels[providerKey]) == "string" then
        return labels[providerKey]
    end

    return fallback or providerKey
end

function CompatRender.RenderOwnerPage(host, ownerName, fnName, opts)
    local function invoke()
        local owner = ns[ownerName]
        local render = owner and owner[fnName]
        if type(render) ~= "function" then
            return nil
        end

        ClearFrame(host)
        local result = render(host)
        if type(result) == "number" then
            return result
        end

        return host and host.GetHeight and host:GetHeight() or nil
    end

    if opts and opts.tileLayout then
        return CompatRender.WithTileLayout(invoke)
    end

    return invoke()
end
