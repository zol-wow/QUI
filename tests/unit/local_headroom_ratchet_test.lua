-- Ratchet test: every QUI-authored Lua file must keep at least MIN_HEADROOM
-- free slots under Lua's 200-local main-chunk ceiling. A file at the ceiling
-- fails to compile the moment anyone adds one more top-level `local` — as a
-- mystery "too many local variables" error pointing at an unrelated line
-- (cdm_blizz_mirror.lua hit exactly this; see its satellite split).
--
-- Method: the compiler itself is the oracle. Prepend MIN_HEADROOM dummy
-- `local` declarations to the source and compile the padded chunk. Padded
-- compile fails while the original compiles => fewer than MIN_HEADROOM free
-- slots => ratchet failure. No source parsing, so multi-name declarations,
-- do-blocks, and loop temporaries are all accounted exactly.
--
-- To fix a failing file: scope helper clusters in do-blocks, group related
-- state tables into a namespace table, or split a section into a satellite
-- file (underscore exports on the module table + nil guard) — see
-- QUI_CDM/cdm/cdm_blizz_mirror_suppression.lua for the reference split.
--
-- Plain Lua 5.1, file-driven (no harness). Run from repo root:
--   lua tests/unit/local_headroom_ratchet_test.lua

local MIN_HEADROOM = 10

-- Grandfathered files already inside the MIN_HEADROOM band when this ratchet
-- landed, with their measured free-slot floor. Each may only IMPROVE: dropping
-- below its floor fails. Once a file reaches MIN_HEADROOM (via do-block
-- scoping, state-table grouping, or a satellite split), remove its entry.
-- Both remaining are candidates for the cdm_blizz_mirror-style satellite split.
-- (cdm_icon_renderer.lua graduated via the CDM dead-code deletions;
-- cdm_spelldata.lua had already accumulated >=10 free slots in earlier
-- rounds and its entry was simply stale — no split needed for either.)
local GRANDFATHERED = {
    ["QUI_GroupFrames/groupframes/groupframes.lua"] = 0,
    ["modules/minimap/minimap.lua"] = 5,
}

local loadchunk = loadstring or load

-- ---------------------------------------------------------------------------
-- File enumeration via git ls-files (same scope as the global-assignment
-- ratchet). The generated search index used to live in its own folder and was
-- skipped by prefix; it is QUI_Options/search_cache.lua now and stays in
-- scope — it declares two file-scope locals, so it costs nothing to check.
-- ---------------------------------------------------------------------------
local function listInScopeFiles()
    local files = {}
    local p = io.popen and io.popen('git ls-files "*.lua"')
    if p then
        for line in p:lines() do
            if line:match("^core/")
                or line:match("^modules/")
                or line:match("^QUI_[^/]+/")
                or line == "init.lua"
            then
                files[#files + 1] = line
            end
        end
        p:close()
    end
    return files
end

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return src
end

local function padPrefix(n)
    local pads = {}
    for i = 1, n do
        pads[i] = ("local _local_headroom_pad_%d"):format(i)
    end
    pads[n + 1] = ""
    return table.concat(pads, "\n")
end

-- Compiles `src` with n dummy locals prepended. Prepending (not appending)
-- keeps the probe valid for files that end in a top-level return.
local function compilesWithPad(src, n, path)
    local chunk = loadchunk(padPrefix(n) .. src, "@" .. path)
    return chunk ~= nil
end

-- Exact free-slot count for diagnostics (only run for failing files).
local function measureHeadroom(src, path)
    for n = MIN_HEADROOM - 1, 0, -1 do
        if compilesWithPad(src, n, path) then
            return n
        end
    end
    return 0
end

local files = listInScopeFiles()
assert(#files > 0, "git ls-files returned no in-scope Lua files (run from repo root)")

local failures = {}
local checked = 0

for _, path in ipairs(files) do
    local src = readFile(path)
    if src then
        if not loadchunk(src, "@" .. path) then
            -- Doesn't compile as-is under this Lua; syntax ownership belongs
            -- to the compile gate (tools/check_compile.sh), not this ratchet.
            -- Skipping keeps the test meaningful on both 5.1 and 5.4.
        else
            checked = checked + 1
            if not compilesWithPad(src, MIN_HEADROOM, path) then
                local free = measureHeadroom(src, path)
                local floor = GRANDFATHERED[path]
                if not floor then
                    failures[#failures + 1] = ("%s: only %d free local slots (minimum %d) — see this test's header for fixes")
                        :format(path, free, MIN_HEADROOM)
                elseif free < floor then
                    failures[#failures + 1] = ("%s: %d free local slots, below its grandfathered floor of %d — the list may only improve")
                        :format(path, free, floor)
                end
            elseif GRANDFATHERED[path] then
                print(("note  %s now has >= %d free local slots — remove it from GRANDFATHERED")
                    :format(path, MIN_HEADROOM))
            end
        end
    end
end

if #failures > 0 then
    for _, msg in ipairs(failures) do
        print("FAIL  " .. msg)
    end
    print(("local_headroom_ratchet: %d of %d files within %d locals of the 200-local ceiling")
        :format(#failures, checked, MIN_HEADROOM))
    os.exit(1)
end

print(("OK: local_headroom_ratchet (%d files, all keep >= %d free local slots)")
    :format(checked, MIN_HEADROOM))
