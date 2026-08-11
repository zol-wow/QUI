-- tests/unit/readycheck_popup_texture_backdrop_test.lua
-- Run: lua tests/unit/readycheck_popup_texture_backdrop_test.lua
--
-- Regression: ReadyCheckFrame text must stay above the skinned background.
-- The ready-check popup can be level 0, so child-frame backdrops cannot be
-- reliably lowered below its XML font regions. Keep this skin on texture
-- regions owned by the popup frame and mark them so decoration hiding skips
-- the skin's own fill and border.

local path = "modules/skinning/notifications/readycheck.lua"
local file = assert(io.open(path, "rb"))
local source = file:read("*a")
file:close()

local function assertContains(needle, message)
    assert(source:find(needle, 1, true), message)
end

local function assertAbsent(needle, message)
    assert(not source:find(needle, 1, true), message)
end

assertContains('TEXTURE_BACKDROP_KEY = "readyCheckTextureBackdrop"',
    "ready-check skin should store its texture backdrop state")
assertContains('parent:CreateTexture(nil, "BACKGROUND", nil, -8)',
    "ready-check skin should draw background as a parent-owned texture")
assertContains('parent:CreateTexture(nil, "BORDER", nil, 7)',
    "ready-check skin should draw borders as parent-owned textures")
assertContains("SkinBase.SetFrameData(texture, OWNED_TEXTURE_KEY, true)",
    "ready-check owned textures must be marked")
assertContains("if not SkinBase.GetFrameData(region, OWNED_TEXTURE_KEY) then",
    "decoration hiding must skip ready-check owned textures")
assertContains('text:SetDrawLayer("OVERLAY", 7)',
    "button labels should be promoted above button skin textures")
assertContains("RegisterScaleRefresh(",
    "owned-texture border must re-lay out on scale refresh: a 1px edge size "
    .. "frozen at ADDON_LOADED goes sub-pixel (edges drop out) once the final "
    .. "UI scale lands")

assertAbsent("SkinBase.CreateBackdrop(",
    "ready-check skin must not use child-frame backdrops over popup text")
assertAbsent("SkinBase.GetBackdrop(",
    "ready-check skin must not refresh child-frame backdrops")
assertAbsent("GetFrameLevel",
    "ready-check skin must not read frame levels to place popup backgrounds")
assertAbsent("SetFrameLevel",
    "ready-check skin must not set protected frame levels for popup backgrounds")

print("OK: readycheck_popup_texture_backdrop_test")
