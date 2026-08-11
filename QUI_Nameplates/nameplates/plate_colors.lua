local ADDON_NAME, ns = ...
local NP = ns.QUI_Nameplates
if not NP then return end

local NPColors = {}
NP.Colors = NPColors

local FALLBACK = { 0.39, 0.11, 0.09 }

local RAID_CLASS_COLORS = _G.RAID_CLASS_COLORS or {}

local function FromTable(t, fallback)
    t = t or fallback or FALLBACK
    return t[1] or 1, t[2] or 1, t[3] or 1
end

local function ResolveThreat(colors, plate, context)
    if not context then return nil end
    if colors.threatInstancesOnly ~= false and context.inInstance ~= true then return nil end
    local threat = plate.npThreat
    if threat == nil then return nil end
    local isTank = context.role == "TANK"
    if isTank then
        if threat == "high" then
            return colors.tankHasAggro
        elseif threat == "offtank" then
            return colors.offTankAggro
        else
            return colors.tankNoAggro
        end
    else
        if threat == "high" then
            return colors.dpsHasAggro
        elseif threat == "near" then
            return colors.dpsNearAggro
        end
    end
    return nil
end

function NPColors.Resolve(plate, settings, context)
    local colors = (settings and settings.colors) or {}

    if plate.npTapDenied == true then
        return FromTable(colors.tapped)
    end

    if colors.questEnabled ~= false and plate.npIsQuest == true then
        return FromTable(colors.quest)
    end

    if colors.threatEnabled ~= false and plate.npReaction ~= "friendly" then
        local threatColor = ResolveThreat(colors, plate, context)
        if threatColor then
            return FromTable(threatColor)
        end
    end

    if colors.targetEnabled == true and plate.npIsTarget == true then
        return FromTable(colors.target)
    end
    if colors.focusEnabled == true and plate.npIsFocus == true then
        return FromTable(colors.focus)
    end

    if colors.classColorEnemyPlayers ~= false and plate.npIsPlayer == true then
        local classColor = plate.npClassToken and RAID_CLASS_COLORS[plate.npClassToken]
        if classColor then
            return classColor.r or 1, classColor.g or 1, classColor.b or 1
        end
    end

    local r, g, b
    if plate.npReaction == "friendly" then
        r, g, b = FromTable(colors.friendly)
    elseif plate.npReaction == "neutral" then
        r, g, b = FromTable(colors.neutral)
    else
        r, g, b = FromTable(colors.hostile)
    end

    if colors.oocDarken ~= false and plate.npInCombat == false and plate.npReaction ~= "friendly" then
        local f = colors.oocDarkenFactor or 0.75
        return r * f, g * f, b * f
    end

    return r, g, b
end
