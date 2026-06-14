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

-- CI enforcement (lua-tests.yml `lint` job): ALL suites are warning-clean
-- and enforced as of 2026-06-13 — QUI_Debug/ core/ modules/ init.lua plus
-- all 16 QUI_* suite directories. Keep it that way: fix warnings or (for
-- genuine WoW API names) add the global here; never exclude a directory
-- to silence a finding.

std = "lua51"
max_line_length = false   -- WoW addons commonly run wider than 120 cols

-- meta/ holds LuaLS ---@meta definition stubs for the editor only (never loaded
-- in-game). They are generated function stubs, so linting them is meaningless
-- and noisy (unused args, "setting read-only global").
exclude_files = { "meta" }

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
    "QUI_StorageDB",
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
    "IsInGroup", "IsInRaid", "IsLoggedIn",

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
    "C_CurveUtil", "C_DurationUtil", "C_Item", "C_ScenarioInfo",
    "C_SpellActivationOverlay",
    "C_SpellBook", "C_StringUtil", "C_TradeSkillUI", "C_Traits",

    -- M+ constants
    "DIFFICULTY_MYTHIC_PLUS",

    -- Enum and utility tables
    "Enum", "AuraUtil", "TextureKitConstants",

    -- WoW Lua extensions (Lua 5.1 base + Blizzard additions)
    "wipe", "strsplit", "strjoin", "strtrim", "strconcat", "format",
    "tContains", "tInvert", "tDeleteItem", "Mixin", "CreateFromMixins",
    "hooksecurefunc", "issecure", "issecurevariable", "IsSecureCmd",
    "tostringall", "issecretvalue", "Clamp",
    "CopyTable", "debugprofilestop", "geterrorhandler", "time", "tinsert",

    -- debug.upvaluejoin is a Blizzard backport (Lua 5.2+) used by the ActionBars
    -- chunk-env setfenv shim (actionbars_env.lua); allow this one field while
    -- still flagging typos like debug.<misspelled>.
    debug = { fields = { "upvaluejoin" } },

    -- Blizzard internals
    "hash_SlashCmdList",

    -- Third-party libs
    "LibStub",
}

-- Additional current WoW/client globals referenced by the checked Lua files.
local additional_read_globals = [[
BonusRollFrame BonusRollFrame_StartBonusRoll CLASS_ICON_TCOORDS LootWonAlertFrame_SetUp MoneyWonAlertFrame_SetUp PagedContentFrameBaseMixin
ADVENTURE_JOURNAL ARMOR ATTACK_POWER_MAGIC_NUMBER ATTACK_SPEED AbbreviateLargeNumbers AbbreviateNumbers AcceptGroup AcceptQuest
AchievementAlertSystem ActionBarController_UpdateAll ActionButtonSpellAlertManager ActionButton_ShowOverlayGlow ActionButton_StartFlash ActionButton_StopFlash ActionButton_Update ActionButton_UpdateCooldown
AddonCompartmentFrame AlertFrame AuctionFrame AuctionHouseFrame BASE_MOVEMENT_SPEED BATTLEFIELD_MINIMAP BLOCK_CHANCE BNConnected
BNET_CLIENT_WOW BNGetNumFriends BNInviteFriend BNToastFrame BOOKTYPE_SPELL BackpackTokenFrame BagsBar BonusRollLootWonFrame
BonusRollMoneyWonFrame BreakUpLargeNumbers BuffFrame CHAT_FRAME_FADE_TIME COMBAT_ZONE CONTESTED_TERRITORY CR_AVOIDANCE CR_AVOIDANCE_TOOLTIP
CR_BLOCK_TOOLTIP CR_CRIT_PARRY_RATING_TOOLTIP CR_CRIT_SPELL CR_CRIT_TOOLTIP CR_DODGE CR_DODGE_BASE_STAT_TOOLTIP CR_DODGE_TOOLTIP CR_HASTE_SPELL
CR_LIFESTEAL CR_LIFESTEAL_TOOLTIP CR_MASTERY CR_PARRY CR_PARRY_BASE_STAT_TOOLTIP CR_PARRY_TOOLTIP CR_SPEED CR_SPEED_TOOLTIP
CR_VERSATILITY_DAMAGE_DONE CR_VERSATILITY_DAMAGE_TAKEN CR_VERSATILITY_TOOLTIP C_Bank C_BattleNet C_CVar C_Calendar C_ChatInfo
C_ClassColor C_Club C_CreatureInfo C_CurrencyInfo C_Cursor C_DateAndTime C_EncodingUtil C_FriendList
C_GossipInfo C_GuildInfo C_IncomingSummon C_LevelLink C_MajorFactions C_Map C_MountJournal C_MythicPlus C_PaperDollInfo
C_PetBattles C_PlayerInfo C_PvP C_QuestLog C_Reputation C_SpecializationInfo C_SummonInfo C_TaskQuest C_TransmogCollection
C_Texture C_ToyBox C_UIWidgetManager C_WeeklyRewards C_WowTokenPublic CanExitVehicle CanGuildBankRepair CanInspect CanMerchantRepair ChallengesFrame ChallengesKeystoneFrame
ChangeChatColor CharacterBackSlot CharacterChestSlot CharacterFeetSlot CharacterFinger0Slot CharacterFinger1Slot CharacterFrame CharacterFrameBg
CharacterFrameInset CharacterFrameInsetRight CharacterFramePortrait CharacterFrameTab1 CharacterFrameTab2 CharacterFrameTab3 CharacterFrameTitleText CharacterHandsSlot
CharacterHeadSlot CharacterLegsSlot CharacterLevelText CharacterMainHandSlot CharacterModelScene CharacterNeckSlot CharacterReagentBag0Slot CharacterSecondaryHandSlot
CharacterShirtSlot CharacterShoulderSlot CharacterStatsPane CharacterTabardSlot CharacterTrinket0Slot CharacterTrinket1Slot CharacterWaistSlot CharacterWristSlot
ChatFontNormal ChatFrame1 ChatFrame1EditBox ChatFrameUtil ChatFrame_AddChannel ChatFrame_AddMessageGroup ChatFrame_RemoveChannel ChatFrame_RemoveMessageGroup
ChatFrame_SendTell CheckInteractDistance ClearCursor ClearInspectPlayer ClearOverrideBindings CloseLoot ColorPickerFrame CombatLogGetCurrentEventInfo
CommunitiesUtil CompactPartyFrame CompactRaidFrameContainer CompactRaidFrameManager CompactUnitFrame_UpdateReadyCheck CompactUnitFrame_UpdateSelectionHighlight CompactUnitFrame_UpdateUnitEvents CompleteLFGRoleCheck
Constants CooldownFrame_Set CreateColor CreateMacro CreateUnitHealPredictionCalculator CriteriaAlertSystem CurveConstants DEFAULT_BAR_COLOR
DEFAULT_CHAT_FRAME DELETE_ITEM_CONFIRM_STRING DODGE_CHANCE DebuffFrame DeleteMacro DigsiteCompleteAlertSystem DungeonCompletionAlertSystem EJMicroButton
ENCHANTED_TOOLTIP_LINE ERR_USE_LOCKED_WITH_SPELL_S EasyMenu EditMacro EditModeMagnetismManager EditModeManagerFrame EmbeddedItemTooltip EncounterWarningsUtil
EncounterWarningsViewElementMixin EntitlementDeliveredAlertSystem EventToastManagerFrame ExpansionLandingPageMinimapButton ExtraAbilityContainer ExtraActionBarFrame FACTION_CONTROLLED_TERRITORY FCFTab_UpdateAlpha
FCFTab_UpdateColors FCF_FadeInScrollbar FCF_FadeOutScrollbar FCF_IsTemporaryWindow FCF_OpenNewWindow FCF_PopOutChat FCF_SetChatWindowFontSize FCF_StartAlertFlash
FCF_Tab_OnClick FCF_UpdateScrollbarAnchors FONT_COLOR_CODE_CLOSE FREE_FOR_ALL_TERRITORY FindSpellBookSlotBySpellID FloatingChatFrame_UpdateScroll FlyoutHasSpell FocusFrame
FormatUnreadMailTooltip GREEN_FONT_COLOR_CODE GameFontNormal GameMenuFrame GameTimeFrame GameTime_GetGameTime GameTime_GetLocalTime GameTooltipHeaderText
GameTooltipStatusBar GameTooltipText GameTooltipTextLeft1 GameTooltip_Hide GameTooltip_SetBackdropStyle GameTooltip_SetDefaultAnchor GameTooltip_SetTitle GarrisonBuildingAlertSystem
GarrisonFollowerAlertSystem GarrisonMissionAlertSystem GarrisonRandomMissionAlertSystem GarrisonShipFollowerAlertSystem GarrisonShipMissionAlertSystem GarrisonTalentAlertSystem GearManagerPopupFrame GetActionCount
GetActionText GetActionTexture GetAddOnCPUUsage GetAttackPowerForStat GetAvailableBandwidth GetAverageItemLevel GetAvoidance GetBindingAction
GetBindingText GetBlockChance GetBuildInfo GetCallPetSpellInfo GetChannelList GetChannelName GetChatWindowInfo GetCombatRating
GetCombatRatingBonus GetCombatRatingBonusForCombatRatingValue GetCritChanceProvidesParryEffect GetCurrentBindingSet GetCurrentKeyBoardFocus GetCursorInfo GetDisplayedInviteType GetDodgeChance
GetDodgeChanceFromAttribute GetDownloadedPercentage GetEffectivePlayerMaxLevel GetFlyoutInfo GetFlyoutSlotInfo GetFramerate GetGameTime GetGuildInfo
GetGuildRosterInfo GetGuildRosterMOTD GetGuildRosterShowOffline GetInspectSpecialization GetInventoryItemDurability GetInventoryItemQuality GetItemGem GetItemInfo
GetItemInfoInstant GetItemQualityColor GetLatestThreeSenders GetLifesteal GetLootRollItemInfo GetLootSlotInfo GetLootSlotLink GetLootSpecialization
GetMasteryEffect GetMaxLevelForPlayerExpansion GetMeleeHaste GetMinimapZoneText GetModifiedClick GetMoney GetMoneyString GetMouseFoci GetMouseFocus
GetNetIpTypes GetNetStats GetNormalizedRealmName GetNumGroupMembers GetNumGuildMembers GetNumLootItems GetNumMacros GetNumQuestChoices
GetNumSavedInstances GetNumSavedWorldBosses GetNumShapeshiftForms GetNumSpecializations GetNumSubgroupMembers GetParryChance GetParryChanceFromAttribute GetPetActionCooldown
GetPetActionInfo GetPetActionSlotUsable GetPhysicalScreenSize GetPlayerInfoByGUID GetPowerBarColor GetPowerRegenForPowerType GetProfessionInfo GetProfessions GetQuestDifficultyColor GetQuestProgressBarPercent
GetQuestReward GetRaidRosterInfo GetRaidTargetIndex GetReadyCheckStatus GetRepairAllCost GetRestState GetRuneCooldown GetSavedInstanceInfo
GetSavedWorldBossInfo GetScaledCursorPosition GetScreenHeight GetScreenWidth GetServerTime GetShapeshiftForm GetShapeshiftFormCooldown GetShapeshiftFormID
GetShapeshiftFormInfo GetShieldBlock GetSpecializationMasterySpells GetSpecializationRole GetSpeed GetSpellBonusDamage GetSpellCharges GetSpellCooldown
GetSpellCritChance GetSpellTexture GetStaggerPercentage GetSubZoneText GetTimePreciseSec GetTotemTimeLeft GetUnitChargedPowerPoints GetUnitEmpowerHoldAtMaxTime
GetUnitMaxHealthModifier GetUnitName GetUnitPowerBarInfo GetUnitPowerBarStrings GetUnitSpeed GetVersatilityBonus GetWeaponEnchantInfo GetWorldElapsedTime
GetXPExhaustion GetZonePVPInfo GetZoneText GroupLootHistoryFrame GuildChallengeAlertSystem GuildRenameAlertSystem HAVE_MAIL HAVE_MAIL_FROM
HEALTH HIGHLIGHT_FONT_COLOR_CODE HUD_EDIT_MODE_COOLDOWN_VIEWER_OPTIONS HasAPEffectsSpellPower HasAction HasNewMail HasOverrideActionBar HasSPEffectsAttackPower
HasVehicleActionBar HeroTalentsSelectionDialog HideUIPanel HonorAwardedAlertSystem HybridMinimap INSPECT INVSLOT_BACK INVSLOT_BODY
INVSLOT_CHEST INVSLOT_FEET INVSLOT_FINGER1 INVSLOT_FINGER2 INVSLOT_HAND INVSLOT_HEAD INVSLOT_LEGS INVSLOT_MAINHAND
INVSLOT_NECK INVSLOT_OFFHAND INVSLOT_SHOULDER INVSLOT_TABARD INVSLOT_TRINKET1 INVSLOT_TRINKET2 INVSLOT_WAIST INVSLOT_WRIST
ITEM_LEVEL ITEM_SOCKETING ITEM_UPGRADE_FRAME_CURRENT_UPGRADE_FORMAT_STRING InspectBackSlot InspectChestSlot InspectFeetSlot InspectFinger0Slot InspectFinger1Slot
InspectFrameBg InspectFrameCloseButton InspectFramePortrait InspectFrameTab1 InspectFrameTab2 InspectFrameTab3 InspectFrame_Show InspectGuildFrame
InspectHandsSlot InspectHeadSlot InspectLegsSlot InspectLevelText InspectMainHandSlot InspectModelFrame InspectModelFrameBorderBottom InspectModelFrameBorderBottom2
InspectModelFrameBorderBottomLeft InspectModelFrameBorderBottomRight InspectModelFrameBorderLeft InspectModelFrameBorderRight InspectModelFrameBorderTop InspectModelFrameBorderTopLeft InspectModelFrameBorderTopRight InspectNeckSlot
InspectPaperDollItemsFrame InspectSecondaryHandSlot InspectShirtSlot InspectShoulderSlot InspectTabardSlot InspectTrinket0Slot InspectTrinket1Slot InspectWaistSlot
InspectWristSlot InvasionAlertSystem IsActionInRange IsAltKeyDown IsAttackAction IsAutoRepeatAction IsControlKeyDown IsCurrentAction
IsCurrentSpell IsEquippedAction IsFlying IsFrameHandle IsInGuild IsInInstance IsMounted IsPetAttackAction
IsPlayerAtEffectiveLevelCap IsResting IsShiftKeyDown IsSpellInRange IsSpellKnownByPlayer IsSpellKnownOrOverridesKnown IsUsableAction IsXPUserDisabled
Item ItemLocation LE_ITEM_CLASS_CONSUMABLE LFDParentFrame LOCALIZED_CLASS_NAMES_FEMALE LOCALIZED_CLASS_NAMES_MALE LegendaryItemAlertSystem LoggingCombat
LootAlertSystem LootFrame LootSlot LootSlotHasItem LootUpgradeAlertSystem MAX_CHARACTER_MACROS MAX_PLAYER_LEVEL MELEE_ATTACK_POWER
MELEE_ATTACK_POWER_TOOLTIP MILLING MINIMAP_TRACKING_TRAINER_CLASS MainMenuBarBackpackButton MainMenuMicroButton_ShowAlert MenuUtil MicroButtonPulse MicroButtonPulseStop
MicroMenuContainer Minimap MinimapBackdrop MinimapBorder MinimapBorderTop MinimapCluster MinimapMailFrameUpdate MinimapNorthTag
MinimapZoneText MoneyWonAlertSystem MonthlyActivityAlertSystem NORMAL_FONT_COLOR NUM_BAG_FRAMES NUM_BAG_SLOTS NUM_GROUP_LOOT_FRAMES NewCosmeticAlertFrameSystem
NewMountAlertSystem NewPetAlertSystem NewRecipeLearnedAlertSystem NewRuneforgePowerAlertSystem NewToyAlertSystem NewWarbandSceneAlertSystem NotifyInspect ObjectiveTrackerBlockMixin
ObjectiveTrackerFrame ObjectiveTracker_Update OpacitySliderFrame PAPERDOLLFRAME_TOOLTIP_FORMAT PARRY_CHANCE PROSPECTING PVEFrame PVEFrame_ToggleFrame
PanelTemplates_GetSelectedTab PanelTemplates_SetTab PaperDollFormatStat PaperDollFrame PaperDollFrameEquipSet PaperDollFrameSaveSet PaperDollFrame_GetArmorReduction PaperDollFrame_GetArmorReductionAgainstTarget
PaperDollSidebarTab1 PaperDollSidebarTab2 PaperDollSidebarTab3 PaperDollSidebarTabs PartyFrame PerksProgramFrame PetCastingBarFrame PetFrame
PickupPetAction PlaySound PlaySoundFile PlayerCastingBarFrame PlayerChoiceFrame PlayerFrame PlayerHasToy PlayerSpellsFrame PlayerSpellsMicroButton
PlayerSpellsUtil PlayerUtil ProfessionsCustomerOrdersFrame QueueStatusButton QuickJoinToastButton RANGE_INDICATOR RED_FONT_COLOR_CODE RafRewardDeliveredAlertSystem RegisterStateDriver RegisterUnitWatch
ReloadUI RepairAllItems ReputationFrame RequestRaidInfo RollOnLoot Round SANCTUARY_TERRITORY SHAMAN_TOTEM_PRIORITIES
SOUNDKIT SPECIALIZATION SPECIALIZATIONS SPELLBOOK SPELLBOOK_ABILITIES_BUTTON SPELL_FAILED_NEED_MORE_ITEMS STANDARD_TOTEM_PRIORITIES STATICPOPUP_NUMDIALOGS
STAT_ARMOR_TARGET_TOOLTIP STAT_ARMOR_TOOLTIP STAT_ATTACK_SPEED_BASE_TOOLTIP STAT_BLOCK_TARGET_TOOLTIP STAT_CRITICAL_STRIKE STAT_CRITICAL_STRIKE_TOOLTIP STAT_HASTE STAT_HASTE_BASE_TOOLTIP
STAT_HASTE_TOOLTIP STAT_HEALTH_PET_TOOLTIP STAT_HEALTH_TOOLTIP STAT_LIFESTEAL STAT_MASTERY STAT_MASTERY_TOOLTIP STAT_NO_BENEFIT_TOOLTIP STAT_SPEED
STAT_SPELLPOWER STAT_SPELLPOWER_TOOLTIP STAT_TOOLTIP_BONUS_AP STAT_TOOLTIP_BONUS_AP_SP STAT_VERSATILITY STAT_VERSATILITY_TOOLTIP SaveBindings ScenarioAlertSystem
ScenarioObjectiveTracker ScrollUtil SecureCmdOptionParse SecureHandlerWrapScript SetActionUIButton SetBinding SetBindingClick SetChatColorNameByClass
SetItemRef SetLargeGuildTabardTextures SetLootSpecialization SetModifiedClick SetOverrideBindingClick SetRaidTargetIconTexture SharedTooltip_SetBackdropStyle SkillLineSpecsUnlockedAlertSystem
SpellbookMicroButton StaticPopup_FindVisible StaticPopup_Hide StatusTrackingBarInfo StatusTrackingBarManager StopSound StoreMicroButton_OnClick SuppressProcVisualFrame
TALENTS TIMEMANAGER_TICKER_12HOUR TIMEMANAGER_TICKER_24HOUR TIMEMANAGER_TOOLTIP_LOCALTIME TIMEMANAGER_TOOLTIP_REALMTIME TIMEMANAGER_TOOLTIP_TITLE TRANSMOGRIFY TalentFrameUtil
TalentLoadoutManagerAPI TalentMicroButton TargetFrame TargetFrameToT TimeManagerClockButton TimeManagerClockTicker TimeManagerFrame TimeManager_Toggle
ToggleAchievementFrame ToggleAllBags ToggleCalendar ToggleChannelFrame ToggleCharacter ToggleCollectionsJournal ToggleDropDownMenu ToggleEncounterJournal
ToggleFriendsFrame ToggleGameMenu ToggleGuildFrame ToggleHelpFrame TogglePlayerSpellsFrame ToggleProfessionsBook ToggleQuestLog ToggleSpellBook ToggleStoreUI
ToggleTalentFrame ToggleWorldMap TokenFrame TooltipDataProcessor TotemFrame UIDropDownMenu_AddButton UIDropDownMenu_CreateInfo UIDropDownMenu_Initialize
UIERRORS_HOLD_TIME UIFrameFadeIn UIFrameFadeRemoveFrame UIFrameFlashStop UiMapPoint UnitArmor UnitAttackPower UnitAttackSpeed
UnitAura UnitCastingDuration UnitChannelDuration UnitClassification UnitControllingVehicle UnitDistanceSquared UnitEffectiveLevel UnitFactionGroup
UnitFullName UnitGUID UnitGetDetailedHealPrediction UnitGetIncomingHeals UnitGetTotalAbsorbs UnitGetTotalHealAbsorbs UnitGroupRolesAssigned UnitHPPerStamina
UnitHasIncomingResurrection UnitHasVehicleUI UnitHealth UnitHealthMax UnitHealthMissing UnitInParty UnitInRaid UnitInRange
UnitInVehicle UnitIsAFK UnitIsConnected UnitIsDeadOrGhost UnitIsGhost UnitIsGroupAssistant UnitIsGroupLeader UnitIsPlayer
UnitIsUnit UnitLevel UnitPhaseReason UnitPower UnitPowerPercent UnitPowerType UnitReaction UnitSex
UnitSpellHaste UnitStagger UnitStat UnitThreatSituation UnitXP UnitXPMax UnregisterStateDriver UpdateAddOnCPUUsage
UpdateMicroButtons UpdateMicroButtonsParent WOW_PROJECT_ID WOW_PROJECT_MAINLINE WardrobeFrame WardrobeTransmogFrame WeeklyRewardsFrame WeeklyRewards_ShowUI WorldMapFrame
WorldQuestCompleteAlertSystem ZoneAbilityFrame debugprofilestart gsub strupper tremove table.unpack table.wipe
]]

for name in additional_read_globals:gmatch("%S+") do
    read_globals[#read_globals + 1] = name
end

local additional_writable_globals = {
    "ApplySpellFlyoutButtonStateTextures",
    "BossTargetFrameContainer",
    "ChatTypeInfo",
    "ClickCastFrames",
    "EncounterWarningsTextElementMixin",
    "GroupLootContainer",
    "HideOwnedFlyout",
    "InspectFrame",
    "MicroMenu",
    "RefreshAll_Composer",
    "SLASH_QUI_AURAPROBE1",
    "SLASH_QUI_CDMDEBUG1",
    "SLASH_QUI_CLEUPROBE1",
    "SLASH_QUI_QSPELL1",
    "SLASH_QUIIMPLUSTIMER1",
    "SLASH_QUIRAIDBUFFS1",
    "SLASH_QUICLEARSCAN1",
    "SLASH_QUIDATAPANELS1",
    "SLASH_QUISCANNED1",
    "SLASH_QUITABFILTERS1",
    "ShowHuntPanel",
    "ShowOwnedFlyoutForButton",
    "SkinSpellFlyoutButtons",
    "StaticPopupDialogs",
    "TalkingHeadFrame",
}

for _, name in ipairs(additional_writable_globals) do
    globals[#globals + 1] = name
end

local project_runtime_globals = [[
CTX_KEY ClearAnalysis HideCopyButton LINKED_BAR_KEYS NCDM QUICore RunNextFrame UIKit
]]

for name in project_runtime_globals:gmatch("%S+") do
    read_globals[#read_globals + 1] = name
end

local project_writable_globals = {
    "_assistRotationButton",
    "initSafePeriod",
    "pendingAnchoredFrameUpdateAfterCombat",
}

for _, name in ipairs(project_writable_globals) do
    globals[#globals + 1] = name
end

-- Suppress intentional legacy/client idioms while keeping undefined-variable
-- checking active for ordinary addon files.
local project_ignored_warning_codes = {
    "122", -- writes into client-owned tables/fields for hooks and constants
    "211", -- unused locals from callback/destructure patterns
    "212", -- unused callback arguments
    "213", -- unused loop variables in table construction
    "221", -- forward declarations filled by runtime hooks
    "231", -- retained state slots read by the client or future hook calls
    "241", -- retained mutation-only state
    "311", -- overwritten staging locals in UI layout code
    "314", -- overwritten default table fields
    "411", -- chunk-local redeclarations after extracted runtime sections
    "421", -- local shadowing in nested builders
    "431", -- upvalue shadowing in nested builders
    "432", -- callback self shadowing
    "433", -- loop-variable shadowing
    "511", -- defensive returns after early exits
    "512", -- single-pass loops over first visible match
    "541", -- intentionally empty compatibility block
    "542", -- intentionally empty pcall fallback branches
}

for _, code in ipairs(project_ignored_warning_codes) do
    ignore[#ignore + 1] = code
end

files["QUI_ActionBars/actionbars/*_compat.lua"] = {
    ignore = { "112", "113" },
}

-- Action bar chunk-env files load under a setfenv() environment swap
-- (SetChunkEnv): every module-internal function and cross-file helper is a
-- field on ActionBarsEnv, not a real Lua global, so luacheck (which can't see
-- the swapped _ENV) reports them all as W111 "setting non-standard global",
-- W112 "mutating non-standard global", and W113 "accessing undefined variable".
-- Those codes carry no signal for these files; genuine breakage surfaces via the
-- unit suite + taint analyzer instead. Scoped to the specific chunk-env files
-- (the non-chunk-env actionbars files — buffborders/gse_compat/totems — keep
-- full undefined-global checking). Extend this list when touching other
-- SetChunkEnv files in QUI_ActionBars/actionbars/.
files["QUI_ActionBars/actionbars/actionbars_flyout.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_usability.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_editmode.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars.lua"] = {
    ignore = { "111", "112", "113", "121" },
}
files["QUI_ActionBars/actionbars/actionbars_cooldowns.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_events.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_glow.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_helpers.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_public.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_mouseover.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_builder.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_extra_buttons.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_layout.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_per_bar_builders.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_petstance.lua"] = {
    ignore = { "111", "112", "113" },
}
files["QUI_ActionBars/actionbars/actionbars_skinning.lua"] = {
    ignore = { "111", "112", "113", "121" },
}

files["QUI_QoL/dungeon/party_keystones.lua"] = {
    ignore = { "113" },
}

files["modules/integrations/*.lua"] = {
    ignore = { "113" },
}

-- Unit / integration tests stub the WoW client API and frame globals by
-- assigning to them (CreateFrame, GetPlayerInfoByGUID, ChatTypeInfo,
-- RAID_CLASS_COLORS, hooksecurefunc, SetChatColorNameByClass, NUM_CHAT_WINDOWS,
-- ChatFrame1, ...), which are read-only or undefined in addon code. Allow
-- defining / overwriting globals in the test harness. 113 (reading an undefined
-- global) stays ON so genuine typos in test reads still surface.
files["tests/"] = {
    ignore = {
        "111", -- setting an undefined global (a test-invented mock global)
        "112", -- mutating an undefined global
        "121", -- setting a read-only global (stubbing a WoW API global)
        "122", -- setting a read-only field of a global
        "131", -- unused implicitly defined global
    },
}
