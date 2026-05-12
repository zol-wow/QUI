-- tests/cdm_icons_gcd_style_test.lua
-- Run: lua tests/cdm_icons_gcd_style_test.lua

local function noop() end

function InCombatLockdown() return false end
function GetTime() return 100 end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}

local gcdDuration = { token = "gcd-duration" }
local realDuration = { token = "real-duration" }
local styleCalls = 0
local styleSawGCD = false
local desaturated
local gcdVisualDesaturated
local usableDesaturated
local resourceDesaturated
local mirrorDesaturated
local staleMirrorDesaturated
local mirrorGapMode = "cooldown"
local cooldownQueryCounts = {}

local ns = {
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        CreateDBGetter = function()
            return function()
                return {
                    essential = {
                        desaturateOnCooldown = true,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function(value) return value end,
        SafeToNumber = function(value) return value end,
        CanAccessTable = function(tbl) return type(tbl) == "table" end,
    },
    Addon = {
        db = {
            profile = { ncdm = {} },
            char = { ncdm = {} },
        },
    },
    CDMShared = {
        IsRuntimeEnabled = function() return true end,
        IsSafeNumeric = function(value) return type(value) == "number" end,
    },
    CDMSources = {
        QuerySpellUsable = function(spellID)
            if spellID == 13579 then
                return true, false
            end
            if spellID == 86421 then
                return true, false
            end
            if spellID == 97531 then
                return false, true
            end
            return nil, nil
        end,
    },
    CDMResolvers = {
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        QueryCharges = function() return nil end,
        QueryCooldown = function(spellID)
            cooldownQueryCounts[spellID] = (cooldownQueryCounts[spellID] or 0) + 1
            if spellID == 24680 then
                return { isActive = true, isOnGCD = true }
            end
            if spellID == 13579 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 97531 then
                return { isActive = true, isOnGCD = false }
            end
            if spellID == 86420 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 86421 then
                return { isActive = false, isOnGCD = nil }
            end
            if spellID == 86424 then
                -- Legitimate transient gap scenario: the live API confirms
                -- the CD is still active (isActive=true) while the mirror
                -- briefly resolves to gcd-only. Preservation MUST fire here.
                return { isActive = true, isOnGCD = true, startTime = 0, duration = 0 }
            end
            if spellID == 86426 then
                -- Genuine CD-end scenario: live API authoritatively says
                -- the cooldown has ended. Preservation MUST NOT fire even
                -- if the icon was just in mirror-cooldown mode.
                return { isActive = false, isOnGCD = nil, startTime = 0, duration = 0 }
            end
            if spellID == 86425 then
                return { isActive = false, isOnGCD = nil, startTime = 0, duration = 0 }
            end
            return nil
        end,
        QueryDuration = function() return nil end,
        QueryChargeDuration = function() return nil end,
        QueryOverrideSpell = function() return nil end,
        QueryDisplayCount = function() return nil end,
        QuerySpellCount = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveMacro = function() return nil end,
        GetEntryTexture = function() return nil end,
        HasRealCooldownState = function() return false end,
        ResolveAuraStateForIcon = function() return nil end,
        ResolveAuraDurationObjectForIcon = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.kind == "aura" end,
        GetChargeMetadataDB = function() return nil end,
        IsItemLikeEntry = function() return false end,
        ResolveItemCooldownIdentity = function() return nil end,
        ResolveEntryItemID = function() return nil end,
        ClassifySpellCooldownState = function() return nil end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function() return nil end,
        ResolveIconDurationObject = function(icon)
            if icon and icon._spellEntry and icon._spellEntry.id == 24680 then
                return realDuration, "cooldown", 24680, nil, nil, 24680
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 13579 then
                return realDuration, "cooldown", 13579, nil, nil, 13579
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 97531 then
                return realDuration, "cooldown", 97531, nil, nil, 97531
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86420 then
                return realDuration, "cooldown", "mirror:777:5", nil, nil, 86420, true
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86421 then
                return realDuration, "cooldown", "mirror:778:9", nil, nil, 86421, true
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86422 then
                return realDuration, "cooldown", "mirror:779:11", nil, nil, 86422, true
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86424 then
                if mirrorGapMode == "gcd-only" then
                    return gcdDuration, "gcd-only", 86424, nil, nil, 86424
                end
                return realDuration, "cooldown", "mirror:780:12", nil, nil, 86424, true
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86425 then
                return nil, "cooldown", "mirror:781:13", nil, nil, 86425, true
            end
            if icon and icon._spellEntry and icon._spellEntry.id == 86426 then
                if mirrorGapMode == "inactive" then
                    return nil, "inactive", nil, nil, nil, 86426
                end
                return realDuration, "cooldown", "mirror:782:14", nil, nil, 86426, true
            end
            return gcdDuration, "gcd-only", 12345, nil, nil, 12345
        end,
    },
    CDMIconFactory = {
        _FinalizeImports = noop,
        AcquireIcon = noop,
        ReleaseIcon = noop,
    },
    CDMRuntimeStore = {
        SetIconState = noop,
    },
    _OwnedSwipe = {
        ApplyToIcon = function(icon)
            styleCalls = styleCalls + 1
            styleSawGCD = icon and icon._showingGCDSwipe == true
        end,
    },
}

assert(loadfile("modules/cdm/cdm_icons.lua"))("QUI", ns)

local icon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    _showingGCDSwipe = nil,
    _showingRealCooldownSwipe = true,
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

local applied = ns.CDMIcons.ApplyResolvedCooldown(icon)

assert(applied == true, "GCD-only duration should be applied")
assert(icon._showingGCDSwipe == true, "GCD-only duration should mark the icon as showing GCD")
assert(styleCalls == 1, "GCD-only duration should reapply swipe styling immediately")
assert(styleSawGCD == true, "swipe styling should run after the GCD flag is set")

local gcdVisualIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            gcdVisualDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _showingGCDSwipe = nil,
    _spellEntry = {
        id = 12345,
        spellID = 12345,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(gcdVisualIcon)

assert(applied == true, "GCD-only duration should still be applied when icon has existing visual state")
assert(gcdVisualDesaturated == nil, "GCD-only duration should not overwrite existing icon desaturation")
assert(gcdVisualIcon._cdDesaturated == true, "GCD-only duration should leave existing desaturation ownership untouched")

local realCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            desaturated = value
        end,
        SetVertexColor = noop,
    },
    _showingGCDSwipe = true,
    _showingRealCooldownSwipe = true,
    _hasCooldownActive = true,
    _hasRealCooldownActive = true,
    _spellEntry = {
        id = 24680,
        spellID = 24680,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(realCooldownIcon)

assert(applied == true, "real cooldown duration should be applied")
assert(realCooldownIcon._hasCooldownActive == true, "real cooldown should remain active during a later GCD")
assert(realCooldownIcon._hasRealCooldownActive == true, "real cooldown flag should remain active during a later GCD")
assert(desaturated == true, "real cooldown should stay desaturated during a later GCD")
assert(realCooldownIcon._showingGCDSwipe == nil, "real cooldown should clear stale GCD swipe state")
assert(realCooldownIcon._showingRealCooldownSwipe == true, "real cooldown swipe state should remain set")

local usableCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            usableDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 13579,
        spellID = 13579,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(usableCooldownIcon)

assert(applied == true, "usable cooldown duration should still be safely applied if provided")
assert(usableCooldownIcon._hasCooldownActive == false, "usable cooldown should not be marked cooldown-active")
assert(usableCooldownIcon._hasRealCooldownActive == false, "usable cooldown should not be marked real-cooldown-active")
assert(usableDesaturated == false, "usable cooldown should not desaturate")

local resourceBlockedIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            resourceDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 97531,
        spellID = 97531,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(resourceBlockedIcon)

assert(applied == true, "resource-blocked cooldown duration should still be safely applied if provided")
assert(resourceBlockedIcon._hasCooldownActive == true, "resource-blocked cooldown should be marked cooldown-active")
assert(resourceBlockedIcon._hasRealCooldownActive == true, "resource-blocked cooldown should be marked real-cooldown-active")
assert(resourceDesaturated == true, "resource-blocked cooldown should desaturate")

local mirroredCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86420,
        spellID = 86420,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownIcon)

assert(applied == true, "active mirrored cooldown duration should win over live API inactive")
assert(mirroredCooldownIcon._hasCooldownActive == true, "active mirrored cooldown should be marked cooldown-active")
assert(mirroredCooldownIcon._hasRealCooldownActive == true, "active mirrored cooldown should be marked real-cooldown-active")
assert(mirrorDesaturated == true,
    "active mirrored real cooldown should desaturate the icon (resolver-owned, paired with the Blizzard swipe)")
assert(cooldownQueryCounts[86420] == nil, "active mirrored cooldown should not query live cooldown state")

mirrorDesaturated = nil

local usableMirroredCooldownIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86421,
        spellID = 86421,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(usableMirroredCooldownIcon)

assert(applied == true, "usable mirrored cooldown duration should win over live API inactive")
assert(usableMirroredCooldownIcon._hasCooldownActive == true,
    "usable active mirrored cooldown should be marked cooldown-active")
assert(usableMirroredCooldownIcon._hasRealCooldownActive == true,
    "usable active mirrored cooldown should be marked real-cooldown-active")
assert(mirrorDesaturated == true,
    "usable + mirror-payload-active is authoritative: mirror says real CD, so the icon desaturates alongside the Blizzard swipe")

local mirrorClearedPriorDesaturated
local priorDesaturatedMirrorIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorClearedPriorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _spellEntry = {
        id = 86421,
        spellID = 86421,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(priorDesaturatedMirrorIcon)

assert(applied == true, "mirrored cooldown should still apply when prior CD desaturation exists")
assert(mirrorClearedPriorDesaturated == true,
    "mirrored real cooldown should reaffirm desaturation (paired with the Blizzard swipe), not release it")
assert(priorDesaturatedMirrorIcon._cdDesaturated == true,
    "mirrored real cooldown should keep the desaturation flag set")

local mirrorNoCooldownInfoDesaturated
local mirrorNoCooldownInfoIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorNoCooldownInfoDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86422,
        spellID = 86422,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorNoCooldownInfoIcon)

assert(applied == true, "mirrored cooldown without live cdInfo should still be applied")
assert(mirrorNoCooldownInfoIcon._hasCooldownActive == true,
    "mirrored cooldown without live cdInfo should remain cooldown-active")
assert(mirrorNoCooldownInfoIcon._hasRealCooldownActive == true,
    "mirrored cooldown without live cdInfo should remain real-cooldown-active")
assert(mirrorNoCooldownInfoDesaturated == true,
    "mirrored cooldown without live cdInfo should desaturate when the mirror reports real-CD active")

mirrorDesaturated = nil
mirrorGapMode = "cooldown"

local mirroredCooldownGapIcon = {
    Cooldown = {
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            mirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86424,
        spellID = 86424,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

-- Resolver mode transitions are honored directly — no "mirror gap"
-- preservation. Per the directive (feedback_blizz_cd_state_signals):
-- isActive/isOnGCD are authoritative; we don't override the resolver from
-- stale icon state. If the resolver flips cooldown→gcd-only this pass,
-- the icon reflects gcd-only. Pre-existing desat is preserved across the
-- transition because gcd-only is the resolver's "no-op" desat mode.
applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownGapIcon)
assert(applied == true, "initial mirror-cooldown setup should apply")
assert(mirroredCooldownGapIcon._resolvedCooldownMode == "cooldown",
    "initial pass should resolve cooldown mode")
assert(mirrorDesaturated == true,
    "initial mirror real-cooldown should desaturate the icon")

mirrorGapMode = "gcd-only"
applied = ns.CDMIcons.ApplyResolvedCooldown(mirroredCooldownGapIcon)

assert(applied == true, "resolver gcd-only flip should still apply")
assert(mirroredCooldownGapIcon._resolvedCooldownMode == "gcd-only",
    "resolver gcd-only output should NOT be overridden back to cooldown — preservation is removed; the directive (isActive/isOnGCD) is authoritative")
assert(mirrorDesaturated == true,
    "gcd-only is the resolver's no-op desat mode — pre-existing desat from the prior cooldown pass must be preserved (not rewritten)")
assert(mirroredCooldownGapIcon._mirrorCooldownPreserveUntil == nil,
    "regression guard: the _mirrorCooldownPreserveUntil mechanism was removed and must not be reintroduced")

-- Genuine CD-end test: live cdInfo says isActive=false; the resolver
-- transitions cleanly to "inactive" and desat releases on the next event.
local cdEndDesaturated
mirrorGapMode = "cooldown"
local mirrorCdEndIcon = {
    Cooldown = {
        Clear = noop,
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            cdEndDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _spellEntry = {
        id = 86426,
        spellID = 86426,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorCdEndIcon)
assert(applied == true, "initial mirror-cooldown setup should apply")
assert(cdEndDesaturated == true,
    "initial mirror real-cooldown should desaturate the icon")

mirrorGapMode = "inactive"
applied = ns.CDMIcons.ApplyResolvedCooldown(mirrorCdEndIcon)

assert(mirrorCdEndIcon._resolvedCooldownMode == "inactive",
    "resolver inactive output must be reflected on the icon — no preservation reverts it back to cooldown")
assert(cdEndDesaturated == false,
    "CD end must release desaturation on the next ApplyResolvedCooldown pass")
assert(mirrorCdEndIcon._cdDesaturated == nil,
    "CD end must clear the _cdDesaturated flag")
assert(mirrorCdEndIcon._mirrorCooldownPreserveUntil == nil,
    "regression guard: preservation mechanism removed; field must never be written")

local staleMirrorNoDurationIcon = {
    Cooldown = {
        Clear = noop,
        SetCooldownFromDurationObject = noop,
        SetReverse = noop,
        SetSwipeTexture = noop,
    },
    Icon = {
        SetDesaturated = function(_, value)
            staleMirrorDesaturated = value
        end,
        SetVertexColor = noop,
    },
    _cdDesaturated = true,
    _spellEntry = {
        id = 86425,
        spellID = 86425,
        kind = "cooldown",
        type = "spell",
        viewerType = "essential",
    },
}

applied = ns.CDMIcons.ApplyResolvedCooldown(staleMirrorNoDurationIcon)

assert(applied == false, "stale mirrored cooldown without a duration should not apply")
assert(staleMirrorNoDurationIcon._hasCooldownActive == false,
    "stale mirrored cooldown should not keep cooldown-active true when live API is inactive")
assert(staleMirrorNoDurationIcon._hasRealCooldownActive == false,
    "stale mirrored cooldown should not keep real-cooldown-active true when live API is inactive")
assert(staleMirrorNoDurationIcon._resolvedCooldownMode == "inactive",
    "stale mirrored cooldown should be normalized to inactive")
assert(staleMirrorDesaturated == false,
    "stale mirrored cooldown should release previous cooldown desaturation once")

print("OK: cdm_icons_gcd_style_test")
