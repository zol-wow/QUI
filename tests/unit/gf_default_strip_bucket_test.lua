-- tests/unit/gf_default_strip_bucket_test.lua
-- Run: lua5.1 tests/unit/gf_default_strip_bucket_test.lua
--
-- The GF shipped strip bucket is surface-aware since the defensives fold-in:
-- party seeds the "defensives" strip enabled, raid seeds it disabled (parity
-- with the retired healer.defensiveIndicator defaults: party ON, raid OFF).
-- The strip is classify-mode bigDefensive+externalDefensive with a green
-- borderColor (the old indicator's visual identity).

local envmod = dofile("tools/_addon_env.lua")
local ns = envmod.LoadCore()
envmod.LoadAddonFile("QUI_GroupFrames/groupframes/groupframes_aura_model.lua", "QUI_GroupFrames", ns)
local Model = ns.QUI_GroupFramesAuraModel

local failures = 0
local function check(name, ok, detail)
    if ok then print(("  ok  %s"):format(name))
    else failures = failures + 1; print(("FAIL  %s  %s"):format(name, detail or "")) end
end

for _, frameType in ipairs({ "party", "raid" }) do
    local bucket = Model.DefaultStripBucket(frameType)
    check(frameType .. ": bucket has 3 elements", #bucket == 3, tostring(#bucket))
    check(frameType .. ": strip/element ids stable", bucket[1].id == "debuffs"
        and bucket[2].id == "buffs" and bucket[3].id == "defensives",
        table.concat({ tostring(bucket[1].id), tostring(bucket[2].id),
            tostring(bucket[3].id) }, ","))
    local d = bucket[3]
    check(frameType .. ": defensives enabled parity",
        d.enabled == (frameType == "party"), tostring(d.enabled))
    check(frameType .. ": classify mode", d.mode == "filterStrip"
        and d.auraType == "HELPFUL" and d.filterMode == "classify", d.filterMode)
    check(frameType .. ": classifications", d.classifications
        and d.classifications.bigDefensive == true
        and d.classifications.externalDefensive == true, "wrong classifications")
    check(frameType .. ": green borderColor", type(d.borderColor) == "table"
        and d.borderColor[1] == 0 and d.borderColor[2] == 0.8
        and d.borderColor[3] == 0 and d.borderColor[4] == 1, "not green")
    check(frameType .. ": geometry matches retired indicator defaults",
        d.anchor == "BOTTOMRIGHT" and d.growDirection == "LEFT"
        and d.iconSize == 15 and d.maxIcons == 3 and d.spacing == 0
        and d.offsetX == 0 and d.offsetY == 4 and d.reverseSwipe == true,
        "geometry drift")
    check(frameType .. ": no rightClickCancel", d.rightClickCancel == false,
        tostring(d.rightClickCancel))
    for i = 1, 3 do
        check(frameType .. ": strip " .. i .. " has no dedupeDefensives",
            bucket[i].dedupeDefensives == nil, tostring(bucket[i].dedupeDefensives))
    end
end

-- No-arg call must not error (legacy callers during rollout); defensives
-- defaults DISABLED when the surface is unknown (conservative).
local anon = Model.DefaultStripBucket()
check("nil frameType: defensives disabled", anon[3].enabled == false, tostring(anon[3].enabled))
check("nil frameType: bucket still 3 elements", #anon == 3, tostring(#anon))

-- Shim: string second arg seeds via the surface-aware bucket.
local auras = {}
Model.EnsureSeeded(auras, "party")
check("EnsureSeeded('party') seeds 3 elements", #auras.elements["*"] == 3,
    tostring(auras.elements and #auras.elements["*"]))
check("EnsureSeeded('party') defensives enabled",
    auras.elements["*"][3].enabled == true, "disabled")

if failures > 0 then os.exit(1) end
print("gf_default_strip_bucket_test: all checks passed")
