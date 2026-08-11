-- tests/unit/groupframes_aura_glue_test.lua
-- Run: lua tests/unit/groupframes_aura_glue_test.lua
local function read(p) local h = assert(io.open(p, "rb")); local s = h:read("*a"); h:close(); return s end
local src = read("QUI_GroupFrames/groupframes/groupframes_auras.lua")
local coreSrc = read("core/aura_surface.lua")
local fails = 0
local function check(n, ok) if ok then print("  ok  " .. n) else fails = fails + 1; print("FAIL  " .. n) end end

check("references the model module (now a core-backed shim)", src:find("QUI_GroupFramesAuraModel", 1, true) ~= nil)
check("calls ActiveElementsForSpec", src:find("ActiveElementsForSpec", 1, true) ~= nil)
check("calls PopulateElementMatches", src:find("PopulateElementMatches", 1, true) ~= nil)
check("defines BuildElementRenderList", src:find("BuildElementRenderList", 1, true) ~= nil)

-- Shared core glue consumption (Tasks 2/3) ----------------------------------
-- The container/tracked runtime now flows through the ONE shared copy of the
-- settings->container glue: ns.AuraGlue (profile + group descriptors +
-- combat-aware RunConfigPass) and ns.AuraSlots (AddAuraSlot tracked runtime).
check("consumes ns.AuraGlue", src:find("ns.AuraGlue", 1, true) ~= nil)
check("consumes ns.AuraSlots", src:find("ns.AuraSlots", 1, true) ~= nil)
check("configures containers via AuraGlue.RunConfigPass", src:find("AuraGlue.RunConfigPass", 1, true) ~= nil)
check("builds group descriptors via AuraGlue.ElementGroups (now in core/aura_surface.lua)",
    coreSrc:find("AuraGlue.ElementGroups", 1, true) ~= nil)
check("derives layout profiles via AuraGlue.ElementProfile", src:find("AuraGlue.ElementProfile", 1, true) ~= nil)
check("reconciles tracked slots via AuraSlots.Sync (now in core/aura_surface.lua)",
    coreSrc:find("AuraSlots.Sync", 1, true) ~= nil)
check("live group-aura settings feed one shared profile override",
    src:find("function QUI_GFA.ProfileOverrides", 1, true) ~= nil
    and src:find("showDispelBorder", 1, true) ~= nil
    and src:find("dispelColorCurve", 1, true) ~= nil
    and src:find("externalSkinning", 1, true) ~= nil
    and src:find("iconSkin", 1, true) ~= nil)
check("profile override reaches both strip groups and tracked slots",
    src:find("AuraGlue.ElementProfile(element, profileOverrides)", 1, true) ~= nil
    and src:find("profileOverrides = profileOverrides,", 1, true) ~= nil
    and coreSrc:find("AuraSlots.Sync(container, element, allowCreate, opts.profileOverrides)", 1, true) ~= nil)
check("parks unused slots via AuraSlots.Park", src:find("AuraSlots.Park", 1, true) ~= nil)
-- Seed bucket must come from the ALWAYS-LOADED model shim, never Options-side:
-- the seed latches elementsSeeded, so an Options-only bucket would latch an
-- EMPTY "*" bucket on Options-disabled installs (Task 4 review regression).
check("seeds via the shim-owned default bucket, no Options-side dependency",
    src:find("QUI_GroupFramesAuraDefaults", 1, true) == nil
    and src:find('AuraModel.DefaultStripBucket("party")', 1, true) ~= nil
    and src:find('AuraModel.DefaultStripBucket("raid")', 1, true) ~= nil
    and src:find("EnsureSeeded(auras, BucketFnFor(frame))", 1, true) ~= nil)

-- PTR4 UNIT_AURA fully-secret payload guards (Task 7) ------------------------
-- groupframes_auras.lua needs real WoW frames + the AuraEvents subscription and
-- cannot run headless, so pin the two secret gates by source position (same
-- idiom as groupframes_auras_container_test.lua).
do
    local ad_i  = src:find("local function ApplyAuraDelta", 1, true)
    local add_i = ad_i and src:find("if updateInfo.addedAuras then", ad_i, true)
    local sec_i = ad_i and src:find("AurasAreSecret()", ad_i, true)
    check("ApplyAuraDelta bails on AurasAreSecret before indexing the cache by instanceID",
        ad_i ~= nil and add_i ~= nil and sec_i ~= nil and sec_i < add_i)

    -- Fast stack/duration path: the == reseat (RefreshUpdatedIcons/Bars) must be
    -- skipped while auras are secret (updatedAuraInstanceIDs are secret then).
    local nUp_i  = src:find("local nUpdated = #updated", 1, true)
    local ri_i   = nUp_i and src:find("Render.RefreshUpdatedIcons", nUp_i, true)
    local fsec_i = nUp_i and src:find("AurasAreSecret()", nUp_i, true)
    check("fast stack/duration path guards the == reseat on AurasAreSecret",
        nUp_i ~= nil and ri_i ~= nil and fsec_i ~= nil and fsec_i < ri_i)
end

if fails > 0 then error(fails .. " failures") end
print("ALL PASS")
