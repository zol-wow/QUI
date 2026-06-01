-- tests/unit/pixel_border_callsite_test.lua
-- Run: lua tests/unit/pixel_border_callsite_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local function listLuaFiles(root)
    local files = {}
    local pipe = assert(io.popen("find " .. root .. " -type f -name '*.lua' | sort"))
    for path in pipe:lines() do
        files[#files + 1] = path
    end
    pipe:close()
    return files
end

local buffBorders = readFile("modules/actionbars/buffborders.lua")
local cdmBars = readFile("modules/cdm/cdm_bar_renderer.lua")
local partyKeystones = readFile("modules/dungeon/party_keystones.lua")

assert(buffBorders:find("local function GetBorderSizePx", 1, true),
    "buff border module must convert configured border size through the pixel helper")
assert(not buffBorders:find("SetHeight(borderSize)", 1, true),
    "buff border textures must not use raw configured border size for height")
assert(not buffBorders:find("SetWidth(borderSize)", 1, true),
    "buff border textures must not use raw configured border size for width")
assert(not buffBorders:find("iconSize %- borderSize %* 2"),
    "private aura icon dimensions must subtract frame-space pixel border size")

assert(cdmBars:find("local function GetBorderSizePx", 1, true),
    "CDM bars must convert configured border size through the pixel helper")
assert(not cdmBars:find("SetHeight(borderSize)", 1, true),
    "CDM bar border textures must not use raw configured border size for height")
assert(not cdmBars:find("SetWidth(borderSize)", 1, true),
    "CDM bar border textures must not use raw configured border size for width")
assert(not cdmBars:find("-borderSize, borderSize", 1, true),
    "CDM bar border frame offsets must not use raw configured border size")

assert(not partyKeystones:find("edgeSize = 1", 1, true),
    "party keystone backdrop must not initialize with a raw 1 UI-unit edge")

local rawBackdropFiles = {
    "QUI_Options/framework.lua",
    "modules/groupframes/groupframes_editmode.lua",
    "modules/groupframes/settings/group_frames_pinned_editor.lua",
    "modules/groupframes/settings/group_frames_aura_indicators_editor.lua",
    "core/diagnostics_console.lua",
    "modules/utility/settings/keybinds_content.lua",
    "modules/chat/settings/chat_frame1_provider.lua",
    "modules/trackers/preytracker.lua",
    "modules/layout/layoutmode_settings.lua",
    "modules/cdm/settings/composer.lua",
    "modules/qol/consumablecheck.lua",
    "modules/layout/layoutmode_composer.lua",
}

for _, path in ipairs(rawBackdropFiles) do
    local src = readFile(path)
    assert(not src:find("edgeSize%s*=%s*1[%s,}]"),
        path .. " must not use raw 1 UI-unit backdrop edges")
end

local characterBorderFiles = {
    "modules/skinning/frames/character.lua",
    "modules/skinning/character_pane/character.lua",
    "modules/skinning/character_pane/inspect.lua",
}

for _, path in ipairs(characterBorderFiles) do
    local src = readFile(path)
    assert(src:find("RegisterScaleRefresh", 1, true)
        or src:find("ApplyChromeBackdrop", 1, true)
        or src:find("SetExpandedPixelPoints", 1, true),
        path .. " must refresh pixel backdrops after scale changes")
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*%-1,%s*1%)"),
        path .. " must not expand border frames with raw -1/1 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*1,%s*%-1%)"),
        path .. " must not expand border frames with raw 1/-1 UI-unit offsets")
end

local rawBorderOffsetFiles = {
    "modules/qol/actiontracker.lua",
    "modules/skinning/gameplay/keystone.lua",
    "modules/skinning/notifications/loot.lua",
    "modules/skinning/frames/overrideactionbar.lua",
    "modules/skinning/frames/instanceframes.lua",
}

for _, path in ipairs(rawBorderOffsetFiles) do
    local src = readFile(path)
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*%-1,%s*1%)"),
        path .. " must not expand border frames with raw -1/1 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*1,%s*%-1%)"),
        path .. " must not expand border frames with raw 1/-1 UI-unit offsets")
end

local rawTwoPixelBorderOffsetFiles = {
    "modules/skinning/gameplay/powerbaralt.lua",
    "modules/skinning/frames/statustracking.lua",
    "modules/skinning/notifications/alerts.lua",
}

for _, path in ipairs(rawTwoPixelBorderOffsetFiles) do
    local src = readFile(path)
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*%-2,%s*2%)"),
        path .. " must not expand border frames with raw -2/2 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*2,%s*%-2%)"),
        path .. " must not expand border frames with raw 2/-2 UI-unit offsets")
end

local layoutMode = readFile("modules/layout/layoutmode.lua")
assert(not layoutMode:find("SetHeight%(HANDLE_BORDER_SIZE%)"),
    "layout mode handle borders must convert handle border size through the pixel helper")
assert(not layoutMode:find("SetWidth%(HANDLE_BORDER_SIZE%)"),
    "layout mode handle borders must convert handle border size through the pixel helper")

local layoutModeSettings = readFile("modules/layout/layoutmode_settings.lua")
assert(not layoutModeSettings:find("SetHeight%(BORDER_SIZE%)"),
    "layout mode settings borders must convert panel border size through the pixel helper")
assert(not layoutModeSettings:find("SetWidth%(BORDER_SIZE%)"),
    "layout mode settings borders must convert panel border size through the pixel helper")

local layoutModeUi = readFile("modules/layout/layoutmode_ui.lua")
assert(not layoutModeUi:find("line:SetHeight%(1%)"),
    "layout mode UI line textures must convert one-pixel heights through the pixel helper")
assert(not layoutModeUi:find("line:SetWidth%(1%)"),
    "layout mode UI line textures must convert one-pixel widths through the pixel helper")
assert(not layoutModeUi:find("guide:SetHeight%(1%)"),
    "layout mode UI snap guides must convert one-pixel heights through the pixel helper")
assert(not layoutModeUi:find("guide:SetWidth%(1%)"),
    "layout mode UI snap guides must convert one-pixel widths through the pixel helper")

-- The skinning engine was relocated into core/uikit.lua (loaded first, exposed as
-- both ns.UIKit and ns.SkinBase). The scale-refreshing pixel backdrop helper now
-- lives there; modules/skinning/base.lua is a thin stub.
local skinBase = readFile("core/uikit.lua")
assert(skinBase:find("function SkinBase.ApplyPixelBackdrop", 1, true),
    "skinning base must expose a scale-refreshing pixel backdrop helper")
assert(skinBase:find("RegisterScaleRefresh", 1, true),
    "skinning pixel backdrops must be registered for scale refresh")

for _, path in ipairs(listLuaFiles("modules/skinning")) do
    local src = readFile(path)
    assert(not src:find("edgeSize%s*=%s*1[%s,}]"),
        path .. " must not use raw 1 UI-unit backdrop edges")
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*1,%s*%-1%)"),
        path .. " must not inset skinning regions with raw 1/-1 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*%-1,%s*1%)"),
        path .. " must not inset skinning regions with raw -1/1 UI-unit offsets")
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*2,%s*%-2%)"),
        path .. " must not inset skinning regions with raw 2/-2 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*%-2,%s*2%)"),
        path .. " must not inset skinning regions with raw -2/2 UI-unit offsets")
    assert(not src:find("SetPoint%(\"TOPLEFT\"[^\n]*3,%s*%-3%)"),
        path .. " must not inset tab backdrops with raw 3/-3 UI-unit offsets")
    assert(not src:find("SetPoint%(\"BOTTOMRIGHT\"[^\n]*%-3,%s*0%)"),
        path .. " must not inset tab backdrops with raw -3/0 UI-unit offsets")
    assert(not src:find("line:SetHeight%(1%)"),
        path .. " must not create one-pixel skinning lines with raw 1 UI-unit height")

    if path ~= "modules/skinning/base.lua" then
        local pos = 1
        while true do
            local startPos = src:find(":SetBackdrop%(%s*%{", pos)
            if not startPos then break end
            local nextSetBackdrop = src:find(":SetBackdrop%(%s*%{", startPos + 1) or (#src + 1)
            local chunk = src:sub(startPos, nextSetBackdrop - 1)
            local isDefaultDialogBackdrop = chunk:find("Interface\\\\DialogFrame\\\\UI%-DialogBox%-Border")
            assert(isDefaultDialogBackdrop,
                path .. " must route pixel-sized direct backdrops through SkinBase.ApplyPixelBackdrop")
            pos = startPos + 1
        end
    end
end

print("OK: pixel_border_callsite_test")
