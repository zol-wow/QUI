local ns = dofile("tools/_addon_env.lua").LoadCore(); local E = ns.AuraElements
local failures=0; local function check(n,ok,d) if ok then print("  ok  "..n) else failures=failures+1; print("FAIL  "..n.." "..(d or "")) end end
local function auras() return { elements = {
    ["*"]   = { { id="a", enabled=true, mode="filterStrip" } },
    [268]   = { { id="b", enabled=true, mode="filterStrip" } },
    -- Legacy context bucket (the removed Encounters cascade's "i"..mapID
    -- shape): must be ignored by the resolver, never selected.
    ["i2549"] = { { id="c", enabled=true, mode="filterStrip" } },
} } end
do
  check("spec bucket wins", E.ActiveElementsForSpec(auras(), 268)[1].id=="b")
  check("nil spec = star", E.ActiveElementsForSpec(auras(), nil)[1].id=="a")
  check("legacy context bucket ignored", E.ActiveElementsForSpec(auras(), nil)[1].id=="a"
    and #E.ActiveElementsForSpec(auras(), nil)==1)
end
print("aura_cascade_test "..(failures==0 and "OK" or "FAILED")); os.exit(failures==0 and 0 or 1)
