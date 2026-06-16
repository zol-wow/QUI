-- Run: lua5.1 tools/test_i18n_extract.lua
local failures = 0
local function check(n, c) if c then print("ok   - "..n) else failures=failures+1; print("FAIL - "..n) end end

local X = assert(loadfile("tools/i18n/extract_strings.lua"))()  -- returns module table

-- collectKeys(sourceText) -> set of keys. Localization uses explicit ns.L["..."] ONLY.
local src = [[
    local label = ns.L["Show tooltips"]
    Shared.BuildSettingRow(s.frame, ns.L["Switch Profile"], w)
    print(ns.L['Profile reset. Please /reload.'])
    local dyn = ns.L[varKey]               -- dynamic, must be ignored
    local layout = MakeLayout(content)     -- overloaded bareword L is common in this repo
    local also = layout["Not A Key"]       -- bareword index, must be ignored
    local foreign = Foo.L["Foreign Key"]   -- foreign L table, must be ignored
    local bareword = L["Bareword Ignored"] -- bareword L (aliased elsewhere), must be ignored
    local arrow = ns.L["A\226\134\146Z"]
    local dash = ns.L["Ready — go"]
    local quote = ns.L["QUI\"Test"]
]]
local keys = X.collectKeys(src)
check("finds double-quote ns.L key", keys["Show tooltips"] == true)
check("finds row label ns.L key",    keys["Switch Profile"] == true)
check("finds single-quote ns.L key", keys["Profile reset. Please /reload."] == true)
check("ignores dynamic ns.L[var]",   keys["varKey"] == nil)
check("ignores bareword layout idx", keys["Not A Key"] == nil)
check("ignores foreign Foo.L",       keys["Foreign Key"] == nil)
check("ignores bareword L[...]",     keys["Bareword Ignored"] == nil)
check("decodes decimal byte escapes", keys["A→Z"] == true)
check("keeps utf8 literals intact", keys["Ready — go"] == true)
check("decodes escaped quote", keys["QUI\"Test"] == true)

if failures > 0 then os.exit(1) end
print("\nextract tests passed")
