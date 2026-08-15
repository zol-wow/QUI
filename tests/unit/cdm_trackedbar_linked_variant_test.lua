-- luacheck: globals InCombatLockdown CreateFrame C_StringUtil

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = f:read("*a")
    f:close()
    return text
end

local layoutSrc = readAll("QUI_CDM/cdm/cdm_buff_layout.lua")
local rendererSrc = readAll("QUI_CDM/cdm/cdm_bar_renderer.lua")

local failures = 0
local function check(name, ok, detail)
    if ok then
        print(("  ok  %s"):format(name))
    else
        failures = failures + 1
        print(("FAIL  %s  %s"):format(name, detail or ""))
    end
end

local function sliceFunction(src, name)
    local start = assert(string.find(src, "local function " .. name, 1, true),
        name .. " definition should exist")
    local finish = assert(string.find(src, "\nend", start, true),
        name .. " should close")
    return string.sub(src, start, finish + 4), start
end

local spellDataBody = sliceFunction(layoutSrc, "GetTrackedBarSpellData(frame)")

check("GetTrackedBarSpellData must launder cdInfo.linkedSpellID through ReadNumber",
    string.find(spellDataBody, "ReadNumber(cdInfo.linkedSpellID", 1, true) ~= nil,
    "no ReadNumber(cdInfo.linkedSpellID ...) read found")

check("GetTrackedBarSpellData must resolve linked before override before base",
    string.find(spellDataBody, "linkedSpellID or overrideSpellID or baseSpellID", 1, true) ~= nil,
    "resolution chain does not put linkedSpellID first")

check("GetTrackedBarSpellData must resolve the variant name from the linked spell",
    string.find(spellDataBody, "QuerySpellInfo(linkedSpellID)", 1, true) ~= nil,
    "no QuerySpellInfo(linkedSpellID) name resolution found")

check("GetTrackedBarSpellData must return the linkedSpellID field",
    string.find(spellDataBody, "linkedSpellID = linkedSpellID", 1, true) ~= nil,
    "returned table does not carry linkedSpellID")

local runtimeBody = sliceFunction(layoutSrc, "GetTrackedBarRuntimeEntries()")

check("runtime entries must carry spellData.linkedSpellID",
    string.find(runtimeBody, "linkedSpellID = spellData.linkedSpellID", 1, true) ~= nil,
    "entry table does not copy spellData.linkedSpellID")

local displaySites = 0
for _ in string.gmatch(rendererSrc, "entry%.linkedSpellID or entry%.overrideSpellID") do
    displaySites = displaySites + 1
end
check("display identity sites must prefer entry.linkedSpellID (rebuild gate, rebind, build, icon)",
    displaySites >= 4,
    ("found %d linked-first identity sites, need >= 4"):format(displaySites))

function InCombatLockdown() return false end
function CreateFrame()
    local frame = {}
    function frame:SetScript() end
    function frame:CreateAnimationGroup()
        local group = {}
        function group:CreateAnimation()
            return { SetDuration = function() end }
        end
        function group:SetLooping() end
        function group:SetScript() end
        return group
    end
    return frame
end
C_StringUtil = {
    WrapString = function(value, prefix, suffix)
        if value == nil or value == "" then return "" end
        return prefix .. tostring(value) .. suffix
    end,
    TruncateWhenZero = function(value)
        if value == 0 then return nil end
        return value
    end,
}

local ns = {
    SafeCall = function(_policy, fn, ...) return pcall(fn, ...) end,
    SafeCallMethod = function(_policy, obj, name, ...) return pcall(function(...) return obj[name](obj, ...) end, ...) end,
    SafeCallMethodIfPresent = function(_policy, obj, name, ...) if obj == nil then return nil end local okP, m = pcall(function() return obj[name] end) if not okP then return false end if m == nil then return nil end return pcall(m, obj, ...) end,
    Helpers = {
        GetGeneralFont = function() return "Fonts\\FRIZQT__.TTF" end,
        GetGeneralFontOutline = function() return "" end,
        IsSecretValue = function() return false end,
    },
}

assert(loadfile("QUI_CDM/cdm/cdm_bar_renderer.lua"))("QUI", ns)
local bars = assert(ns.CDMBars, "CDMBars table was not exported")

local RTB_BASE, RTB_X, RTB_Y, RTB_Z = 315508, 193356, 193357, 193358
local RTB_CDID = 424242

local normalizeTracked = assert(bars._NormalizeTrackedBarRuntimeEntries,
    "tracked-bar runtime entry normalizer should be exported for focused tests")

local function liveVariantRuntime(linked)
    return {
        spellID = linked or RTB_BASE,
        baseSpellID = RTB_BASE,
        linkedSpellID = linked,
        name = linked and ("Variant " .. linked) or "Roll the Bones",
        iconTexture = linked and (1000 + linked) or 999,
        cooldownID = RTB_CDID,
        layoutIndex = 1,
        isActive = true,
        frame = { token = "blz-frame" },
    }
end

local normalized = normalizeTracked({ liveVariantRuntime(RTB_Y) })
check("normalizer must use the live linked variant as the runtime identity",
    normalized ~= nil and normalized[1].id == RTB_Y,
    normalized and ("id resolved to " .. tostring(normalized[1].id)) or "no entries normalized")
check("normalizer must carry linkedSpellID on the runtime entry",
    normalized ~= nil and normalized[1].linkedSpellID == RTB_Y,
    "linkedSpellID missing from the normalized entry")
check("normalizer must preserve the base spell ID",
    normalized ~= nil and normalized[1].spellID == RTB_BASE,
    normalized and ("spellID resolved to " .. tostring(normalized[1].spellID)) or "")

local buildTracked = assert(bars._BuildTrackedBarSpellList,
    "tracked-bar ownership merge helper should be exported for focused tests")

local function variantConfig(sid)
    return {
        id = sid,
        spellID = sid,
        name = "Configured " .. sid,
        type = "spell",
        kind = "aura",
        viewerType = "trackedBar",
        cooldownID = RTB_CDID,
        source = "owned-config",
    }
end

local merged = buildTracked({ liveVariantRuntime(RTB_Y) },
    { variantConfig(RTB_X), variantConfig(RTB_Y), variantConfig(RTB_Z) }, true)
check("live variant frame must bind the config that claims it, not the first config",
    merged[2] and merged[2]._trackedBarRuntime == true,
    "config for the live variant did not receive the runtime frame")
check("sibling variant configs must stay unbound while their variant is not live",
    merged[1] and not merged[1]._trackedBarRuntime
        and merged[3] and not merged[3]._trackedBarRuntime,
    "a sibling variant config consumed the live variant frame")

local vetoed = buildTracked({ liveVariantRuntime(RTB_Y) }, { variantConfig(RTB_X) }, true)
check("a lone sibling variant config must not fuzzy-bind a different live variant",
    vetoed[1] and not vetoed[1]._trackedBarRuntime,
    "cooldownID fuzzy match bound the frame to the wrong variant config")

local baseBound = buildTracked({ liveVariantRuntime(RTB_Y) }, { variantConfig(RTB_BASE) }, true)
check("a base-spell config must still bind whichever variant is live",
    baseBound[1] and baseBound[1]._trackedBarRuntime == true,
    "base config no longer matches a live variant frame")
check("a base-spell config bound to a live variant must display the variant identity",
    baseBound[1] and baseBound[1].linkedSpellID == RTB_Y
        and baseBound[1].name == "Variant " .. RTB_Y
        and baseBound[1].iconTexture == 1000 + RTB_Y,
    baseBound[1] and ("got linked=%s name=%s icon=%s"):format(
        tostring(baseBound[1].linkedSpellID), tostring(baseBound[1].name),
        tostring(baseBound[1].iconTexture)) or "no merged entry")

print(("\n%d failure(s)"):format(failures))
os.exit(failures == 0 and 0 or 1)
