-- tests/unit/cdm_items_skipauraphase_with_auraonly_test.lua
-- Lock-test: even if the runtime sets bar._skipAuraPhase = true on an
-- auraOnly item entry whose aura is inactive, the bar must render
-- "inactive" — NOT fall through to cooldown rendering. The auraOnly
-- coercion in UpdateItemBarCooldown runs BEFORE the resolver fallback
-- that consults skipAuraPhase, so the interaction is inert by ordering.

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
    Helpers = {
        GetGeneralFont = function() return "" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
    },
    CDMSpellData = {
        GetSpellOverride = function() return nil end,
        ResolveDisplayName = function() return nil end,
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
        QueryItemCooldown = function() return _now - 1, 60, 1 end,
        QueryBaseSpell = function(id) return id end,
        QueryCooldownAuraBySpellID = function() return nil end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = function() return {} end,
        ResolveCooldownState = function()
            -- Would return item-cooldown mode if reached. The auraOnly
            -- coercion must short-circuit BEFORE this fires.
            return {
                isActive = true,
                isOnCooldown = true,
                mode = "item-cooldown",
                numericCooldownActive = true,
                start = _now - 1,
                duration = 60,
            }
        end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)

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

local CDMBars = assert(ns.CDMBars, "CDMBars not exported")

-- Aura inactive — coercion path is what we want to exercise.
scannedAuras = { [6001] = { active = false, duration = 0, expiration = 0 } }

local bar = {
    _spellEntry = {
        id = 6001,
        type = "item",
        kind = "cooldown",
        displayMode = "auraOnly",
        viewerType = "customBar:test",
    },
    _spellID = 6001,
    _skipAuraPhase = true,    -- simulate the runtime-driven flag
    IconTexture = { SetTexture = function() end },
    NameText = { SetText = function() end },
    StatusBar = { SetValue = function() end, SetMinMaxValues = function() end },
}
CDMBars:UpdateOwnedBarAura(bar)

local state = barStates[bar]
assert(state ~= nil, "bar state must be set")
assert(state.mode == "inactive",
    "skipAuraPhase=true + displayMode=auraOnly + aura-inactive must yield "
    .. "inactive (got " .. tostring(state.mode) .. "). The coercion in "
    .. "UpdateItemBarCooldown must short-circuit before the resolver "
    .. "fallback that consults skipAuraPhase.")
assert(bar._active ~= true, "bar must not be active")

print("PASS: skipAuraPhase + auraOnly + aura-inactive = inactive (coercion ordering lock)")
