-- tests/unit/skinning_addon_loaded_gate_test.lua
-- Run: lua tests/unit/skinning_addon_loaded_gate_test.lua
--
-- C_AddOns.IsAddOnLoaded returns loadedOrLoading first and fully-loaded second.
-- Skin catch-up gates must use the fully-loaded result so they do not run while
-- Blizzard's LOD frame globals are still being created.

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

local apiDocs = readFile("tests/framexml/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua")
assertContains(apiDocs, "{ Name = \"loadedOrLoading\", Type = \"bool\", Nilable = false }",
    "local API docs must expose IsAddOnLoaded's loading-state return")
assertContains(apiDocs, "{ Name = \"loaded\", Type = \"bool\", Nilable = false }",
    "local API docs must expose IsAddOnLoaded's fully-loaded return")

local uikit = readFile("core/uikit.lua")
assertContains(uikit, "function SkinBase.IsAddOnFullyLoaded(addonName)",
    "SkinBase must expose a shared fully-loaded addon gate")
assertAbsent(uikit, "if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName) then",
    "SkinBase.OnAddOnLoaded must not treat loadedOrLoading as loaded")

for _, path in ipairs({
    "QUI_Skinning/skinning/character_pane/inspect.lua",
    "QUI_Skinning/skinning/frames/statustracking.lua",
}) do
    local source = readFile(path)
    assertAbsent(source, "C_AddOns.IsAddOnLoaded(",
        path .. " must use SkinBase.IsAddOnFullyLoaded instead of the loading-state return")
    assertContains(source, "IsAddOnFullyLoaded(",
        path .. " must retain an immediate catch-up path for already-loaded Blizzard addons")
end

-- keystone routes its single-addon gate through the shared OnAddOnLoaded helper,
-- which uses IsAddOnFullyLoaded internally for the already-loaded catch-up.
local keystone = readFile("QUI_Skinning/skinning/gameplay/keystone.lua")
assertAbsent(keystone, "C_AddOns.IsAddOnLoaded(",
    "keystone.lua must not consume the loading-state return directly")
assertContains(keystone, "SkinBase.OnAddOnLoaded(\"Blizzard_ChallengesUI\"",
    "keystone.lua must gate skinning through the shared OnAddOnLoaded helper (immediate catch-up if already loaded)")

for _, entry in ipairs({
    {
        path = "QUI_Skinning/skinning/frames/auctionhouse.lua",
        addon = "Blizzard_AuctionHouseUI",
        skin = "SkinAuctionHouse",
    },
    {
        path = "QUI_Skinning/skinning/frames/professions.lua",
        addon = "Blizzard_Professions",
        skin = "SkinProfessions",
    },
    {
        path = "QUI_Skinning/skinning/frames/craftingorders.lua",
        addon = "Blizzard_ProfessionsCustomerOrders",
        skin = "SkinCraftingOrders",
    },
}) do
    local source = readFile(entry.path)
    assertAbsent(source, "C_Timer.After(0.1, " .. entry.skin .. ")",
        entry.path .. " must not use fixed 0.1s load catch-up timers")
    assertContains(source,
        "SkinBase.OnAddOnLoaded(\"" .. entry.addon .. "\", " .. entry.skin .. ", 0)",
        entry.path .. " must use the shared fully-loaded addon hook")
end

print("OK: skinning_addon_loaded_gate_test")
