-- tests/unit/skinning_font_reassertions_test.lua
-- Run: lua tests/unit/skinning_font_reassertions_test.lua
--
-- Source regression guard for Blizzard text paths that reapply font objects or
-- direct fonts after the initial QUI skin pass. These sites must either
-- re-style text on every Blizzard setup/rebind or lock descendant FontStrings.

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

local function blockBetween(text, startNeedle, endNeedle)
    local startPos = assert(text:find(startNeedle, 1, true), "missing block start: " .. startNeedle)
    local endPos = assert(text:find(endNeedle, startPos, true), "missing block end: " .. endNeedle)
    return text:sub(startPos, endPos - 1)
end

local function assertOrdered(text, first, second, reason)
    local firstPos = assert(text:find(first, 1, true), reason .. " (missing first marker)")
    local secondPos = assert(text:find(second, 1, true), reason .. " (missing second marker)")
    assert(firstPos < secondPos, reason)
end

---------------------------------------------------------------------------
-- Character equipment manager rows: PaperDoll rebinds row text/color.
---------------------------------------------------------------------------
local character = readFile("QUI_Skinning/skinning/frames/character.lua")
assertContains(character, "local function RestyleEquipmentSetEntryText(entry)",
    "equipment manager must split text restyle from one-time row chrome")
local equipEntry = blockBetween(character, "local function SkinEquipmentSetEntry(entry)",
    "-- Style Equip/Save buttons")
assertOrdered(equipEntry, "RestyleEquipmentSetEntryText(entry)",
    "if skinnedEntries[entry] then return end",
    "equipment row text must be reasserted before the already-skinned early return")
local equipRefresh = blockBetween(character, "RefreshEquipmentManagerColors = function()",
    "-- Update buttons")
assertContains(equipRefresh, "RestyleEquipmentSetEntryText(entry)",
    "equipment manager refresh must reassert visible row text")

---------------------------------------------------------------------------
-- Entitlement/RAF alerts: AlertFrame setup rebinds Title every toast.
---------------------------------------------------------------------------
local alerts = readFile("QUI_Skinning/skinning/notifications/alerts.lua")
assertContains(alerts, "local function RestyleEntitlementAlertText(frame)",
    "entitlement alerts need a per-toast text restyle helper")
local entitlement = blockBetween(alerts, "local function SkinEntitlementAlert(frame)",
    "--- Skin Digsite Complete Alert")
assertAbsent(entitlement, "if not frame or SkinBase.IsSkinned(frame) then return end",
    "entitlement alerts must not skip text restyle on already-skinned pooled frames")
assertOrdered(entitlement, "RestyleEntitlementAlertText(frame)",
    "if SkinBase.IsSkinned(frame) then return end",
    "entitlement alert text must be reasserted before the already-skinned return")

---------------------------------------------------------------------------
-- Professions/crafting/PVP/dropdown/interaction frames: lock text rebinds.
---------------------------------------------------------------------------
local crafting = readFile("QUI_Skinning/skinning/frames/craftingorders.lua")
local durationBlock = blockBetween(crafting, "-- Duration dropdown", "-- Note edit box")
assertContains(durationBlock, "SkinBase.SkinFontString(pc.DurationDropdown.Text, { fontOnly = true })",
    "customer order duration dropdown visible text must use the QUI font")
assertContains(durationBlock, "SkinBase.LockFrameTextObjects(pc.DurationDropdown, 2)",
    "customer order duration dropdown text must survive Blizzard SetFontObject")
assertContains(crafting, "LockDropdownText(form.MinimumQuality.Dropdown)",
    "customer order minimum quality dropdown visible text must be locked")
assertContains(crafting, "LockDropdownText(form.OrderRecipientDropdown)",
    "customer order recipient dropdown visible text must be locked")

local professions = readFile("QUI_Skinning/skinning/frames/professions.lua")
local orderTypeTabs = blockBetween(professions, "-- Order type tab buttons",
    "    end\n\n    -- Order view")
assertContains(orderTypeTabs, "SkinBase.SkinTab(tab, browseFrame, { hover = true })",
    "crafter order type tabs must use durable tab font-object handling")
assertContains(orderTypeTabs, "SkinBase.LockFrameTextObjects(tab, 2)",
    "crafter order type tabs must lock SetTabSelected font-object swaps")
local orderView = blockBetween(professions, "-- Order view (individual order detail)",
    "end\nend\n\n---------------------------------------------------------------------------\n-- SKIN SPEC PAGE")
assertContains(orderView, "local noteTitle = orderView.OrderInfo and orderView.OrderInfo.NoteBox and orderView.OrderInfo.NoteBox.NoteTitle",
    "crafter order note title must be targeted explicitly")
assertContains(orderView, "SkinBase.LockFontObject(noteTitle, { fontOnly = true })",
    "crafter order note title must survive SetOrder font-object swaps")

local instanceFrames = readFile("QUI_Skinning/skinning/frames/instanceframes.lua")
local pveGroupButtons = blockBetween(instanceFrames, "local function StyleGroupFinderButton(button",
    "-- Skin PVEFrame (main container)")
assertContains(pveGroupButtons, "SkinBase.SkinFontString(button.name, { fontOnly = true })",
    "PVE group finder labels must reapply the QUI font")
assertContains(pveGroupButtons, "LockFrameTextObjects(button, 2)",
    "PVE group finder labels must survive GroupFinderFrameButton_SetEnabled font-object swaps")
assertContains(instanceFrames, "SkinBase.SkinFontString(av.AutoAcceptButton.Label, { fontOnly = true })",
    "LFG application auto-accept label must reapply the QUI font")
assertContains(instanceFrames, "LockFrameTextObjects(av.AutoAcceptButton, 2)",
    "LFG application auto-accept label must survive dynamic font-object resets")
local pvpCategories = blockBetween(instanceFrames, "-- Style category buttons",
    "-- Style Honor frame")
assertContains(pvpCategories, "LockFrameTextObjects(catButton, 2)",
    "PVP category buttons must lock Name font-object swaps")

local popups = readFile("QUI_Skinning/skinning/system/popups.lua")
assertOrdered(popups, "SkinBase.SkinFrameText(frame, { recurse = true })",
    "SkinBase.LockFrameTextObjects(frame, 3)",
    "legacy dropdown text must be locked after skinning")
assertContains(popups, "StyleButton(popup.ExtraButton or (name and _G[name .. \"ExtraButton\"]), \"staticPopup\")",
    "StaticPopup ExtraButton must use durable button font-object styling")
assertContains(popups, "RefreshButtonState(self.ExtraButton or (recapName and _G[recapName .. \"ExtraButton\"]))",
    "StaticPopup recap refresh must include ExtraButton text state")

local journals = readFile("QUI_Skinning/skinning/frames/journals.lua")
local encounterTextFrame = blockBetween(journals, "local function SkinEncounterJournalTextFrame(frame)",
    "local function ScheduleEncounterJournalTextFrame(frame)")
assertContains(encounterTextFrame, "SkinBase.LockFrameTextObjects(frame, 3)",
    "Adventure Guide text frames must lock SetFontObject resets after skinning")
assertContains(journals, "local function LockCollectionsText(frame)",
    "Collections Journal must have a durable text lock helper")
assertContains(journals, "local function GetEncounterJournalBottomTabs(frame)",
    "Adventure Guide bottom content tabs must be collected explicitly")
assertContains(journals, "SkinBase.SkinTabGroup(tabs, frame)",
    "Adventure Guide bottom content tabs must be styled as tabs")
assertContains(journals, "SkinBase.LockFrameTextObjects(tab, 2)",
    "Adventure Guide bottom content tabs must lock PanelTemplates font-object swaps")
assertContains(journals, "LockCollectionsScrollBox(_G.MountJournal and _G.MountJournal.ScrollBox)",
    "Mount Journal pooled rows must lock font-object resets")
assertContains(journals, "LockCollectionsScrollBox(_G.PetJournal and _G.PetJournal.ScrollBox)",
    "Pet Journal pooled rows must lock font-object resets")
assertContains(journals, "LockCollectionsScrollBox(_G.HeirloomsJournal and _G.HeirloomsJournal.ScrollBox)",
    "Heirlooms Journal pooled rows must lock font-object resets")

local achievement = readFile("QUI_Skinning/skinning/frames/achievement.lua")
-- Pooled list/stat rows must go through the guarded row-font helper (runs the
-- recursive pass once per row) rather than an unguarded per-acquire re-skin —
-- the unguarded form was the open-window hitch.
assertContains(achievement, "SkinBase.HookScrollBoxRowFonts(scrollBox, 3)",
    "Achievement list ScrollBoxes must use the guarded row-font helper, not an unguarded per-acquire re-skin")
assertContains(achievement, "SkinBase.HookScrollBoxRowFonts(statScrollBox, 3)",
    "Achievement comparison stat ScrollBox must use the guarded row-font helper")
assertContains(achievement, "SkinBase.HookScrollBoxRowFonts(achScrollBox, 3)",
    "Achievement comparison achievement-list ScrollBox must lock cold-acquired row fonts")
assertContains(achievement, "if not SkinBase.GetFrameData(button, \"qListRowFonted\") then",
    "Achievement summary buttons must guard the recursive font pass so the Update hook does not re-walk every refresh")
assertContains(achievement, "local function LockAchievementSummaryText()",
    "Achievement summary buttons must have a durable text lock helper")
assertContains(achievement, "hooksecurefunc(\"AchievementFrameSummary_UpdateAchievements\"",
    "Achievement summary refresh must hook Blizzard's dynamic point-font update")
assertContains(achievement, "local function LockAchievementComparisonText()",
    "Achievement comparison rows must have a durable text lock helper")
assertContains(achievement, "AchievementFrameComparison.StatContainer.ScrollBox",
    "Achievement comparison stat ScrollBox must be locked")

local auctionhouse = readFile("QUI_Skinning/skinning/frames/auctionhouse.lua")
local auctionsTabs = blockBetween(auctionhouse, "local function SkinAuctionHouseAuctionsTabs(auctionsFrame)",
    "local function LockDurationDropdownText(dropdown)")
assertContains(auctionsTabs, "SkinBase.SkinTabGroup(tabs, auctionsFrame, { font = true })",
    "Auction House inner Auctions/Bids tabs must be skinned as a durable tab group")
assertContains(auctionsTabs, "SkinBase.LockFrameTextObjects(tab, 2)",
    "Auction House inner Auctions/Bids tabs must lock PanelTemplates font-object swaps")
local auctionsPanel = blockBetween(auctionhouse, "local function SkinAuctionsPanel()",
    "-- Suppress a category button's default textures")
assertContains(auctionsPanel, "SkinAuctionHouseAuctionsTabs(auctionsFrame)",
    "Auction House auctions panel must skin its inner Auctions/Bids tabs")
assertContains(auctionhouse, "local function LockDurationDropdownText(dropdown)",
    "Auction House duration dropdowns must have a visible text lock helper")
assertContains(auctionhouse, "LockDurationDropdownText(commoditiesSell.DurationDropdown)",
    "commodities sell duration dropdown text must survive Blizzard font-object swaps")
assertContains(auctionhouse, "LockDurationDropdownText(itemSell.DurationDropdown)",
    "item sell duration dropdown text must survive Blizzard font-object swaps")
assertContains(auctionhouse, "local function LockAuctionHouseTokenText()",
    "Auction House WoW Token price labels must have a durable text lock helper")
assertContains(auctionhouse, "AuctionHouseFrame.WoWTokenResults",
    "WoW Token buy result text must be explicitly locked")
assertContains(auctionhouse, "AuctionHouseFrame.WoWTokenSellFrame",
    "WoW Token sell text must be explicitly locked")
assertContains(auctionhouse, "local function LockAuctionHouseBuyDialogText()",
    "Auction House buy dialog notification text must have a durable text lock helper")
assertContains(auctionhouse, "AuctionHouseFrame.BuyDialog.Notification",
    "Auction House buy dialog notification text must be explicitly locked")

local social = readFile("QUI_Skinning/skinning/frames/social.lua")
assertContains(social, "HookListRows(frame.CommunitiesList.ScrollBox)",
    "Communities list rows must lock font-object resets")
assertContains(social, "HookListRows(frame.ApplicantList.ScrollBox)",
    "Club finder applicant rows must lock font-object resets")
assertContains(social, "HookListRows(frame.GuildBenefitsFrame.Rewards.ScrollBox)",
    "Guild reward rows must lock font-object resets")
assertContains(social, "local function LockGuildNameAlertText(frame)",
    "guild name alert must have a durable text lock helper")
assertContains(social, "SkinBase.LockFontObject(alert, { fontOnly = true })",
    "guild name alert must survive dynamic font-object resets")

local interaction = readFile("QUI_Skinning/skinning/frames/interaction.lua")
local lockCount = 0
for _ in interaction:gmatch("SkinBase%.LockFrameTextObjects%(frame, %d%)") do
    lockCount = lockCount + 1
end
assert(lockCount >= 4, "Bank/Merchant/Mail/GuildBank skins must lock descendant text objects")

local characterPane = readFile("QUI_Skinning/skinning/character_pane/character.lua")
local characterSettings = blockBetween(characterPane, "-- \"Settings\" label",
    "-- Close button (X)")
assertContains(characterSettings, "CJKFont(gearLabel, STANDARD_TEXT_FONT, 12, \"\")",
    "Character settings gear label must route through CJK fallback")
assertContains(characterSettings, "CJKFont(title, STANDARD_TEXT_FONT, 14, \"\")",
    "Character settings panel title must route through CJK fallback")

local inspectPane = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")
local inspectSettings = blockBetween(inspectPane, "local gearLabel = gearBtn:CreateFontString",
    "-- Close button")
assertContains(inspectSettings, "CJKFont(gearLabel, STANDARD_TEXT_FONT, 12, \"\")",
    "Inspect settings gear label must route through CJK fallback")
assertContains(inspectSettings, "CJKFont(title, STANDARD_TEXT_FONT, 14, \"\")",
    "Inspect settings panel title must route through CJK fallback")

---------------------------------------------------------------------------
-- Ready check: direct SetFont bypasses CJK fallback and button font objects.
---------------------------------------------------------------------------
local readycheck = readFile("QUI_Skinning/skinning/notifications/readycheck.lua")
assertAbsent(readycheck, "text:SetFont(font, 12, FONT_FLAGS)",
    "ready-check button labels must not bypass CJK fallback")
assertContains(readycheck, "CJKFont(text, font, 12, FONT_FLAGS)",
    "ready-check button labels must route through CJK fallback")
assertContains(readycheck, "SkinBase.ApplyButtonFontObjects(button, { size = 12",
    "ready-check buttons must drive state font objects")
assertAbsent(readycheck, "text:SetFont(STANDARD_TEXT_FONT, 12, FONT_FLAGS)",
    "ready-check main text must not bypass CJK fallback")
assertContains(readycheck, "CJKFont(text, STANDARD_TEXT_FONT, 12, FONT_FLAGS)",
    "ready-check main text must route through CJK fallback")

local tooltips = readFile("QUI_Skinning/skinning/system/tooltips.lua")
assertContains(tooltips, "if tooltip ~= GameTooltip then",
    "GameTooltip must be excluded from recursive SkinFrameText")
assertContains(tooltips, "SkinBase.SkinFrameText(tooltip, { recurse = true })",
    "non-GameTooltip tooltip text should still route through the shared text skin")

---------------------------------------------------------------------------
-- Shared pooled-row font helper: single source of truth for "lock a ScrollBox's
-- rows once". It MUST guard per row (qListRowFonted) so the expensive recursive
-- SkinFrameText pass runs once and the open-window hitch can't return; every
-- list panel routes through it instead of an inline per-acquire re-skin.
---------------------------------------------------------------------------
local uikit = readFile("core/uikit.lua")
local rowFontHelper = blockBetween(uikit, "function SkinBase.HookScrollBoxRowFonts(scrollBox, depth)",
    "\nend")
assertContains(rowFontHelper, "SkinBase.GetFrameData(row, \"qListRowFonted\")",
    "HookScrollBoxRowFonts must guard per row so the recursive font pass runs once")
assertContains(rowFontHelper, "SkinBase.SetFrameData(row, \"qListRowFonted\", true)",
    "HookScrollBoxRowFonts must mark the row fonted after the one-time pass")

for _, frame in ipairs({
    { path = "QUI_Skinning/skinning/frames/journals.lua",       what = "Collections journal rows" },
    { path = "QUI_Skinning/skinning/frames/instanceframes.lua", what = "LFD/LFG list rows" },
    { path = "QUI_Skinning/skinning/frames/social.lua",         what = "friends/guild list rows" },
}) do
    local src = readFile(frame.path)
    assertContains(src, "SkinBase.HookScrollBoxRowFonts(",
        frame.what .. " must use the guarded row-font helper, not an unguarded per-acquire re-skin")
end

print("OK: skinning_font_reassertions_test")
