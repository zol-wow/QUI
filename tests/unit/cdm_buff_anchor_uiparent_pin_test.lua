-- tests/unit/cdm_buff_anchor_uiparent_pin_test.lua
-- Source-level assertions that lock in the UIParent-pin change for the CDM
-- buff/bar anchor functions.  Uses the established readFile pattern (see
-- cdm_buff_container_border_test.lua) — no behavioral harness required because
-- the target functions are file-local inside a heavily ns-coupled module.
--
-- Run from repo root: lua tests/unit/cdm_buff_anchor_uiparent_pin_test.lua

local env = dofile("tools/_addon_env.lua")
env.LoadCore()

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function readFile(path)
    local fh = assert(io.open(path, "rb"), "failed to open " .. path)
    local s = fh:read("*a")
    fh:close()
    return s
end

local src = readFile("QUI_CDM/cdm/cdm_buff_layout.lua")

-- Count how many times the old combat-bail pattern appears in the file.
-- After the edit there should be ZERO in these two functions.
local combatBailLiteral = "InCombatLockdown() and not inInitSafeWindow then return end"

local function countLiteral(haystack, needle)
    local count = 0
    local s = 1
    while true do
        local i = haystack:find(needle, s, true)
        if not i then break end
        count = count + 1
        s = i + 1
    end
    return count
end

---------------------------------------------------------------------------
-- 1. The combat-bail return is gone from ApplyTrackedBarAnchor and
--    ApplyBuffIconAnchor (the two anchor apply functions).  We check by
--    counting total occurrences in the file — post-edit the count must be 0
--    (neither function retains it).
---------------------------------------------------------------------------
local combatBailCount = countLiteral(src, combatBailLiteral)
check("combat-bail gone from anchor functions (0 occurrences)",
    combatBailCount == 0,
    "found " .. combatBailCount .. " occurrence(s) of the combat-bail return")

---------------------------------------------------------------------------
-- 2. Helpers.PinFrameToTargetAbsolute is called at least twice (once for
--    ApplyBuffIconAnchor, once for ApplyTrackedBarAnchor).
---------------------------------------------------------------------------
local pinCount = countLiteral(src, "Helpers.PinFrameToTargetAbsolute")
check("Helpers.PinFrameToTargetAbsolute called at least twice (buff + bar)",
    pinCount >= 2,
    "found " .. pinCount .. " call(s)")

---------------------------------------------------------------------------
-- 3. Both restriction predicates gate each function: IsProtected (directly
--    secure targets) AND IsAnchoringRestricted (dependent case, e.g. an
--    essential container hosting SecureActionButton icon children).
---------------------------------------------------------------------------
local protCount = countLiteral(src, "Helpers.FrameIsProtected")
check("Helpers.FrameIsProtected called at least twice (buff + bar)",
    protCount >= 2,
    "found " .. protCount .. " call(s)")
local restrCount = countLiteral(src, "Helpers.FrameIsAnchoringRestricted")
check("Helpers.FrameIsAnchoringRestricted called at least twice (buff + bar)",
    restrCount >= 2,
    "found " .. restrCount .. " call(s)")

---------------------------------------------------------------------------
-- 4. The insecure-target relative branch still exists: a
--    viewer:SetPoint(sourcePoint, anchorFrame call must remain for the
--    non-protected path in at least one anchor function.
---------------------------------------------------------------------------
local relSetPointCount = countLiteral(src, "viewer:SetPoint(sourcePoint, anchorFrame")
check("insecure-target viewer:SetPoint(sourcePoint, anchorFrame still present",
    relSetPointCount >= 1,
    "found " .. relSetPointCount .. " occurrence(s)")

---------------------------------------------------------------------------
-- 5. Edit Mode bail (Helpers.IsEditModeActive) is still present in both
--    anchor functions — check at least two occurrences in the file.
---------------------------------------------------------------------------
local editModeCount = countLiteral(src, "Helpers.IsEditModeActive")
check("Helpers.IsEditModeActive still present (>= 2 occurrences)",
    editModeCount >= 2,
    "found " .. editModeCount .. " occurrence(s)")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
