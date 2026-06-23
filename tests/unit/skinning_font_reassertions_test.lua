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
-- SkinDropdown owns the dropdown text durability: it faces the visible text in the QUI
-- font (SkinFontString{fontOnly}) AND locks it against Blizzard SetFontObject
-- (LockFontObject + LockFrameTextObjects(dropdown, 2)) — see SkinBase.SkinDropdown ->
-- LockDropdownText in core/uikit.lua. So routing through it is the single source of truth.
assertContains(durationBlock, "SkinBase.SkinDropdown(pc.DurationDropdown)",
    "customer order duration dropdown must route through SkinDropdown (QUI font + survives Blizzard SetFontObject)")
-- SkinDropdown calls LockDropdownText internally, so routing the form dropdowns through it
-- guarantees their visible text is faced + locked (no separate post-lock call needed).
assertContains(crafting, "SkinBase.SkinDropdown(form.MinimumQuality.Dropdown)",
    "customer order minimum quality dropdown must route through SkinDropdown (faces + locks its text)")
assertContains(crafting, "SkinBase.SkinDropdown(form.OrderRecipientDropdown)",
    "customer order recipient dropdown must route through SkinDropdown (faces + locks its text)")

local professions = readFile("QUI_Skinning/skinning/frames/professions.lua")
local orderTypeTabs = blockBetween(professions, "-- Order type tab buttons",
    "    end\n\n    -- Order view")
assertContains(orderTypeTabs, "SkinBase.SkinTab(tab, browseFrame, { hover = true })",
    "crafter order type tabs must use durable tab font-object handling")
-- LockFrameTextObjects(tab, 2) was removed from the order-type tab loop; SkinTab
-- owns tab font-object durability via its own selection hooks. Interactive font-object
-- reverts on bare-root tab surfaces are accepted under the global object override.
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
-- LockFrameTextObjects(button, 2) was removed from StyleGroupFinderButton;
-- static text durability from global object override; interactive reverts accepted.
assertContains(instanceFrames, "SkinBase.SkinFontString(av.AutoAcceptButton.Label, { fontOnly = true })",
    "LFG application auto-accept label must reapply the QUI font")
-- LockFrameTextObjects(av.AutoAcceptButton, 2) was removed; global override owns durability.
-- LockFrameTextObjects(catButton, 2) was removed from PVP category button styling;
-- global object override owns static text durability for these bare-root surfaces.

local popups = readFile("QUI_Skinning/skinning/system/popups.lua")
-- popups.lua: SkinStaticPopup still calls SkinFrameText(chrome=true) for the
-- per-popup text color pass; LockFrameTextObjects was removed (global override owns durability).
assertContains(popups, "SkinBase.SkinFrameText(popup, { recurse = true",
    "StaticPopup must still run a recursive SkinFrameText pass for chrome color")
assertContains(popups, "StyleButton(popup.ExtraButton or (name and _G[name .. \"ExtraButton\"]), \"staticPopup\")",
    "StaticPopup ExtraButton must use durable button font-object styling")
assertContains(popups, "RefreshButtonState(self.ExtraButton or (recapName and _G[recapName .. \"ExtraButton\"]))",
    "StaticPopup recap refresh must include ExtraButton text state")

local journals = readFile("QUI_Skinning/skinning/frames/journals.lua")
local encounterTextFrame = blockBetween(journals, "local function SkinEncounterJournalTextFrame(frame)",
    "local function ScheduleEncounterJournalTextFrame(frame)")
-- LockFrameTextObjects(frame, 3) was removed from SkinEncounterJournalTextFrame;
-- ApplyButtonFontObjectsDeep now handles interactive object swaps for boss-list buttons.
-- Static text durability from global object override; interactive reverts accepted.
assertContains(encounterTextFrame, "SkinBase.ApplyButtonFontObjectsDeep(frame, 3)",
    "Adventure Guide text frames must drive descendant button font objects after skinning")
-- LockCollectionsText was renamed to LockCollectionsScrollBox (scrollbox-scoped helper).
assertContains(journals, "local function LockCollectionsScrollBox(scrollBox)",
    "Collections Journal must have a durable scrollbox text lock helper")
assertContains(journals, "local function GetEncounterJournalBottomTabs(frame)",
    "Adventure Guide bottom content tabs must be collected explicitly")
assertContains(journals, "SkinBase.SkinTabGroup(tabs, frame)",
    "Adventure Guide bottom content tabs must be styled as tabs")
-- LockFrameTextObjects(tab, 2) was removed from the bottom-tabs loop; interactive
-- font-object reverts on bare-root tab surfaces are accepted under the global override.
assertContains(journals, "LockCollectionsScrollBox(_G.MountJournal and _G.MountJournal.ScrollBox)",
    "Mount Journal pooled rows must lock font-object resets")
assertContains(journals, "LockCollectionsScrollBox(_G.PetJournal and _G.PetJournal.ScrollBox)",
    "Pet Journal pooled rows must lock font-object resets")
assertContains(journals, "local function HookHeirloomsJournal(journal)",
    "Heirlooms Journal must use its FrameXML owner lifecycle, not a fake ScrollBox")
assertContains(journals, "HookHeirloomsJournal(_G.HeirloomsJournal)",
    "Collections refresh must hook the real HeirloomsJournal owner")
assertContains(journals, "hooksecurefunc(journal, \"AcquireFrame\"",
    "Heirlooms Journal must lock newly acquired entry/header frames")
assertContains(journals, "hooksecurefunc(journal, \"RefreshView\"",
    "Heirlooms Journal must re-check active pools on refresh")
assertContains(journals, "hooksecurefunc(journal, \"UpdateButton\"",
    "Heirlooms Journal must relock entries after UpdateButton font-object resets")

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
-- Achievement summary buttons no longer use a qListRowFonted guard; LockAchievementSummaryText
-- calls RecolorSummaryDescription (color re-assert only, no recursive font walk) so re-walk
-- cost is gone. Verify the summary helper still iterates buttons and recolors descriptions.
assertContains(achievement, "local function RecolorSummaryDescription(button)",
    "Achievement summary must have a per-button description recolor helper")
assertContains(achievement, "local function LockAchievementSummaryText()",
    "Achievement summary buttons must have a durable text lock helper")
assertContains(achievement, "hooksecurefunc(\"AchievementFrameSummary_UpdateAchievements\"",
    "Achievement summary refresh must hook Blizzard's dynamic point-font update")
assertContains(achievement, "local function LockAchievementComparisonText()",
    "Achievement comparison rows must have a durable text lock helper")
assertContains(achievement, "AchievementFrameComparison.StatContainer.ScrollBox",
    "Achievement comparison stat ScrollBox must be locked")

local auctionhouse = readFile("QUI_Skinning/skinning/frames/auctionhouse.lua")
local auctionHouseTableXml = readFile("tests/framexml/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseTableBuilder.xml")
assertContains(auctionHouseTableXml, "AuctionHouseTableHeaderStringTemplate\" mixin=\"AuctionHouseTableHeaderStringMixin\" inherits=\"ColumnDisplayButtonShortTemplate\"",
    "Auction House sort headers must still inherit the shared column-display button template")
local sharedPanelTemplates = readFile("tests/framexml/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml")
local columnDisplayButtonShort = blockBetween(sharedPanelTemplates, "<Button name=\"ColumnDisplayButtonShortTemplate\"",
    "	</Button>")
assertContains(columnDisplayButtonShort, "<NormalFont style=\"GameFontHighlightSmall\"/>",
    "Auction House sort headers inherit a stock button font object that can reappear on button state changes")
local auctionHeaderSkin = blockBetween(auctionhouse, "local function HookAuctionHeaderSkin()",
    "-- Skin browse panel")
assertContains(auctionHeaderSkin, "SkinBase.ApplyButtonFontObjects(self)",
    "Auction House sort headers must drive normal/highlight/disabled font objects")
-- LockFrameTextObjects(self, 2) was removed from HookAuctionHeaderSkin; ApplyButtonFontObjects
-- drives the font objects directly so hover/disable swaps carry the QUI face. Global override
-- owns static text durability; interactive reverts on bare-root button surfaces accepted.
local auctionsTabs = blockBetween(auctionhouse, "local function SkinAuctionHouseAuctionsTabs(auctionsFrame)",
    "local function LockDurationDropdownText(dropdown)")
assertContains(auctionsTabs, "SkinBase.SkinTabGroup(tabs, auctionsFrame, { font = true })",
    "Auction House inner Auctions/Bids tabs must be skinned as a durable tab group")
-- LockFrameTextObjects(tab, 2) was removed from SkinAuctionHouseAuctionsTabs; interactive
-- font-object reverts on bare-root tab surfaces are accepted under the global override.
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
local mail = readFile("QUI_Skinning/skinning/frames/mail.lua")
-- The interaction window skins (Bank/Merchant/Gossip/Quest/GuildBank/Trainer/
-- Macro) route through the canonical SkinBase.SkinWindow, which BUNDLES the
-- durable font lock (LockFrameTextObjects) — that bundling is pinned by
-- skinbase_coverage_verbs_test. So "they lock descendant text" is now verified
-- by "they go through SkinWindow".
local skinWindowCount = select(2, interaction:gsub("SkinBase%.SkinWindow%(", ""))
assert(skinWindowCount >= 5,
    "interaction window skins must route through SkinBase.SkinWindow (which locks descendant text)")
-- Mail drives interactive button font objects via ApplyButtonFontObjectsDeep (bespoke item-button
-- skin); LockFrameTextObjects was removed — global override owns static text durability.
local mailBtnFontCount = select(2, mail:gsub("SkinBase%.ApplyButtonFontObjectsDeep%(", ""))
assert(mailBtnFontCount >= 1, "Mail skin must drive descendant button font objects via ApplyButtonFontObjectsDeep")

local characterPane = readFile("QUI_Skinning/skinning/character_pane/character.lua")
local characterSettings = blockBetween(characterPane, "-- \"Settings\" label",
    "-- Close button (X)")
assertContains(characterSettings, "CJKFont(gearLabel, GeneralFontFace(), 12, \"\")",
    "Character settings gear label must route through CJK fallback")
assertContains(characterSettings, "CJKFont(title, GeneralFontFace(), 14, \"\")",
    "Character settings panel title must route through CJK fallback")

local inspectPane = readFile("QUI_Skinning/skinning/character_pane/inspect.lua")
local inspectSettings = blockBetween(inspectPane, "local gearLabel = gearBtn:CreateFontString",
    "-- Close button")
assertContains(inspectSettings, "CJKFont(gearLabel, GeneralFontFace(), 12, \"\")",
    "Inspect settings gear label must route through CJK fallback")
assertContains(inspectSettings, "CJKFont(title, GeneralFontFace(), 14, \"\")",
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
assertContains(readycheck, "CJKFont(text, GeneralFontFace(), 12, FONT_FLAGS)",
    "ready-check main text must route through CJK fallback using the QUI font face")

-- tooltips.lua: SkinFrameText recurse was removed; tooltip text now comes from the global
-- font-object override. GameTooltip font sizing is now handled via SetFontObject on
-- GameTooltipText/GameTooltipHeaderText (taint-safe); SkinFrameText is not called.
-- Verify the tooltip skin still handles GameTooltip (the main text target).
local tooltips = readFile("QUI_Skinning/skinning/system/tooltips.lua")
assertContains(tooltips, "pcall(GameTooltipText.SetFontObject, GameTooltipText, family)",
    "GameTooltip body text must size via the taint-safe SetFontObject path")

---------------------------------------------------------------------------
-- Shared pooled-row font helper: single source of truth for "lock a ScrollBox's
-- rows once". It MUST guard per row (qListRowFonted) so the expensive recursive
-- SkinFrameText pass runs once and the open-window hitch can't return; every
-- list panel routes through it instead of an inline per-acquire re-skin.
---------------------------------------------------------------------------
local uikit = readFile("core/uikit.lua")
assertContains(uikit, "function SkinBase.LockPooledRowText(row, depth)",
    "SkinBase must expose one shared guarded row-font lock helper")
local lockPooledRowText = blockBetween(uikit, "function SkinBase.LockPooledRowText(row, depth)",
    "\nend\n\nfunction SkinBase.HookScrollBoxRowFonts")
assertContains(lockPooledRowText, "SkinBase.GetFrameData(row, \"qListRowFonted\")",
    "LockPooledRowText must guard per row so the recursive font pass runs once")
assertContains(lockPooledRowText, "SkinBase.SetFrameData(row, \"qListRowFonted\", true)",
    "LockPooledRowText must mark the row fonted after the one-time pass")
local rowFontHelper = blockBetween(uikit, "function SkinBase.HookScrollBoxRowFonts(scrollBox, depth)",
    "\nend")
assertContains(rowFontHelper, "SkinBase.LockPooledRowText(row, depth or 3)",
    "HookScrollBoxRowFonts must route through the shared row-font helper")
assertContains(rowFontHelper, "{ sync = true }",
    "HookScrollBoxRowFonts must run pure font locks synchronously before first paint")

for _, frame in ipairs({
    { path = "QUI_Skinning/skinning/frames/journals.lua",       what = "Collections journal rows" },
    { path = "QUI_Skinning/skinning/frames/instanceframes.lua", what = "LFD/LFG list rows" },
    { path = "QUI_Skinning/skinning/frames/social.lua",         what = "friends/guild list rows" },
}) do
    local src = readFile(frame.path)
    assertContains(src, "SkinBase.HookScrollBoxRowFonts(",
        frame.what .. " must use the guarded row-font helper, not an unguarded per-acquire re-skin")
end

for _, frame in ipairs({
    { path = "QUI_Skinning/skinning/frames/auctionhouse.lua",    what = "Auction House rows" },
    { path = "QUI_Skinning/skinning/frames/craftingorders.lua",  what = "Crafting Orders rows" },
    { path = "QUI_Skinning/skinning/frames/professions.lua",     what = "Professions rows" },
    { path = "QUI_Skinning/skinning/frames/character.lua",       what = "Reputation/Currency rows" },
}) do
    local src = readFile(frame.path)
    assertContains(src, "SkinBase.LockPooledRowText(",
        frame.what .. " must reuse the shared guarded row-font helper")
end

-- Reputation/Currency pooled rows skin via HookScrollBoxAcquired (they also do
-- backdrop/icon work), so they route fonts through LockPooledRowText rather than
-- an inline per-acquire recursive SkinFrameText that would revert on rebind.
local characterRows = readFile("QUI_Skinning/skinning/frames/character.lua")
assertContains(characterRows, "SkinReputationEntry(row)\n                SkinBase.LockPooledRowText(row, 4)",
    "Reputation rows must lock pooled-row text after SkinReputationEntry")
assertContains(characterRows, "SkinCurrencyEntry(row)\n                SkinBase.LockPooledRowText(row, 4)",
    "Currency rows must lock pooled-row text after SkinCurrencyEntry")

local ahRow = blockBetween(readFile("QUI_Skinning/skinning/frames/auctionhouse.lua"),
    "local function skinRow(row)", "end\n\n-- TableBuilder")
assertContains(ahRow, "SkinBase.LockPooledRowText(row, 4)",
    "AH row text must route through the shared helper")
assertAbsent(ahRow, "SkinBase.SkinFrameText(row, { recurse = true })",
    "AH row text must not do a duplicate recursive pass before LockPooledRowText")

local coRow = blockBetween(readFile("QUI_Skinning/skinning/frames/craftingorders.lua"),
    "local function skinRow(row)", "end\n\n-- Order-table")
assertContains(coRow, "SkinBase.LockPooledRowText(row, 4)",
    "Crafting Orders row text must route through the shared helper")
assertAbsent(coRow, "SkinBase.SkinFrameText(row, { recurse = true })",
    "Crafting Orders row text must not do a duplicate recursive pass before LockPooledRowText")

local profRow = blockBetween(readFile("QUI_Skinning/skinning/frames/professions.lua"),
    "local function StyleScrollBoxRow(row)", "end\n\n---------------------------------------------------------------------------\n-- HIDE DECORATIONS")
assertContains(profRow, "SkinBase.LockPooledRowText(row, 4)",
    "Professions row text must route through the shared helper")
assertAbsent(profRow, "SkinBase.SkinFrameText(row, { recurse = true })",
    "Professions row text must not do a duplicate recursive pass before LockPooledRowText")

print("OK: skinning_font_reassertions_test")
