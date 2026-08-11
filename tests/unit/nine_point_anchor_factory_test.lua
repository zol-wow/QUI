-- tests/unit/nine_point_anchor_factory_test.lua
-- Run: lua tests/unit/nine_point_anchor_factory_test.lua
--
-- The nine-point anchor dropdown list was copy-pasted across 7 settings
-- files (identical values AND label keys — verified before consolidation).
-- One factory now owns it: ns.QUI_SettingsLayoutShared.BuildNinePointAnchor-
-- Options() in core/settings_layout_shared.lua (root-loaded before every
-- consumer; returns a FRESH table per call so dropdown consumers can't
-- alias each other's options). Deliberately different lists stay put:
-- containers_page 5-point icon anchors, minimap 4-corner + grow-direction.

local CONSUMERS = {
    "QUI_Options/shared.lua",
    "core/settings/provider_panels.lua",
    "QUI_Options/aura_elements_editor.lua",
    "QUI_CDM/cdm/settings/containers_page.lua",
    "modules/minimap/settings/minimap_providers.lua",
    "modules/ui/settings/settings_layout_shared.lua",
    "QUI_GroupFrames/groupframes/settings/group_frames_schema.lua",
}

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local text = fh:read("*a")
    fh:close()
    return text
end

local host = readFile("core/settings_layout_shared.lua")
assert(host:find("function Shared.BuildNinePointAnchorOptions()", 1, true),
    "canonical nine-point factory must live in core/settings_layout_shared.lua")

-- the TOPLEFT->TOP adjacency only occurs in the full nine-point list (the
-- deliberate 5-point/4-corner/grow lists order differently)
local FINGERPRINT_A = '"Top Left"%]%s*},%s*{%s*value = "TOP"'

for _, path in ipairs(CONSUMERS) do
    local src = readFile(path)
    assert(src:find("BuildNinePointAnchorOptions()", 1, true),
        path .. " must build its nine-point list via the factory")
    assert(not src:find(FINGERPRINT_A),
        path .. " must not carry an inline nine-point copy")
end

print("PASS nine_point_anchor_factory_test")
