local ns = dofile("tools/_addon_env.lua").LoadCore()
local W, E = ns.QUI_AuraWizard, ns.AuraElements
local failures=0; local function check(n,ok,d) if ok then print("  ok  "..n) else failures=failures+1; print("FAIL  "..n.." "..(d or "")) end end
do -- RoleDefaults
  local h = W.RoleDefaults("HEALER")
  check("healer party buffs mine", h.groupParty.buffs[1]=="mine")
  check("healer party debuffs dispellable", h.groupParty.debuffs[1]=="dispellable")
  check("healer player defensives", h.player.buffs[1]=="defensives")
  local t = W.RoleDefaults("TANK")
  check("tank target boss", t.target.debuffs[1]=="boss")
  local d = W.RoleDefaults("DAMAGER")
  check("dps target mine", d.target.debuffs[1]=="mine")
end
do -- SeedSurface produces an element that derives back to the intent
  local e = W.SeedSurface({}, "HARMFUL", "dispellable")
  check("seed harmful element", e.mode=="filterStrip" and e.auraType=="HARMFUL")
  check("seed derives dispellable", E.DeriveWhatToShow(e)=="dispellable", E.DeriveWhatToShow(e))
end
do -- PlayerSpecID: nil-safe outside the game client (no C_SpecializationInfo stub in harness)
  check("PlayerSpecID nil-guarded", W.PlayerSpecID() == nil)
end
do -- ActiveBucketKey (Finding 1): resolves to the spec bucket only when one exists
  local elements = { ["*"] = {} }
  check("no override -> '*'", W.ActiveBucketKey(elements, 261) == "*")
  check("nil specID -> '*'", W.ActiveBucketKey(elements, nil) == "*")
  elements[261] = {}
  check("override present -> spec key", W.ActiveBucketKey(elements, 261) == 261)
end
do -- SeedBucketForRole (Finding 2): retargets the debuff strip, defensives survives
  local debuffs = E.NewFilterStripElement("HARMFUL"); debuffs.id = "debuffs"
  local defensives = E.NewFilterStripElement("HELPFUL")
  defensives.id = "defensives"
  defensives.filterMode = "classify"
  defensives.classifications = { bigDefensive = true, externalDefensive = true }
  local bucket = { debuffs, defensives }

  local result = W.SeedBucketForRole(bucket, nil, { "dispellable" }, nil)

  check("retarget: element count unchanged", #result == 2, tostring(#result))
  check("retarget: debuff strip retargeted", E.DeriveWhatToShow(result[1]) == "dispellable", E.DeriveWhatToShow(result[1]))
  check("retarget: debuff strip enabled", result[1].enabled == true)
  check("retarget: defensives id survives", result[2].id == "defensives")
  check("retarget: defensives classification survives",
    result[2].classifications.bigDefensive == true and result[2].classifications.externalDefensive == true)
end
do -- SeedBucketForRole: buff intent skips the defensives strip, appends a new one
  local defensives = E.NewFilterStripElement("HELPFUL")
  defensives.id = "defensives"
  defensives.filterMode = "classify"
  defensives.classifications = { bigDefensive = true, externalDefensive = true }
  local bucket = { defensives }

  local result = W.SeedBucketForRole(bucket, { "mine" }, nil, nil)

  check("buff retarget: defensives untouched + new strip appended", #result == 2, tostring(#result))
  check("buff retarget: defensives id survives", result[1].id == "defensives")
  check("buff retarget: new strip derives mine", E.DeriveWhatToShow(result[2]) == "mine", E.DeriveWhatToShow(result[2]))
end
do -- SeedBucketForRole: empty/absent bucket seeds from defaultBucketFn, deep-copied
  local seedDebuff = E.NewFilterStripElement("HARMFUL"); seedDebuff.id = "debuffs"
  local seedBucket = { seedDebuff }
  local function defaultFn() return seedBucket end

  local result = W.SeedBucketForRole(nil, nil, { "boss" }, defaultFn)

  check("empty-seed: one element from default", #result == 1, tostring(#result))
  check("empty-seed: retargeted + enabled", E.DeriveWhatToShow(result[1]) == "boss" and result[1].enabled == true)
  check("empty-seed: deep-copied, not aliased", result[1] ~= seedDebuff)
  check("empty-seed: source table untouched by retarget", seedDebuff.gateBossAura ~= true)
end
do -- Finding 1 + 2 integration: spec-override bucket retargets independently of "*"
  local starDebuff = E.NewFilterStripElement("HARMFUL"); starDebuff.id = "debuffs"
  local overrideDebuff = E.NewFilterStripElement("HARMFUL"); overrideDebuff.id = "debuffs"
  local auras = { elements = { ["*"] = { starDebuff }, [105] = { overrideDebuff } } }

  local key = W.ActiveBucketKey(auras.elements, 105)
  check("finding1: resolves to spec bucket", key == 105)

  auras.elements[key] = W.SeedBucketForRole(auras.elements[key], nil, { "dispellable" }, nil)
  check("finding1: override bucket retargeted", E.DeriveWhatToShow(auras.elements[105][1]) == "dispellable")
  check("finding1: '*' bucket left untouched", E.DeriveWhatToShow(auras.elements["*"][1]) ~= "dispellable")
end
do -- WizardSteps
    check("healer+party = 5 steps", #W.WizardSteps("HEALER", { party = true, player = true }) == 5)
    check("tank+party = 4 steps (no placeHoTs)", #W.WizardSteps("TANK", { party = true }) == 4)
    local s = W.WizardSteps("HEALER", { player = true }) -- party unchecked
    check("no party = 3 steps", #s == 3, tostring(#s))
    check("no party: step2 surfaces", s[2] == "surfaces")
    check("no party: step3 review", s[3] == "review")
    local h = W.WizardSteps("HEALER", { party = true })
    check("healer step3 partyAuras", h[3] == "partyAuras")
    check("healer step4 placeHoTs", h[4] == "placeHoTs")
end

do -- FocusDefaults mirrors Target
    check("focus mirrors tank target (boss)", W.FocusDefaults("TANK").debuffs[1] == "boss")
    check("focus mirrors dps target (mine)", W.FocusDefaults("DAMAGER").debuffs[1] == "mine")
    check("focus healer target empty", #W.FocusDefaults("HEALER").debuffs == 0)
end

do -- CommitTrackedHoTs
    local bucket = {}
    W.CommitTrackedHoTs(bucket, {
        [774]  = { corner = "TOPLEFT",  displayType = "square" },
        [8936] = { corner = "TOPRIGHT", displayType = "icon" },
    })
    check("commit appends 2 tracked", #bucket == 2, tostring(#bucket))
    local e774
    for _, e in ipairs(bucket) do if e.spells and e.spells[1] == 774 then e774 = e end end
    check("774 mode tracked", e774 and e774.mode == "tracked")
    check("774 displayType square", e774 and e774.displayType == "square")
    check("774 anchor TOPLEFT", e774 and e774.anchor == "TOPLEFT")
    -- re-commit REPLACES: no duplicate, and the staged corner/display wins
    -- (the review step promises the wizard's selection replaces the layout —
    -- a silent keep-the-old-config no-op broke that promise).
    W.CommitTrackedHoTs(bucket, { [774] = { corner = "BOTTOMLEFT", displayType = "bar" } })
    local n774, new774 = 0, nil
    for _, e in ipairs(bucket) do if e.spells and e.spells[1] == 774 then n774 = n774 + 1; new774 = e end end
    check("774 not duplicated", n774 == 1, tostring(n774))
    check("774 re-commit replaces corner", new774 and new774.anchor == "BOTTOMLEFT", tostring(new774 and new774.anchor))
    check("774 re-commit replaces display", new774 and new774.displayType == "bar", tostring(new774 and new774.displayType))
    check("untouched sibling keeps config", (function()
        for _, e in ipairs(bucket) do
            if e.spells and e.spells[1] == 8936 then return e.anchor == "TOPRIGHT" and e.displayType == "icon" end
        end
    end)())
end

do -- CommitTrackedHoTs: staged ids inside multi-spell elements (2026-07
    -- re-review). A staged id must be removed from EVERY position of an
    -- existing element — not just spells[1] — and the element survives with
    -- its remaining spells; it is only deleted when nothing is left.
    local function count(bucket, sid)
        local n = 0
        for _, e in ipairs(bucket) do
            for _, s in ipairs(e.spells or {}) do
                if s == sid then n = n + 1 end
            end
        end
        return n
    end
    -- staged id at spells[2]: {774,8936} keeps 774, 8936 moves to the new
    -- element (the old code left it in place AND added a duplicate).
    local bucket = { { id = "m1", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 774, 8936 }, anchor = "TOPLEFT" } }
    W.CommitTrackedHoTs(bucket, { [8936] = { corner = "TOPRIGHT", displayType = "icon" } })
    check("multi: 8936 tracked exactly once", count(bucket, 8936) == 1, tostring(count(bucket, 8936)))
    check("multi: 774 survives in old element", count(bucket, 774) == 1, tostring(count(bucket, 774)))
    check("multi: old element kept (spells remain)", bucket[1].id == "m1" and #bucket == 2, tostring(#bucket))

    -- staged id at spells[1]: {774,8936} must NOT be deleted whole — the old
    -- code dropped 8936 entirely here.
    local bucket2 = { { id = "m2", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 774, 8936 }, anchor = "TOPLEFT" } }
    W.CommitTrackedHoTs(bucket2, { [774] = { corner = "BOTTOMLEFT", displayType = "bar" } })
    check("multi head: 8936 not lost", count(bucket2, 8936) == 1, tostring(count(bucket2, 8936)))
    check("multi head: 774 tracked exactly once", count(bucket2, 774) == 1, tostring(count(bucket2, 774)))

    -- every spell staged: the emptied element is removed.
    local bucket3 = { { id = "m3", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 774, 8936 }, anchor = "TOPLEFT" } }
    W.CommitTrackedHoTs(bucket3, {
        [774]  = { corner = "TOPLEFT", displayType = "icon" },
        [8936] = { corner = "TOPRIGHT", displayType = "icon" },
    })
    for _, e in ipairs(bucket3) do
        check("emptied element removed", e.id ~= "m3")
    end
    check("both spells re-committed", count(bucket3, 774) == 1 and count(bucket3, 8936) == 1)
end

do -- CommitTrackedHoTs: slot occupancy (2026-07 re-review round 2). An icon
    -- element renders one indicator PER SPELL (R.RenderIcon), so a surviving
    -- multi-spell element spans #spells slots — the new element must step
    -- past its LAST icon, not its first.
    local bucket = { { id = "m1", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 111, 222, 333 }, anchor = "TOPLEFT", iconSize = 16 } }
    W.CommitTrackedHoTs(bucket, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    local new222
    for _, e in ipairs(bucket) do
        if e.id ~= "m1" and e.spells and e.spells[1] == 222 then new222 = e end
    end
    check("span: survivor keeps {111,333}", #bucket[1].spells == 2)
    check("span: new element steps past BOTH surviving icons",
        new222 and new222.offsetX == 36, tostring(new222 and new222.offsetX))

    -- Hole reuse: three singles at slots 0/1/2; re-staging the middle one
    -- frees slot 1, and the recommit lands back in the hole instead of
    -- stacking past slot 2 onto the third icon.
    local b2 = {}
    W.CommitTrackedHoTs(b2, {
        [100] = { corner = "TOPLEFT", displayType = "icon" },
        [200] = { corner = "TOPLEFT", displayType = "icon" },
        [300] = { corner = "TOPLEFT", displayType = "icon" },
    })
    W.CommitTrackedHoTs(b2, { [200] = { corner = "TOPLEFT", displayType = "icon" } })
    local by = {}
    for _, e in ipairs(b2) do by[e.spells[1]] = e end
    check("hole: re-staged element reuses the freed slot",
        (by[200].offsetX or 0) == 18, tostring(by[200].offsetX))
    check("hole: third element untouched", by[300].offsetX == 36, tostring(by[300].offsetX))

    -- Squares span #spells too: EVERY tracked container element gets one
    -- slot per spell (core/aura_slots.lua Sync — displayType only affects
    -- the skin). 2026-07 round-3 review reproduced the square collision.
    local b3 = { { id = "sq", enabled = true, mode = "tracked",
        displayType = "square", spells = { 111, 222, 333 }, anchor = "TOPLEFT", iconSize = 16 } }
    W.CommitTrackedHoTs(b3, { [222] = { corner = "TOPLEFT", displayType = "square" } })
    local newSq
    for _, e in ipairs(b3) do
        if e.id ~= "sq" and e.spells and e.spells[1] == 222 then newSq = e end
    end
    check("square span: new square steps past both survivors",
        newSq and newSq.offsetX == 36, tostring(newSq and newSq.offsetX))

    -- Mixed sizes are PIXEL intervals, not ordinal slots: a retained 30px
    -- two-spell icon spans [0,64); a new 16px icon must start at 64, not at
    -- ordinal slot 2 (= 36px, inside the survivor's second icon).
    local b4 = { { id = "big", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 111, 333 }, anchor = "TOPLEFT", iconSize = 30 } }
    W.CommitTrackedHoTs(b4, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    local new16
    for _, e in ipairs(b4) do
        if e.id ~= "big" and e.spells and e.spells[1] == 222 then new16 = e end
    end
    check("mixed sizes: new icon clears the 30px survivor in pixels",
        new16 and new16.offsetX == 64, tostring(new16 and new16.offsetX))

    -- maxIcons caps the reserved span: 3 spells capped to 2 rendered icons
    -- occupy [0,36), so the next element lands at 36.
    local b5 = { { id = "cap", enabled = true, mode = "tracked", maxIcons = 2,
        displayType = "icon", spells = { 111, 333, 444 }, anchor = "TOPLEFT", iconSize = 16 } }
    W.CommitTrackedHoTs(b5, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    local capped
    for _, e in ipairs(b5) do
        if e.id ~= "cap" and e.spells and e.spells[1] == 222 then capped = e end
    end
    check("maxIcons: span capped to rendered icons",
        capped and capped.offsetX == 36, tostring(capped and capped.offsetX))

    -- Geometry mirrors the runtime (2026-07 round-4): per-element SPACING is
    -- part of the step (AnchorSlot: size + profile.spacing) — a retained
    -- 16px icon with spacing 10 occupies [0,26), so the new icon starts at
    -- 26 (the hardcoded +2 put it at 18, overlapping by 6px)...
    local b6 = { { id = "sp", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 111 }, anchor = "TOPLEFT",
        iconSize = 16, spacing = 10 } }
    W.CommitTrackedHoTs(b6, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    local spNew
    for _, e in ipairs(b6) do
        if e.id ~= "sp" and e.spells and e.spells[1] == 222 then spNew = e end
    end
    check("spacing: survivor's spacing widens its occupied cell",
        spNew and spNew.offsetX == 26, tostring(spNew and spNew.offsetX))

    -- ...an element with NO iconSize uses the ElementProfile fallback 22
    -- (not the NewTrackedElement seed 16)...
    local b7 = { { id = "prof", enabled = true, mode = "tracked",
        displayType = "icon", spells = { 111 }, anchor = "TOPLEFT" } }
    W.CommitTrackedHoTs(b7, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    local profNew
    for _, e in ipairs(b7) do
        if e.id ~= "prof" and e.spells and e.spells[1] == 222 then profNew = e end
    end
    check("profile default: sizeless icon occupies 22+2",
        profNew and profNew.offsetX == 24, tostring(profNew and profNew.offsetX))

    -- ...and a bar with no bar config renders at the runtime 12px fallback,
    -- not a 4px guess (the guess produced overlapping bars).
    local b8 = { { id = "bar0", enabled = true, mode = "tracked",
        displayType = "bar", spells = { 111 }, anchor = "BOTTOMLEFT" } }
    W.CommitTrackedHoTs(b8, { [222] = { corner = "BOTTOMLEFT", displayType = "bar" } })
    local barNew
    for _, e in ipairs(b8) do
        if e.id ~= "bar0" and e.spells and e.spells[1] == 222 then barNew = e end
    end
    check("bar fallback: config-less bar occupies 12+2",
        barNew and barNew.offsetY == 14, tostring(barNew and barNew.offsetY))

    -- Round-5 grow-direction probes: spans follow the element's OWN
    -- growDirection (AnchorSlot), not an |offset|+forward assumption.
    local function newFor(bucket)
        for _, e in ipairs(bucket) do
            if e.spells and e.spells[1] == 222 and e.id ~= "g" then return e end
        end
    end
    -- LEFT-growing survivor {111,333} at off 0 occupies [-18, 18) — the new
    -- icon fits at +18, NOT at 36 (the forward model double-reserved).
    local gL = { { id = "g", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333 }, anchor = "TOPLEFT", iconSize = 16, growDirection = "LEFT" } }
    W.CommitTrackedHoTs(gL, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    check("grow LEFT: span extends negative, new icon at +18",
        newFor(gL).offsetX == 18, tostring(newFor(gL).offsetX))

    -- UP-growing survivor occupies the Y axis; its cross-cell blocks the
    -- corner, so the new icon steps sideways past ONE cell only.
    local gU = { { id = "g", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333 }, anchor = "BOTTOMLEFT", iconSize = 16, growDirection = "UP" } }
    W.CommitTrackedHoTs(gU, { [222] = { corner = "BOTTOMLEFT", displayType = "icon" } })
    check("grow UP: vertical strip blocks one X cell, new icon at +18",
        newFor(gU).offsetX == 18, tostring(newFor(gU).offsetX))

    -- CENTER-growing 3-spell survivor anchors cells at -18/0/+18, each
    -- extending +18 → span [-18, 36); the new icon clears the +edge at 36.
    local gC = { { id = "g", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333, 444 }, anchor = "TOPLEFT", iconSize = 16, growDirection = "CENTER" } }
    W.CommitTrackedHoTs(gC, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    check("grow CENTER: symmetric span [-18,36), new icon at 36",
        newFor(gC).offsetX == 36, tostring(newFor(gC).offsetX))

    -- Horizontal-grow BAR stacks along X with length-sized cells; a new
    -- wizard bar at the same corner clears its thickness row vertically.
    local gB = { { id = "g", enabled = true, mode = "tracked", displayType = "bar",
        spells = { 111, 333 }, anchor = "BOTTOMLEFT", growDirection = "RIGHT" } }
    W.CommitTrackedHoTs(gB, { [222] = { corner = "BOTTOMLEFT", displayType = "bar" } })
    check("horizontal bar row: new bar steps above its thickness cell",
        newFor(gB).offsetY == 14, tostring(newFor(gB).offsetY))
end

do -- CommitTrackedHoTs: same-corner HoTs step sideways (matches step-4 preview)
    local bucket = {}
    W.CommitTrackedHoTs(bucket, {
        [774]   = { corner = "TOPLEFT",  displayType = "icon" },
        [8936]  = { corner = "TOPLEFT",  displayType = "icon" },
        [33763] = { corner = "TOPRIGHT", displayType = "icon" },
    })
    local by = {}
    for _, e in ipairs(bucket) do by[e.spells[1]] = e end
    check("first TOPLEFT unshifted", (by[774].offsetX or 0) == 0, tostring(by[774].offsetX))
    check("second TOPLEFT stepped +x (iconSize+2)", by[8936].offsetX == 18, tostring(by[8936].offsetX))
    check("other corner slot independent", (by[33763].offsetX or 0) == 0, tostring(by[33763].offsetX))

    local b2 = {}
    W.CommitTrackedHoTs(b2, {
        [100] = { corner = "BOTTOMRIGHT", displayType = "icon" },
        [200] = { corner = "BOTTOMRIGHT", displayType = "icon" },
    })
    local by2 = {}
    for _, e in ipairs(b2) do by2[e.spells[1]] = e end
    check("right-side corner steps -x (toward center)", by2[200].offsetX == -18, tostring(by2[200].offsetX))

    -- re-commit into a bucket with an existing tracked HoT on the corner:
    -- the counter seeds from the bucket, so the new one keeps stepping
    W.CommitTrackedHoTs(bucket, { [155777] = { corner = "TOPLEFT", displayType = "icon" } })
    local e3
    for _, e in ipairs(bucket) do if e.spells[1] == 155777 then e3 = e end end
    check("counter seeds from existing bucket", e3 and e3.offsetX == 36, tostring(e3 and e3.offsetX))
end

do -- CommitTrackedHoTs: same-corner BARS step vertically (they're wide — a
   -- sideways icon-width step would still overlap; matches step-4 preview)
    local bucket = {}
    W.CommitTrackedHoTs(bucket, {
        [774]  = { corner = "TOPLEFT", displayType = "bar" },
        [8936] = { corner = "TOPLEFT", displayType = "bar" },
        [200]  = { corner = "TOPLEFT", displayType = "icon" },
    })
    local by = {}
    for _, e in ipairs(bucket) do by[e.spells[1]] = e end
    -- Step derives from the element's own bar thickness (whatever
    -- NewTrackedElement seeds) + 2px gap. Staged ids commit in sorted order,
    -- so the icon (200) claims the corner cell first; round-5 cross-axis
    -- occupancy then pushes BOTH bars below the icon's row (previously the
    -- first bar sat directly on top of the icon) — the first bar lands one
    -- ICON row down, the second one bar-step below that.
    local step = ((by[8936].bar and by[8936].bar.thickness) or 4) + 2
    local iconRow = 16 + 2 -- staged icon: NewTrackedElement iconSize 16 + spacing 2
    check("icon claims the corner cell", (by[200].offsetX or 0) == 0 and (by[200].offsetY or 0) == 0)
    check("first TOPLEFT bar steps below the icon row", by[774].offsetY == -iconRow,
        tostring(by[774].offsetY) .. " vs -" .. tostring(iconRow))
    check("second TOPLEFT bar one bar-step further down", by[8936].offsetY == -(iconRow + step),
        tostring(by[8936].offsetY) .. " vs -" .. tostring(iconRow + step))
    check("bars don't shift sideways", (by[8936].offsetX or 0) == 0, tostring(by[8936].offsetX))

    local b2 = {}
    W.CommitTrackedHoTs(b2, {
        [100] = { corner = "BOTTOMLEFT", displayType = "bar" },
        [300] = { corner = "BOTTOMLEFT", displayType = "bar" },
    })
    local by2 = {}
    for _, e in ipairs(b2) do by2[e.spells[1]] = e end
    local step2 = ((by2[300].bar and by2[300].bar.thickness) or 4) + 2
    check("bottom corner bar steps up (+y)", by2[300].offsetY == step2,
        tostring(by2[300].offsetY) .. " vs " .. tostring(step2))
end

do -- SeedBucketForRole: multiple intents claim SEPARATE strips (review fix —
   -- the old loop retargeted the same first strip per key, last intent won)
  local bucket = {}
  W.SeedBucketForRole(bucket, nil, { "dispellable", "boss", "crowdControl" }, nil)
  local derived = {}
  for _, e in ipairs(bucket) do derived[#derived + 1] = E.DeriveWhatToShow(e) end
  check("3 debuff intents -> 3 strips", #bucket == 3, tostring(#bucket))
  check("intents preserved in order", table.concat(derived, ",") == "dispellable,boss,crowdControl", table.concat(derived, ","))
end
do -- SeedBucketForRole: "defensives" intent enables the shipped strip in place (no clone)
  local defensives = E.NewFilterStripElement("HELPFUL")
  defensives.id = "defensives"; defensives.enabled = false
  defensives.filterMode = "classify"
  defensives.classifications = { bigDefensive = true, externalDefensive = true }
  local bucket = { defensives }
  W.SeedBucketForRole(bucket, { "defensives" }, nil, nil)
  check("defensives intent: no clone appended", #bucket == 1, tostring(#bucket))
  check("defensives intent: shipped strip enabled in place", bucket[1].enabled == true and bucket[1].id == "defensives")
end
do -- SeedBucketForRole explicit: unchecked polarity strips get disabled
  local buff = E.NewFilterStripElement("HELPFUL"); buff.enabled = true
  local debuff = E.NewFilterStripElement("HARMFUL"); debuff.enabled = true
  local bucket = { buff, debuff }
  W.SeedBucketForRole(bucket, { "mine" }, {}, nil, true) -- buffs: mine; debuffs: none
  check("explicit: buff strip claimed + enabled", bucket[1].enabled == true and E.DeriveWhatToShow(bucket[1]) == "mine")
  check("explicit: unchecked debuff strip disabled", bucket[2].enabled == false)
end
do -- SeedBucketForRole non-explicit (role defaults): empty keys leave strips untouched
  local debuff = E.NewFilterStripElement("HARMFUL"); debuff.enabled = true
  local bucket = { debuff }
  W.SeedBucketForRole(bucket, nil, nil, nil)
  check("role-default: empty keys leave strip enabled", bucket[1].enabled == true)
end
do -- SurfaceIsCustomized: deep compare, volatile ids ignored
  local function defFn()
    local e = E.NewFilterStripElement("HARMFUL")
    e.iconSize = 20
    return { e }
  end
  local auras = { elementsSeeded = true, elements = { ["*"] = defFn() } }
  check("untouched surface not customized", W.SurfaceIsCustomized(auras, defFn, "*") == false)
  auras.elements["*"][1].whitelist = { [774] = true }
  check("whitelist edit detected", W.SurfaceIsCustomized(auras, defFn, "*") == true)
  auras.elements["*"][1].whitelist = {}
  auras.elements["*"][1].iconSize = 21
  check("geometry edit detected", W.SurfaceIsCustomized(auras, defFn, "*") == true)
end

do -- PARTY intent menus exist and use valid WhatToShow keys
    check("PARTY_BUFF_INTENTS is table", type(W.PARTY_BUFF_INTENTS) == "table" and #W.PARTY_BUFF_INTENTS >= 1)
    check("PARTY_DEBUFF_INTENTS is table", type(W.PARTY_DEBUFF_INTENTS) == "table" and #W.PARTY_DEBUFF_INTENTS >= 1)
    check("buff menu first key = mine", W.PARTY_BUFF_INTENTS[1].key == "mine")
    check("debuff menu has boss", (function()
        for _, e in ipairs(W.PARTY_DEBUFF_INTENTS) do if e.key == "boss" then return true end end
        return false
    end)())
end

do -- Round-6 wrapped-occupancy: retained elements block their FULL wrapped
   -- rectangle (widest row × row count), not just the first row/column.
    local function newFor(bucket)
        for _, e in ipairs(bucket) do
            if e.spells and e.spells[1] == 222 and e.id ~= "w" then return e end
        end
    end
    -- 4-spell icon element wrapped at 2/row on TOPLEFT: rows stack DOWN, so
    -- Y-occupancy is 2 cells = [-36, 0). A new BAR (stacking down from the
    -- TOP corner) must clear BOTH rows: offsetY -36, not -18 (inside row 2).
    local wA = { { id = "w", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333, 444, 555 }, anchor = "TOPLEFT", iconSize = 16,
        iconsPerRow = 2 } }
    W.CommitTrackedHoTs(wA, { [222] = { corner = "TOPLEFT", displayType = "bar" } })
    check("wrap: new bar clears BOTH wrapped rows",
        newFor(wA).offsetY == -36, tostring(newFor(wA).offsetY))
    -- Same element, new ICON: X-occupancy is the widest ROW (2 cells =
    -- [0, 36)), so the icon lands at 36 — the round-5 model already had the
    -- first row right; guard it stays capped at iconsPerRow, not #spells.
    local wB = { { id = "w", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333, 444, 555 }, anchor = "TOPLEFT", iconSize = 16,
        iconsPerRow = 2 } }
    W.CommitTrackedHoTs(wB, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    check("wrap: main axis stays capped at the widest row",
        newFor(wB).offsetX == 36, tostring(newFor(wB).offsetX))
    -- Vertical (DOWN) 4-spell element wrapped at 2/column on TOPLEFT: extra
    -- COLUMNS advance rightward, X-occupancy 2 cells = [0, 36); a new icon
    -- must clear both columns: offsetX 36, not 18 (inside column 2).
    local wC = { { id = "w", enabled = true, mode = "tracked", displayType = "icon",
        spells = { 111, 333, 444, 555 }, anchor = "TOPLEFT", iconSize = 16,
        iconsPerRow = 2, growDirection = "DOWN" } }
    W.CommitTrackedHoTs(wC, { [222] = { corner = "TOPLEFT", displayType = "icon" } })
    check("wrap: new icon clears BOTH wrapped columns of a vertical element",
        newFor(wC).offsetX == 36, tostring(newFor(wC).offsetX))
end

print("aura_wizard_test "..(failures==0 and "OK" or "FAILED")); os.exit(failures==0 and 0 or 1)
