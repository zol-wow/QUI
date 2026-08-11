local ns = dofile("tools/_addon_env.lua").LoadCore(); local E = ns.AuraElements
local failures=0; local function check(n,ok,d) if ok then print("  ok  "..n) else failures=failures+1; print("FAIL  "..n.." "..(d or "")) end end

-- ── ElementAppliesToRole ────────────────────────────────────────────────────
do
  check("nil gate = applies", E.ElementAppliesToRole({}, "TANK", false)==true)
  check("all = applies", E.ElementAppliesToRole({applyToRoles="all"}, "HEALER", false)==true)
  check("tank matches TANK", E.ElementAppliesToRole({applyToRoles="tank"}, "TANK", false)==true)
  check("tank rejects HEALER", E.ElementAppliesToRole({applyToRoles="tank"}, "HEALER", false)==false)
  check("healer matches HEALER", E.ElementAppliesToRole({applyToRoles="healer"}, "HEALER", false)==true)
  check("dps matches DAMAGER", E.ElementAppliesToRole({applyToRoles="dps"}, "DAMAGER", false)==true)
  check("me needs isSelf", E.ElementAppliesToRole({applyToRoles="me"}, "TANK", true)==true)
  check("me rejects non-self", E.ElementAppliesToRole({applyToRoles="me"}, "TANK", false)==false)
  check("role gate w/ nil frameRole rejects", E.ElementAppliesToRole({applyToRoles="tank"}, nil, false)==false)
  check("unknown token fails open", E.ElementAppliesToRole({applyToRoles="wat"}, nil, false)==true)
end

-- ── MaxBucketElementCount (union pre-stage sizing) ──────────────────────────
do
  -- "e3470"/"i2549" are legacy context buckets (the removed Encounters
  -- cascade's key shapes) that can still sit in old profiles: the resolver
  -- can never select them, so union sizing must SKIP them — counting them
  -- would pre-create permanently-unreachable containers per frame.
  local a = { elements = {
    ["*"]     = { {id=1}, {id=2} },
    [105]     = { {id=1}, {id=2}, {id=3} },
    ["e3470"] = { {id=1}, {id=2}, {id=3}, {id=4} },
    ["i2549"] = { {id=1} },
  } }
  check("MaxBucketElementCount reachable union", E.MaxBucketElementCount(a)==3)
  check("MaxBucketElementCount skips legacy context buckets",
    E.MaxBucketElementCount({elements={["*"]={{id=1}}, ["e9"]={{id=1},{id=2}}}})==1)
  check("MaxBucketElementCount empty store", E.MaxBucketElementCount({elements={}})==0)
  check("MaxBucketElementCount nil", E.MaxBucketElementCount(nil)==0)
end

-- ── New element defaults (applyToRoles + border) ────────────────────────────
do
  local t = E.NewTrackedElement({12345})
  check("tracked seeds applyToRoles all", t.applyToRoles=="all")
  check("tracked seeds border table", type(t.border)=="table" and t.border.thickness==2)
  local s = E.NewFilterStripElement("HELPFUL")
  check("strip seeds applyToRoles all", s.applyToRoles=="all")
  local m = E.NewMissingRaidBuffElement()
  check("mrb seeds applyToRoles all", m.applyToRoles=="all")
  -- border is a valid displayType
  check("border validates", E.Validate({mode="tracked", displayType="border", spells={1}})==true)
end

-- ── NormalizeElement backfills new fields on legacy elements ────────────────
do
  local legacy = { mode="tracked", displayType="icon", spells={1}, auraType="HELPFUL" }
  E.NormalizeElement(legacy)
  check("normalize backfills applyToRoles", legacy.applyToRoles=="all")
  check("normalize backfills border", type(legacy.border)=="table")
  local legacyStrip = { mode="filterStrip", auraType="HARMFUL" }
  E.NormalizeElement(legacyStrip)
  check("normalize strip applyToRoles", legacyStrip.applyToRoles=="all")
end

print("aura_role_border_test "..(failures==0 and "OK" or "FAILED")); os.exit(failures==0 and 0 or 1)
