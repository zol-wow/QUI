-- tests/taint/index_load.lua
-- Populate a Registry from a loaded api-index table + taint config.
-- Extracted from tools/test_taint.lua so the sink-allowlist generation is
-- unit-testable. `warn(msg)` receives the cross-check warning strings
-- (byte-for-byte identical to the runner's former io.stderr:write calls).
-- Returns indexedEvents (event name → meta) so the runner can run its own
-- config-side cross-check (a configured event_payload_params entry that has
-- gone missing from the index) alongside that config's registration; the
-- reverse cross-check (an index event with no configured payload positions)
-- is pure index-scan logic and lives entirely in here.

local M = {}

function M.populate(registry, indexTable, cfg, warn)
    warn = warn or function() end

    -- event:* entries harvested from the api-index (event name → meta
    -- table); cross-checked against the config's event_payload_params below.
    local indexedEvents = {}

    -- Which precondition flags mark a RESTRICTION hazard (hard error while
    -- encounter/M+/PvP addon restrictions are active). Most Requires* flags
    -- are plain argument/state validation (RequiresValidActionSlot,
    -- RequiresFriendList, ...) — flagging those raw calls would drown the
    -- review tier. Extendable via config restriction_preconditions.
    local restrictionPre = { RequiresUnitAuraAccess = true }
    for _, name in ipairs(cfg.restriction_preconditions or {}) do
        restrictionPre[name] = true
    end

    -- Index meta keys that must NEVER make an entry a taint source:
    -- preconditions = call-errors (separate track below); eventFlags/
    -- secretPayload = event entries ("event:*" keys, never call sites).
    -- Event payload ANALYSIS is driven by the config's event_payload_params
    -- (wired to the registry by the runner) — the index metadata is per-
    -- event only and cannot say WHICH handler argument is secret, so
    -- positions are configured explicitly. Aspect flags are also non-source
    -- here: secretArgumentsAddAspect marks setters (never a secret RETURN),
    -- and secretReturnsForAspect getters are widget METHODS — their dotted
    -- doc names never match a call site, so they register on the method
    -- track below instead.
    -- conditionalSecretContents: the container return is NOT secret (its
    -- truth-test is safe) — only its ELEMENTS secretize. Sourcing the whole
    -- call would FP every `if auras` container check; element-level hazard
    -- modeling is backlog (see .taintrc header).
    local nonSourceKeys = {
        preconditions = true, eventFlags = true, secretPayload = true,
        secretReturnsForAspect = true, secretArgumentsAddAspect = true,
        conditionalSecretContents = true,
    }

    for funcName, meta in pairs(indexTable) do
        -- Collect event:* entries for the config↔index cross-check below
        -- (round-4: config-only event coverage silently rots when 12.1
        -- adds/removes event flags).
        local eventName = funcName:match("^event:(.+)$")
        if eventName and type(meta) == "table" then
            indexedEvents[eventName] = meta
        end
        -- Filter by coverage flags from config
        local include = false
        if type(meta) == "table" then
            for coverageKey, _ in pairs(meta) do
                if cfg.coverage[coverageKey] and not nonSourceKeys[coverageKey] then
                    include = true
                    break
                end
            end
        else
            include = true
        end
        if include then
            registry:addSource(funcName)
        end
        -- Precondition-guarded APIs are NOT taint sources — the hazard is a
        -- hard ERROR under restrictions, not a secret return — so they
        -- register on a separate track feeding the analyzer's precondition
        -- scan, filtered to the restriction flags above.
        if type(meta) == "table" and type(meta.preconditions) == "table"
            and cfg.coverage.preconditions then
            local relevant
            for _, flag in ipairs(meta.preconditions) do
                if restrictionPre[flag] then
                    relevant = relevant or {}
                    relevant[#relevant + 1] = flag
                end
            end
            if relevant then
                registry:addPreconditionAPI(funcName, relevant)
            end
        end
        -- Aspect-returning widget getters register by bare method name (call
        -- sites are `obj:GetAlpha()`). Exposure is gated per-file by config
        -- aspect_paths at analyze time.
        if type(meta) == "table" and type(meta.secretReturnsForAspect) == "table"
            and cfg.coverage.secretReturnsForAspect
            and not funcName:match("^event:") and not funcName:match("^C_") then
            local method = funcName:match("([%w_]+)$")
            if method then
                registry:addAspectReturningMethod(method, meta.secretReturnsForAspect)
            end
        end
        -- conditionalSecretContents (round-23): container return readable,
        -- ELEMENTS secretize. Registers on the element track only — the
        -- nonSourceKeys entry above keeps it off the whole-call source
        -- track (container truth-tests are safe).
        if type(meta) == "table" and meta.conditionalSecretContents == true
            and cfg.coverage.conditionalSecretContents
            and not funcName:match("^event:") then
            registry:addElementSecretFunction(funcName)
        end
    end

    -- Reverse check: index events carrying an aura-restriction flag that have
    -- NO configured payload positions are an analysis coverage gap. Warn so
    -- a new 12.1 flag shows up here instead of silently going unanalyzed.
    -- The flag set mirrors the precondition scan's restriction focus; extend
    -- via config restriction_event_flags.
    do
        local restrictionEventFlags = { SecretWhenAurasRestricted = true }
        for _, flag in ipairs(cfg.restriction_event_flags or {}) do
            restrictionEventFlags[flag] = true
        end
        for eventName, meta in pairs(indexedEvents) do
            if not (cfg.event_payload_params and cfg.event_payload_params[eventName]) then
                local hazard
                if meta.secretPayload == true then
                    hazard = "secretPayload"
                else
                    for _, flag in ipairs(meta.eventFlags or {}) do
                        if restrictionEventFlags[flag] then
                            hazard = flag
                            break
                        end
                    end
                end
                if hazard then
                    warn(string.format(
                        "WARNING: api-index event %q carries %s but has no "
                        .. "event_payload_params entry — handler payloads are unanalyzed\n",
                        eventName, hazard))
                end
            end
        end
    end

    -- NEW (backlog item 2): sink allowlist + documented reject-set, generated
    -- from SecretArguments/DurationObject evidence. Bare keys are widget
    -- methods when scriptObject, bare globals otherwise; a bare key WITHOUT
    -- scriptObject registers on BOTH tracks (receiver-blind call sites can
    -- produce either lookup).
    for funcName, meta in pairs(indexTable) do
        if type(meta) == "table" and not funcName:match("^event:") then
            local allow = meta.secretArguments == "AllowedWhenTainted"
                or meta.secretArgumentsAnyTainted == true
                or meta.durationObjectArg == true
            local restricted = not allow and meta.secretArguments ~= nil
                and (meta.secretArguments == "AllowedWhenUntainted"
                     or meta.secretArguments == "NotAllowed")
            local dotted = funcName:find("%.", 1) ~= nil
            if allow then
                if dotted then
                    registry:addSafeSinkFunction(funcName)
                else
                    registry:addSafeSinkMethod(funcName)
                    if not meta.scriptObject then
                        registry:addSafeSinkFunction(funcName)
                    end
                end
            elseif restricted then
                if dotted then
                    registry:addDocArgRestrictedFunction(funcName, meta.secretArguments)
                else
                    registry:addDocArgRestrictedMethod(funcName, meta.secretArguments)
                    if not meta.scriptObject then
                        registry:addDocArgRestrictedFunction(funcName, meta.secretArguments)
                    end
                end
            end
        end
    end

    return indexedEvents
end

return M
