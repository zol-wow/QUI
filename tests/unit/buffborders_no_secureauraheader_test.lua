-- tests/unit/buffborders_no_secureauraheader_test.lua
-- PTR4 removed SecureAuraHeaderTemplate from Mainline. The buff right-click
-- cancel path is now SetCancelAuraButtons on engine-created AuraButtons.
local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return (data:gsub("\r\n", "\n"))
end
local src = readAll("QUI_ActionBars/actionbars/buffborders.lua")

assert(not src:find("SecureAuraHeaderTemplate", 1, true), "SecureAuraHeaderTemplate removed in PTR4")
assert(not src:find("buffCancelHeader", 1, true), "cancel-header machinery must be fully deleted")
assert(not src:find("initialConfigFunction", 1, true), "no secure-header initialConfigFunction remains")
assert(not src:find("RegisterStateDriver", 1, true), "cancel visibility driver deleted with the header")
assert(not src:find("AddAuraFilter", 1, true), "AddAuraFilter replaced by AuraGlue-configured groups")

-- E4/element cutover: the container is configured through the SHARED core glue
-- (AuraGlue.RunConfigPass wraps AuraSkin.Configure OOC / Restyle in combat), so
-- buffborders.lua no longer names AuraSkin.Configure or a local cancelButtons /
-- SORT_TRANSLATIONS table directly — filter, SORT and cancel are element-borne
-- and travel through AuraGlue.ElementGroups.
assert(src:find("G.RunConfigPass", 1, true) or src:find("AuraGlue.RunConfigPass", 1, true),
    "must configure containers via the shared AuraGlue.RunConfigPass")
assert(src:find("G.ElementGroups", 1, true) or src:find("AuraGlue.ElementGroups", 1, true),
    "group descriptors (filter/sort/cancel) must come from AuraGlue.ElementGroups")
assert(not src:find("SORT_TRANSLATIONS", 1, true),
    "sort is element-borne (element.sortRule) — no local SORT_TRANSLATIONS table remains")
-- The old per-zone group descriptor set `cancelButtons = isBuff and "RightButtonUp"`
-- inline; that idiom must be gone (cancel now travels through ElementGroups). The
-- bare word `cancelButtons` may still appear in the header comment describing the
-- engine mechanism, so pin the old ASSIGNMENT idiom, not the word.
assert(not src:find('cancelButtons = isBuff', 1, true),
    "engine click-cancel must not be a per-zone local cancelButtons string (it is element-borne via AuraGlue.ElementGroups)")

-- Cancel eligibility is delegated to AuraGlue.ElementGroups (which gates cancel
-- to HELPFUL strips on cancel-eligible hosts) and is PER-HOST: only the buff
-- mover is eligible — a HELPFUL strip in the DEBUFF store must not gain cancel
-- behavior its editor mount (cancelEligible=false) can't show or disable.
assert(src:find("G.ElementGroups(\"player\", element, profile, isBuff)", 1, true),
    "cancel eligibility must be the per-host isBuff flag passed to AuraGlue.ElementGroups")
assert(not src:find("BB_CANCEL_ELIGIBLE", 1, true),
    "the both-hosts-eligible constant is retired (debuff store must never cancel)")

-- BuildZoneGroups (and its buff/debuff sortReverse and/or pitfall) is gone —
-- sort/filter now live on the element and compile in core/aura_elements.lua.
assert(not src:find("BuildZoneGroups", 1, true),
    "the per-zone BuildZoneGroups helper must be deleted (element-borne now)")
print("buffborders_no_secureauraheader_test OK")
