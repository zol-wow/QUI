-- tests/unit/cdm_icon_factory_mirror_empty_stack_test.lua
-- Run: lua tests/unit/cdm_icon_factory_mirror_empty_stack_test.lua
-- luacheck: globals InCombatLockdown GetTime CreateFrame wipe C_Timer C_StringUtil issecretvalue

local BuildCooldownStateContext = dofile("tests/helpers/cdm_context_builder_stub.lua")

local function noop() end

local inCombat = false
function InCombatLockdown() return inCombat end
function GetTime() return 100 end
function CreateFrame()
    return {
        RegisterEvent = noop,
        RegisterUnitEvent = noop,
        UnregisterAllEvents = noop,
        SetScript = noop,
    }
end
function wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

C_Timer = {
    After = function(_, callback) callback() end,
    NewTimer = function()
        return { Cancel = noop }
    end,
}
C_StringUtil = {
    TruncateWhenZero = function(value)
        return value == 0 and "" or tostring(value)
    end,
}

local stackWrites = {}
local textureWrites = {}
local secretAuraIcon = { token = "secret-aura-icon" }
local secretChargeCount = { token = "secret-charge-count" }
local forbidMindBlastChargeQueries = false
local forbidTentacleChargeQueries = false
local forbidHiddenChargeQueries = false

function issecretvalue(value)
    return value == secretChargeCount
end

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
                    buff = {
                        desaturateOnCooldown = true,
                    },
                }
            end
        end,
        IsSecretValue = function() return false end,
        SafeValue = function()
            error("SafeValue must not be used in the icon factory combat display path")
        end,
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
        QuerySpellCharges = function(spellID)
            if forbidMindBlastChargeQueries and (spellID == 8092 or spellID == 450983) then
                error("combat mirror-backed charge count must not query the live API")
            end
            if forbidTentacleChargeQueries and spellID == 123456 then
                error("visible mirror ChargeCount zero must not query the live charge API")
            end
            if forbidHiddenChargeQueries and spellID == 8093 then
                error("hidden mirror ChargeCount must not query the live charge API")
            end
            if spellID == 8092 then
                return {
                    currentCharges = 1,
                    maxCharges = 1,
                    isActive = true,
                }
            end
            if spellID == 450983 then
                return {
                    currentCharges = secretChargeCount,
                    maxCharges = 2,
                    isActive = true,
                }
            end
            if spellID == 49998 then
                return {
                    currentCharges = 3,
                    maxCharges = 3,
                    isActive = false,
                }
            end
            if spellID == 8093 then
                return {
                    currentCharges = 0,
                    maxCharges = 2,
                    isActive = true,
                }
            end
            return nil
        end,
        QuerySpellCooldown = function()
            return {
                startTime = 0,
                duration = 0,
                isActive = false,
            }
        end,
        QuerySpellDisplayCount = function(spellID)
            if spellID == 8092 then
                error("charge-mode mirror fallback should use currentCharges before display count")
            end
            if spellID == 450983 then
                error("charge-mode mirror fallback should use override currentCharges before display count")
            end
            if spellID == 49998 then
                return 3
            end
            if spellID == 123456 then
                error("visible mirror ChargeCount zero must not query display count")
            end
            if spellID == 8093 then
                error("hidden mirror ChargeCount must not query display count")
            end
            return nil
        end,
        QueryOverrideSpell = function(spellID)
            if spellID == 8092 then
                return 450983
            end
            return nil
        end,
    },
    CDMResolvers = {
        BuildCooldownStateContext = BuildCooldownStateContext,
        _textureCycleCache = {},
        _FinalizeImports = noop,
        Subscribe = noop,
        GetEntryTexture = function() return nil end,
        GetSpellTexture = function() return nil end,
        ResolveCooldownState = function(context)
            local entry = context and context.entry
            if entry and entry.spellID == 8092 then
                return {
                    mode = "charge",
                    active = true,
                    isActive = true,
                    durObj = { token = "mind-blast-charge" },
                    sourceID = "charge:mirror:8194:1",
                    spellID = context.runtimeSpellID or 8092,
                    mirrorBacked = true,
                    isOnCooldown = false,
                    rechargeActive = true,
                    hasCharges = true,
                    hasChargesRemaining = false,
                    gcdOnly = false,
                    mirrorCooldownID = 8194,
                    mirrorCategory = "essential",
                    cooldownID = 8194,
                    category = "essential",
                    state = {
                        cooldownID = 8194,
                        viewerCategory = "essential",
                        isActive = true,
                        mode = "charge",
                    },
                }
            end
            if entry and entry.spellID == 195182 then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    auraActive = true,
                    isTotemInstance = false,
                    count = {
                        sinkText = "7",
                        value = 7,
                        shown = true,
                        source = "display-count",
                    },
                }
            end
            if entry and entry.spellID == 195183 then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    auraActive = true,
                    isTotemInstance = false,
                    auraData = {
                        icon = secretAuraIcon,
                    },
                    count = {
                        sinkText = "8",
                        value = 8,
                        shown = true,
                        source = "display-count",
                    },
                    resolvedAuraSpellID = 195183,
                }
            end
            if entry and entry.spellID == 55090 then
                return {
                    mode = "aura",
                    active = true,
                    isActive = true,
                    auraActive = true,
                    auraUnit = "target",
                    isTotemInstance = false,
                    count = {
                        sinkText = "4",
                        value = 4,
                        shown = true,
                        source = "display-count",
                    },
                }
            end
            if entry and entry.spellID == 123456 then
                return {
                    mode = "charge",
                    active = true,
                    isActive = true,
                    durObj = { token = "tentacle-slam-charge" },
                    sourceID = "charge:mirror:123456:1",
                    spellID = 123456,
                    mirrorBacked = true,
                    isOnCooldown = true,
                    rechargeActive = true,
                    hasCharges = true,
                    hasChargesRemaining = false,
                    gcdOnly = false,
                    mirrorCooldownID = 123456,
                    mirrorCategory = "essential",
                    cooldownID = 123456,
                    category = "essential",
                    state = {
                        cooldownID = 123456,
                        viewerCategory = "essential",
                        isActive = true,
                        mode = "charge",
                    },
                }
            end
            if entry and entry.spellID == 8093 then
                return {
                    mode = "charge",
                    active = true,
                    isActive = true,
                    durObj = { token = "hidden-charge-mirror" },
                    sourceID = "charge:mirror:8195:1",
                    spellID = 8093,
                    mirrorBacked = true,
                    isOnCooldown = true,
                    rechargeActive = true,
                    hasCharges = true,
                    hasChargesRemaining = false,
                    gcdOnly = false,
                    mirrorCooldownID = 8195,
                    mirrorCategory = "essential",
                    cooldownID = 8195,
                    category = "essential",
                    state = {
                        cooldownID = 8195,
                        viewerCategory = "essential",
                        isActive = true,
                        mode = "charge",
                    },
                }
            end
            return {
                mode = "inactive",
                active = false,
                isActive = false,
                auraActive = false,
            }
        end,
        ResolveMacro = function() return nil end,
        IsAuraEntry = function(entry) return entry and entry.type == "aura" end,
        ResolveSpellActiveState = function() return nil end,
        ResolveCooldownActivityState = function()
            return { isOnCooldown = false, rechargeActive = false }
        end,
    },
    CDMBlizzMirror = {
        GetStateByCooldownID = function(cooldownID, category)
            if cooldownID == 8194 and category == "essential" then
                return {
                    mode = "charge",
                    stackTextSource = "ChargeCount",
                    mirrorEpoch = 44,
                }
            end
            if cooldownID == 123456 and category == "essential" then
                return {
                    mode = "charge",
                    stackText = 0,
                    stackTextSource = "ChargeCount",
                    stackTextShown = true,
                    cooldownChargesCount = 0,
                    cooldownChargesShown = true,
                    chargeCountFrameShown = true,
                    mirrorEpoch = 45,
                }
            end
            if cooldownID == 8195 and category == "essential" then
                return {
                    mode = "charge",
                    stackText = 0,
                    stackTextSource = "ChargeCount",
                    stackTextShown = false,
                    cooldownChargesCount = 0,
                    cooldownChargesShown = false,
                    chargeCountFrameShown = false,
                    mirrorEpoch = 46,
                }
            end
            if cooldownID == 27928 and category == "essential" then
                return {
                    mode = "cooldown",
                    stackTextShown = false,
                    cooldownChargesCount = secretChargeCount,
                    cooldownChargesShown = nil,
                    chargeCountFrameShown = false,
                    chargeTextOwnerShown = true,
                    mirrorEpoch = 47,
                }
            end
            return nil
        end,
    },
}

local loadChunk = dofile("tests/helpers/load_cdm_consolidated_chunk.lua")
loadChunk("QUI_CDM/cdm/cdm_icon_renderer.lua", "cdm_icon_factory.lua")("QUI", ns)
dofile("tests/helpers/load_cdm_icon_runtime.lua")(ns)
assert(loadfile("QUI_CDM/cdm/cdm_icon_renderer.lua"))("QUI", ns)

ns.CDMIcons.DebugStackText = function(_icon, op, value, reason)
    stackWrites[#stackWrites + 1] = { op = op, value = value, reason = reason }
end
ns.CDMIcons.ShouldAllowStackTextWrites = function() return true end

local function MakeStackText()
    return {
        SetText = function(_, value)
            stackWrites[#stackWrites + 1] = { op = "set", value = value }
        end,
        Hide = function()
            stackWrites[#stackWrites + 1] = { op = "frame-hide" }
        end,
        Show = function()
            stackWrites[#stackWrites + 1] = { op = "frame-show" }
        end,
        SetTextColor = function() end,
    }
end

local function MakeCooldown()
    return {
        SetDrawSwipe = function() end,
        SetDrawBling = function() end,
        SetSwipeTexture = function() end,
        SetSwipeColor = function() end,
        SetHideCountdownNumbers = function() end,
        SetReverse = function() end,
        Clear = function() end,
        Show = function() end,
    }
end

local staleIcon = {
    _spellEntry = {
        id = 49998,
        spellID = 49998,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Death Strike",
    },
    Icon = {
        Show = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
    TextOverlay = {
        Show = function() end,
    },
}

ns.CDMIconFactory.SetIconBlizzMirrorBinding(staleIcon, 12345, "essential")

assert(#stackWrites >= 1, "binding an empty mirror-backed cooldown should clear stale stack text")
assert(stackWrites[1].op == "set" and stackWrites[1].value == "", "binding should clear stale stack text")

stackWrites = {}

local icon = {
    _spellEntry = {
        id = 49998,
        spellID = 49998,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Death Strike",
    },
    _blizzMirrorCooldownID = 12345,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(icon)

assert(stackWrites[1] and stackWrites[1].op == "hide",
    "mirror-empty cooldown icon should hide stack text")
assert(stackWrites[1].reason == "mirror-stack-empty", "mirror-empty cooldown icon should use mirror-empty reason")

stackWrites = {}

local mindBlastIcon = {
    _spellEntry = {
        id = 8092,
        spellID = 8092,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Mind Blast",
    },
    _blizzMirrorCooldownID = 8194,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(mindBlastIcon)

local mindBlastText
local mindBlastHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and rawequal(write.value, secretChargeCount) then
        mindBlastText = write.value
    elseif write.op == "hide" then
        mindBlastHideReason = write.reason
    end
end
assert(mindBlastText == nil,
    "charge-mode mirror with empty Blizzard count text should not forward live charge counts")
assert(mindBlastHideReason == "mirror-stack-hidden",
    "charge-mode mirror with empty count text should stay mirror-owned")

stackWrites = {}
inCombat = true
forbidMindBlastChargeQueries = true

local combatMindBlastIcon = {
    _spellEntry = {
        id = 8092,
        spellID = 8092,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Mind Blast",
    },
    _blizzMirrorCooldownID = 8194,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(combatMindBlastIcon)

forbidMindBlastChargeQueries = false

local combatMindBlastText
local combatMindBlastHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and rawequal(write.value, secretChargeCount) then
        combatMindBlastText = write.value
    elseif write.op == "hide" then
        combatMindBlastHideReason = write.reason
    end
end
assert(combatMindBlastText == nil,
    "combat mirror-backed charge should not forward live API charge text")
assert(combatMindBlastHideReason == "mirror-stack-hidden",
    "combat mirror-backed charge with empty mirror count should stay mirror-owned")

stackWrites = {}
inCombat = true
forbidTentacleChargeQueries = true

local tentacleSlamIcon = {
    _spellEntry = {
        id = 123456,
        spellID = 123456,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Tentacle Slam",
        hasCharges = true,
    },
    _blizzMirrorCooldownID = 123456,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(tentacleSlamIcon)

forbidTentacleChargeQueries = false

local tentacleSlamText
local tentacleSlamHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and write.value ~= "" then
        tentacleSlamText = write.value
    elseif write.op == "hide" then
        tentacleSlamHideReason = write.reason
    end
end
assert(tentacleSlamText == "0",
    "visible mirror ChargeCount zero should render as 0 for charged abilities")
assert(tentacleSlamHideReason ~= "api-aura-stack-empty",
    "visible mirror ChargeCount zero must not be truncated into an empty stack")

stackWrites = {}
inCombat = true
forbidHiddenChargeQueries = true

local hiddenChargeIcon = {
    _spellEntry = {
        id = 8093,
        spellID = 8093,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Void Blast",
        hasCharges = true,
    },
    _blizzMirrorCooldownID = 8195,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(hiddenChargeIcon)

forbidHiddenChargeQueries = false

local hiddenChargeText
local hiddenChargeHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and write.value ~= "" then
        hiddenChargeText = write.value
    elseif write.op == "hide" then
        hiddenChargeHideReason = write.reason
    end
end
assert(hiddenChargeText == nil,
    "hidden combat mirror ChargeCount must suppress stale or live zero charge text")
assert(hiddenChargeHideReason == "mirror-stack-hidden",
    "hidden combat mirror ChargeCount should hide stack text while remaining mirror-owned")

stackWrites = {}
inCombat = true

local marrowrendIcon = {
    _spellEntry = {
        id = 195182,
        spellID = 195182,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Marrowrend",
    },
    _blizzMirrorCooldownID = 195182,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(marrowrendIcon)

local marrowrendText
local marrowrendHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and write.value ~= "" then
        marrowrendText = write.value
    elseif write.op == "hide" then
        marrowrendHideReason = write.reason
    end
end
assert(marrowrendText == "7", "Marrowrend should forward the resolver's display count")
assert(marrowrendHideReason ~= "mirror-stack-empty",
    "mirror-empty cooldown stack pass must not clobber resolver aura counts in combat")

stackWrites = {}

local scourgeStrikeIcon = {
    _spellEntry = {
        id = 55090,
        spellID = 55090,
        type = "spell",
        kind = "cooldown",
        viewerType = "essential",
        name = "Scourge Strike",
    },
    _blizzMirrorCooldownID = 27928,
    _blizzMirrorCategory = "essential",
    Icon = {
        SetTexture = function() end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(scourgeStrikeIcon)

local scourgeStrikeText
local scourgeStrikeHideReason
for _, write in ipairs(stackWrites) do
    if write.op == "set" and write.value ~= "" then
        scourgeStrikeText = write.value
    elseif write.op == "hide" then
        scourgeStrikeHideReason = write.reason
    end
end
assert(rawequal(scourgeStrikeText, secretChargeCount),
    "cooldown mirror ChargeCount should show when the child count text owner is shown")
assert(scourgeStrikeHideReason ~= "mirror-stack-hidden",
    "shown child count text owner should not be hidden by the parent count frame state")

stackWrites = {}
textureWrites = {}

local secretTextureIcon = {
    _spellEntry = {
        id = 195183,
        spellID = 195183,
        type = "aura",
        kind = "aura",
        viewerType = "buff",
        name = "Secret Aura Icon",
    },
    Icon = {
        SetTexture = function(_, texture)
            textureWrites[#textureWrites + 1] = texture
        end,
        SetDesaturated = function() end,
        SetVertexColor = function() end,
    },
    Cooldown = MakeCooldown(),
    StackText = MakeStackText(),
}

ns.CDMIcons.OnContainerIconPlaced(secretTextureIcon)

assert(textureWrites[1] == secretAuraIcon, "combat aura icon texture should be passed directly to SetTexture")
local secretAuraText
for _, write in ipairs(stackWrites) do
    if write.op == "set" and write.value ~= "" then
        secretAuraText = write.value
    end
end
assert(secretAuraText == "8", "combat aura count should be applied without SafeValue filtering")

print("OK: cdm_icon_factory_mirror_empty_stack_test")
