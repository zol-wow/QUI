-- tests/unit/cdm_editmode_policy_test.lua
-- Run: lua tests/unit/cdm_editmode_policy_test.lua
--
-- Edit Mode policy enforcement (reference-parity). The re-anchor reference
-- forces VisibleSetting=Always on ALL CooldownViewer viewers and resets
-- HideWhenInactive=1 on the buff viewers (BuffIcon + BuffBar) ONCE at init --
-- that is what makes native item shown-state trustworthy for the claim pass.
-- A layout stores a setting entry ONLY when changed away from Blizzard's
-- default, so an ABSENT entry means "already at the default": it must be left
-- absent when the default equals the desired value (no change -> no SaveLayouts
-- -> no forced reload for users already at defaults).

-- WoW global stubs BEFORE the chunk loads (module registers its event frame).
local registeredEvents = {}
local eventHandler
_G.CreateFrame = function()
    return {
        RegisterEvent = function(_, ev) registeredEvents[ev] = true end,
        UnregisterEvent = function(_, ev) registeredEvents[ev] = nil end,
        SetScript = function(_, name, fn)
            if name == "OnEvent" then eventHandler = fn end
        end,
    }
end

local ENUMS = {
    cooldownSystem = 13,
    visSetting = 6,
    visAlways = 0,
    hideEnum = 8,
    buffIconIdx = 3,
    buffBarIdx = 4,
}

_G.Enum = {
    EditModeSystem = { CooldownViewer = ENUMS.cooldownSystem },
    EditModeCooldownViewerSetting = { VisibleSetting = ENUMS.visSetting, HideWhenInactive = ENUMS.hideEnum },
    CooldownViewerVisibleSetting = { Always = ENUMS.visAlways, InCombat = 1, Hidden = 2 },
    EditModeCooldownViewerSystemIndices = {
        Essential = 1, Utility = 2, BuffIcon = ENUMS.buffIconIdx, BuffBar = ENUMS.buffBarIdx,
    },
}

local savedLayouts = {}
local layoutInfoToReturn
_G.C_EditMode = {
    GetLayouts = function() return layoutInfoToReturn end,
    SaveLayouts = function(info) savedLayouts[#savedLayouts + 1] = info end,
}

local popupsShown = {}
_G.StaticPopupDialogs = {}
_G.StaticPopup_Show = function(which) popupsShown[#popupsShown + 1] = which end
_G.ReloadUI = function() end
_G.QUI_IsCDMMasterEnabled = function() return true end
_G.C_Timer = { After = function(_, fn) fn() end }

local ns = {}
local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns)
local P = assert(ns.CDMEditModePolicy, "CDMEditModePolicy exported")
assert(type(P.ApplyToSystems) == "function", "pure core ApplyToSystems exported")
assert(type(P.Enforce) == "function", "Enforce exported")

---------------------------------------------------------------------------
-- Pure core: ApplyToSystems(systems, enums) -> changed
---------------------------------------------------------------------------
local function mkSystems(settingsByIdx)
    local systems = {}
    for idx = 1, 4 do
        systems[#systems + 1] = {
            system = ENUMS.cooldownSystem,
            systemIndex = idx,
            settings = settingsByIdx[idx] or {},
        }
    end
    -- one non-CDM system that must never be touched
    systems[#systems + 1] = { system = 99, systemIndex = 1, settings = { { setting = 6, value = 2 } } }
    return systems
end

-- All settings absent (fresh install at Blizzard defaults): nothing changes,
-- nothing is inserted (absent == default Always / default HideWhenInactive=1).
do
    local systems = mkSystems({})
    local changed = P.ApplyToSystems(systems, ENUMS)
    assert(changed == false, "defaults everywhere -> no change")
    for i = 1, 4 do
        assert(#systems[i].settings == 0, "no entries inserted when default equals desired")
    end
end

-- VisibleSetting stored as Hidden (2) on a viewer -> reset to Always, changed.
do
    local systems = mkSystems({ [1] = { { setting = ENUMS.visSetting, value = 2 } } })
    local changed = P.ApplyToSystems(systems, ENUMS)
    assert(changed == true, "stale VisibleSetting -> changed")
    assert(systems[1].settings[1].value == ENUMS.visAlways, "VisibleSetting reset to Always")
end

-- HideWhenInactive=0 on BuffIcon -> reset to 1; the same stale value on
-- Essential is NOT policy-managed (buff viewers only) and stays untouched.
do
    local systems = mkSystems({
        [ENUMS.buffIconIdx] = { { setting = ENUMS.hideEnum, value = 0 } },
        [1] = { { setting = ENUMS.hideEnum, value = 0 } },
    })
    local changed = P.ApplyToSystems(systems, ENUMS)
    assert(changed == true, "stale buff HideWhenInactive -> changed")
    assert(systems[ENUMS.buffIconIdx].settings[1].value == 1, "BuffIcon HideWhenInactive reset to 1")
    assert(systems[1].settings[1].value == 0, "Essential HideWhenInactive not policy-managed")
end

-- Already-correct stored values -> no change (idempotent, no save loop).
do
    local systems = mkSystems({
        [ENUMS.buffBarIdx] = {
            { setting = ENUMS.visSetting, value = ENUMS.visAlways },
            { setting = ENUMS.hideEnum, value = 1 },
        },
    })
    assert(P.ApplyToSystems(systems, ENUMS) == false, "correct stored values -> no change")
end

-- Non-CDM system untouched.
do
    local systems = mkSystems({})
    P.ApplyToSystems(systems, ENUMS)
    assert(systems[5].settings[1].value == 2, "non-CooldownViewer system never modified")
end

---------------------------------------------------------------------------
-- Enforce wiring: one-shot at PLAYER_ENTERING_WORLD; SaveLayouts + reload
-- prompt ONLY when something changed; preset-active layouts never saved.
---------------------------------------------------------------------------
assert(registeredEvents["PLAYER_ENTERING_WORLD"], "policy registers PLAYER_ENTERING_WORLD")
assert(type(eventHandler) == "function", "policy installs an OnEvent handler")

-- changed case: stale VisibleSetting on the active (non-preset) layout
layoutInfoToReturn = {
    activeLayout = 1,
    layouts = {
        { systems = mkSystems({ [1] = { { setting = ENUMS.visSetting, value = 2 } } }) },
    },
}
eventHandler(nil, "PLAYER_ENTERING_WORLD")
assert(#savedLayouts == 1, "changed layout -> SaveLayouts called once")
assert(#popupsShown == 1, "changed layout -> reload prompt shown")

-- one-shot latch: a second PEW must not re-run enforcement
eventHandler(nil, "PLAYER_ENTERING_WORLD")
assert(#savedLayouts == 1 and #popupsShown == 1, "enforcement is one-shot per session")

-- fresh module + already-correct layout -> no save, no popup
do
    local ns2 = {}
    savedLayouts, popupsShown = {}, {}
    layoutInfoToReturn = { activeLayout = 1, layouts = { { systems = mkSystems({}) } } }
    loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns2)
    eventHandler(nil, "PLAYER_ENTERING_WORLD")
    assert(#savedLayouts == 0, "no change -> SaveLayouts never called")
    assert(#popupsShown == 0, "no change -> no reload prompt")
end

-- preset-active layout: read-only, never saved (would loop enforce->save->reload)
do
    local ns3 = {}
    savedLayouts, popupsShown = {}, {}
    _G.EditModePresetLayoutManager = {
        GetCopyOfPresetLayouts = function()
            return { { systems = mkSystems({ [1] = { { setting = ENUMS.visSetting, value = 2 } } }) } }
        end,
    }
    _G.tAppendAll = function(dst, src)
        for _, v in ipairs(src) do dst[#dst + 1] = v end
        return dst
    end
    -- activeLayout = 1 resolves to the PRESET after the merge
    layoutInfoToReturn = { activeLayout = 1, layouts = {} }
    loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns3)
    eventHandler(nil, "PLAYER_ENTERING_WORLD")
    assert(#savedLayouts == 0, "preset-active layout is read-only: never saved")
    _G.EditModePresetLayoutManager = nil
end

---------------------------------------------------------------------------
-- Loop breaker: forced reload at most once per unresolved correction, then
-- manual instructions each login until the layout comes back clean.
---------------------------------------------------------------------------
local staleLayout = function()
    return { activeLayout = 1, layouts = {
        { systems = mkSystems({ [1] = { { setting = ENUMS.visSetting, value = 2 } } }) },
    } }
end

do
    local ns4 = {}
    savedLayouts, popupsShown = {}, {}
    _G.QUIDB = {}
    layoutInfoToReturn = staleLayout()
    loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns4)
    eventHandler(nil, "PLAYER_ENTERING_WORLD")
    assert(#savedLayouts == 1, "first unresolved correction -> save attempted")
    assert(popupsShown[1] == "QUI_CDM_EDITMODE_RELOAD", "first unresolved correction -> forced reload prompt")
    assert(_G.QUIDB.cdmEditModeSavePending == true, "save-pending flag latched")
end

do
    local ns5 = {}
    savedLayouts, popupsShown = {}, {}
    layoutInfoToReturn = staleLayout()
    loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns5)
    eventHandler(nil, "PLAYER_ENTERING_WORLD")
    assert(popupsShown[1] == "QUI_CDM_EDITMODE_MANUAL", "still unresolved next session -> manual instructions, no reload loop")
    assert(_G.QUIDB.cdmEditModeSavePending == true, "save-pending flag stays latched while unresolved")
end

do
    local ns6 = {}
    savedLayouts, popupsShown = {}, {}
    layoutInfoToReturn = { activeLayout = 1, layouts = { { systems = mkSystems({}) } } }
    loadChunk("QUI_CDM/cdm/cdm_editmode_policy.lua", "cdm_editmode_policy.lua")("QUI", ns6)
    eventHandler(nil, "PLAYER_ENTERING_WORLD")
    assert(#savedLayouts == 0 and #popupsShown == 0, "settled layout -> no save, no prompt")
    assert(_G.QUIDB.cdmEditModeSavePending == nil, "settled layout re-arms the loop breaker")
    _G.QUIDB = nil
end

print("OK: cdm_editmode_policy_test")
