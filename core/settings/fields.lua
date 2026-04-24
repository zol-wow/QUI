local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Fields = Settings.Fields or {}
Settings.Fields = Fields

local function CloneTable(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

function Fields.Define(kind, definition)
    local field = CloneTable(definition)
    field.kind = kind
    return field
end

function Fields.Checkbox(definition)
    return Fields.Define("checkbox", definition)
end

function Fields.Slider(definition)
    return Fields.Define("slider", definition)
end

function Fields.Dropdown(definition)
    return Fields.Define("dropdown", definition)
end

function Fields.Color(definition)
    return Fields.Define("color", definition)
end

function Fields.Button(definition)
    return Fields.Define("button", definition)
end

function Fields.Custom(definition)
    return Fields.Define("custom", definition)
end

function Fields.Section(definition)
    return Fields.Define("section", definition)
end

local function ResolveValue(value, ctx, field, parent)
    if type(value) == "function" then
        return value(ctx, field, parent)
    end
    return value
end

local function ResolveStateTable(field, ctx, parent)
    local state = ResolveValue(field.state, ctx, field, parent)
    if type(state) == "table" then
        return state
    end
    return ctx and ctx.state
end

function Fields.Render(field, ctx, parent)
    local GUI = QUI and QUI.GUI
    if type(field) ~= "table" or type(field.kind) ~= "string" or not GUI then
        return nil
    end

    if field.kind == "dropdown" then
        local widget
        local options = ResolveValue(field.options, ctx, field, parent) or {}
        local stateTable = ResolveStateTable(field, ctx, parent)
        local stateKey = field.stateKey or field.key or field.dbKey
        local registryInfo = CloneTable(field.registryInfo)
        if field.pinLabel ~= nil and registryInfo.pinLabel == nil then
            registryInfo.pinLabel = field.pinLabel
        end
        if field.pinPath ~= nil and registryInfo.pinPath == nil then
            registryInfo.pinPath = field.pinPath
        end
        if field.pinnable ~= nil and registryInfo.pinnable == nil then
            registryInfo.pinnable = field.pinnable
        end
        widget = GUI:CreateFormDropdown(parent, field.label, options, stateKey, stateTable, function(value)
            if type(field.onChange) == "function" then
                field.onChange(ctx, value, field, widget)
            end
        end, registryInfo, field.opts)
        if field.width and widget.SetWidth then
            widget:SetWidth(field.width)
        end
        if field.height and widget.SetHeight then
            widget:SetHeight(field.height)
        end
        if type(field.afterCreate) == "function" then
            field.afterCreate(ctx, widget, field)
        end
        return widget
    end

    if field.kind == "button" then
        local widget
        widget = GUI:CreateButton(
            parent,
            ResolveValue(field.text or field.label, ctx, field, parent),
            field.width,
            field.height,
            function()
                if type(field.onClick) == "function" then
                    field.onClick(ctx, field, widget)
                end
            end,
            field.variant
        )
        if type(field.afterCreate) == "function" then
            field.afterCreate(ctx, widget, field)
        end
        return widget
    end

    if field.kind == "custom" and type(field.render) == "function" then
        return field.render(parent, ctx, field)
    end

    return nil
end
