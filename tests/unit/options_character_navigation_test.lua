-- tests/unit/options_character_navigation_test.lua
-- Run: lua tests/unit/options_character_navigation_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function loadTile(path)
    local captured = {}
    local ns = {
        QUI_Options = {
            RegisterFeatureTile = function(_, spec)
                captured[#captured + 1] = spec
            end,
        },
    }
    (dofile("tests/helpers/locale.lua"))(ns)
    local chunk = assert(loadfile(path))
    chunk("QUI", ns)

    local moduleName = path:match("([^/\\]+)%.lua$")
    local module = ns["QUI_" .. moduleName:gsub("^%l", string.upper) .. "Tile"]
    if moduleName == "gameplay" then
        module = ns.QUI_GameplayTile
    elseif moduleName == "appearance" then
        module = ns.QUI_AppearanceTile
    end
    assert(module and type(module.Register) == "function", path .. " should expose a Register function")
    module.Register({})
    assert(captured[1], path .. " should register a tile")
    return captured[1]
end

local function findSubPage(tile, id)
    for index, subPage in ipairs(tile.subPages or {}) do
        if subPage.id == id then
            return subPage, index
        end
    end
end

local gameplay = loadTile("QUI_Options/tiles/gameplay.lua")
local appearance = loadTile("QUI_Options/tiles/appearance.lua")

assert(not findSubPage(gameplay, "character"), "Character should not remain under Gameplay")

local character, characterIndex = findSubPage(appearance, "character")
local skinning, skinningIndex = findSubPage(appearance, "skinning")
assert(character, "Character should be a sub-page under Appearance")
assert(skinning, "Skinning should remain a sub-page under Appearance")
assert(character.featureId == "characterPane", "Character should still render the characterPane feature")
assert(characterIndex + 1 == skinningIndex, "Character should appear immediately to the left of Skinning")

local characterContent = readFile("QUI_Skinning/skinning/character_pane/settings/character_pane_content.lua")
assert(
    characterContent:find('category = "appearance"', 1, true),
    "characterPane feature category should be appearance")
assert(
    characterContent:find('nav = { tileId = "appearance", subPageIndex = 3 }', 1, true),
    "characterPane feature nav should route to Appearance > Character")
assert(
    not characterContent:find('category = "gameplay"', 1, true),
    "characterPane feature should no longer be categorized as gameplay")

local ns = {}
assert(loadfile("QUI_OptionsSearch/search_cache.lua"))("QUI", ns)
local cache = assert(ns.QUI_SearchCache, "search cache should load")

local foundCharacterEntry = false
for _, list in ipairs({ cache.navigation or {}, cache.settings or {} }) do
    for _, entry in ipairs(list) do
        if entry.featureId == "characterPane" then
            foundCharacterEntry = true
            assert(entry.tileId == "appearance", "characterPane cache entry should route to Appearance")
            assert(entry.tabName == "Appearance", "characterPane cache entry should label the Appearance tab")
            assert(entry.subPageIndex == 3, "characterPane cache entry should use the Character sub-page index")
            assert(entry.subTabName == "Character", "characterPane cache entry should label the Character sub-page")
            assert(entry.category == nil or entry.category == "appearance", "characterPane cache entry should not be gameplay")
        end
    end
end

assert(foundCharacterEntry, "search cache should include characterPane entries")

print("OK: options_character_navigation_test")
