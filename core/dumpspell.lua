--[[
    QUI /qspell — print everything we can about a spell.

    Usage: /qspell <spellID | spell link | partial name>
    Examples:
        /qspell 1953
        /qspell [Blink]              (shift-click a spell into chat)
        /qspell ice barrier
]]

local ADDON_NAME, ns = ...
local Helpers = ns and ns.Helpers
local SafeValue = Helpers and Helpers.SafeValue or function(v) return v end

local PREFIX = "|cff34D399[QSpell]|r "
local LABEL_COLOR = "|cffA7F3D0"
local DIM = "|cff9CA3AF"
local RESET = "|r"

local function p(line) print(PREFIX .. (line or "")) end
local function row(label, value)
    if value == nil then value = DIM .. "nil" .. RESET end
    print(("  %s%s%s = %s"):format(LABEL_COLOR, label, RESET, tostring(value)))
end
local function header(text) print(("%s%s%s"):format(LABEL_COLOR, text, RESET)) end

-- Resolve a user argument into a spellID. Accepts a number, a |Hspell:ID|h
-- hyperlink, or a partial name lookup against the player's spellbook via
-- C_Spell.GetSpellIDForSpellIdentifier (preferred) or GetSpellInfo by name.
local function ResolveSpellID(arg)
    if arg == nil or arg == "" then return nil end
    local n = tonumber(arg)
    if n then return n end
    -- Hyperlink: |Hspell:12345:0|h[Name]|h or just spell:12345
    local linkID = arg:match("|Hspell:(%d+)") or arg:match("spell:(%d+)")
    if linkID then return tonumber(linkID) end
    -- Try a name lookup
    if C_Spell and C_Spell.GetSpellIDForSpellIdentifier then
        local ok, id = pcall(C_Spell.GetSpellIDForSpellIdentifier, arg)
        if ok and id then return id end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, arg)
        if ok and info and info.spellID then return info.spellID end
    end
    return nil
end

local function fmtBool(v)
    if v == nil then return DIM .. "nil" .. RESET end
    if v then return "|cff86EFACtrue" .. RESET end
    return "|cffFCA5A5false" .. RESET
end

local function tryCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

local function DumpIdentity(spellID)
    header("Identity")
    row("spellID", spellID)
    local info = tryCall(C_Spell and C_Spell.GetSpellInfo, spellID)
    if type(info) == "table" then
        row("name", SafeValue(info.name, nil))
        row("iconID", SafeValue(info.iconID, nil))
        row("originalIconID", SafeValue(info.originalIconID, nil))
        row("castTime (ms)", SafeValue(info.castTime, nil))
        row("minRange", SafeValue(info.minRange, nil))
        row("maxRange", SafeValue(info.maxRange, nil))
        row("spellID (echo)", SafeValue(info.spellID, nil))
    else
        row("GetSpellInfo", "(no data — unknown spellID?)")
    end
    local link = tryCall(C_Spell and C_Spell.GetSpellLink, spellID)
    row("link", link)
    local tex = tryCall(C_Spell and C_Spell.GetSpellTexture, spellID)
    row("texture", tex)
end

local function DumpOverride(spellID)
    header("Override / base")
    local override = tryCall(C_Spell and C_Spell.GetOverrideSpell, spellID)
    row("C_Spell.GetOverrideSpell", override)
    local baseID = tryCall(_G.FindBaseSpellByID, spellID)
    row("FindBaseSpellByID", baseID)
    local ovrID = tryCall(_G.FindSpellOverrideByID, spellID)
    row("FindSpellOverrideByID", ovrID)
    if override and override ~= spellID then
        local ovInfo = tryCall(C_Spell and C_Spell.GetSpellInfo, override)
        if type(ovInfo) == "table" then
            row("override.name", SafeValue(ovInfo.name, nil))
        end
    end
end

local function DumpKnowledge(spellID)
    header("Knowledge / state")
    row("IsPlayerSpell", fmtBool(tryCall(_G.IsPlayerSpell, spellID)))
    row("IsSpellKnown", fmtBool(tryCall(_G.IsSpellKnown, spellID)))
    row("IsSpellKnownOrOverridesKnown", fmtBool(tryCall(_G.IsSpellKnownOrOverridesKnown, spellID)))
    row("C_Spell.IsSpellPassive", fmtBool(tryCall(C_Spell and C_Spell.IsSpellPassive, spellID)))
    row("C_Spell.IsSpellHarmful", fmtBool(tryCall(C_Spell and C_Spell.IsSpellHarmful, spellID)))
    row("C_Spell.IsSpellHelpful", fmtBool(tryCall(C_Spell and C_Spell.IsSpellHelpful, spellID)))
    row("C_Spell.IsSpellUsable", fmtBool(tryCall(C_Spell and C_Spell.IsSpellUsable, spellID)))
    row("C_Spell.IsSpellInRange (target)", fmtBool(tryCall(C_Spell and C_Spell.IsSpellInRange, spellID, "target")))
end

local function DumpTiming(spellID)
    header("Cooldown / charges")
    if C_Spell and C_Spell.GetSpellCooldown then
        local cd = tryCall(C_Spell.GetSpellCooldown, spellID)
        if type(cd) == "table" then
            row("cd.startTime",  SafeValue(cd.startTime, nil))
            row("cd.duration",   SafeValue(cd.duration, nil))
            row("cd.isEnabled",  fmtBool(SafeValue(cd.isEnabled, nil)))
            row("cd.modRate",    SafeValue(cd.modRate, nil))
        end
    end
    if C_Spell and C_Spell.GetSpellCharges then
        local ch = tryCall(C_Spell.GetSpellCharges, spellID)
        if type(ch) == "table" then
            row("charges.current", SafeValue(ch.currentCharges, nil))
            row("charges.max",     SafeValue(ch.maxCharges, nil))
            row("charges.cdStart", SafeValue(ch.cooldownStartTime, nil))
            row("charges.cdDur",   SafeValue(ch.cooldownDuration, nil))
            row("charges.modRate", SafeValue(ch.chargeModRate, nil))
        end
    end
    -- Cooldown duration (DurationObject in 12.x — secret-safe)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local dur = tryCall(C_Spell.GetSpellCooldownDuration, spellID)
        row("GetSpellCooldownDuration", dur and "<DurationObject>" or nil)
    end
end

local function DumpAura(spellID)
    header("Active aura on player")
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = tryCall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if type(aura) == "table" then
            row("name",                SafeValue(aura.name, nil))
            row("auraInstanceID",      SafeValue(aura.auraInstanceID, nil))
            row("spellId",             SafeValue(aura.spellId, nil))
            row("dispelName",          SafeValue(aura.dispelName, nil))
            row("isHarmful",           fmtBool(SafeValue(aura.isHarmful, nil)))
            row("isHelpful",           fmtBool(SafeValue(aura.isHelpful, nil)))
            row("applications",        SafeValue(aura.applications, nil))
            row("isFromPlayerOrPet",   fmtBool(SafeValue(aura.isFromPlayerOrPlayerPet, nil)))
            row("sourceUnit",          SafeValue(aura.sourceUnit, nil))
            row("expirationTime",      SafeValue(aura.expirationTime, nil))
            row("duration",            SafeValue(aura.duration, nil))
        else
            row("GetPlayerAuraBySpellID", DIM .. "(not active)" .. RESET)
        end
    end
end

local function DumpDescription(spellID)
    header("Description")
    local desc = tryCall(C_Spell and C_Spell.GetSpellDescription, spellID)
    if type(desc) == "string" and desc ~= "" then
        for line in desc:gmatch("[^\r\n]+") do
            print("  " .. line)
        end
    else
        row("description", DIM .. "(empty)" .. RESET)
    end
end

SLASH_QUI_QSPELL1 = "/qspell"
SlashCmdList["QUI_QSPELL"] = function(msg)
    local arg = msg and strtrim(msg) or ""
    local spellID = ResolveSpellID(arg)
    if not spellID then
        p("Usage: /qspell <spellID | spell link | partial name>")
        return
    end
    p(("Dumping spell |cffFFD100%d|r"):format(spellID))
    DumpIdentity(spellID)
    DumpOverride(spellID)
    DumpKnowledge(spellID)
    DumpTiming(spellID)
    DumpAura(spellID)
    DumpDescription(spellID)
end
