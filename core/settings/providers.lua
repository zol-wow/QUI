local ADDON_NAME, ns = ...

local Settings = ns.Settings or {}
ns.Settings = Settings

local Providers = Settings.Providers or {}
Settings.Providers = Providers
Settings.ProviderRegistry = Providers

Providers._byKey = Providers._byKey or {}

local function ForEachProviderKey(key, callback)
    if type(callback) ~= "function" then
        return
    end

    if type(key) == "table" then
        for _, value in ipairs(key) do
            if type(value) == "string" and value ~= "" then
                callback(value)
            end
        end
        return
    end

    if type(key) == "string" and key ~= "" then
        callback(key)
    end
end

function Providers:Register(key, provider)
    if type(provider) ~= "table" then
        return nil
    end

    ForEachProviderKey(key, function(providerKey)
        self._byKey[providerKey] = provider
    end)

    return provider
end

function Providers:Unregister(key)
    ForEachProviderKey(key, function(providerKey)
        self._byKey[providerKey] = nil
    end)
end

function Providers:Get(key)
    if type(key) ~= "string" or key == "" then
        return nil
    end

    return self._byKey[key]
end

function Providers:Has(key)
    return self:Get(key) ~= nil
end
