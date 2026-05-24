-- luacheck configuration for QUI
--
-- Run:  luacheck <files>
-- Or:   luacheck QUI_Debug/ core/ modules/ init.lua
--
-- This config silences false-positive "undefined variable" warnings for the
-- WoW client API surface used by this addon. The full WoW API is enormous;
-- this list only covers what's currently referenced. Add globals here as
-- new ones surface in warnings — keep the list minimal so real undefined-
-- variable bugs (like use-before-define of locals) still show up.

std = "lua51"
max_line_length = false   -- WoW addons commonly run wider than 120 cols

-- Suppress noise from common WoW idioms:
--   212/self   — frames pass `self` to OnEvent/OnUpdate scripts; often unused
--   212/event  — OnEvent handlers receive event but often only inspect args
--   21./_.*    — leading-underscore vars/args are by convention intentionally
--                unused (e.g. `local _, _, _, _, icon = X`). Suppresses both
--                W211 (unused variable) and W212 (unused argument).
ignore = {
    "212/self",
    "212/event",
    "21./_.*",
}

-- Project-defined globals (written to from any file in the addon).
globals = {
    "QUI",
    "QUI_DB",
    "QuaziiUI_DB",
    "QUI_MemAudit",
    "QUI_RefreshActionTracker",
    "QUI_ToggleActionTrackerPreview",
    "QUI_IsActionTrackerPreviewMode",
    "QUI_HasFrameAnchor",
    "QUI_ApplyFrameAnchor",
    "QUI_DiagnoseEditMode",
    "QUI_PerfRegistry",
    "QUI_PerfExperiments",
    "QUI_CompartmentClick",
    "QUI_CompartmentOnEnter",
    "QUI_CompartmentOnLeave",
    "SLASH_QUISCAN1",
    "SLASH_QUISCAN2",
    "SLASH_QUIKB1",
    "SLASH_QUI_CDM1",
    "SlashCmdList",
    "BINDING_NAME_QUI_TOGGLE_OPTIONS",
}

-- WoW client globals — read-only from addon code.
read_globals = {
    -- Frame creation / UI primitives
    "CreateFrame", "EnumerateFrames", "UIParent", "WorldFrame", "GameTooltip",
    "QuickKeybindFrame", "ShowUIPanel", "UIFrameFadeOut", "Settings",
    "CooldownViewerSettings", "EventRegistry", "AssistedCombatManager",
    "STANDARD_TEXT_FONT", "UIErrorsFrame", "UISpecialFrames",
    "MouseIsOver", "StaticPopup_Show", "StopDrag",
    "GENERAL", "MAX_TOTEMS", "NUM_CHAT_WINDOWS", "RAID_CLASS_COLORS",
    "CUSTOM_CLASS_COLORS", "SetPortraitTexture",

    -- Time, combat, addon lifecycle
    "GetTime", "InCombatLockdown", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
    "IsAddOnLoaded", "LoadAddOn", "date",
    "IsInGroup", "IsInRaid",

    -- CVars, cursor, environment
    "GetCVar", "GetCVarBool", "SetCVar", "GetCursorPosition",
    "GetInstanceInfo", "GetRealmName",

    -- Inventory, item
    "GetInventoryItemCooldown", "GetInventoryItemID",
    "GetInventoryItemLink", "GetInventoryItemTexture",

    -- Units, bindings
    "UnitExists", "UnitCanAttack", "GetBindingKey",
    "UnitAffectingCombat", "UnitCastingInfo", "UnitChannelInfo",
    "UnitClass", "UnitHealthPercent", "UnitIsDead", "UnitName", "UnitRace",
    "UnitPowerMax",
    "IsMouseButtonDown",

    -- Spells, actions, macros
    "GetSpellInfo", "GetActionInfo", "GetMacroSpell", "FindBaseSpellByID",
    "GetMacroBody", "GetMacroIndexByName", "GetMacroInfo", "GetMacroItem",
    "IsHarmfulSpell", "IsHelpfulSpell", "IsPlayerSpell", "IsSpellKnown",

    -- Specialization, talents, totems
    "GetSpecialization", "GetSpecializationInfo", "GetSpecializationInfoByID",
    "GetTotemDuration", "GetTotemInfo", "GetNumTotemSlots",

    -- C_* namespace tables (whitelisted whole — methods accessed via dot/colon)
    "C_ActionBar", "C_AddOnProfiler", "C_AddOns", "C_AssistedCombat",
    "C_PartyInfo", "C_Spell", "C_Timer", "C_UnitAuras", "C_TooltipInfo",
    "C_NamePlate", "C_ItemCallbacks",
    "C_ChallengeMode", "C_ClassTalents", "C_Container", "C_CooldownViewer",
    "C_CurveUtil", "C_DurationUtil", "C_Item", "C_SpellActivationOverlay",
    "C_SpellBook", "C_StringUtil", "C_TradeSkillUI", "C_Traits",

    -- Enum and utility tables
    "Enum", "AuraUtil", "TextureKitConstants",

    -- WoW Lua extensions (Lua 5.1 base + Blizzard additions)
    "wipe", "strsplit", "strjoin", "strtrim", "strconcat", "format",
    "tContains", "tInvert", "tDeleteItem", "Mixin", "CreateFromMixins",
    "hooksecurefunc", "issecure", "issecurevariable",
    "tostringall", "issecretvalue", "Clamp",
    "CopyTable", "debugprofilestop", "geterrorhandler", "time", "tinsert",

    -- Blizzard internals
    "hash_SlashCmdList",

    -- Third-party libs
    "LibStub",
}
