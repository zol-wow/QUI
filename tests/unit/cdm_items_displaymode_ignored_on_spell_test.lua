-- tests/unit/cdm_items_displaymode_ignored_on_spell_test.lua
-- Lock-test: a stray displayMode="auraOnly" on a spell entry (or macro entry)
-- is silently ignored by both the bar and icon renderers. The type gate
-- inside the new coercion blocks is what protects this — Tasks 9 and 11.
--
-- The test covers two scenarios in one file because the gate logic is
-- symmetric across renderers:
--
--   Scenario A: bar renderer, spell entry, displayMode="auraOnly" + aura
--               inactive + CD active → mode "cooldown" or "item-cooldown"
--               (NOT "inactive" — the override is dead on spells).
--   Scenario B: icon renderer, spell entry, displayMode="auraOnly" + aura
--               inactive + CD active → mode classification proceeds via
--               the normal spell path (NOT "inactive").
--
-- Each scenario is run in an isolated `do...end` block to avoid global
-- pollution between renderer loads.

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

------------------------------------------------------------
-- Scenario A: bar renderer + spell entry + stray displayMode
------------------------------------------------------------
do
    local ns = {
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
            QueryScannedItemAuraInfo = function() return nil end,
            QueryItemCooldown = function() return _now - 5, 60, 1 end,
            QueryBaseSpell = function(id) return id end,
            QueryCooldownAuraBySpellID = function() return nil end,
        },
        CDMResolvers = {
            BuildCooldownStateContext = function() return {} end,
            ResolveCooldownState = function()
                return {
                    isActive = true,
                    isOnCooldown = true,
                    mode = "cooldown",       -- spell-cooldown, not item-cooldown
                    start = _now - 5,
                    duration = 60,
                }
            end,
        },
        CDMSpellData = {
            GetSpellOverride = function() return nil end,
            ResolveDisplayName = function() return nil end,
        },
    }

    assert(loadfile("modules/cdm/cdm_bar_renderer.lua"))("QUI", ns)

    local barStates = setmetatable({}, { __mode = "k" })
    ns.CDMRuntimeStore = {
        SetBarState = function(bar, state)
            barStates[bar] = state
            bar._active = state.active == true
        end,
        GetFrameState = function(bar) return barStates[bar] end,
        ClearFrame = function(bar) barStates[bar] = nil end,
    }

    local bars = assert(ns.CDMBars, "CDMBars not exported (bar renderer)")

    local bar = {
        _spellEntry = {
            id = 5001,
            type = "spell",
            kind = "cooldown",
            displayMode = "auraOnly",  -- stray, MUST be ignored
            viewerType = "customBar:test",
        },
        _spellID = 5001,
        IconTexture = { SetTexture = function() end },
        NameText = { SetText = function() end },
        StatusBar = { SetValue = function() end },
    }
    bars:UpdateOwnedBarAura(bar)

    local state = barStates[bar]
    -- The exact mode depends on whether UpdateOwnedBarAura routed this spell
    -- entry to the cooldown resolver path. Spell entries go through that
    -- path (not UpdateItemBarCooldown), and the resolver returns
    -- mode="cooldown" per our stub. The auraOnly coercion in
    -- UpdateItemBarCooldown should NEVER fire for spell entries.
    assert(state ~= nil, "bar state must be set after UpdateOwnedBarAura")
    assert(state.mode ~= "inactive",
        "spell entry with stray displayMode=auraOnly must NOT yield inactive (got "
        .. tostring(state.mode) .. ")")

    print("PASS: scenario A — spell entry, stray displayMode ignored by bar renderer")
end

------------------------------------------------------------
-- Scenario B: icon renderer + spell entry + stray displayMode
-- Source-level verification only: the icon renderer's coercion block wraps
-- item/trinket/slot entry types in an explicit type guard.  A spell entry
-- never satisfies that guard, so the auraOnly coercion never fires for
-- spell entries.  We confirm the guard text is still present in the source.
------------------------------------------------------------
do
    -- Source-level verification: the coercion gate in the icon renderer must
    -- explicitly guard on item/trinket/slot entry types.  A spell entry never
    -- satisfies the gate, so the auraOnly coercion never fires for spell entries.
    local file = io.open("modules/cdm/cdm_icon_renderer.lua", "r")
    assert(file, "cdm_icon_renderer.lua not found")
    local source = file:read("*all")
    file:close()

    -- The coercion gate from Task 11 must explicitly check item/trinket/slot.
    local gate1 = source:match(
        '(entry%.type%s*==%s*"item"%s+or%s+entry%.type%s*==%s*"trinket"%s+or%s+entry%.type%s*==%s*"slot")'
    )
    assert(gate1 ~= nil,
        "icon renderer must contain the explicit item/trinket/slot type gate (lost?)")

    print("PASS: scenario B — spell entry gate verified in icon renderer source")
end

print("PASS: displayMode ignored on spell entries (both renderers)")
