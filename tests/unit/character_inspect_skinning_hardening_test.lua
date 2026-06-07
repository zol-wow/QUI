-- tests/unit/character_inspect_skinning_hardening_test.lua
-- Run: lua tests/unit/character_inspect_skinning_hardening_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function assertContains(text, needle, reason)
    assert(text:find(needle, 1, true), reason)
end

local function assertAbsent(text, needle, reason)
    assert(not text:find(needle, 1, true), reason)
end

local characterSource = readFile("QUI_Skinning/skinning/character_pane/character.lua")
local inspectSource = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")
local legacyGuildGuardKey = "__qui_" .. "guild_nil_guard"
local forbiddenValueHelper = "Helpers." .. "Sa" .. "feValue"
local forbiddenNumberHelper = "Helpers." .. "Sa" .. "feToNumber"
local characterItemHelperBlock = assert(
    characterSource:match("Structured item%-data helpers.-Get durability for a slot"),
    "Character structured item helper block should exist")
local characterEquipmentSlotBlock = assert(
    characterSource:match("local function SkinEquipmentSlot%(slot%).-local function UpdateSlotBorder%(slot%)"),
    "Character equipment slot skinning block should exist")
local characterUpdateSlotBorderBlock = assert(
    characterSource:match("local function UpdateSlotBorder%(slot%).-%-%- All equipment slot names"),
    "Character equipment slot border update block should exist")
local characterLayoutStart = assert(
    characterSource:find("ApplyCharacterPaneLayout = function(force)", 1, true),
    "Character layout entry point should exist")
local characterLayoutDelayStart = assert(
    characterSource:find("C_Timer.After(0.1, function()", characterLayoutStart, true),
    "Character first-open delayed layout block should exist")
local characterLayoutDelayEnd = assert(
    characterSource:find("    end)", characterLayoutDelayStart, true),
    "Character first-open delayed layout block should be closed")
local characterLayoutDelayBlock = characterSource:sub(characterLayoutDelayStart, characterLayoutDelayEnd)

assertContains(
    characterSource,
    "local function IsInspectUnit(unit)",
    "Shared character overlays must treat every non-player inspect unit as inspect data")

assertAbsent(
    characterSource,
    "unit == \"target\" and settings.inspect",
    "Inspect overlay settings must not be limited to the target unit token")

assertContains(
    characterSource,
    "C_Item.GetDetailedItemLevelInfo",
    "Character overlays should use the structured item-level API before tooltip text parsing")

assertContains(
    characterSource,
    "C_Item.GetItemUpgradeInfo",
    "Character overlays should use the structured upgrade API before tooltip text parsing")

assertContains(
    characterSource,
    "C_Item.GetItemNumSockets",
    "Character overlays should use the structured socket-count API")

assertContains(
    characterSource,
    "C_Item.GetItemGem",
    "Character overlays should use the structured gem API")

assertContains(
    characterSource,
    "TooltipDataLineType.ItemEnchantmentPermanent",
    "Enchantment parsing should prefer Blizzard's structured tooltip line type")

assertContains(
    characterSource,
    "CanItemUsePermanentEnchant",
    "Missing-enchant state should be based on item equipment type rather than only slot IDs")

assertContains(
    characterSource,
    "local function GetSkinBase()",
    "Character pane must look up SkinBase after load because skinning base loads later")

assertAbsent(
    characterSource,
    "local SkinBase = ns.SkinBase",
    "Character pane must not capture nil SkinBase before skinning base loads")

assertContains(
    characterEquipmentSlotBlock,
    "SetSlotBorderPoints(borderFrame, slot)",
    "Character equipment slot borders must route point layout through the shared pixel-point wrapper")

assertContains(
    characterEquipmentSlotBlock,
    "ApplySlotPixelBackdrop(borderFrame",
    "Character equipment slot borders must use the shared pixel-backdrop helper")

assertAbsent(
    characterUpdateSlotBorderBlock,
    "quality >= 1",
    "Character equipment slot borders must not hide poor-quality item borders")

assertAbsent(
    characterUpdateSlotBorderBlock,
    "borderFrame:Hide()",
    "Character equipment slot borders must remain visible with a default color when item quality is unavailable")

assertContains(
    characterSource,
    "local function RefreshEquipmentSlotBorders()",
    "Character equipment slot borders must have a shared refresh pass")

assertContains(
    characterLayoutDelayBlock,
    "RefreshEquipmentSlotBorders()",
    "Character first-open delayed layout must refresh slot borders after slot repositioning")

assertAbsent(
    characterSource,
    "pendingCharacterLayout",
    "Character layout work must not be deferred behind combat lockdown")

assertContains(
    characterSource,
    "ApplyCharacterPaneLayout = function(force)",
    "Character layout should remain callable through the shared layout entry point")

assertContains(
    inspectSource,
    "local function IsCurrentInspectUnit(unit)",
    "Inspect updates must validate INSPECT_READY GUID state before reading inspected equipment")

assertContains(
    inspectSource,
    "local pendingInspectReadyGUID = nil",
    "Inspect ready GUIDs must be retained when INSPECT_READY fires before InspectFrame.unit/OnShow state is stable")

assertContains(
    inspectSource,
    "RefreshCurrentInspectGUID = function(unit)",
    "Inspect OnShow must preserve an already-ready GUID for the current inspected unit")

assertContains(
    inspectSource,
    "pendingInspectReadyGUID = arg1",
    "INSPECT_READY must store the GUID before attempting to match the current unit")

local inspectOnShowStart = assert(
    inspectSource:find("InspectFrame:HookScript(\"OnShow\"", 1, true),
    "Inspect OnShow hook should exist")
local inspectOnShowEnd = assert(
    inspectSource:find("-- NOTE: do NOT call NotifyInspect here", inspectOnShowStart, true),
    "Inspect OnShow hook should retain NotifyInspect ordering note")
local inspectOnShowBlock = inspectSource:sub(inspectOnShowStart, inspectOnShowEnd)

assertContains(
    inspectOnShowBlock,
    "RefreshCurrentInspectGUID(unit)",
    "Inspect OnShow must refresh/preserve inspect readiness instead of blindly clearing it")

assertAbsent(
    inspectOnShowBlock,
    "currentInspectGUID = nil",
    "Inspect OnShow must not wipe a fast INSPECT_READY GUID before the first overlay update")

assertContains(
    inspectSource,
    "local dataReady = IsCurrentInspectUnit(unit)",
    "Inspect slot updates must be gated by the current inspected GUID")

assertContains(
    inspectSource,
    "C_PaperDollInfo.GetInspectItemLevel",
    "Inspect average item level should use Blizzard's structured inspect item-level API")

assertContains(
    inspectSource,
    "local inspectGuildNilGuard = Helpers.CreateStateTable()",
    "Inspect guild nil-guard state must live outside Blizzard frame keys")

assertAbsent(
    inspectSource,
    legacyGuildGuardKey,
    "Inspect guild nil-guard state must not be stored on Blizzard frame keys")

assertContains(
    inspectSource,
    "local function SetInspectScaleDeferred(scale)",
    "Inspect panel scale changes must be combat-deferred")

assertContains(
    inspectSource,
    "SetInspectScaleDeferred(INSPECT_CONFIG.BASE_SCALE * multiplier)",
    "Inspect settings scale slider must use the combat-deferred scale wrapper")

assertContains(
    inspectSource,
    "ApplyInspectPaneLayout = function(force)",
    "Inspect layout should be force-replayable after combat deferral")

assertContains(
    inspectSource,
    "pendingInspectLayout = true",
    "Inspect layout work must be deferred during combat lockdown")

assertAbsent(
    inspectSource,
    forbiddenValueHelper,
    "Inspect skinning must not unwrap protected API values with the forbidden value helper")

assertAbsent(
    inspectSource,
    forbiddenNumberHelper,
    "Inspect skinning must not collapse protected API values with the forbidden numeric helper")

assertAbsent(
    characterSource,
    forbiddenValueHelper,
    "Character skinning must not unwrap protected API values with the forbidden value helper")

assertAbsent(
    characterSource,
    forbiddenNumberHelper,
    "Character skinning must not collapse protected API values with the forbidden numeric helper")

print("OK: character_inspect_skinning_hardening_test")
