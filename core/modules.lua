---------------------------------------------------------------------------
-- QUI Modules — pub/sub for module-state changes.
-- Subscribe / Unsubscribe / NotifyChanged. Used by surfaces (Modules
-- panel, Layout Mode drawer, search-result rows) to refresh their row
-- visuals when any module's enable state flips.
--
-- State of the module itself lives in the module's own DB key — this
-- helper carries no state, only fans out notifications.
---------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local QUI_Modules = {
    _specific = {},   -- [featureId] = { [token] = callback }
    _wildcard = {},   -- [token] = callback
    _nextToken = 1,
}
ns.QUI_Modules = QUI_Modules

local function NewToken(self)
    local t = self._nextToken
    self._nextToken = t + 1
    return t
end

--- Subscribe to state-change notifications for a feature.
-- @param featureId string — feature id, or "*" for all features.
-- @param callback function(featureId) — fired when NotifyChanged runs.
-- @return table — opaque token; pass to Unsubscribe to remove.
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

--- Dispatch a state-change notification synchronously.
-- All callbacks are pcall'd; one failure does not block others.
function QUI_Modules:NotifyChanged(featureId)
    if type(featureId) ~= "string" or featureId == "" then return end
    local bucket = self._specific[featureId]
    if bucket then
        for _, cb in pairs(bucket) do
            local ok, err = pcall(cb, featureId)
            if not ok and DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[QUI_Modules]|r " .. tostring(err))
            end
        end
    end
    for _, cb in pairs(self._wildcard) do
        local ok, err = pcall(cb, featureId)
        if not ok and DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[QUI_Modules]|r " .. tostring(err))
        end
    end
end
