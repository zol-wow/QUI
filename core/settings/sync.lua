local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Sync = Settings.Sync or {
    _listeners = {},
    _nextToken = 0,
}
Settings.Sync = Sync

function Sync:RegisterListener(featureId, callback)
    if type(featureId) ~= "string" or featureId == "" or type(callback) ~= "function" then
        return nil
    end

    self._nextToken = self._nextToken + 1
    local token = self._nextToken
    self._listeners[token] = {
        featureId = featureId,
        callback = callback,
    }
    return token
end

function Sync:UnregisterListener(token)
    self._listeners[token] = nil
end

function Sync:NotifyChanged(featureId, opts)
    if type(featureId) ~= "string" or featureId == "" then
        return
    end

    -- The listener set is intentionally small today, so a linear pass keeps
    -- registration simple. Bucket by featureId if profiling ever shows this
    -- notification path growing large enough to matter.
    for _, listener in pairs(self._listeners) do
        if listener.featureId == featureId then
            local ok, err = pcall(listener.callback, featureId, opts or {})
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
end
