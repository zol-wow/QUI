-- tests/unit/skinning_backdrop_persist_audit_test.lua
-- Run: lua tests/unit/skinning_backdrop_persist_audit_test.lua
--
-- Regression guard for the "skinned backdrop turns white on scale refresh" bug
-- across every QUI skinning module that drives SkinBase.ApplyPixelBackdrop.
--
-- WHY A SOURCE AUDIT (not a behavioral test per module):
-- The behavioral mechanism is already proven by tests/unit/loot_backdrop_persist_test.lua
-- (a bare SetBackdropColor is dropped to white on a real SkinBase scale-refresh
-- rebuild; Helpers.SetFrameBackdrop* survives it -- for both full-bg and
-- border-only frames) and by tests/unit/mplus_timer_backdrop_persist_test.lua
-- (a full real production path). The remaining skinning modules below style
-- frames that are module-local and/or have load-time game dependencies
-- (Enum, UnitPower, hook-driven Blizzard frames), so they cannot be driven in a
-- headless unit test the way the M+ timer (a QUI-owned global frame with a clean
-- exported apply function) can.
--
-- So this test enforces the SOURCE INVARIANT the fix establishes: a frame passed
-- to SkinBase.ApplyPixelBackdrop must have its colors set via
-- Helpers.SetFrameBackdropColor / Helpers.SetFrameBackdropBorderColor, never a
-- bare frame:SetBackdropColor / frame:SetBackdropBorderColor. Each file lists the
-- exact bare calls that are KNOWN-SAFE (and why); any other bare backdrop-color
-- call -- i.e. a newly introduced or un-converted one -- fails this test.
--
-- This test FAILS on the pre-fix source (the converted Style* sites used bare
-- colours that are NOT on these allowlists), and PASSES once they route through
-- Helpers.

local function ReadLines(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local lines = {}
    for line in f:lines() do lines[#lines + 1] = line end
    f:close()
    return lines
end

-- Collapse runs of whitespace and trim, so the allowlist isn't brittle to
-- reindentation/spacing.
local function Normalize(s)
    return (s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local BARE_PATTERNS = { ":SetBackdropColor%(", ":SetBackdropBorderColor%(" }

local function BareBackdropColorLines(path)
    local out = {}
    for _, line in ipairs(ReadLines(path)) do
        for _, pat in ipairs(BARE_PATTERNS) do
            if line:find(pat) then
                out[#out + 1] = Normalize(line)
                break
            end
        end
    end
    return out
end

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- KNOWN-SAFE remaining bare calls per file (normalized). Each is safe because it
-- targets a frame that is NOT a SkinBase.ApplyPixelBackdrop-registered frame:
--   * transient OnEnter/OnLeave hover highlights (reset on the opposite event);
--   * frames built via SkinBase.CreateBackdrop / ApplyFullBackdrop, whose manual
--     backdrop path already records _quiBg*/_quiBorder* (persists on rebuild);
--   * the alt-power-bar mover overlay (never given a pixel backdrop).
local ALLOW = {
    ["modules/skinning/frames/instanceframes.lua"] = Set({
        -- GroupFinder / PVP / BG button hover highlights (transient)
        "bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)",
        "bd:SetBackdropBorderColor(unpack(sc))",
        "bd:SetBackdropBorderColor(1, 1, 1, 1)",
        "bd:SetBackdropBorderColor(sr, sg, sb, sa)",
        -- UpdateGroupFinderButtonColors: bd is an ApplyFullBackdrop frame (persists)
        "bd:SetBackdropColor(btnBgR, btnBgG, btnBgB, 1)",
        -- PVEFrame + LFG SearchBox: CreateBackdrop frames (persist)
        "pveBd:SetBackdropColor(bgr, bgg, bgb, bga)",
        "pveBd:SetBackdropBorderColor(sr, sg, sb, sa)",
        "sbBd:SetBackdropColor(bgr, bgg, bgb, bga)",
        "sbBd:SetBackdropBorderColor(sr, sg, sb, sa)",
    }),
    ["modules/skinning/gameplay/keystone.lua"] = Set({
        -- Start-button hover highlight (transient)
        "bd:SetBackdropBorderColor(math.min(r * 1.3, 1), math.min(g * 1.3, 1), math.min(b * 1.3, 1), a)",
        "bd:SetBackdropBorderColor(unpack(sc))",
        -- ksBd: SkinBase.GetBackdrop/CreateBackdrop frame (manual path persists)
        "ksBd:SetBackdropColor(bgr, bgg, bgb, bga)",
        "ksBd:SetBackdropBorderColor(sr, sg, sb, sa)",
    }),
    ["modules/skinning/gameplay/powerbaralt.lua"] = Set({
        -- Mover overlay: not a pixel-backdrop frame
        "powerBarMover:SetBackdropColor(sr, sg, sb, 0.3)",
        "powerBarMover:SetBackdropBorderColor(sr, sg, sb, 1)",
    }),
    -- These must contain NO bare backdrop-color calls at all.
    ["modules/skinning/frames/overrideactionbar.lua"] = Set({}),
    ["modules/skinning/frames/statustracking.lua"] = Set({}),
    ["modules/skinning/gameplay/mplus_timer.lua"] = Set({}),
}

-- Files that MUST prove the fix is present (use the persisting helpers).
local MUST_USE_HELPERS = {
    "modules/skinning/frames/instanceframes.lua",
    "modules/skinning/frames/overrideactionbar.lua",
    "modules/skinning/gameplay/keystone.lua",
    "modules/skinning/gameplay/powerbaralt.lua",
    "modules/skinning/frames/statustracking.lua",
    "modules/skinning/gameplay/mplus_timer.lua",
}

local failures = 0
local function check(cond, msg)
    if not cond then
        io.write("FAIL: ", msg, "\n")
        failures = failures + 1
    end
end

for path, allow in pairs(ALLOW) do
    for _, line in ipairs(BareBackdropColorLines(path)) do
        check(allow[line],
            path .. " has a bare backdrop-color call that is not on the known-safe allowlist "
            .. "(a pixel-backdrop frame must use Helpers.SetFrameBackdrop*): " .. line)
    end
end

for _, path in ipairs(MUST_USE_HELPERS) do
    local lines = ReadLines(path)
    local found = false
    for _, line in ipairs(lines) do
        if line:find("Helpers%.SetFrameBackdropColor%(")
            or line:find("Helpers%.SetFrameBackdropBorderColor%(") then
            found = true
            break
        end
    end
    check(found, path .. " must set pixel-backdrop colors via Helpers.SetFrameBackdrop* (fix missing)")
end

if failures > 0 then
    error(failures .. " backdrop-persist audit failure(s)")
end
print("OK: skinning_backdrop_persist_audit_test")
