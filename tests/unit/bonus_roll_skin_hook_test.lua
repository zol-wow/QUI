-- tests/unit/bonus_roll_skin_hook_test.lua
-- Run: lua tests/unit/bonus_roll_skin_hook_test.lua
--
-- Regression guard for "bonus rolls aren't getting skinned".
--
-- BonusRollLootWonFrame / BonusRollMoneyWonFrame are standalone ContainedAlertFrames
-- that Blizzard sets up via the GLOBAL LootWonAlertFrame_SetUp / MoneyWonAlertFrame_SetUp
-- (GroupLootFrame.lua) and adds straight to AlertFrame -- they never flow through the
-- pooled Loot/MoneyWon alert systems whose setUpFunction QUI hooks. A one-shot init
-- skin therefore races frame creation and is wiped each time Blizzard re-runs SetUp on
-- show. The skinning must instead post-hook those two global setup funcs so the frames
-- get (re)skinned on every show. This test asserts that wiring exists in source.

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("QUI_Skinning/skinning/notifications/alerts.lua")

-- Must post-hook BOTH global setup functions.
assert(source:find('hooksecurefunc("LootWonAlertFrame_SetUp"', 1, true),
    "alerts.lua must hooksecurefunc the global LootWonAlertFrame_SetUp so bonus-roll loot frames skin on show")
assert(source:find('hooksecurefunc("MoneyWonAlertFrame_SetUp"', 1, true),
    "alerts.lua must hooksecurefunc the global MoneyWonAlertFrame_SetUp so bonus-roll money frames skin on show")

-- The hooks must route the bonus-roll frames through the canonical alert skinners.
local lootHook = source:match('hooksecurefunc%("LootWonAlertFrame_SetUp".-end%)')
assert(lootHook and lootHook:find("BonusRollLootWonFrame", 1, true)
    and lootHook:find("SkinLootWonAlert", 1, true),
    "the LootWonAlertFrame_SetUp hook must skin BonusRollLootWonFrame via SkinLootWonAlert")

local moneyHook = source:match('hooksecurefunc%("MoneyWonAlertFrame_SetUp".-end%)')
assert(moneyHook and moneyHook:find("BonusRollMoneyWonFrame", 1, true)
    and moneyHook:find("SkinMoneyWonAlert", 1, true),
    "the MoneyWonAlertFrame_SetUp hook must skin BonusRollMoneyWonFrame via SkinMoneyWonAlert")

-- The prompt window must be skinned by post-hooking the global StartBonusRoll.
assert(source:find('hooksecurefunc("BonusRollFrame_StartBonusRoll"', 1, true),
    "alerts.lua must hooksecurefunc BonusRollFrame_StartBonusRoll so the bonus-roll prompt window skins on show")
local promptHook = source:match('hooksecurefunc%("BonusRollFrame_StartBonusRoll".-end%)')
assert(promptHook and promptHook:find("SkinBonusRollPrompt", 1, true),
    "the BonusRollFrame_StartBonusRoll hook must skin the prompt via SkinBonusRollPrompt")

-- Guard against regressing to the old one-shot approach.
assert(not source:find("SkinBonusRollFrames", 1, true),
    "bonus-roll skinning must not rely on a one-shot SkinBonusRollFrames() init pass")

print("OK: bonus_roll_skin_hook_test")
