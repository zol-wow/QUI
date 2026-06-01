-- tests/unit/actionbars_extra_button_anchor_sync_test.lua
-- Run: lua tests/unit/actionbars_extra_button_anchor_sync_test.lua

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local source = readFile("modules/actionbars/actionbars_extra_buttons.lua")

local function blockBetween(startText, endText)
    local startPos = assert(source:find(startText, 1, true), "missing block start: " .. startText)
    local endPos = assert(source:find(endText, startPos, true), "missing block end: " .. endText)
    return source:sub(startPos, endPos - 1)
end

assert(
    source:find("function SaveExtraButtonHolderPosition", 1, true),
    "extra/zone mover drags must use a shared persistence helper")

assert(
    source:find("profile.frameAnchoring", 1, true)
        and source:find("fa[buttonType]", 1, true),
    "extra/zone mover persistence must update frameAnchoring for the same key")

local dragStopBlock = blockBetween('mover:SetScript("OnDragStop"', "    return holder, mover")
assert(
    dragStopBlock:find("SaveExtraButtonHolderPosition", 1, true),
    "extra/zone mover drag stop must sync actionBars position and frameAnchoring")

local nudgeBlock = blockBetween('btn:SetScript("OnClick"', "    return btn")
assert(
    nudgeBlock:find("SaveExtraButtonHolderPosition", 1, true),
    "extra/zone mover nudges must sync actionBars position and frameAnchoring")

local reanchorBlock = blockBetween("function QueueExtraButtonReanchor", "function HookExtraButtonPositioning")
assert(
    reanchorBlock:find("ApplyExtraButtonSettings%(buttonType%)")
        and reanchorBlock:find("ApplyExtraButtonFrameAnchor%(buttonType%)"),
    "extra/zone reanchor refresh must reapply the saved frame anchor after updating holder size")

local holderSizeBlock = blockBetween("function GetExtraButtonHolderSize", "pendingExtraButtonReanchor")
assert(
    holderSizeBlock:find("settings.hideArtwork", 1, true)
        and holderSizeBlock:find("GetExtraButtonVisualFrame", 1, true)
        and holderSizeBlock:find("holder:SetSize(holderWidth, holderHeight)", 1, true),
    "extra/zone holder sizing must use the visible button footprint when artwork is hidden before anchors reapply")

local hookBlock = blockBetween("function HookExtraButtonPositioning", "function ShowExtraButtonMovers")
assert(
    hookBlock:find("ExtraAbilityContainer", 1, true)
        and hookBlock:find('QueueExtraButtonReanchor("extraActionButton")', 1, true)
        and hookBlock:find('QueueExtraButtonReanchor("zoneAbility")', 1, true),
    "extra/zone reanchor hooks must observe Blizzard's shared ExtraAbilityContainer")

print("OK: actionbars_extra_button_anchor_sync_test")
