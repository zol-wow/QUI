-- tests/unit/cdm_items_auraonly_override_mode_test.lua
-- Lock-test: items with displayMode="auraOnly" in a custom container show
-- mode "item-aura" when their buff IS active. Complements the
-- auraOnly+inactive case (Case C) in cdm_items_in_aura_container_mode_test.lua
-- by proving the aura-active path runs BEFORE the new auraOnly coercion.

local function noop() end
local _now = 1000.0

function InCombatLockdown() return false end
function GetTime() return _now end
function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
end
function CreateFrame()
    local frame = {}
    function frame:SetScript() end
    function frame:CreateAnimationGroup()
        local group = {}
        function group:CreateAnimation()
            return { SetDuration = function() end }
        end
        function group:SetLooping() end
        function group:SetScript() end
        return group
    end
    return frame
end

C_StringUtil = {
    WrapString = function(_, prefix, suffix) return tostring(prefix or "") .. tostring(suffix or "") end,
    TruncateWhenZero = function(v) return v end,
}

local scannedAuras = {}

local ns = {
    CDMSpellData = {    -- required by UpdateOwnedBarAura guard
        GetSpellOverride = function() return nil end,
        ResolveDisplayName = function() return nil end,
    },
    Helpers = {
        GetGeneralFont = function() return "" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
    },
    CDMShared = {
        GetContainerDB = function(key)
            if key == "customBar:test" then
                return { containerType = "customBar" }
            end
            return nil
        end,
        IsCustomBarContainer = function(db)
            return type(db) == "table" and db.containerType == "customBar"
        end,
    },
    CDMSources = {
        QueryInventoryItemID = function() return nil end,
        QueryInventoryItemTexture = function() return nil end,
        QueryItemIconByID = function() return nil end,
        QueryItemNameByID = function() return nil end,
        QueryItemInfoInstant = function() return nil end,
        QueryBestOwnedItemVariant = function(id) return id end,
        QueryScannedItemAuraInfo = function(id) return scannedAuras[id] end,
        QueryItemCooldown = function() return _now - 10, 120, 1 end,
        QueryBaseSpell = function(id) return id end,
        QueryCooldownAuraBySpellID = function() return nil end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = function() return {} end,
        ResolveCooldownState = function()
            return {
                isActive = true,
                isOnCooldown = true,
                mode = "item-cooldown",
                numericCooldownActive = true,
                start = _now - 10,
                duration = 120,
            }
        end,
    },
}

assert(loadfile("modules/cdm/cdm_bar_renderer.lua"))("QUI", ns)

local barStates = setmetatable({}, { __mode = "k" })
ns.CDMRuntimeStore = {
    SetBarState = function(bar, state)
        barStates[bar] = state
        bar._active = state.active == true
        return state
    end,
    GetFrameState = function(bar) return bar and barStates[bar] or nil end,
    ClearFrame = function(bar) barStates[bar] = nil end,
}

local CDMBars = assert(ns.CDMBars, "CDMBars table was not exported")

local function makeBar(entry)
    return {
        _spellEntry = entry,
        _spellID = entry.id,
        IconTexture = { SetTexture = function() end },
        NameText = { SetText = function() end },
        StatusBar = {
            SetValue = function() end,
            SetMinMaxValues = function() end,
        },
    }
end

-- The protagonist: auraOnly + aura ACTIVE -> mode must be "item-aura"
-- (proves the aura-active path fires BEFORE the new auraOnly coercion).
scannedAuras = { [4242] = { active = true, duration = 15, expiration = _now + 12 } }

local bar = makeBar({
    id = 4242,
    type = "item",
    kind = "cooldown",            -- intentionally cooldown -- the override is what matters
    displayMode = "auraOnly",
    viewerType = "customBar:test",
})
CDMBars:UpdateOwnedBarAura(bar)

local state = barStates[bar]
assert(state ~= nil, "bar state must be set")
assert(state.mode == "item-aura",
    "displayMode=auraOnly + aura ACTIVE must yield item-aura (got "
    .. tostring(state.mode) .. ")")
assert(bar._active == true, "bar must be active during aura phase")

print("PASS: auraOnly + aura active = item-aura (ordering lock)")
