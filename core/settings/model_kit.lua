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
    message:SetText((label or ns.L["Settings"]) .. (suffix or ns.L[" unavailable."]))
    if message.SetTextColor then
        message:SetTextColor(1, 1, 1, 0.6)
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

function ModelKit.GetTabDefinition(model, tabKey)
    if type(model) ~= "table" or type(model.GetTabDefinitions) ~= "function" then return nil end
    for index, definition in ipairs(model.GetTabDefinitions()) do
        if definition.key == tabKey then return definition, index end
    end
end

-- Search walks the same tabs and selector options as the mounted surface.
-- Models supply only the state transform for their own selector.
function ModelKit.EnumerateSearchTabs(model)
    local destinations = {}
    if type(model) ~= "table" or type(model.GetTabDefinitions) ~= "function" then
        return destinations
    end
    for _, tab in ipairs(model.GetTabDefinitions()) do
        local contexts = type(model.GetSearchContexts) == "function"
            and model.GetSearchContexts(tab.key) or { { state = {}, searchContext = {} } }
        for _, context in ipairs(contexts or {}) do
            local state = context.state or {}
            if type(tab.render) == "function"
                and (type(tab.visible) ~= "function" or tab.visible(state, tab, model) ~= false) then
                local searchContext = {}
                for key, value in pairs(context.searchContext or {}) do
                    searchContext[key] = value
                end
                searchContext.surfaceTabKey = tab.key
                searchContext.subTabName = tab.label
                destinations[#destinations + 1] = {
                    tab = tab,
                    state = state,
                    searchContext = searchContext,
                    label = context.label,
                }
            end
        end
    end
    return destinations
end
