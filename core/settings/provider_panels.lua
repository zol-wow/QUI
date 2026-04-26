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
        local adapters = Settings.RenderAdapters
        if adapters and type(adapters.NotifyProviderChanged) == "function" then
            adapters.NotifyProviderChanged(key, { structural = true })
        end
    end

    function ctx.NotifyProviderFor(widget, opts)
        if GUI and GUI.NotifyProviderChangedForWidget then
            GUI:NotifyProviderChangedForWidget(widget, opts)
        end
    end

    function ctx.CreateTileCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
        return U.CreateCollapsible(parent, title, contentHeight, buildFunc, sections, relayout)
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

ProviderPanels._pendingRegistrations = ProviderPanels._pendingRegistrations or {}
ProviderPanels._registeredCallbacks = ProviderPanels._registeredCallbacks or {}

function ProviderPanels:FlushPending()
    local pending = self._pendingRegistrations
    if type(pending) ~= "table" or #pending == 0 then
        return true
    end

    local ctx = self:GetContext()
    if not ctx then
        return false
    end

    self._pendingRegistrations = {}
    for _, registerFunc in ipairs(pending) do
        if self._registeredCallbacks[registerFunc] ~= true then
            self._registeredCallbacks[registerFunc] = true
            local ok, err = xpcall(function()
                registerFunc(ctx)
            end, geterrorhandler and geterrorhandler() or debug.traceback)
            if not ok then
                self._registeredCallbacks[registerFunc] = nil
            end
        end
    end

    return true
end

function ProviderPanels:ScheduleFlush()
    if self._flushFrame then
        return
    end

    local core = ns.Addon
    if core and type(core.RegisterPostInitialize) == "function" then
        core:RegisterPostInitialize(function()
            self:FlushPending()
        end)
    end

    local frame = CreateFrame("Frame")
    local elapsedSinceCheck = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSinceCheck = elapsedSinceCheck + (elapsed or 0)
        if elapsedSinceCheck < 0.05 then
            return
        end
        elapsedSinceCheck = 0
        if self:FlushPending() then
            frame:SetScript("OnUpdate", nil)
            frame:Hide()
            self._flushFrame = nil
        end
    end)
    frame:Show()
    self._flushFrame = frame
end

function ProviderPanels:RegisterAfterLoad(registerFunc)
    if type(registerFunc) ~= "function" then
        return
    end

    if self._registeredCallbacks[registerFunc] == true then
        return
    end

    local ctx = self:GetContext()
    if ctx then
        self._registeredCallbacks[registerFunc] = true
        registerFunc(ctx)
        return
    end

    self._pendingRegistrations[#self._pendingRegistrations + 1] = registerFunc
    self:ScheduleFlush()
end
