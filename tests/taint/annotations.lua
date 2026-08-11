-- tests/taint/annotations.lua
-- Scan Lua source for `-- @secret-safe: <reason>` and
-- `-- @secret-policy: <name>` comments and produce a per-line lookup of
-- suppressions.
--
-- Suppression contract (Drew's 12d canon): `@secret-policy:` names a
-- deliberate unknown-handling ACTION POLICY and suppresses ONLY
-- `<secret-collapse>` findings; `@secret-safe:` suppresses every OTHER
-- finding kind but never a collapse — collapses must carry a NAMED policy.

local M = {}

-- Match the annotation marker followed by optional space + reason text.
-- Captures the reason text (may be empty if user wrote the marker only).
-- POLICY is tried FIRST: `@secret-policy` contains no `@secret-safe`
-- substring, but keep the order explicit and deterministic.
local SAFE_PATTERN   = "%-%-%s*@secret%-safe:%s*(.*)$"
local POLICY_PATTERN = "%-%-%s*@secret%-policy:%s*(.*)$"

--- Scan source. Returns a table indexed by 1-based line number, with each
--- entry { reason = string|nil, emptyReason = boolean, kind = "safe"|"policy" }.
function M.scan(source)
    local result = {}
    local lineNum = 0
    local pendingForNextLine = nil

    -- Iterate lines including final no-newline line
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lineNum = lineNum + 1
        local trimmed = line:match("^%s*(.-)%s*$")
        local kind = "policy"
        local pattern = POLICY_PATTERN
        local reason = trimmed:match(POLICY_PATTERN)
        if reason == nil then
            kind = "safe"
            pattern = SAFE_PATTERN
            reason = trimmed:match(SAFE_PATTERN)
        end

        if reason ~= nil then
            -- Is this an annotation-only line (no code)?
            local codePart = trimmed:gsub(pattern, "")
            codePart = codePart:match("^%s*(.-)%s*$")
            if codePart == "" then
                -- Annotation-only line → applies to the NEXT non-blank line
                pendingForNextLine = {
                    reason = (#reason > 0) and reason or nil,
                    emptyReason = (#reason == 0),
                    kind = kind,
                }
            else
                -- Trailing-style annotation → applies to THIS line
                result[lineNum] = {
                    reason = (#reason > 0) and reason or nil,
                    emptyReason = (#reason == 0),
                    kind = kind,
                }
                pendingForNextLine = nil
            end
        else
            -- No annotation on this line. If pending, attach to this line
            -- (only if this line has actual code, not blank).
            if pendingForNextLine and trimmed ~= "" then
                result[lineNum] = pendingForNextLine
                pendingForNextLine = nil
            end
        end
    end

    return result
end

--- Apply annotations to findings. `@secret-policy:` suppresses ONLY
--- `<secret-collapse>` findings (the named-action-policy discipline);
--- `@secret-safe:` suppresses every OTHER finding kind but never collapse.
--- Entries without `kind` default to "safe" (back-compat). Mutates findings
--- in place, setting suppressed=true and suppression_reason on matches.
function M.apply(findings, annotations)
    for _, f in ipairs(findings) do
        local a = annotations[f.line]
        if a and a.reason then
            local isCollapse = f.sink == "<secret-collapse>"
            local kind = a.kind or "safe"
            if (kind == "policy") == isCollapse then
                f.suppressed = true
                f.suppression_reason = a.reason
            end
        end
    end
end

return M
