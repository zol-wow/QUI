-- tests/unit/skinning_primitive_consistency_lint_test.lua
-- Run: lua tests/unit/skinning_primitive_consistency_lint_test.lua
--
-- ARCHITECTURAL ENFORCEMENT (gap C). The whole skinning module's "consistent
-- look" depends on the SAME widget primitive always routing through the ONE
-- canonical SkinBase verb in core/uikit.lua — never a per-frame fork or a
-- bespoke open-coded reimplementation. Consistency that is hand-assembled per
-- frame silently drifts; this ratchet makes the architecture enforce it.
--
-- Each rule below corresponds to a primitive that was unified onto its canonical
-- verb. The rule fails the build if a removed fork returns or a known-bespoke
-- pattern reappears, so the inconsistency cannot re-grow. As more sites migrate,
-- ADD rules here (this is a one-way ratchet, like global_assignment_ratchet).

local function ReadLines(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

local function FileList()
    local cmd = "find QUI_Skinning/skinning -type f -name '*.lua' | sort"
    local pipe = assert(io.popen(cmd, "r"))
    local files = {}
    for path in pipe:lines() do
        files[#files + 1] = path
    end
    pipe:close()
    return files
end

-- Each rule: a fixed-string needle that must NOT appear anywhere in the skinning
-- tree, plus the canonical verb callers must use instead.
local FORBIDDEN = {
    { needle = "ScrollBar.Background:Hide()",
      fix = "scrollbars must route through SkinBase.SkinTrimScrollBar (which hides the background + styles the thumb + hides arrows), not a bare Background:Hide()" },
    { needle = "function StyleCharacterFrameTab",
      fix = "CharacterFrame tabs must use SkinBase.SkinTabGroup, not a private fork of SkinTabButton" },
    { needle = "function UpdateCharacterFrameTabSelectedState",
      fix = "CharacterFrame tab selection must use the canonical RefreshTabSelected (via SkinTabGroup), not a private fork" },
    { needle = "function StyleInspectFrameTab",
      fix = "InspectFrame tabs must use SkinBase.SkinTabGroup, not a private fork of SkinTabButton" },
    { needle = "function UpdateInspectFrameTabSelectedState",
      fix = "InspectFrame tab selection must use the canonical RefreshTabSelected (via SkinTabGroup); the old fork's live-only SetBackdropColors lost the tint on scale rebuild" },
    { needle = "function InsetButtonBackdrop",
      fix = "page-nav arrows must use SkinBase.SkinNextPrevButton (canonical chevron), not the bespoke InsetButtonBackdrop stack" },
}

local failures = {}
for _, path in ipairs(FileList()) do
    for lineNo, line in ipairs(ReadLines(path)) do
        for _, rule in ipairs(FORBIDDEN) do
            if line:find(rule.needle, 1, true) then
                failures[#failures + 1] = string.format(
                    "%s:%d: bespoke primitive reimplementation — %s\n    > %s",
                    path, lineNo, rule.fix, line:gsub("^%s+", ""))
            end
        end
    end
end

if #failures > 0 then
    error("\nskinning primitive-consistency ratchet violated (use the canonical SkinBase verb):\n"
        .. table.concat(failures, "\n"))
end

print("OK: skinning_primitive_consistency_lint_test (" .. #FileList() .. " files scanned)")
