-- tests/unit/cdm_items_in_aura_container_mode_test.lua
-- Asserts items added to built-in buff/trackedBar containers (kind="aura")
-- and items with displayMode="auraOnly" in custom containers render mode
-- "item-aura" while their buff is active and "inactive" off-aura. The
-- item's use-cooldown is NOT consulted in either case.

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

-- Per-item scanned-aura table the stub Sources consults.
local scannedAuras = {}

local ns = {
    CDMSpellData = {},  -- required by UpdateOwnedBarAura guard
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
        QueryItemCooldown = function() return _now - 10, 120, 1 end,  -- always "on cooldown" 110s left
        QueryBaseSpell = function(id) return id end,
        QueryCooldownAuraBySpellID = function() return nil end,
    },
    -- Resolver returns a cooldown state that, if consumed, would render mode
    -- "item-cooldown". For our test we want the kind/auraOnly branches to
    -- short-circuit BEFORE this resolver result is consumed.
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

-- Capture state writes from UpdateOwnedBarAura's downstream calls.
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
    local bar = {
        _spellEntry = entry,
        _spellID = entry.id,
        IconTexture = { SetTexture = function() end },
        NameText = { SetText = function() end },
        StatusBar = {
            SetValue = function() end,
            SetMinMaxValues = function() end,
            SetStatusBarColor = function() end,
        },
    }
    return bar
end

local function getMode(bar) return barStates[bar] and barStates[bar].mode end

------------------------------------------------------------
-- Case A: kind=aura + aura INACTIVE → mode=inactive
------------------------------------------------------------
scannedAuras = { [1001] = { active = false, duration = 0, expiration = 0 } }
local barA = makeBar({ id = 1001, type = "item", kind = "aura" })
CDMBars:UpdateOwnedBarAura(barA)
assert(getMode(barA) == "inactive",
    "kind=aura + aura-inactive must yield inactive (got " .. tostring(getMode(barA)) .. ")")
assert(barA._active ~= true, "bar must not be active when aura inactive")

------------------------------------------------------------
-- Case B: kind=aura + aura ACTIVE → mode=item-aura
------------------------------------------------------------
scannedAuras = { [1002] = { active = true, duration = 20, expiration = _now + 12 } }
local barB = makeBar({ id = 1002, type = "item", kind = "aura" })
CDMBars:UpdateOwnedBarAura(barB)
assert(getMode(barB) == "item-aura",
    "kind=aura + aura-active must yield item-aura (got " .. tostring(getMode(barB)) .. ")")
assert(barB._active == true, "bar must be active during aura phase")

------------------------------------------------------------
-- Case C: displayMode=auraOnly in custom + aura INACTIVE → inactive
-- (entry.kind="cooldown", the override is what coerces.)
------------------------------------------------------------
scannedAuras = { [2001] = { active = false, duration = 0, expiration = 0 } }
local barC = makeBar({
    id = 2001, type = "item", kind = "cooldown",
    displayMode = "auraOnly", viewerType = "customBar:test",
})
CDMBars:UpdateOwnedBarAura(barC)
assert(getMode(barC) == "inactive",
    "displayMode=auraOnly + aura-inactive must yield inactive (got "
    .. tostring(getMode(barC)) .. ")")

------------------------------------------------------------
-- Case D: regression — kind=cooldown + no override + aura inactive
-- must still produce item-cooldown (today's behavior).
------------------------------------------------------------
scannedAuras = { [3001] = { active = false, duration = 0, expiration = 0 } }
local barD = makeBar({ id = 3001, type = "item", kind = "cooldown" })
CDMBars:UpdateOwnedBarAura(barD)
assert(getMode(barD) == "item-cooldown",
    "kind=cooldown + aura-inactive (no override) must preserve item-cooldown (got "
    .. tostring(getMode(barD)) .. ")")

print("PASS: items in aura container and auraOnly override mode resolution")
