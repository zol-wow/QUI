local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local ProviderPanels = Settings.ProviderPanels or {}
Settings.ProviderPanels = ProviderPanels

local function BuildAnchorOptions()
    return {
        { value = "TOPLEFT", text = "Top Left" },
        { value = "TOP", text = "Top" },
        { value = "TOPRIGHT", text = "Top Right" },
        { value = "LEFT", text = "Left" },
        { value = "CENTER", text = "Center" },
        { value = "RIGHT", text = "Right" },
        { value = "BOTTOMLEFT", text = "Bottom Left" },
        { value = "BOTTOM", text = "Bottom" },
        { value = "BOTTOMRIGHT", text = "Bottom Right" },
    }
end

function ProviderPanels:GetContext()
    local settingsPanel = ns.QUI_LayoutMode_Settings
    local GUI = QUI and QUI.GUI
    local U = ns.QUI_LayoutMode_Utils
    if not settingsPanel or not GUI or not U then
        return nil
    end

    local ctx = {
        settingsPanel = settingsPanel,
        GUI = GUI,
        U = U,
        P = U.PlaceRow,
        FORM_ROW = U.FORM_ROW,
        anchorOptions = BuildAnchorOptions(),
    }

    function ctx.RegisterShared(key, provider)
        settingsPanel:RegisterSharedProvider(key, provider)
    end

    function ctx.NotifyProviderFor(widget, opts)
        if GUI and GUI.NotifyProviderChangedForWidget then
            GUI:NotifyProviderChangedForWidget(widget, opts)
        end
    end

    function ctx.CreateSingleColumnCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        return U.CreateCollapsible(parent, title, contentHeight, function(body)
            local section = body and (body._logicalSection or (body.GetParent and body:GetParent()))
            if section then
                section._quiSkipDualColumnLayout = true
            end
            if body then
                body._quiSkipDualColumnLayout = true
            end
            if buildFunc then
                buildFunc(body)
            end
        end, sections, relayout)
    end

    return ctx
end

function ProviderPanels:RegisterAfterLoad(registerFunc)
    if type(registerFunc) ~= "function" then
        return
    end

    C_Timer.After(3, function()
        local ctx = self:GetContext()
        if ctx then
            registerFunc(ctx)
        end
    end)
end
