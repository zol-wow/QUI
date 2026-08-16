local ADDON_NAME, ns = ...

local QUI_Modules = {
    _specific = {},
    _wildcard = {},
    _nextToken = 1,
    _changeSerialByFeature = {},
}
ns.QUI_Modules = QUI_Modules

local function NewToken(self)
    local t = self._nextToken
    self._nextToken = t + 1
    return t
end

function QUI_Modules:Subscribe(featureId, callback)
    if type(callback) ~= "function" then return nil end
    local token = { id = NewToken(self), key = featureId }
    if featureId == "*" then
        self._wildcard[token.id] = callback
    elseif type(featureId) == "string" and featureId ~= "" then
        local bucket = self._specific[featureId]
        if not bucket then
            bucket = {}
            self._specific[featureId] = bucket
        end
        bucket[token.id] = callback
    else
        return nil
    end
    return token
end

function QUI_Modules:Unsubscribe(token)
    if type(token) ~= "table" or type(token.id) ~= "number" then return end
    if token.key == "*" then
        self._wildcard[token.id] = nil
        return
    end
    local bucket = self._specific[token.key]
    if bucket then
        bucket[token.id] = nil
    end
end

local function DispatchCallback(cb, featureId)
    local ok, err = pcall(cb, featureId)
    if not ok and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[QUI_Modules]|r " .. tostring(err))
    end
end

function QUI_Modules:NotifyChanged(featureId)
    if type(featureId) ~= "string" or featureId == "" then return end
    self._changeSerialByFeature[featureId]
        = (self._changeSerialByFeature[featureId] or 0) + 1
    local bucket = self._specific[featureId]
    if bucket then
        for _, cb in pairs(bucket) do
            DispatchCallback(cb, featureId)
        end
    end
    for _, cb in pairs(self._wildcard) do
        DispatchCallback(cb, featureId)
    end

    -- Module master switches are also rendered as ordinary settings widgets
    -- on several feature pages. Refresh every live binding after the shared
    -- state changes so those controls cannot retain a stale visual value.
    local GUI = _G.QUI and _G.QUI.GUI
    if GUI and type(GUI.RefreshWidgetInstances) == "function" then
        GUI:RefreshWidgetInstances()
    end
end

local function GetModuleEntry(featureId)
    local settings = ns.Settings
    local registry = settings and settings.Registry
    local feature = registry and type(registry.GetFeature) == "function"
        and registry:GetFeature(featureId)
    local entry = feature and feature.moduleEntry
    if type(entry) ~= "table" then return nil end
    return entry
end

function QUI_Modules:GetEntry(featureId)
    if type(featureId) ~= "string" or featureId == "" then return nil end
    return GetModuleEntry(featureId)
end

function QUI_Modules:IsEnabled(featureId)
    local entry = self:GetEntry(featureId)
    if not entry or type(entry.isEnabled) ~= "function" then return false end
    return entry.isEnabled() and true or false
end

function QUI_Modules:SetEnabled(featureId, enabled, options)
    local entry = self:GetEntry(featureId)
    if not entry or type(entry.setEnabled) ~= "function" then return false end

    -- Some older entries notify from inside setEnabled. Only emit here when
    -- the entry did not, keeping this API safe while all callers converge on
    -- the shared path.
    local serial = self._changeSerialByFeature[featureId] or 0
    entry.setEnabled(enabled and true or false, options)
    if (self._changeSerialByFeature[featureId] or 0) == serial then
        self:NotifyChanged(featureId)
    end
    return true
end
