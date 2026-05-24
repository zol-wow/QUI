-- CDM-specific Blizzard API facts that are too important to live only in
-- comments or agent instructions. The vendored FrameXML documentation remains
-- the raw source; this table records the policy CDM code and tests enforce.

return {
    sourceDocs = {
        cooldownViewer = "tests/api-docs/blizzard/CooldownViewerDocumentation.lua",
        cooldownFrame = "tests/api-docs/blizzard/FrameAPICooldownDocumentation.lua",
        curveUtil = "tests/api-docs/blizzard/CurveUtilDocumentation.lua",
        statusBar = "tests/api-docs/blizzard/SimpleStatusBarAPIDocumentation.lua",
        totem = "tests/api-docs/blizzard/TotemDocumentation.lua",
        unitAura = "tests/api-docs/blizzard/UnitAuraDocumentation.lua",
    },

    apiIndexContracts = {
        ["C_CooldownViewer.GetCooldownViewerCategorySet"] = {
            secretArguments = "AllowedWhenUntainted",
        },
        ["C_CooldownViewer.GetCooldownViewerCooldownInfo"] = {
            secretArguments = "AllowedWhenUntainted",
        },
        ["C_CooldownViewer.GetValidAlertTypes"] = {
            secretArguments = "AllowedWhenUntainted",
        },
        ["C_UnitAuras.GetAuraDuration"] = {
            secretArguments = "AllowedWhenUntainted",
        },
        ["Totem.GetTotemDuration"] = {
            secretArguments = "AllowedWhenUntainted",
        },
    },

    durationObjectSources = {
        ["C_UnitAuras.GetAuraDuration"] = {
            doc = "unitAura",
            returnType = "LuaDurationObject",
            use = "aura duration lane",
        },
        ["Totem.GetTotemDuration"] = {
            doc = "totem",
            runtimeName = "GetTotemDuration",
            returnType = "LuaDurationObject",
            use = "totem duration lane",
        },
    },

    durationObjectSinks = {
        SetCooldownFromDurationObject = {
            doc = "cooldownFrame",
            receiver = "CooldownFrame",
            argumentType = "LuaDurationObject",
            policy = "preferred cooldown frame sink for secret-capable timing",
        },
        SetTimerDuration = {
            doc = "statusBar",
            receiver = "StatusBar",
            argumentType = "LuaDurationObject",
            policy = "preferred bar fill sink for secret-capable timing",
        },
    },

    cooldownFrame = {
        preferredSecretSafeSetter = "SetCooldownFromDurationObject",
        unsafeSecretSetters = {
            "SetCooldown",
            "SetCooldownFromExpirationTime",
            "SetCooldownDuration",
            "SetCooldownUNIX",
        },
        numericFallback = {
            facade = "CDMRenderers.ApplyNumericCooldown",
            method = "SetCooldown",
            allowedCallSites = {
                ["modules/cdm/cdm_frame_writes.lua"] = true,
            },
            -- Out-of-combat preview-only exceptions. These sites drive
            -- the settings preview pane with cycle-script timing built
            -- from GetTime() + constants. Values are never secret-derived
            -- and never reach the runtime CDM render path, so they can
            -- safely call SetCooldown directly without going through the
            -- ApplyNumericCooldown facade. The facade count (== 1)
            -- assertion is intentionally not affected by these.
            previewExceptionSites = {
                ["modules/cdm/settings/composer_preview_driver.lua"] = true,
            },
            policy = "clean item timing only; never secret-derived cooldown timing",
        },
        -- Why no secret-passthrough facade exists. We tried a second
        -- blessed facade (ApplyHookPassthroughCooldown) that forwarded
        -- Blizzard's Cooldown:Set* args from a hooksecurefunc callback
        -- directly to addon-owned Cooldown widgets. The hypothesis was
        -- that being inside a hooksecurefunc frame from Blizzard's
        -- CooldownViewer call would preserve enough taint context for
        -- the C side to accept the secret args. Empirical test on Mind
        -- Blast 8092 -> 450983 (Shadow Priest) returned:
        --   "bad argument #2 to 'SetCooldown' ... Secret values are
        --    only allowed during untainted execution for this argument."
        -- The taint check on SetCooldown is per-receiving-widget: only
        -- Blizzard-owned widgets accept secret args, regardless of the
        -- caller's frame. Addon-owned Cooldown subframes are insecure
        -- and reject. There is no Lua-visible workaround. Spells whose
        -- CooldownViewer mixin uses SetCooldown(start, duration)
        -- instead of SetCooldownFromDurationObject simply can't have
        -- their swipe mirrored to the addon icon in combat. The icon's
        -- desaturation still works (the resolver classifies mode=cooldown
        -- from cdInfo.isActive=true, and the icon-side chargesRemaining
        -- query keeps charge spells with remaining charges saturated),
        -- but the animated swipe is unreachable.
    },

    secretBooleanDecode = {
        functionName = "C_CurveUtil.EvaluateColorValueFromBoolean",
        docFunctionName = "EvaluateColorValueFromBoolean",
        doc = "curveUtil",
        secretArguments = "AllowedWhenTainted",
        valueIfTrue = 1,
        valueIfFalse = 0,
        returnType = "SingleColorValue",
        policy = "only approved Lua-visible decode path for potentially-secret booleans",
    },
}
