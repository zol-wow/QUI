local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local ModelKit = Settings.ModelKit or {}
Settings.ModelKit = ModelKit

function ModelKit.RenderUnavailable(host, label, suffix)
    if not host or not host.CreateFontString then
        return
    end

    local message = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOPLEFT", 20, -20)
    message:SetText((label or "Settings") .. (suffix or " unavailable."))
    if message.SetTextColor then
        message:SetTextColor(0.6, 0.6, 0.6, 1)
    end
end

function ModelKit.RenderSchema(schema, methodName, host, context, label, unavailableSuffix)
    local render = schema and schema[methodName]
    if type(render) == "function" and render(host, context) then
        return true
    end

    ModelKit.RenderUnavailable(host, label, unavailableSuffix)
    return false
end

function ModelKit.BuildSchemaRender(options)
    options = options or {}
    local schemaName = options.schemaName
    local methodName = options.methodName
    local label = options.label
    local selector = options.selector
    local suffix = options.unavailableSuffix

    return function(host, state)
        local schema = schemaName and ns[schemaName] or nil
        local context = selector and selector(state) or nil
        return ModelKit.RenderSchema(schema, methodName, host, context, label, suffix)
    end
end

function ModelKit.NormalizeTabDefinitions(definitions)
    return type(definitions) == "table" and definitions or {}
end
