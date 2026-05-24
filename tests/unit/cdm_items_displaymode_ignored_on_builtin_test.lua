-- tests/unit/cdm_items_displaymode_ignored_on_builtin_test.lua
-- Run: lua tests/unit/cdm_items_displaymode_ignored_on_builtin_test.lua
--
-- Task 11 (icon renderer kind=aura / displayMode=auraOnly coercion):
--   Items in built-in buff containers (kind="aura") must go inactive
--   when their buff is not active, and must show the aura phase when
--   the buff IS active. Items with displayMode="auraOnly" in custom
--   containers obey the same rule.
--
-- Task 12 gate (displayMode ignored on built-in cooldown containers):
--   A stray displayMode="auraOnly" set on an item in a built-in
--   essential/utility container MUST be ignored by the icon renderer.
--   The field is only honoured for custom containers.

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end
local _now = 1000.0

function InCombatLockdown() return false end
function GetTime() return _now end
function wipe(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, cb) cb() end,
    NewTimer = function() return { Cancel = noop } end,
}

-- Per-item scanned-aura table.  Tests overwrite this table before each case.
local scannedAuras = {}

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function() return {} end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(v) return v end,
        SafeToNumber = function(v) return v end,
        CanAccessTable = function(t) return type(t) == "table" end,
        IsEditModeActive = function() return false end,
        IsLayoutModeActive = function() return false end,
    },
    Addon = {
        db = {
            profile = { ncdm = {} },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(v) return type(v) == "number" end,
        -- Built-in containers: buff=aura, essential=cooldown, utility=cooldown.
        GetContainerDB = function(key)
            if key == "buff" then
                return { containerType = "buff" }
            elseif key == "essential" then
                return { containerType = "essential" }
            elseif key == "customBar:test" then
                return { containerType = "customBar" }
            end
            return nil
        end,
        IsCustomBarContainer = function(db)
            return type(db) == "table" and db.containerType == "customBar"
        end,
        GetBuiltinContainerEntryKind = function(key)
            return ({
                essential = "cooldown",
                utility = "cooldown",
                buff = "aura",
                trackedBar = "aura",
            })[key]
        end,
    },
    CDMSources = {
        QuerySpellUsable = function() return true, false end,
        QuerySpellHasRange = function() return false end,
        QuerySpellInRange = function() return true end,
        QueryBestOwnedItemVariant = function(id) return id end,
        QueryInventoryItemID = function() return nil end,
        QueryItemCount = function() return 1 end,
        QueryItemInfoInstant = function() return nil end,
        QueryItemSpell = function() return nil, nil end,
        QueryCooldownAuraBySpellID = function() return nil end,
        QueryBaseSpell = function(id) return id end,
        QueryScannedItemAuraInfo = function(id)
            return scannedAuras[id]
        end,
        -- QueryItemCooldown always returns "on cooldown" so that without
        -- the coercion gate the resolver would produce mode="item-cooldown".
        QueryItemCooldown = function()
            return _now - 10, 120, 1
        end,
    },
    -- The resolver is stubbed to:
    --   • Return mode="aura" (auraResolved=true) when the item's scanned aura
    --     is active — mirrors what the real resolver does via ResolveItemAuraForContext.
    --   • Return mode="item-cooldown" when the aura is inactive but the item
    --     is on cooldown — this is what the real resolver returns, and the
    --     coercion gate must short-circuit BEFORE this result is consumed for
    --     kind=aura / auraOnly entries.
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetSpellTexture = function() return nil end,
        GetEntryTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function()
            return { isOnCooldown = false, rechargeActive = false }
        end,
        ResolveCooldownState = function(context)
            -- Simulate item-aura detection: if the entry is item-backed and
            -- the scanned aura is active, return mode="aura".
            local entry = context and context.entry
            local itemID = entry and entry.id
            local scanned = itemID and scannedAuras[itemID]
            if scanned and scanned.active == true
               and type(scanned.duration) == "number" and scanned.duration > 0
               and type(scanned.expiration) == "number"
               and (scanned.expiration - _now) > 0 then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    auraResolved = true,
                    auraActive = true,
                    auraIsActive = true,
                    isOnCooldown = false,
                    spellID = itemID,
                    auraUnit = "player",
                    resolvedAuraSpellID = itemID,
                }
            end
            -- Item on cooldown but aura inactive.
            return {
                mode = "item-cooldown",
                active = true,
                isActive = true,
                isOnCooldown = true,
                numericCooldownActive = true,
                start = _now - 10,
                duration = 120,
            }
        end,
    },
    CDMIconFactory = {
        _iconPools = {},
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
        SyncCooldownBling = noop,
        GetIconPool = function(self, viewerType)
            return self._iconPools[viewerType] or {}
        end,
        EnsurePool = function(self, viewerType)
            if not self._iconPools[viewerType] then
                self._iconPools[viewerType] = {}
            end
            return self._iconPools[viewerType]
        end,
    },
    CDMRuntimeStore = {
        SetIconState = function(icon, state)
            icon._testStoredState = {
                mode = state.mode,
                active = state.active,
            }
        end,
        GetFrameState = function(icon)
            return icon._testStoredState
        end,
        ClearFrame = function(icon)
            icon._testStoredState = nil
        end,
    },
    _OwnedSwipe = {
        ApplyToIcon = noop,
        GetSettings = function()
            return { showBuffSwipe = false, showCooldownIconAuraPhase = false }
        end,
    },
}

dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("modules/cdm/cdm_icon_renderer.lua"))("QUI", ns)

local icons = assert(ns.CDMIcons, "CDMIcons should be exported")

-- Helper: create a minimal icon suitable for UpdateCooldownsForType.
local function makeItemIcon(entry)
    local icon = {
        _spellEntry = entry,
        Cooldown = {
            Clear = noop,
            SetReverse = noop,
            SetSwipeTexture = noop,
            SetDrawSwipe = noop,
            SetDrawEdge = noop,
            SetSwipeColor = noop,
            SetHideCountdownNumbers = noop,
            Show = noop,
        },
        Icon = {
            SetDesaturated = noop,
            SetVertexColor = noop,
            SetTexture = noop,
        },
        StackText = {
            SetText = noop,
            Hide = noop,
            Show = noop,
            SetTextColor = noop,
            SetAlpha = noop,
        },
        Border = { SetAlpha = noop },
    }
    function icon:IsShown() return true end
    function icon:Show() self._shown = true end
    function icon:Hide() self._shown = false end
    function icon:SetAlpha(v) self._alpha = v end
    return icon
end

-- Run UpdateIconCooldown via the CDMIcons pool path.
local function runUpdateForIcon(icon, viewerType)
    local priorPool = ns.CDMIconFactory._iconPools[viewerType]
    ns.CDMIconFactory._iconPools[viewerType] = { icon }
    icons:UpdateCooldownsForType(viewerType)
    ns.CDMIconFactory._iconPools[viewerType] = priorPool
end

local function getMode(icon)
    return icon._testStoredState and icon._testStoredState.mode
end

--------------------------------------------------------------------
-- Case 1 (Task 11 positive — kind=aura, aura INACTIVE):
--   Item in built-in buff container; buff is not active.
--   Coercion gate must fire → mode="inactive".
--------------------------------------------------------------------
scannedAuras = { [1001] = { active = false, duration = 0, expiration = 0 } }
local iconCase1 = makeItemIcon({
    id = 1001, type = "item", kind = "aura", viewerType = "buff",
})
runUpdateForIcon(iconCase1, "buff")
assert(getMode(iconCase1) == "inactive",
    "Case 1: kind=aura + aura-inactive must yield 'inactive' (got "
    .. tostring(getMode(iconCase1)) .. ")")
assert(iconCase1._hasCooldownActive ~= true,
    "Case 1: icon must not be marked as having an active cooldown")

--------------------------------------------------------------------
-- Case 2 (Task 11 positive — kind=aura, aura ACTIVE):
--   Item in built-in buff container; buff IS active.
--   Coercion gate must NOT block the resolver — mode becomes whatever
--   the resolver returns (here item-cooldown as the stub fallback, but
--   the active-aura guard lets the call through to ApplyResolvedCooldown
--   which in a real run would produce "aura").  We assert the gate did
--   NOT short-circuit to "inactive".
--------------------------------------------------------------------
scannedAuras = { [1002] = { active = true, duration = 20, expiration = _now + 12 } }
local iconCase2 = makeItemIcon({
    id = 1002, type = "item", kind = "aura", viewerType = "buff",
})
runUpdateForIcon(iconCase2, "buff")
assert(getMode(iconCase2) ~= "inactive",
    "Case 2: kind=aura + aura-active must NOT short-circuit to 'inactive' (got "
    .. tostring(getMode(iconCase2)) .. ")")

--------------------------------------------------------------------
-- Case 3 (Task 11 positive — displayMode=auraOnly in custom container,
--          aura INACTIVE):
--   Item in a custom bar with displayMode="auraOnly"; buff is inactive.
--   Coercion gate must fire → mode="inactive".
--------------------------------------------------------------------
scannedAuras = { [2001] = { active = false, duration = 0, expiration = 0 } }
local iconCase3 = makeItemIcon({
    id = 2001, type = "item", kind = "cooldown",
    displayMode = "auraOnly", viewerType = "customBar:test",
})
runUpdateForIcon(iconCase3, "customBar:test")
assert(getMode(iconCase3) == "inactive",
    "Case 3: displayMode=auraOnly + aura-inactive in custom bar must yield 'inactive' (got "
    .. tostring(getMode(iconCase3)) .. ")")

--------------------------------------------------------------------
-- Case 4 (Task 12 gate — displayMode=auraOnly stray-set on built-in
--          essential container MUST be ignored):
--   item in essential (cooldown-type built-in); stray displayMode="auraOnly"
--   is present but must have no effect. The coercion gate should NOT fire
--   because it only honours displayMode for CUSTOM containers.
--   Resolver fallback → mode="item-cooldown".
--------------------------------------------------------------------
scannedAuras = { [3001] = { active = false, duration = 0, expiration = 0 } }
local iconCase4 = makeItemIcon({
    id = 3001, type = "item", kind = "cooldown",
    displayMode = "auraOnly", viewerType = "essential",
})
runUpdateForIcon(iconCase4, "essential")
assert(getMode(iconCase4) == "item-cooldown",
    "Case 4: stray displayMode=auraOnly on built-in essential must be ignored, "
    .. "mode should remain 'item-cooldown' (got " .. tostring(getMode(iconCase4)) .. ")")

print("PASS: cdm_items_displaymode_ignored_on_builtin_test")
