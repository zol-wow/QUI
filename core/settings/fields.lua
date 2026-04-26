local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Fields = Settings.Fields or {}
Settings.Fields = Fields

local function CloneTable(source)
    local util = Settings.Util
    if util and type(util.ShallowCopy) == "function" then
        return util.ShallowCopy(source)
    end
    return {}
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

function Fields.Textarea(definition)
    return Fields.Define("textarea", definition)
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
        local enabled = ResolveValue(field.enabled, ctx, field, parent)
        if enabled == nil then
            enabled = true
        end
        widget = GUI:CreateButton(
            parent,
            ResolveValue(field.text or field.label, ctx, field, parent),
            field.width,
            field.height,
            function()
                if enabled ~= false and type(field.onClick) == "function" then
                    field.onClick(ctx, field, widget)
                end
            end,
            field.variant or field.style
        )
        if widget then
            if widget.EnableMouse then widget:EnableMouse(enabled ~= false) end
            if widget.SetAlpha then widget:SetAlpha(enabled ~= false and 1 or 0.45) end
        end
        if type(field.afterCreate) == "function" then
            field.afterCreate(ctx, widget, field)
        end
        return widget
    end

    if field.kind == "textarea" then
        local height = ResolveValue(field.height, ctx, field, parent) or 120
        local value = ""
        if type(field.getText) == "function" then
            value = field.getText(ctx, field) or ""
        else
            value = ResolveValue(field.text, ctx, field, parent) or ""
        end

        local wrapper = CreateFrame("Frame", nil, parent)
        wrapper:SetHeight(height + (field.label and 22 or 0))

        local anchor = wrapper
        if field.label then
            local label = GUI:CreateLabel(wrapper, ResolveValue(field.label, ctx, field, parent), 11)
            label:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
            label:SetPoint("RIGHT", wrapper, "RIGHT", 0, 0)
            label:SetJustifyH("LEFT")
            anchor = label
        end

        local box = GUI:CreateScrollableTextBox(wrapper, height, value, {
            fontSize = field.monospace ~= false and 10 or 11,
        })
        if field.label then
            box:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        else
            box:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
        end
        box:SetPoint("RIGHT", wrapper, "RIGHT", 0, 0)

        local editBox = box.editBox
        if editBox then
            local suppress
            if field.readOnly then
                editBox:SetScript("OnEditFocusGained", function(self)
                    self:HighlightText()
                end)
                editBox:SetScript("OnTextChanged", function(self, userInput)
                    if suppress or not userInput then
                        return
                    end
                    suppress = true
                    self:SetText(value)
                    self:HighlightText()
                    suppress = false
                end)
            elseif type(field.setText) == "function" then
                editBox:SetScript("OnTextChanged", function(self, userInput)
                    if userInput then
                        field.setText(ctx, self:GetText(), field)
                    end
                end)
            end
        end

        wrapper.textarea = box
        wrapper.editBox = editBox
        if type(field.afterCreate) == "function" then
            field.afterCreate(ctx, wrapper, field)
        end
        return wrapper
    end

    if field.kind == "custom" then
        local render = field.render or field.build
        if type(render) ~= "function" then
            return nil
        end
        local ok, result = pcall(render, parent, ctx, field)
        if ok then
            return result
        end

        local stub = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        stub:SetText("Section failed to render.")
        stub:SetTextColor(1, 0.35, 0.35, 1)
        local handler = geterrorhandler and geterrorhandler()
        if type(handler) == "function" then
            handler(result)
        end
        return stub
    end

    return nil
end
